$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoName = Split-Path $root -Leaf
$regexFecha = '^\d{2}-\d{2}-\d{4}$'

function Normalize-Html([string]$html) {
    if ([string]::IsNullOrEmpty($html)) { return "" }

    # Si viene escapado como &lt;...&gt; lo decodificamos para poder parsear
    $t = $html -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'" -replace '&amp;', '&'

    return $t
}

function Find-GeneralReport([string]$folderPath) {
    $cands = Get-ChildItem -Path $folderPath -File -Filter *.html -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne "index.html" }

    foreach ($f in ($cands | Sort-Object LastWriteTime -Descending)) {
        $raw = Get-Content -Raw -Encoding UTF8 $f.FullName
        $html = Normalize-Html $raw
        if ($html -match '(?i)Reporte\s+General\s+GDEA') { return $f }
    }
    return $null
}

function Extract-Counts([string]$rawHtml) {
    $html = Normalize-Html $rawHtml

    $total = 0; $ok = 0; $fail = 0; $dur = "-"

    $m = [regex]::Match($html, '(?is)Total\s*tests\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $total = [int]$m.Groups[1].Value }

    $m = [regex]::Match($html, '(?is)\bOK\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $ok = [int]$m.Groups[1].Value }

    $m = [regex]::Match($html, '(?is)Fallid(?:os|as)\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $fail = [int]$m.Groups[1].Value }

    # Duracion total (con o sin acento)
    $m = [regex]::Match($html, '(?is)Duraci[oó]n\s*total\s*:\s*</b>\s*([^<]+)</p>')
    if ($m.Success) { $dur = $m.Groups[1].Value.Trim() }

    return [PSCustomObject]@{ Total = $total; Ok = $ok; Fail = $fail; Duracion = $dur }
}

function Extract-TestResultsFromGeneral([string]$rawHtml) {
    $html = Normalize-Html $rawHtml
    $map = @{}

    # MUY robusto: no depende de "–" ni de mojibake.
    # Captura dentro de cada <div class="test ok|fail"> ... GDEA_xxx_Run ... OK/FAIL ... 12,34s ... </div>
    $pattern = '(?is)<div[^>]*class\s*=\s*"test\s+(ok|fail)"[^>]*>.*?([A-Za-z0-9_]+_Run).*?(OK|FAIL).*?([0-9]+(?:[.,][0-9]+)?s).*?</div>'
    $matches = [regex]::Matches($html, $pattern)

    foreach ($m in $matches) {
        $name = $m.Groups[2].Value.Trim()
        $status = $m.Groups[3].Value.Trim().ToUpper()
        $dur = $m.Groups[4].Value.Trim()

        $map[$name] = @{ Status = $status; Duration = $dur }
    }

    return $map
}

function Clean-Label([string]$folderName) {
    $label = $folderName -replace '_\d{8}_\d{6}$', ''
    $label = $label -replace '_', ' '
    return $label.Trim()
}

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

function Map-FolderToTestName([string]$folderName) {
    $n = $folderName.ToUpper()

    if ($n -match 'AGENDA' -and $n -match 'ALTA') { return 'GDEA_AGENDA_ALTA_Run' }
    if ($n -match 'AGENDA' -and ($n -match 'MODIF' -or $n -match 'MOD')) { return 'GDEA_AGENDA_MODIFICACION_Run' }
    if ($n -match 'AGENDA' -and $n -match 'BAJA') { return 'GDEA_AGENDA_BAJA_Run' }

    if ($n -match 'LICEN' -and $n -match 'ALTA') { return 'GDEA_LICENCIA_ALTA_Run' }
    if ($n -match 'LICEN' -and $n -match 'BAJA') { return 'GDEA_LICENCIA_BAJA_Run' }

    if ($n -match 'EQUIPOPROFESIONAL' -and $n -match 'ALTA') { return 'GDEA_EQUIPOPROFESIONAL_ALTA_Run' }
    if ($n -match 'EQUIPOPROFESIONAL' -and ($n -match 'MODIF' -or $n -match 'MOD')) { return 'GDEA_EQUIPOPROFESIONAL_MODIFICACION_Run' }
    if ($n -match 'EQUIPOPROFESIONAL' -and $n -match 'BAJA') { return 'GDEA_EQUIPOPROFESIONAL_BAJA_Run' }

    if ($n -match 'FERIAD' -and $n -match 'ALTA') { return 'GDEA_FERIADOS_ALTA_Run' }
    if ($n -match 'FERIAD' -and ($n -match 'MODIF' -or $n -match 'MOD')) { return 'GDEA_FERIADOS_MODIFICACION_Run' }
    if ($n -match 'FERIAD' -and $n -match 'BAJA') { return 'GDEA_FERIADOS_BAJA_Run' }

    if ($n -match 'GRUPOUSUARIO' -and $n -match 'ALTA') { return 'GDEA_GRUPOUSUARIO_ALTA_Run' }
    if ($n -match 'GRUPOUSUARIO' -and ($n -match 'MODIF' -or $n -match 'MOD')) { return 'GDEA_GRUPOUSUARIO_MODIFICACION_Run' }
    if ($n -match 'GRUPOUSUARIO' -and $n -match 'BAJA') { return 'GDEA_GRUPOUSUARIO_BAJA_Run' }

    if ($n -match 'REPORT') { return 'GDEA_REPORTES_Run' }

    return $null
}

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

        $testName = Map-FolderToTestName $d.Name
        $status = "UNKNOWN"
        $duration = ""

        if ($testName -and $testMap.ContainsKey($testName)) {
            $status = $testMap[$testName].Status
            $duration = $testMap[$testName].Duration
        }

        if ([string]::IsNullOrEmpty($href)) {
            $status = "UNKNOWN"
        }

        $items.Add([PSCustomObject]@{
            Label    = Clean-Label $d.Name
            Href     = $href
            TestName = $testName
            Status   = $status
            Duration = $duration
        })
    }

    return $items
}

Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -match $regexFecha } | ForEach-Object {

    $dateName = $_.Name
    $datePath = $_.FullName

    $counts = [PSCustomObject]@{ Total = 0; Ok = 0; Fail = 0; Duracion = "-" }
    $testMap = @{}

    $general = Find-GeneralReport $datePath
    if ($general) {
        $raw = Get-Content -Raw -Encoding UTF8 $general.FullName
        $counts = Extract-Counts $raw
        $testMap = Extract-TestResultsFromGeneral $raw

        if ($counts.Total -eq 0 -and $testMap.Keys.Count -gt 0) {
            $counts.Total = $testMap.Keys.Count
            $counts.Ok = @($testMap.Values | Where-Object { $_.Status -eq "OK" }).Count
            $counts.Fail = @($testMap.Values | Where-Object { $_.Status -eq "FAIL" }).Count
        }
    }

    $items = Build-ItemsFromImmediateSubfolders $datePath $testMap

    $p = $dateName -split '-'
    $fechaTitulo = "$($p[0])/$($p[1])"
    $duracion = $counts.Duracion

    $baseHref = "/$repoName/$dateName/"

    $outHtml = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Reporte QA</title>
  <base href="$baseHref">
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
    <h2>Resumen de Ejecucion $fechaTitulo GDEA</h2>
    <div class="summary">
      <div class="card"><div>Total Tests</div><div class="big">$($counts.Total)</div></div>
      <div class="card"><div>Passed</div><div class="big">$($counts.Ok) &#9989;</div></div>
      <div class="card"><div>Failed</div><div class="big">$($counts.Fail) &#10060;</div></div>
      <div class="card"><div>Duracion</div><div class="big">$duracion</div></div>
    </div>
  </div>

  <div class="qa-panel">
    <h2>Reportes Detallados</h2>
    <div class="qa-actions">
"@

    foreach ($it in $items) {
        if ([string]::IsNullOrEmpty($it.Href)) {
            $outHtml += "<span class='qa-button unknown'>$($it.Label)</span>`n"
        } else {
            $btnClass = "unknown"
            if ($it.Status -eq "OK") { $btnClass = "ok" }
            elseif ($it.Status -eq "FAIL") { $btnClass = "fail" }
            $outHtml += "<a class='qa-button $btnClass' href='$($it.Href)' target='_blank'>$($it.Label)</a>`n"
        }
    }

    $outHtml += @"
    </div>
  </div>

  <div class="qa-panel">
    <h2>Resultados de Tests</h2>
    <div class="results">
"@

    foreach ($it in $items) {
        $icon = "&#9888;"  # warning
        $cls = "unk"
        $st = "UNKNOWN"

        if ($it.Status -eq "OK") { $icon = "&#10004;"; $cls = "pass"; $st = "OK" }      # ✔
        elseif ($it.Status -eq "FAIL") { $icon = "&#10006;"; $cls = "failtxt"; $st = "FAIL" } # ✖

        $durTxt = ""
        if (-not [string]::IsNullOrEmpty($it.Duration)) { $durTxt = " <span class='meta'>($($it.Duration))</span>" }

        $outHtml += "<div class='test'><span class='$cls'>$icon</span> $($it.Label) <span class='meta'>- $st</span>$durTxt</div>`n"
    }

    $outHtml += @"
    </div>
  </div>

</div>
</body>
</html>
"@

    $outPath = Join-Path $datePath "index.html"
    $outHtml | Set-Content -Encoding UTF8 $outPath

    Write-Host "OK ${dateName}: index.html generado. Subcarpetas: $($items.Count)"
}
