$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoName = Split-Path $root -Leaf
$regexFecha = '^\d{2}-\d{2}-\d{4}$'

# ---------------------------------------------------------
# Escribir archivos en UTF-8 SIN BOM (evita problemas raros)
# ---------------------------------------------------------
function Write-Utf8NoBom([string]$path, [string]$content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# ---------------------------------------------------------
# Normalización HTML (decodifica &lt; &gt; &amp; etc. varias veces)
# ---------------------------------------------------------
function Normalize-Html([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return "" }
    $t = $html
    for ($i = 0; $i -lt 4; $i++) {
        $d = [System.Net.WebUtility]::HtmlDecode($t)
        if ($d -eq $t) { break }
        $t = $d
    }
    return $t
}

function Normalize-TestKey([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return ($s.ToUpper() -replace '[^A-Z0-9]', '')
}

# ---------------------------------------------------------
# Buscar Reporte General en carpeta de fecha
# ---------------------------------------------------------
function Find-GeneralReport([string]$folderPath) {
    $cands = Get-ChildItem -Path $folderPath -File -Filter *.html -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne "index.html" }

    foreach ($f in ($cands | Sort-Object LastWriteTime -Descending)) {
        $raw  = Get-Content -Raw -Encoding UTF8 $f.FullName
        $html = Normalize-Html $raw
        if ($html -match '(?i)Reporte\s+General\s+GDEA') { return $f }
    }
    return $null
}

# ---------------------------------------------------------
# Contadores (Total/OK/Fail/Duracion) desde Reporte General
# ---------------------------------------------------------
function Extract-Counts([string]$rawHtml) {
    $html = Normalize-Html $rawHtml

    $total = 0; $ok = 0; $fail = 0; $dur = "-"

    if ($html -match '(?is)Total\s*tests\s*:\s*</b>\s*(\d+)') { $total = [int]$matches[1] }
    if ($html -match '(?is)\bOK\s*:\s*</b>\s*(\d+)')         { $ok    = [int]$matches[1] }
    if ($html -match '(?is)Fallid(?:os|as)\s*:\s*</b>\s*(\d+)') { $fail = [int]$matches[1] }

    # soporta: Duración / Duracion / DuraciÃ³n
    if ($html -match '(?is)Duraci(?:ó|o|Ã³)n\s*total\s*:\s*</b>\s*([^<]+)') {
        $dur = $matches[1].Trim()
    }
    # soporta: "Duracion total:" sin </b> en algunos casos
    elseif ($html -match '(?is)Duraci(?:ó|o|Ã³)n\s*total\s*:\s*([^<]+)') {
        $dur = $matches[1].Trim()
    }

    return [PSCustomObject]@{ Total=$total; Ok=$ok; Fail=$fail; Duracion=$dur }
}

# ---------------------------------------------------------
# Parsear tests OK/FAIL desde Reporte General
# Acepta: class="test ok" y class='test ok'
# ---------------------------------------------------------
function Extract-TestResultsFromGeneral([string]$rawHtml) {

    # 1) Primer intento: HTML normalizado (casos nuevos)
    $html = Normalize-Html $rawHtml
    $map  = @{}

    $patternReal = '(?is)<div[^>]*class\s*=\s*("|\x27)(?:[^"\x27]*)test\s+(ok|fail)(?:[^"\x27]*)\1[^>]*>\s*(.*?)\s*</div>'
    $matches = [regex]::Matches($html, $patternReal)

    # 2) Si no encontró nada, intentar HTML escapado (casos viejos)
    if ($matches.Count -eq 0) {
        $patternEscaped = '(?is)&lt;div[^&]*class\s*=\s*("|\x27)(?:[^"\x27]*)test\s+(ok|fail)(?:[^"\x27]*)\1[^&]*&gt;\s*(.*?)\s*&lt;/div&gt;'
        $matches = [regex]::Matches($rawHtml, $patternEscaped)
    }

    foreach ($m in $matches) {

        $status = $m.Groups[2].Value.Trim().ToUpper()   # OK | FAIL
        $text   = [System.Net.WebUtility]::HtmlDecode(
                    ($m.Groups[3].Value -replace '\s+', ' ').Trim()
                  )

        # Nombre del test
        if ($text -notmatch '\b([A-Za-z0-9_]+)\b') { continue }
        $name = $matches[1]

        # Duración
        $dur = ""
        if ($text -match '([0-9]+(?:[.,][0-9]+)?s)') {
            $dur = $matches[1]
        }

        $key = Normalize-TestKey $name
        if ($key) {
            $map[$key] = @{
                Status   = $status
                Duration = $dur
            }
        }
    }

    return $map
}
# ---------------------------------------------------------
# Encontrar un HTML "reporte" dentro de la subcarpeta
# ---------------------------------------------------------
function Find-ReportInSubfolder([string]$subfolderPath) {
    $p1 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "report_GDEA.html" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($p1) { return $p1 }

    $p2 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "report*.html" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($p2) { return $p2 }

    $p3 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "*.html" -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -ne "index.html" } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $p3
}

