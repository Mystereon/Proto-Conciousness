Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$prodDir = "C:\indigo"
$sandboxDir = "C:\indigo_sandbox"
$sandboxApp = Join-Path $sandboxDir "app.py"
$sandboxBrain = Join-Path $sandboxDir "brain.py"
$sandboxRun = Join-Path $sandboxDir "run_sandbox.bat"
$sandboxNodeId = Join-Path $sandboxDir "node_id.txt"
$prodVenvPython = Join-Path $prodDir "venv\Scripts\python.exe"

if (-not (Test-Path $prodDir)) {
    throw "Production Indigo folder not found: $prodDir"
}
if (-not (Test-Path $prodVenvPython)) {
    throw "Python venv not found: $prodVenvPython"
}

$requiredDirs = @(
    $sandboxDir,
    (Join-Path $sandboxDir "memory"),
    (Join-Path $sandboxDir "known_nodes"),
    (Join-Path $sandboxDir "logs"),
    (Join-Path $sandboxDir "backup")
)

foreach ($dir in $requiredDirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

if (-not (Test-Path $sandboxNodeId)) {
    [guid]::NewGuid().ToString() | Set-Content -Path $sandboxNodeId -Encoding ascii
}

Copy-Item -Path (Join-Path $prodDir "app.py") -Destination $sandboxApp -Force
Copy-Item -Path (Join-Path $prodDir "brain.py") -Destination $sandboxBrain -Force

$brainText = Get-Content -Raw -Path $sandboxBrain
$brainText = $brainText.Replace('BASE_DIR = Path(r"C:\indigo")', 'BASE_DIR = Path(r"C:\indigo_sandbox")')
$brainText = $brainText.Replace('MODELS_DIR = BASE_DIR / "models"', 'MODELS_DIR = Path(r"C:\indigo\models")')
$brainText = $brainText.Replace('LLAMA_DIR = BASE_DIR / "llama.cpp"', 'LLAMA_DIR = Path(r"C:\indigo\llama.cpp")')
$brainText = $brainText.Replace('PIPER_DIR = BASE_DIR / "piper"', 'PIPER_DIR = Path(r"C:\indigo\piper")')
$brainText = $brainText.Replace('PIPER_MODELS_DIR = BASE_DIR / "piper_models"', 'PIPER_MODELS_DIR = Path(r"C:\indigo\piper_models")')
$brainText = $brainText.Replace(
    'MODEL_PATH = select_model()',
    'MODEL_PATH = pick_first_existing([MODELS_DIR / "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf", MODELS_DIR / "mistral-7b-instruct-v0.2.Q4_K_M.gguf"]) or select_model()'
)
Set-Content -Path $sandboxBrain -Value $brainText -Encoding utf8

$appText = Get-Content -Raw -Path $sandboxApp
$appText = $appText.Replace("port=5000", "port=5001")
$appText = $appText.Replace("127.0.0.1:5000", "127.0.0.1:5001")
Set-Content -Path $sandboxApp -Value $appText -Encoding utf8

$runText = @"
@echo off
title INDIGO SANDBOX - PREVIEW NODE
cd /d C:\indigo_sandbox
call C:\indigo\venv\Scripts\activate.bat
echo [SANDBOX] Indigo preview is starting on http://127.0.0.1:5001
python app.py
pause
"@

Set-Content -Path $sandboxRun -Value $runText -Encoding ascii

# Smoke checks
& $prodVenvPython -m py_compile $sandboxApp
& $prodVenvPython -m py_compile $sandboxBrain

Push-Location $sandboxDir
try {
    & $prodVenvPython -c "import app; c=app.app.test_client(); r=c.get('/health'); print(r.status_code); print(r.get_json())"
} finally {
    Pop-Location
}

Write-Host "Sandbox created: $sandboxDir" -ForegroundColor Green
Write-Host "Run preview: $sandboxRun" -ForegroundColor Green
