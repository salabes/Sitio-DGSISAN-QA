$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputFile = Join-Path $basePath "index.html"

# Regex para carpetas dd-mm-yyyy
$regexFecha = '^\d{2}-\d{2}-\d{4}$'

$carpetas = Get-ChildItem -Directory $basePath |
    Where-Object { $_.Name -match $regexFecha } |
    ForEach-Object {
        $partes = $_.Name -split '-'
        [PSCustomObject]@{
            Nombre = $_.Name
            Fecha  = Get-Date "$($partes[2])-$($partes[1])-$($partes[0])"
        }
    } |
    Sort-Object Fecha -Descending

$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Índice de ejecuciones</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Ubuntu;
            background: linear-gradient(135deg, #0f2027, #203a43, #2c5364);
            margin: 0;
            padding: 40px;
            color: #fff;
        }
        h1 {
            text-align: center;
            margin-bottom: 40px;
        }
        .container {
            max-width: 900px;
            margin: auto;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
        }
        a.button {
            display: block;
            padding: 20px;
            text-align: center;
            background: rgba(255,255,255,0.08);
            border-radius: 14px;
            text-decoration: none;
            color: #fff;
            font-size: 18px;
            font-weight: 500;
            transition: all 0.25s ease;
            box-shadow: 0 10px 25px rgba(0,0,0,0.25);
        }
        a.button:hover {
            background: rgba(255,255,255,0.18);
            transform: translateY(-4px);
        }
        .fecha {
            font-size: 14px;
            opacity: 0.75;
            margin-top: 8px;
        }
        footer {
            text-align: center;
            opacity: 0.6;
            margin-top: 50px;
            font-size: 13px;
        }
    </style>
</head>
<body>
    <h1>📂 Ejecuciones por fecha</h1>

    <div class="container">
"@

foreach ($c in $carpetas) {
    $html += @"
        <a class="button" href="./$($c.Nombre)/index.html">
            $($c.Nombre)
            <div class="fecha">$($c.Fecha.ToString("dd/MM/yyyy"))</div>
        </a>
"@
}

$html += @"
    </div>

    <footer>
        Generado automáticamente
    </footer>
</body>
</html>
"@

$html | Set-Content -Encoding UTF8 $outputFile

Write-Host "index.html generado correctamente"