function Clean-Label([string]$folderName) {
    $label = $folderName -replace '_\d{8}_\d{6}$', ''
    $label = $label -replace '_', ' '
    return $label.Trim()
}

# ---------------------------------------------------------
# Mapeo subcarpeta -> test(s) candidatos
# ---------------------------------------------------------
function Get-TestNameCandidates([string]$folderName) {
    $n = Normalize-TestKey $folderName
    $c = New-Object System.Collections.Generic.List[string]

    if ($n -match 'AGENDA' -and $n -match 'ALTA') { $c.Add('GDEA_AGENDA_ALTA_Run') }
    if ($n -match 'AGENDA' -and $n -match 'MOD')  { $c.Add('GDEA_AGENDA_MODIFICACION_Run') }
    if ($n -match 'AGENDA' -and $n -match 'BAJA') { $c.Add('GDEA_AGENDA_BAJA_Run') }

    # Licencias: genérico = ALTA (como pediste)
    if ($n -match 'LICEN' -and -not ($n -match 'BAJA' -or $n -match 'MOD')) {
        $c.Add('GDEA_LICENCIA_ALTA_Run')
    }
    if ($n -match 'LICEN' -and $n -match 'BAJA') {
        $c.Add('GDEA_LICENCIA_BAJA_Run')
    }

    if ($n -match 'EQUIPOPROFESIONAL' -and $n -match 'ALTA') { $c.Add('GDEA_EQUIPOPROFESIONAL_ALTA_Run') }
    if ($n -match 'EQUIPOPROFESIONAL' -and $n -match 'MOD')  { $c.Add('GDEA_EQUIPOPROFESIONAL_MODIFICACION_Run') }
    if ($n -match 'EQUIPOPROFESIONAL' -and $n -match 'BAJA') { $c.Add('GDEA_EQUIPOPROFESIONAL_BAJA_Run') }

    if ($n -match 'FERIAD' -and $n -match 'ALTA') { $c.Add('GDEA_FERIADOS_ALTA_Run') }
    if ($n -match 'FERIAD' -and $n -match 'MOD')  { $c.Add('GDEA_FERIADOS_MODIFICACION_Run') }
    if ($n -match 'FERIAD' -and $n -match 'BAJA') { $c.Add('GDEA_FERIADOS_BAJA_Run') }

    if ($n -match 'GRUPOUSUARIO' -and $n -match 'ALTA') { $c.Add('GDEA_GRUPOUSUARIO_ALTA_Run') }
    if ($n -match 'GRUPOUSUARIO' -and $n -match 'MOD')  { $c.Add('GDEA_GRUPOUSUARIO_MODIFICACION_Run') }
    if ($n -match 'GRUPOUSUARIO' -and $n -match 'BAJA') { $c.Add('GDEA_GRUPOUSUARIO_BAJA_Run') }

    if ($n -match 'REPORT') { $c.Add('GDEA_REPORTES_Run') }

    # Login/Acceso => GDEARun en tu reporte
    if ($n -match 'LOGIN' -or $n -match 'ACCESOGDEA' -or $n -match 'OTORGARTURNO') {
        $c.Add('GDEARun')
    }

    return $c.ToArray()
}

