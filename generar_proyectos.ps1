$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Escribir archivo UTF-8 sin BOM (acentos OK)
# ---------------------------------------------------------
function Write-Utf8NoBom([string]$path, [string]$content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# Directorio actual
$root = Get-Location

# Tomar carpetas que NO sean .github
$folders = Get-ChildItem -Path $root -Directory |
           Where-Object { $_.Name -ne ".github" } |
           Sort-Object Name

# ---------------------------------------------------------
# HTML base
# ---------------------------------------------------------
$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Proyectos QA DGSISAN</title>
<style>
body {
    background: #0b1220;
    color: #e8eefc;
    font-family: Segoe UI, Arial, sans-serif;
    padding: 40px;
}
h1 {
    margin-bottom: 30px;
    text-align: center;
}
.container {
    display: flex;
    flex-wrap: wrap;
    gap: 20px;
    justify-content: center;
}
.project {
    background: #163d66;
    padding: 20px 30px;
    border-radius: 14px;
    text-decoration: none;
    color: white;
    font-weight: 600;
    font-size: 16px;
    transition: transform 0.1s ease, filter 0.1s ease;
}
.project:hover {
    transform: translateY(-2px);
    filter: brightness(1.1);
}
</style>
</head>
<body>

<h1>Proyectos QA</h1>

<div class="container">
"@

# ---------------------------------------------------------
# Botones por proyecto
# ---------------------------------------------------------
foreach ($f in $folders) {
    $name = $f.Name.Replace('_', ' ')
    $href = "./$($f.Name)/index.html"

    $html += "  <a class='project' href='$href'>$name</a>`n"
}

# ---------------------------------------------------------
# Cierre HTML
# ---------------------------------------------------------
$html += @"
</div>

</body>
</html>
"@

# Escribir index.html en el directorio raíz
$outPath = Join-Path $root "index.html"
Write-Utf8NoBom $outPath $html

Write-Host "OK: index.html generado con $($folders.Count) proyectos."
