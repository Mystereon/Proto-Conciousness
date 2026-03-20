param(
    [string]$Repo = "Mystereon/Proto-Conciousness",
    [string]$Branch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tempRoot = Join-Path $env:TEMP ("proto-consciousness-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "repo.zip"

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$zipUrl = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
Write-Host "Downloading $zipUrl"
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 180

Write-Host "Extracting package..."
Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

$bundleRoot = Join-Path $tempRoot ("Proto-Conciousness-" + $Branch)
$installer = Join-Path $bundleRoot "ProtoConsciousIndigo.ps1"

if (-not (Test-Path $installer)) {
    throw "Installer not found: $installer"
}

Write-Host "Launching Indigo installer..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer
