param([int]$Port = 8090, [switch]$Rebuild, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if ($Rebuild -or -not (Test-Path -LiteralPath 'build\web\index.html')) {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install dependencies.' }
    flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define-from-file=config.json
    if ($LASTEXITCODE -ne 0) { throw 'Failed to build Flutter Web.' }
}
Write-Host "Autoritm: http://127.0.0.1:$Port"
Write-Host 'Stop: Ctrl+C'
if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$Port" }
node server.mjs $Port