# ---------------------------------------------------------
# Construir items (Label, Href, Status, Duration)
# ---------------------------------------------------------
function Build-ItemsFromImmediateSubfolders([string]$dateFolderPath, [hashtable]$testMap) {
    $items = New-Object System.Collections.Generic.List[object]
    $subdirs = Get-ChildItem -Path $dateFolderPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name

    foreach ($d in $subdirs) {
        $report = Find-ReportInSubfolder $d.FullName

        $href = $null
        if ($report) {
            $base = $dateFolderPath.TrimEnd('\')
            $full = $report.FullName
            if ($full.Length -gt ($base.Length + 1)) {
                $href = $full.Substring($base.Length + 1).Replace('\','/')
            }
        }

        $status = "UNKNOWN"
        $duration = ""
        $cands = Get-TestNameCandidates $d.Name

        foreach ($cand in $cands) {
            $key = Normalize-TestKey $cand
            if ($key -and $testMap.ContainsKey($key)) {
                $status = $testMap[$key].Status
                $duration = $testMap[$key].Duration
                break
            }
        }

        $items.Add([PSCustomObject]@{
            Label    = Clean-Label $d.Name
            Href     = $href
            Status   = $status
            Duration = $duration
        })
    }

    return $items
}

# =========================================================
# MAIN
# =========================================================
Get-ChildItem -Path $root -Directory |
Where-Object { $_.Name -match $regexFecha } |
ForEach-Object {

    $dateName = $_.Name
    $datePath = $_.FullName

    $counts = [PSCustomObject]@{ Total = 0; Ok = 0; Fail = 0; Duracion = "-" }
    $testMap = @{}

    $general = Find-GeneralReport $datePath
    if ($general) {
        $raw = Get-Content -Raw -Encoding UTF8 $general.FullName
        $counts = Extract-Counts $raw
        $testMap = Extract-TestResultsFromGeneral $raw
    }

    # Debug mínimo (ASCII)
    Write-Host ("[{0}] Tests detectados: {1}" -f $dateName, $testMap.Keys.Count)

    $items = Build-ItemsFromImmediateSubfolders $datePath $testMap

    

    # HTML REAL (NO escapado)
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Reporte QA GDEA</title>
<style>
body { background-color:#708fac; color:#ffffff; font-family:Segoe UI,Calibri,Arial,sans-serif; }
.container { max-width:1100px; margin:40px auto; }
.qa-panel { padding:26px 30px; background:#163d66; border-radius:14px; margin-bottom:30px; }
.qa-panel h2 { margin-top:0; color:#dbe9ff; }
.qa-actions { display:flex; gap:14px; flex-wrap:wrap; margin-top:18px; }
.qa-button { padding:12px 20px; border-radius:10px; text-decoration:none; font-weight:600; color:white; display:inline-block; }
.qa-button.ok { background:#16a34a; }
.qa-button.fail { background:#dc2626; }
.qa-button.unknown { background:#1f6feb; }
.qa-button:hover { filter:brightness(1.06); }
.summary { display:flex; gap:30px; flex-wrap:wrap; margin-top:15px; }
.card { background:#1e4f7a; padding:15px; border-radius:10px; min-width:150px; text-align:center; }
.big { font-size:28px; font-weight:bold; }

.results { background:#ffffff; color:#000; padding:20px; border-radius:10px; }
.test { padding:10px; margin-bottom:10px; border-radius:6px; background:#e6eff7; }
.pass { color:green; font-weight:bold; }
.failtxt { color:#b00020; font-weight:bold; }
.unk { color:#111827; font-weight:bold; }
.meta { opacity:.8; font-weight:normal; }
</style>
</head>
<body>
<div class="container">

<div class="qa-panel">
  <h2>Resumen de ejecucion $dateName GDEA</h2>
  <div class="summary">
    <div class="card"><div>Total Tests</div><div class="big">$($counts.Total)</div></div>
    <div class="card"><div>Passed</div><div class="big">$($counts.Ok) &#9989;</div></div>
    <div class="card"><div>Failed</div><div class="big">$($counts.Fail) &#10060;</div></div>
    <div class="card"><div>Duracion</div><div class="big">$($counts.Duracion)</div></div>
  </div>
</div>

<div class="qa-panel">
  <h2>Reportes detallados</h2>
  <div class="qa-actions">
"@

    # Botones
    foreach ($it in $items) {
        $cls = "unknown"
        if ($it.Status -eq "OK") { $cls = "ok" }
        elseif ($it.Status -eq "FAIL") { $cls = "fail" }

        if ([string]::IsNullOrWhiteSpace($it.Href)) {
            $html += "<span class='qa-button $cls'>$($it.Label)</span>`n"
        } else {
            $html += "<a class='qa-button $cls' href='$($it.Href)' target='_blank'>$($it.Label)</a>`n"
        }
    }

    $html += @"
  </div>
</div>

<div class="qa-panel">
  <h2>Resultados de tests</h2>
  <div class="results">
"@

    # Resultados
    foreach ($it in $items) {
        $icon = "&#9888;"   # warning
        $clsTxt = "unk"
        $st = "UNKNOWN"

        if ($it.Status -eq "OK")   { $icon = "&#10004;"; $clsTxt = "pass";    $st = "OK" }
        elseif ($it.Status -eq "FAIL") { $icon = "&#10006;"; $clsTxt = "failtxt"; $st = "FAIL" }

        $durTxt = ""
        if (-not [string]::IsNullOrWhiteSpace($it.Duration)) {
            $durTxt = " <span class='meta'>($($it.Duration))</span>"
        }

        $html += "<div class='test'><span class='$clsTxt'>$icon</span> $($it.Label) <span class='meta'>- $st</span>$durTxt</div>`n"
    }

    $html += @"
  </div>
</div>

</div>
</body>
</html>
"@

    $outPath = Join-Path $datePath "index.html"
    Write-Utf8NoBom $outPath $html

    Write-Host ("OK {0}: index.html generado. Subcarpetas: {1}" -f $dateName, $items.Count)
}