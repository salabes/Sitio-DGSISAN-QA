$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoName = Split-Path $root -Leaf
$regexFecha = '^\d{2}-\d{2}-\d{4}$'

function Find-GeneralReport([string]$folderPath) {
    $cands = Get-ChildItem -Path $folderPath -File -Filter *.html | Where-Object { $_.Name -ne "index.html" }
    foreach ($f in ($cands | Sort-Object LastWriteTime -Descending)) {
        $html = Get-Content -Raw -Encoding UTF8 $f.FullName
        if ($html -match '(?i)Reporte\s+General\s+GDEA') { return $f }
    }
    return $null
}

function Extract-Counts([string]$html) {
    $total = 0; $ok = 0; $fail = 0

    $m = [regex]::Match($html, '(?is)Total\s*tests\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $total = [int]$m.Groups[1].Value }

    $m = [regex]::Match($html, '(?is)\bOK\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $ok = [int]$m.Groups[1].Value }

    $m = [regex]::Match($html, '(?is)Fallid(?:os|as)\s*:\s*</b>\s*([0-9]+)')
    if ($m.Success) { $fail = [int]$m.Groups[1].Value }

    return [PSCustomObject]@{ Total = $total; Ok = $ok; Fail = $fail }
}

function Clean-Label([string]$folderName) {
    $label = $folderName -replace '_\d{8}_\d{6}$', ''   # saca _YYYYMMDD_HHMMSS
    $label = $label -replace '_', ' '
    return $label.Trim()
}

function Find-ReportInSubfolder([string]$subfolderPath) {
    # Prioridad 1: report_GDEA.html
    $p1 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "report_GDEA.html" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($p1) { return $p1 }

    # Prioridad 2: report*.html
    $p2 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "report*.html" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($p2) { return $p2 }

    # Prioridad 3: cualquier html
    $p3 = Get-ChildItem -Path $subfolderPath -Recurse -File -Filter "*.html" -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -ne "index.html" } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $p3
}

function Build-ButtonsFromImmediateSubfolders([string]$dateFolderPath) {
    $items = New-Object System.Collections.Generic.List[object]

    $subdirs = Get-ChildItem -Path $dateFolderPath -Directory | Sort-Object Name
    foreach ($d in $subdirs) {
        $report = Find-ReportInSubfolder $d.FullName
        if (-not $report) { continue }

        # HREF relativo al index dentro de la carpeta fecha:
        # subcarpeta/.../archivo.html (si está más profundo, lo armamos recortando la ruta base)
        $base = $dateFolderPath.TrimEnd('\')
        $full = $report.FullName

        if ($full.Length -le ($base.Length + 1)) { continue }
        $rel = $full.Substring($base.Length + 1).Replace('\','/')

        $items.Add([PSCustomObject]@{
            Label = Clean-Label $d.Name
            Href  = $rel
        })
    }

    return $items
}

Get-ChildItem -Path $root -Directory |
Where-Object { $_.Name -match $regexFecha } |
ForEach-Object {

    $dateFolder = $_
    $datePath   = $dateFolder.FullName
    $dateName   = $dateFolder.Name

    # Conteos desde reporte general (si existe)
    $counts = [PSCustomObject]@{ Total = 0; Ok = 0; Fail = 0 }
    $general = Find-GeneralReport $datePath
    if ($general) {
        $htmlGeneral = Get-Content -Raw -Encoding UTF8 $general.FullName
        $counts = Extract-Counts $htmlGeneral
    }

    # Botones desde subcarpetas inmediatas (lo que pedís)
    $buttons = Build-ButtonsFromImmediateSubfolders $datePath

    # titulo dd/MM
    $p = $dateName -split '-'
    $fechaTitulo = "$($p[0])/$($p[1])"
    $duracion = "-"

    # Base para GitHub Pages
    $baseHref = "/$repoName/$dateName/"

    $outHtml = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Reporte QA</title>

  <base href="$baseHref">

  <style>
    body {
      background-color: #708fac;
      color: #ffffff;
      font-family: Segoe UI, Calibri, Arial, sans-serif;
    }
    .container { max-width: 1100px; margin: 40px auto; }
    .qa-panel { padding: 26px 30px; background: #163d66; border-radius: 14px; margin-bottom: 30px; }
    .qa-panel h2 { margin-top: 0; color: #dbe9ff; }
    .qa-actions { display: flex; gap: 14px; flex-wrap: wrap; margin-top: 18px; }
    .qa-button { padding: 12px 20px; border-radius: 10px; text-decoration: none; font-weight: 600; background: #1f6feb; color: white; }
    .qa-button:hover { background: #388bfd; }
    .summary { display: flex; gap: 30px; flex-wrap: wrap; margin-top: 15px; }
    .card { background: #1e4f7a; padding: 15px; border-radius: 10px; min-width: 150px; text-align: center; }
    .big { font-size: 28px; font-weight: bold; }
    .results { background: #ffffff; color: #000; padding: 20px; border-radius: 10px; }
    .test { padding: 10px; margin-bottom: 10px; border-radius: 6px; background: #e6eff7; }
    .pass { color: green; font-weight: bold; }
    .fail { color: #b00020; font-weight: bold; }
  </style>
</head>

<body>
<div class="container">

  <div class="qa-panel">
    <h2>Resumen de Ejecucion $fechaTitulo GDEA</h2>

    <div class="summary">
      <div class="card">
        <div>Total Tests</div>
        <div class="big">$($counts.Total)</div>
      </div>

      <div class="card">
        <div>Passed</div>
        <div class="big">$($counts.Ok) &#9989;</div>
      </div>

      <div class="card">
        <div>Failed</div>
        <div class="big">$($counts.Fail) &#10060;</div>
      </div>

      <div class="card">
        <div>Duracion</div>
        <div class="big">$duracion</div>
      </div>
    </div>
  </div>

  <div class="qa-panel">
    <h2>Reportes Detallados</h2>
    <div class="qa-actions">
"@

    if ($buttons.Count -eq 0) {
        $outHtml += @"
      <div style="opacity:.9;">No se encontraron reportes HTML dentro de subcarpetas.</div>
"@
    } else {
        foreach ($b in $buttons) {
            $outHtml += @"
      <a class="qa-button" href="$($b.Href)" target="_blank">$($b.Label)</a>
"@
        }
    }

    $outHtml += @"
    </div>
  </div>

  <div class="qa-panel">
    <h2>Resultados de Tests</h2>
    <div class="results">
"@

    $globalOk = ($counts.Fail -eq 0)
    $cls  = if ($globalOk) { "pass" } else { "fail" }
    $icon = if ($globalOk) { "&#10004;" } else { "&#10006;" }

    if ($buttons.Count -eq 0) {
        $outHtml += @"
      <div class="test"><span class="$cls">$icon</span> Ejecucion (sin reportes detallados encontrados)</div>
"@
    } else {
        foreach ($b in $buttons) {
            $outHtml += @"
      <div class="test"><span class="$cls">$icon</span> $($b.Label)</div>
"@
        }
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

    Write-Host "OK ${dateName}: index.html generado. Botones: $($buttons.Count)"
}
