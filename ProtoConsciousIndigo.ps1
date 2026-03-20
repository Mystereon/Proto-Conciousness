# ==========================================
# INDIGO ALPHA SEVEN REPAIR INSTALLER
# Normalises an existing C:\indigo install
# ==========================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseDir = "C:\indigo"
$backupDir = Join-Path $baseDir "backup"
$llamaDir = Join-Path $baseDir "llama.cpp"
$modelsDir = Join-Path $baseDir "models"
$memoryDir = Join-Path $baseDir "memory"
$knownNodesDir = Join-Path $baseDir "known_nodes"
$logsDir = Join-Path $baseDir "logs"
$piperDir = Join-Path $baseDir "piper"
$piperModelsDir = Join-Path $baseDir "piper_models"
$whisperDir = Join-Path $baseDir "whisper"
$venvDir = Join-Path $baseDir "venv"
$nodeIdPath = Join-Path $baseDir "node_id.txt"
$appPath = Join-Path $baseDir "app.py"
$brainPath = Join-Path $baseDir "brain.py"
$readmePath = Join-Path $baseDir "README.txt"
$runBatPath = Join-Path $baseDir "run_indigo.bat"
$runWebBatPath = Join-Path $baseDir "run_indigo_web.bat"
$checkModelPath = Join-Path $baseDir "check_model.ps1"
$survivalToolsPath = Join-Path $baseDir "survival_tools.py"
$survivalRunnerPath = Join-Path $baseDir "run_survival_tools.bat"
$preferredModelPath = Join-Path $modelsDir "preferred_model.txt"
$preferredLogicalModelPath = Join-Path $modelsDir "preferred_model_logical.txt"
$preferredCreativeModelPath = Join-Path $modelsDir "preferred_model_creative.txt"
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $invocationPath = $null

    if ($null -ne $MyInvocation) {
        $invocationPath = [string]$MyInvocation.PSCommandPath
        if ([string]::IsNullOrWhiteSpace($invocationPath)) {
            $myCommand = $MyInvocation.MyCommand
            if ($null -ne $myCommand) {
                $pathProp = $myCommand.PSObject.Properties["Path"]
                if ($pathProp -and -not [string]::IsNullOrWhiteSpace([string]$pathProp.Value)) {
                    $invocationPath = [string]$pathProp.Value
                } else {
                    $definitionProp = $myCommand.PSObject.Properties["Definition"]
                    if ($definitionProp -and -not [string]::IsNullOrWhiteSpace([string]$definitionProp.Value) -and (Test-Path ([string]$definitionProp.Value))) {
                        $invocationPath = [string]$definitionProp.Value
                    }
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($invocationPath) -and (Test-Path $invocationPath)) {
        $scriptRoot = Split-Path -Parent $invocationPath
    } else {
        $scriptRoot = (Get-Location).Path
    }
}
$survivalSourcePath = Join-Path $scriptRoot "survival_tools.py"
$appSourcePath = Join-Path $scriptRoot "app.py"
$brainSourcePath = Join-Path $scriptRoot "brain.py"
$llamaZip = Join-Path $baseDir "llama.zip"
$piperZip = Join-Path $baseDir "piper.zip"
$piperExePath = Join-Path $piperDir "piper.exe"
$venvPiperExePath = Join-Path $venvDir "Scripts\piper.exe"
$piperModelPath = Join-Path $piperModelsDir "en_GB-cori-medium.onnx"
$piperModelJsonPath = Join-Path $piperModelsDir "en_GB-cori-medium.onnx.json"

function Write-Step {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Backup-FileIfExists {
    param([string]$Path)

    if (Test-Path $Path) {
        Ensure-Directory $backupDir
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $leaf = Split-Path $Path -Leaf
        $destination = Join-Path $backupDir "$timestamp-$leaf"
        Copy-Item -Path $Path -Destination $destination -Force
        Write-Host "-> Backed up $leaf to $destination" -ForegroundColor DarkGray
    }
}

function Find-PythonLauncher {
    $candidates = @(
        @{ Command = "py"; Args = @("-3", "--version") },
        @{ Command = "python"; Args = @("--version") }
    )

    foreach ($candidate in $candidates) {
        try {
            & $candidate.Command @($candidate.Args) *> $null
            return $candidate.Command
        } catch {
        }
    }

    return $null
}

function Get-PythonExePath {
    param([string]$PythonLauncher)

    if ($PythonLauncher -eq "py") {
        return (& py -3 -c "import sys; print(sys.executable)")
    }

    return (& python -c "import sys; print(sys.executable)")
}

function Get-PreferredModelPath {
    param([string]$ModelsPath)

    $preferredFile = Join-Path $ModelsPath "preferred_model.txt"
    if (Test-Path $preferredFile) {
        try {
            $preferredValue = [string](Get-Content -Path $preferredFile -ErrorAction Stop | Select-Object -First 1)
            $preferredValue = $preferredValue.Trim()
            if ($preferredValue) {
                $candidatePaths = @(
                    $preferredValue,
                    (Join-Path $ModelsPath $preferredValue)
                ) | Select-Object -Unique

                foreach ($candidate in $candidatePaths) {
                    if (Test-Path $candidate) {
                        return (Resolve-Path $candidate).Path
                    }
                }
            }
        } catch {
        }
    }

    $preferredNames = @(
        "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
        "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
        "phi-3.5-mini.Q4_K_M.gguf",
        "mistral-7b.Q4_K_M.gguf",
        "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        "tinyllama.Q4_K_M.gguf"
    )

    foreach ($name in $preferredNames) {
        $candidate = Join-Path $ModelsPath $name
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $latestModel = Get-ChildItem -Path $ModelsPath -File -Filter "*.gguf" -ErrorAction SilentlyContinue |
        Sort-Object -Property @(
            @{ Expression = "Length"; Descending = $true },
            @{ Expression = "LastWriteTime"; Descending = $true }
        ) |
        Select-Object -First 1

    if ($latestModel) {
        return $latestModel.FullName
    }

    return $null
}

function Get-RoleModelPaths {
    param(
        [string]$ModelsPath,
        [object[]]$ModelCatalog,
        [string[]]$RequestedKeys
    )

    $ordered = New-Object System.Collections.Generic.List[string]
    $addPath = {
        param([string]$candidatePath)
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path $candidatePath) -and (-not $ordered.Contains($candidatePath))) {
            [void]$ordered.Add((Resolve-Path $candidatePath).Path)
        }
    }

    foreach ($key in @($RequestedKeys)) {
        $entry = $ModelCatalog | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        if ($entry) {
            & $addPath (Join-Path $ModelsPath $entry.FileName)
        }
    }

    $namedPreferenceFiles = @(
        (Join-Path $ModelsPath "preferred_model.txt"),
        (Join-Path $ModelsPath "preferred_model_logical.txt"),
        (Join-Path $ModelsPath "preferred_model_creative.txt")
    )
    foreach ($prefFile in $namedPreferenceFiles) {
        if (Test-Path $prefFile) {
            try {
                $leaf = [string](Get-Content -Path $prefFile -ErrorAction Stop | Select-Object -First 1)
                $leaf = $leaf.Trim()
                if ($leaf) {
                    & $addPath (Join-Path $ModelsPath $leaf)
                }
            } catch {
            }
        }
    }

    $fallbackOrder = @(
        "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
        "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
        "phi-3.5-mini.Q4_K_M.gguf",
        "mistral-7b.Q4_K_M.gguf",
        "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        "tinyllama.Q4_K_M.gguf"
    )
    foreach ($name in $fallbackOrder) {
        & $addPath (Join-Path $ModelsPath $name)
    }

    $remaining = Get-ChildItem -Path $ModelsPath -File -Filter "*.gguf" -ErrorAction SilentlyContinue |
        Sort-Object -Property @(
            @{ Expression = "Length"; Descending = $true },
            @{ Expression = "LastWriteTime"; Descending = $true }
        )
    foreach ($file in $remaining) {
        & $addPath $file.FullName
    }

    $logical = if ($ordered.Count -ge 1) { $ordered[0] } else { $null }
    $creative = if ($ordered.Count -ge 2) { $ordered[1] } elseif ($ordered.Count -ge 1) { $ordered[0] } else { $null }

    return [pscustomobject]@{
        LogicalPath = $logical
        CreativePath = $creative
    }
}

function SafeDownload {
    param(
        [string[]]$Urls,
        [string]$OutFile
    )

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "-> Downloading: $url (attempt $attempt/3)"
                Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec 180
                if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
                    return $url
                }
            } catch {
                Write-Host "Warning: download failed for $url" -ForegroundColor Yellow
                if ($attempt -lt 3) {
                    Start-Sleep -Seconds 2
                }
            }
        }
    }

    return $null
}

function Get-LlamaExecutable {
    param([string]$SearchRoot)

    $preferredNames = @(
        "llama-cli.exe",
        "llama-server.exe",
        "main.exe"
    )

    foreach ($name in $preferredNames) {
        $match = Get-ChildItem -Path $SearchRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

function Get-HardwareProfile {
    $cpuName = "Unknown CPU"
    $logicalCores = 0
    $totalRamGB = 0
    $gpuProfiles = @()

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        if ($cpu) {
            $cpuName = [string]$cpu.Name
            $logicalCores = [int]$cpu.NumberOfLogicalProcessors
        }
    } catch {
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($os) {
            # TotalVisibleMemorySize is in KB.
            $totalRamGB = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 1)
        }
    } catch {
    }

    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController
        foreach ($gpu in $gpus) {
            $name = [string]$gpu.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $vendor = "OTHER"
            if ($name -match "(?i)nvidia") {
                $vendor = "NVIDIA"
            } elseif ($name -match "(?i)amd|radeon") {
                $vendor = "AMD"
            } elseif ($name -match "(?i)intel") {
                $vendor = "INTEL"
            }

            $ramGB = 0
            try {
                $adapterRam = [double]$gpu.AdapterRAM
                if ($adapterRam -gt 0) {
                    $ramGB = [math]::Round(($adapterRam / 1GB), 1)
                }
            } catch {
            }

            $gpuProfiles += [pscustomobject]@{
                Name = $name
                Vendor = $vendor
                RamGB = $ramGB
            }
        }
    } catch {
    }

    $bestGpu = $gpuProfiles | Sort-Object -Property RamGB -Descending | Select-Object -First 1
    $hasNvidia = $gpuProfiles | Where-Object { $_.Vendor -eq "NVIDIA" } | Select-Object -First 1
    $hasAmd = $gpuProfiles | Where-Object { $_.Vendor -eq "AMD" } | Select-Object -First 1
    $hasIntel = $gpuProfiles | Where-Object { $_.Vendor -eq "INTEL" } | Select-Object -First 1
    $hasRtx = $gpuProfiles | Where-Object { $_.Name -match "(?i)\bRTX\b" } | Select-Object -First 1

    $recommendedRuntime = "cpu"
    $reason = "No supported GPU detected; CPU build is safer."
    if ($hasNvidia) {
        $recommendedRuntime = "cuda"
        if ($hasRtx) {
            $reason = "Detected NVIDIA RTX GPU; CUDA is usually the best-performing path."
        } else {
            $reason = "Detected NVIDIA GPU; CUDA is likely the fastest option."
        }
    } elseif ($hasAmd -or $hasIntel) {
        $recommendedRuntime = "vulkan"
        $reason = "Detected AMD/Intel GPU; Vulkan is the best available acceleration path."
    }

    return [pscustomobject]@{
        CpuName = $cpuName
        LogicalCores = $logicalCores
        TotalRamGB = $totalRamGB
        Gpus = $gpuProfiles
        BestGpu = $bestGpu
        HasNvidia = [bool]$hasNvidia
        HasAmd = [bool]$hasAmd
        HasIntel = [bool]$hasIntel
        HasRtx = [bool]$hasRtx
        RecommendedRuntime = $recommendedRuntime
        RecommendationReason = $reason
    }
}

function Get-LlamaRuntimeUrls {
    param(
        [ValidateSet("cpu", "vulkan", "cuda")]
        [string]$Runtime
    )

    $urls = @()
    try {
        $headers = @{ "User-Agent" = "IndigoInstaller/1.0" }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" -Headers $headers -TimeoutSec 60
        $assets = @($release.assets)

        if ($assets.Count -gt 0) {
            $pattern = switch ($Runtime) {
                "cpu"    { "(?i)win.*cpu.*x64.*\.zip|win.*cpu.*\.zip" }
                "vulkan" { "(?i)win.*vulkan.*x64.*\.zip|win.*vulkan.*\.zip" }
                "cuda"   { "(?i)win.*cuda.*x64.*\.zip|win.*cuda.*\.zip" }
            }

            $matched = $assets | Where-Object { $_.name -match $pattern }
            foreach ($asset in $matched) {
                if ($asset.browser_download_url) {
                    $urls += [string]$asset.browser_download_url
                }
            }
        }
    } catch {
    }

    if (-not $urls) {
        $urls = switch ($Runtime) {
            "cpu" {
                @(
                    "https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-binaries-win-cpu-x64.zip",
                    "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-cpu-x64.zip"
                )
            }
            "vulkan" {
                @(
                    "https://github.com/ggml-org/llama.cpp/releases/download/b8400/llama-b8400-bin-win-vulkan-x64.zip",
                    "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-vulkan-x64.zip"
                )
            }
            "cuda" {
                @(
                    "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-cuda-cu12.4-x64.zip",
                    "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-cuda-cu12.2-x64.zip",
                    "https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-binaries-win-cuda-cu12.2-x64.zip"
                )
            }
        }
    }

    return $urls | Select-Object -Unique
}

function Get-ModelCatalog {
    return @(
        [pscustomobject]@{
            Key = "smol"
            Name = "SmolLM2-1.7B-Instruct (Q4_K_M)"
            Purpose = "Very lightweight and fast for low-resource hardware."
            FileName = "SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
            Url = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf?download=true"
        },
        [pscustomobject]@{
            Key = "qwen"
            Name = "Qwen2.5-3B-Instruct (Q4_K_M)"
            Purpose = "Strong multilingual and instruction performance in a compact size."
            FileName = "Qwen2.5-3B-Instruct-Q4_K_M.gguf"
            Url = "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf?download=true"
        },
        [pscustomobject]@{
            Key = "phi"
            Name = "Phi-3.5-mini-instruct (Q4_K_M)"
            Purpose = "General instruction-following with good quality/size balance."
            FileName = "Phi-3.5-mini-instruct-Q4_K_M.gguf"
            Url = "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf?download=true"
        },
        [pscustomobject]@{
            Key = "llama"
            Name = "Llama-3.2-3B-Instruct (Q4_K_M)"
            Purpose = "Balanced reasoning/chat model for broad testing."
            FileName = "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
            Url = "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true"
        }
    )
}

Write-Step "[1/9] Preparing Indigo directories..."

$paths = @(
    $baseDir,
    $llamaDir,
    $modelsDir,
    $memoryDir,
    $knownNodesDir,
    $logsDir,
    $piperDir,
    $piperModelsDir,
    $whisperDir
)

foreach ($path in $paths) {
    Ensure-Directory $path
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

Write-Step "[2/9] Checking Python..."

$pythonLauncher = Find-PythonLauncher
if (-not $pythonLauncher) {
    Write-Host "Python 3.10+ is required but was not found." -ForegroundColor Red
    exit 1
}

$pythonExe = Get-PythonExePath -PythonLauncher $pythonLauncher
Write-Host "-> Using Python: $pythonExe" -ForegroundColor Green

Write-Step "[3/9] Creating or refreshing virtual environment..."

if (-not (Test-Path (Join-Path $venvDir "Scripts\python.exe"))) {
    & $pythonExe -m venv $venvDir
}

$venvPython = Join-Path $venvDir "Scripts\python.exe"
$venvPip = Join-Path $venvDir "Scripts\pip.exe"

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install flask flask-cors requests duckduckgo-search
try {
    & $venvPython -m pip install piper-tts pathvalidate
} catch {
    Write-Host "Warning: pip-based Piper install failed. Installer will continue and try binary runtime download." -ForegroundColor Yellow
}

Write-Step "[4/9] Checking Piper voice runtime..."

if (-not (Test-Path $piperExePath) -and -not (Test-Path $venvPiperExePath)) {
    $piperUrls = @(
        "https://github.com/rhasspy/piper/releases/latest/download/piper_windows_amd64.zip",
        "https://github.com/rhasspy/piper/releases/latest/download/piper_windows_x64.zip"
    )
    $piperDownload = SafeDownload -Urls $piperUrls -OutFile $piperZip
    if ($piperDownload) {
        Expand-Archive -Path $piperZip -DestinationPath $piperDir -Force
        Remove-Item $piperZip -Force -ErrorAction SilentlyContinue

        $foundPiperExe = Get-ChildItem -Path $piperDir -Recurse -File -Filter "piper.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundPiperExe -and ($foundPiperExe.FullName -ne $piperExePath)) {
            Copy-Item -Path $foundPiperExe.FullName -Destination $piperExePath -Force
        }
    } else {
        Write-Host "Warning: Piper runtime download failed. Voice will be disabled unless piper.exe is placed in $piperDir." -ForegroundColor Yellow
    }
}

if (-not (Test-Path $piperModelPath)) {
    $voiceModelUrls = @(
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/cori/medium/en_GB-cori-medium.onnx?download=true",
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx?download=true"
    )
    $voiceModelDownload = SafeDownload -Urls $voiceModelUrls -OutFile $piperModelPath
    if (-not $voiceModelDownload) {
        Write-Host "Warning: Piper voice model download failed. Voice will be disabled unless model is added manually." -ForegroundColor Yellow
    }
}

if (-not (Test-Path $piperModelJsonPath)) {
    try {
        Invoke-WebRequest -Uri "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/cori/medium/en_GB-cori-medium.onnx.json?download=true" -OutFile $piperModelJsonPath -UseBasicParsing -TimeoutSec 120
    } catch {
        try {
            Invoke-WebRequest -Uri "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx.json?download=true" -OutFile $piperModelJsonPath -UseBasicParsing -TimeoutSec 120
        } catch {
            Write-Host "Warning: Piper model metadata (.json) download failed." -ForegroundColor Yellow
        }
    }
}

$resolvedPiperExe = @($piperExePath, $venvPiperExePath) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($resolvedPiperExe) {
    Write-Host "-> Piper runtime found: $resolvedPiperExe" -ForegroundColor Green
} else {
    Write-Host "Warning: Piper runtime not found. Install piper.exe in $piperDir or via venv Scripts." -ForegroundColor Yellow
}

if (Test-Path $piperModelPath) {
    Write-Host "-> Piper model found: $piperModelPath" -ForegroundColor Green
}

Write-Step "[5/9] Checking llama.cpp runtime..."

$existingExe = Get-LlamaExecutable -SearchRoot $llamaDir

if (-not $existingExe) {
    Write-Host "No llama executable found in $llamaDir" -ForegroundColor Yellow
    $hardware = Get-HardwareProfile
    Write-Host "-> Detected CPU: $($hardware.CpuName)"
    if ($hardware.LogicalCores -gt 0) {
        Write-Host "-> Logical cores: $($hardware.LogicalCores)"
    }
    if ($hardware.TotalRamGB -gt 0) {
        Write-Host "-> System RAM: $($hardware.TotalRamGB) GB"
    }

    if ($hardware.Gpus.Count -gt 0) {
        Write-Host "-> Detected GPU(s):"
        foreach ($gpu in $hardware.Gpus) {
            $ramLabel = if ($gpu.RamGB -gt 0) { "$($gpu.RamGB) GB" } else { "unknown VRAM" }
            Write-Host "   - $($gpu.Name) [$($gpu.Vendor), $ramLabel]"
        }
    } else {
        Write-Host "-> Detected GPU(s): none"
    }

    $autoChoice = switch ($hardware.RecommendedRuntime) {
        "cuda"   { "4" }
        "vulkan" { "3" }
        default  { "2" }
    }
    $autoLabel = switch ($autoChoice) {
        "4" { "CUDA" }
        "3" { "Vulkan" }
        default { "CPU" }
    }
    Write-Host "Auto recommendation: $autoLabel" -ForegroundColor Green
    Write-Host "Reason: $($hardware.RecommendationReason)"

    Write-Host "1 = Keep current folder and skip runtime download"
    Write-Host "2 = Download CPU build"
    Write-Host "3 = Download Vulkan build"
    Write-Host "4 = Download CUDA build (NVIDIA)"
    $runtimeChoiceInput = Read-Host "Choose 1, 2, 3, or 4 (press Enter for Auto: $autoLabel)"
    if ([string]::IsNullOrWhiteSpace($runtimeChoiceInput)) {
        $runtimeChoice = $autoChoice
    } else {
        $runtimeChoice = $runtimeChoiceInput.Trim()
    }

    if ($runtimeChoice -notin @("1", "2", "3", "4")) {
        Write-Host "Warning: invalid choice '$runtimeChoice'. Using Auto: $autoLabel." -ForegroundColor Yellow
        $runtimeChoice = $autoChoice
    }

    if ($runtimeChoice -ne "1") {
        $cpuUrls = Get-LlamaRuntimeUrls -Runtime "cpu"
        $vulkanUrls = Get-LlamaRuntimeUrls -Runtime "vulkan"
        $cudaUrls = Get-LlamaRuntimeUrls -Runtime "cuda"

        $candidateUrls = switch ($runtimeChoice) {
            "4" { $cudaUrls }
            "3" { $vulkanUrls }
            default { $cpuUrls }
        }
        $downloadedFrom = SafeDownload -Urls $candidateUrls -OutFile $llamaZip

        if ((-not $downloadedFrom) -and ($runtimeChoice -eq "4")) {
            Write-Host "Warning: CUDA runtime download failed. Falling back to Vulkan build..." -ForegroundColor Yellow
            $runtimeChoice = "3"
            $downloadedFrom = SafeDownload -Urls $vulkanUrls -OutFile $llamaZip
        }

        if ((-not $downloadedFrom) -and ($runtimeChoice -eq "3")) {
            Write-Host "Warning: Vulkan runtime download failed. Falling back to CPU build..." -ForegroundColor Yellow
            $runtimeChoice = "2"
            $downloadedFrom = SafeDownload -Urls $cpuUrls -OutFile $llamaZip
        }

        if (-not $downloadedFrom) {
            Write-Host "Failed to download llama.cpp runtime." -ForegroundColor Red
            exit 1
        }

        $runtimeLabel = switch ($runtimeChoice) {
            "4" { "CUDA" }
            "3" { "Vulkan" }
            default { "CPU" }
        }
        Write-Host "-> Selected runtime: $runtimeLabel" -ForegroundColor Green
        Write-Host "-> Runtime downloaded from: $downloadedFrom" -ForegroundColor Green

        $staleBinaries = Get-ChildItem -Path $llamaDir -File -Include *.exe,*.dll -ErrorAction SilentlyContinue
        foreach ($file in $staleBinaries) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }

        Expand-Archive $llamaZip -DestinationPath $llamaDir -Force
        Remove-Item $llamaZip -Force -ErrorAction SilentlyContinue
        $existingExe = Get-LlamaExecutable -SearchRoot $llamaDir
    }
}

if (-not $existingExe) {
    Write-Host "Still no usable llama executable found. Repair installer cannot continue." -ForegroundColor Red
    exit 1
}

Write-Host "-> Runtime executable: $existingExe" -ForegroundColor Green

Write-Step "[6/9] Selecting GGUF model variants..."

$modelCatalog = Get-ModelCatalog
$defaultModelKey = "smol"
$defaultModelSelection = "smol,qwen"
$preferredModelFile = $preferredModelPath
$preferredLogicalFile = $preferredLogicalModelPath
$preferredCreativeFile = $preferredCreativeModelPath

Write-Host "Available model variants:" -ForegroundColor White
for ($i = 0; $i -lt $modelCatalog.Count; $i++) {
    $model = $modelCatalog[$i]
    Write-Host ("- {0} / {1}: {2}" -f ($i + 1), $model.Key, $model.Name) -ForegroundColor Gray
    Write-Host ("  Purpose: {0}" -f $model.Purpose) -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "Selection tips:" -ForegroundColor White
Write-Host "- Press Enter to use default pair: $defaultModelSelection" -ForegroundColor Gray
Write-Host "- Enter multiple keys with commas (example: smol,qwen)" -ForegroundColor Gray
Write-Host "- Numeric indexes also work (example: 2,3)" -ForegroundColor Gray
Write-Host "- Enter 'existing' to skip downloads and keep current models" -ForegroundColor Gray

$selectionInput = Read-Host "Model selection"
$selectionRaw = if ([string]::IsNullOrWhiteSpace($selectionInput)) { $defaultModelSelection } else { $selectionInput.Trim().ToLower() }

$selectedModel = $null
$selectedModelKey = $null
$requestedKeyOrder = New-Object System.Collections.Generic.List[string]

if ($selectionRaw -eq "existing") {
    Write-Host "-> Keeping existing models only." -ForegroundColor Green
} else {
    $requestedTokens = @(
        $selectionRaw -split "," |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ) | Select-Object -Unique

    $validModels = New-Object System.Collections.Generic.List[object]
    foreach ($token in $requestedTokens) {
        $key = $token
        if ($token -match "^\d+$") {
            $index = [int]$token
            if (($index -ge 1) -and ($index -le $modelCatalog.Count)) {
                $key = $modelCatalog[$index - 1].Key
            }
        }

        $match = $modelCatalog | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        if ($match) {
            if (-not ($requestedKeyOrder -contains $match.Key)) {
                [void]$requestedKeyOrder.Add($match.Key)
            }
            if (-not ($validModels | Where-Object { $_.Key -eq $match.Key } | Select-Object -First 1)) {
                [void]$validModels.Add($match)
            }
        } else {
            Write-Host "Warning: unknown model token '$token' (ignored)." -ForegroundColor Yellow
        }
    }

    if ($validModels.Count -eq 0) {
        $fallback = $modelCatalog | Where-Object { $_.Key -eq $defaultModelKey } | Select-Object -First 1
        if ($fallback) {
            [void]$validModels.Add($fallback)
            [void]$requestedKeyOrder.Add($fallback.Key)
            Write-Host "-> Falling back to default model: $($fallback.Name)" -ForegroundColor Yellow
        }
    }

    foreach ($model in $validModels) {
        $targetPath = Join-Path $modelsDir $model.FileName
        if ((Test-Path $targetPath) -and ((Get-Item $targetPath).Length -gt 0)) {
            Write-Host "-> Model already present: $($model.FileName)" -ForegroundColor Green
        } else {
            Write-Host "-> Downloading $($model.Name)..." -ForegroundColor White
            $downloadedFrom = SafeDownload -Urls @($model.Url) -OutFile $targetPath
            if (-not $downloadedFrom) {
                Write-Host "Warning: failed to download $($model.Name)." -ForegroundColor Yellow
                Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "-> Downloaded from: $downloadedFrom" -ForegroundColor DarkGray
            }
        }

        if ((-not $selectedModel) -and (Test-Path $targetPath)) {
            $selectedModel = (Resolve-Path $targetPath).Path
            $selectedModelKey = $model.Key
        }
    }
}

if (-not $selectedModel) {
    $selectedModel = Get-PreferredModelPath -ModelsPath $modelsDir
    if ($selectedModel) {
        $selectedLeaf = Split-Path $selectedModel -Leaf
        $selectedEntry = $modelCatalog | Where-Object { $_.FileName -eq $selectedLeaf } | Select-Object -First 1
        if ($selectedEntry) {
            $selectedModelKey = $selectedEntry.Key
        }
    }
}

$roleModels = Get-RoleModelPaths -ModelsPath $modelsDir -ModelCatalog $modelCatalog -RequestedKeys @($requestedKeyOrder)
$logicalModel = $roleModels.LogicalPath
$creativeModel = $roleModels.CreativePath

if ($logicalModel) {
    $selectedModel = $logicalModel
    $selectedLeaf = Split-Path $selectedModel -Leaf
    Set-Content -Path $preferredModelFile -Value $selectedLeaf -Encoding ascii
    Set-Content -Path $preferredLogicalFile -Value (Split-Path $logicalModel -Leaf) -Encoding ascii
    if ($creativeModel) {
        Set-Content -Path $preferredCreativeFile -Value (Split-Path $creativeModel -Leaf) -Encoding ascii
    }

    Write-Host "-> Preferred model: $selectedModel" -ForegroundColor Green
    if ($selectedModelKey) {
        Write-Host "-> Preferred key: $selectedModelKey" -ForegroundColor DarkGreen
    }
    Write-Host "-> Logical model: $logicalModel" -ForegroundColor Green
    if ($creativeModel) {
        Write-Host "-> Creative model: $creativeModel" -ForegroundColor Green
    }
    if ($creativeModel -and ($logicalModel -ne $creativeModel)) {
        Write-Host "-> Conductor mode: dual-model (logical + creative)." -ForegroundColor DarkGreen
    } elseif ($logicalModel) {
        Write-Host "-> Conductor mode: single-model fallback (same model for both roles)." -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: no .gguf model found yet in $modelsDir" -ForegroundColor Yellow
}

Write-Step "[7/9] Repairing node identity and launchers..."

if (-not (Test-Path $nodeIdPath)) {
    [guid]::NewGuid().ToString() | Set-Content -Path $nodeIdPath -Encoding ascii
}

$runBat = @"
@echo off
title INDIGO ALPHA SEVEN - NODE
echo.
echo   INDIGO ALPHA SEVEN - NODE
echo   A seed intelligence awakens...
echo.
cd /d C:\indigo
call venv\Scripts\activate.bat
echo [OK] Python environment loaded
echo [OK] Neural pathways initialized
for /f %%i in (node_id.txt) do set NODE_ID=%%i
echo [OK] Node ID: %NODE_ID%
echo.
echo Indy is ready
echo Web interface: http://127.0.0.1:5000
echo.
python app.py
pause
"@

$runWebBat = @"
@echo off
cd /d C:\indigo
call venv\Scripts\activate.bat
python app.py
pause
"@

$checkModel = @"
# Model fallback checker
`$modelsPath = 'C:\indigo\models'
`$preferredFile = Join-Path `$modelsPath 'preferred_model.txt'

if (Test-Path `$preferredFile) {
    `$preferred = [string](Get-Content -Path `$preferredFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    `$preferred = `$preferred.Trim()
    if (`$preferred) {
        `$preferredPath = Join-Path `$modelsPath `$preferred
        if (Test-Path `$preferredPath) {
            Write-Host ('Using preferred model: ' + (Split-Path `$preferredPath -Leaf)) -ForegroundColor Green
            Write-Host ('Path: ' + (Resolve-Path `$preferredPath).Path) -ForegroundColor DarkGreen
            return
        }
    }
}

`$models = Get-ChildItem -Path `$modelsPath -File -Filter '*.gguf' -ErrorAction SilentlyContinue |
    Sort-Object -Property @(
        @{ Expression = "Length"; Descending = `$true },
        @{ Expression = "LastWriteTime"; Descending = `$true }
    )

if (`$models) {
    Write-Host ('Using model: ' + `$models[0].Name) -ForegroundColor Green
    Write-Host ('Path: ' + `$models[0].FullName) -ForegroundColor DarkGreen
} else {
    Write-Host 'No GGUF model found in C:\indigo\models' -ForegroundColor Red
    Write-Host 'Add a model, then run Indigo again.' -ForegroundColor Yellow
}
"@

Set-Content -Path $runBatPath -Value $runBat -Encoding ascii
Set-Content -Path $runWebBatPath -Value $runWebBat -Encoding ascii
Set-Content -Path $checkModelPath -Value $checkModel -Encoding utf8

Write-Step "[8/9] Writing stable default app files..."

Backup-FileIfExists -Path $appPath
Backup-FileIfExists -Path $brainPath
Backup-FileIfExists -Path $readmePath
Backup-FileIfExists -Path $survivalToolsPath
Backup-FileIfExists -Path $survivalRunnerPath

$appCode = @'
from threading import Lock

from flask import Flask, jsonify, render_template_string, request
from flask_cors import CORS
from brain import (
    broadcast_presence,
    get_node_info,
    get_reasoning_trace,
    process_message,
    text_to_speech,
)

app = Flask(__name__)
CORS(app)
chat_lock = Lock()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>INDIGO ALPHA SEVEN - NODE</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --bg: #10131a;
            --text: #dcecff;
            --muted: #9ab4d5;
            --container-bg: #1a2230;
            --container-border: #7dc4ff44;
            --container-shadow: #73c7ff2b;
            --panel-bg: #202b3a;
            --panel-border: #84bff944;
            --accent: #86c6ff;
            --accent-strong: #b6dcff;
            --accent-contrast: #091320;
            --bubble-user-bg: #6bb8ff33;
            --bubble-user-text: #f6fbff;
            --bubble-indy-bg: #26374f;
            --bubble-indy-text: #deeeff;
            --reason-bg: #162030;
            --voice-accent: #8cc2ff;
            --voice-accent-contrast: #0c1a2a;
        }
        body.theme-covert {
            --bg: #140708;
            --text: #ffd7d7;
            --muted: #d39b9b;
            --container-bg: #220d10;
            --container-border: #ff59594d;
            --container-shadow: #ff474729;
            --panel-bg: #2a1216;
            --panel-border: #ff6d6d3f;
            --accent: #ff7f7f;
            --accent-strong: #ffb6b6;
            --accent-contrast: #1b0607;
            --bubble-user-bg: #ff7c7c30;
            --bubble-user-text: #fff6f6;
            --bubble-indy-bg: #3b1a1f;
            --bubble-indy-text: #ffd7d7;
            --reason-bg: #1f0f12;
            --voice-accent: #ffc163;
            --voice-accent-contrast: #2a1904;
        }
        body.theme-aero {
            --bg: #10131a;
            --text: #dcecff;
            --muted: #9ab4d5;
            --container-bg: #1a2230;
            --container-border: #7dc4ff44;
            --container-shadow: #73c7ff2b;
            --panel-bg: #202b3a;
            --panel-border: #84bff944;
            --accent: #86c6ff;
            --accent-strong: #b6dcff;
            --accent-contrast: #091320;
            --bubble-user-bg: #6bb8ff33;
            --bubble-user-text: #f6fbff;
            --bubble-indy-bg: #26374f;
            --bubble-indy-text: #deeeff;
            --reason-bg: #162030;
            --voice-accent: #8cc2ff;
            --voice-accent-contrast: #0c1a2a;
        }
        body.theme-n64 {
            --bg: #17142b;
            --text: #ffe2a6;
            --muted: #d2c19b;
            --container-bg: #1f2d68;
            --container-border: #ffb3474d;
            --container-shadow: #5d8dff30;
            --panel-bg: #243679;
            --panel-border: #ffb3474f;
            --accent: #ffb347;
            --accent-strong: #ffd08a;
            --accent-contrast: #1e2f6d;
            --bubble-user-bg: #ffb34733;
            --bubble-user-text: #fff7e8;
            --bubble-indy-bg: #2f4a9a;
            --bubble-indy-text: #ffe7bb;
            --reason-bg: #1a2a5f;
            --voice-accent: #87dbff;
            --voice-accent-contrast: #0c2231;
        }
        body.theme-army {
            --bg: #0f1410;
            --text: #d5e7c9;
            --muted: #9eb091;
            --container-bg: #1a2519;
            --container-border: #7f9b6a4e;
            --container-shadow: #607a4d2a;
            --panel-bg: #223021;
            --panel-border: #8fac7345;
            --accent: #a4c17f;
            --accent-strong: #c0d89a;
            --accent-contrast: #10180f;
            --bubble-user-bg: #8caf6d2f;
            --bubble-user-text: #f2f9ea;
            --bubble-indy-bg: #2b3a2b;
            --bubble-indy-text: #d9eac9;
            --reason-bg: #172117;
            --voice-accent: #d1af65;
            --voice-accent-contrast: #2c2008;
        }
        body {
            background: var(--bg);
            color: var(--text);
            font-family: "Courier New", monospace;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
            transition: background 0.25s ease, color 0.25s ease;
        }
        .container {
            width: 100%;
            max-width: 1180px;
            background: var(--container-bg);
            border: 2px solid var(--container-border);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 0 30px var(--container-shadow);
            transition: background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease;
        }
        .header {
            text-align: center;
            margin-bottom: 24px;
            border-bottom: 1px solid var(--panel-border);
            padding-bottom: 20px;
        }
        .header h1 {
            font-size: 2.4rem;
            letter-spacing: 0.3rem;
            color: var(--accent-strong);
            text-shadow: 0 0 12px var(--container-shadow);
        }
        .subtitle {
            color: var(--muted);
            margin-top: 10px;
        }
        .theme-bar {
            display: flex;
            align-items: center;
            gap: 8px;
            flex-wrap: wrap;
            margin-bottom: 14px;
            padding: 10px 12px;
            border: 1px solid var(--panel-border);
            border-radius: 12px;
            background: var(--panel-bg);
        }
        .theme-label {
            color: var(--muted);
            margin-right: 4px;
        }
        .theme-btn {
            padding: 7px 12px;
            border-radius: 999px;
            border: 1px solid var(--accent);
            background: transparent;
            color: var(--accent);
            font-size: 0.82rem;
        }
        .theme-btn.active,
        .theme-btn:hover {
            background: var(--accent);
            color: var(--accent-contrast);
        }
        .node-info, .chat-container, .reason-panel {
            background: var(--panel-bg);
            border: 1px solid var(--panel-border);
            border-radius: 14px;
        }
        .node-info {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 12px;
            padding: 14px 16px;
            margin-bottom: 18px;
        }
        .workspace {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(300px, 1fr);
            gap: 16px;
            margin-bottom: 18px;
        }
        .chat-container {
            padding: 18px;
        }
        #chat {
            height: 400px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 14px;
        }
        .reason-panel {
            padding: 16px;
        }
        .reason-title {
            font-size: 0.95rem;
            letter-spacing: 0.1rem;
            color: var(--accent-strong);
            margin-bottom: 10px;
        }
        .waterfall-wrap {
            border: 1px solid var(--panel-border);
            border-radius: 10px;
            background: var(--reason-bg);
            padding: 8px;
            margin-bottom: 10px;
        }
        #reasoningWaterfall {
            width: 100%;
            height: 140px;
            display: block;
            border-radius: 6px;
            image-rendering: pixelated;
        }
        .waterfall-meta {
            margin-top: 6px;
            color: var(--muted);
            font-size: 0.72rem;
            letter-spacing: 0.03rem;
        }
        #reasoning {
            height: 250px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .reason-item {
            border: 1px solid var(--panel-border);
            border-radius: 10px;
            background: var(--reason-bg);
            padding: 8px 10px;
        }
        .reason-stage {
            font-size: 0.72rem;
            text-transform: uppercase;
            color: var(--accent);
            letter-spacing: 0.08rem;
            margin-bottom: 3px;
        }
        .reason-detail {
            font-size: 0.84rem;
            color: var(--text);
            line-height: 1.25rem;
            white-space: pre-wrap;
        }
        .reason-time {
            margin-top: 4px;
            font-size: 0.7rem;
            color: var(--muted);
        }
        .message {
            display: flex;
            flex-direction: column;
            max-width: 82%;
        }
        .message.user {
            align-self: flex-end;
        }
        .message.indy {
            align-self: flex-start;
        }
        .message-content {
            padding: 12px 16px;
            border-radius: 18px;
            line-height: 1.45;
            white-space: pre-wrap;
        }
        .user .message-content {
            background: var(--bubble-user-bg);
            border: 1px solid var(--accent);
            color: var(--bubble-user-text);
            border-bottom-right-radius: 4px;
        }
        .indy .message-content {
            background: var(--bubble-indy-bg);
            border: 1px solid var(--panel-border);
            color: var(--bubble-indy-text);
            border-bottom-left-radius: 4px;
        }
        .timestamp {
            margin-top: 4px;
            padding: 0 8px;
            font-size: 0.72rem;
            color: var(--muted);
        }
        .input-area {
            display: flex;
            gap: 12px;
            background: var(--panel-bg);
            border-radius: 999px;
            padding: 10px;
            border: 1px solid var(--panel-border);
        }
        #msg {
            flex: 1;
            background: transparent;
            border: none;
            color: var(--text);
            font-family: inherit;
            font-size: 1rem;
            padding: 10px 14px;
            outline: none;
        }
        #msg::placeholder {
            color: var(--muted);
        }
        button {
            background: transparent;
            border: 1px solid var(--accent);
            color: var(--accent);
            border-radius: 999px;
            padding: 10px 20px;
            font-family: inherit;
            cursor: pointer;
        }
        button:hover {
            background: var(--accent);
            color: var(--accent-contrast);
        }
        .voice-btn {
            border-color: var(--voice-accent);
            color: var(--voice-accent);
        }
        .voice-btn:hover {
            background: var(--voice-accent);
            color: var(--voice-accent-contrast);
        }
        .status {
            margin-top: 18px;
            text-align: center;
            color: var(--muted);
            font-size: 0.9rem;
        }
        @media (max-width: 980px) {
            .workspace {
                grid-template-columns: 1fr;
            }
            #reasoning, #chat {
                height: 300px;
            }
            #reasoningWaterfall {
                height: 120px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>INDIGO</h1>
            <div class="subtitle">ALPHA SEVEN - NODE <span id="nodeId"></span></div>
        </div>
        <div class="theme-bar">
            <span class="theme-label">Themes:</span>
            <button class="theme-btn" data-theme="theme-covert" onclick="setTheme('theme-covert')">Covert Red</button>
            <button class="theme-btn" data-theme="theme-aero" onclick="setTheme('theme-aero')">Aero</button>
            <button class="theme-btn" data-theme="theme-n64" onclick="setTheme('theme-n64')">N64</button>
            <button class="theme-btn" data-theme="theme-army" onclick="setTheme('theme-army')">Army</button>
        </div>
        <div class="node-info">
            <span><span id="nodeCount">0</span> other seed(s) nearby</span>
            <button onclick="broadcastNode()">Broadcast presence</button>
        </div>
        <div class="workspace">
            <div class="chat-container">
                <div id="chat"></div>
            </div>
            <div class="reason-panel">
                <div class="reason-title">Reasoning Feed <span id="thinkingBadge"></span></div>
                <div class="waterfall-wrap">
                    <canvas id="reasoningWaterfall"></canvas>
                    <div class="waterfall-meta">SDR-style trace: new rows represent the latest reasoning pulse.</div>
                </div>
                <div id="reasoning"></div>
            </div>
        </div>
        <div class="input-area">
            <input id="msg" type="text" placeholder="Ask me anything, mate..." autocomplete="off">
            <button id="sendBtn" onclick="sendMessage()">Send</button>
            <button class="voice-btn" onclick="speakLast()">Voice</button>
        </div>
        <div class="status" id="status">Seed intelligence active | Local node online</div>
    </div>

    <script>
        const THEMES = ["theme-covert", "theme-aero", "theme-n64", "theme-army"];
        const WATERFALL_BINS = 72;
        let awaitingReply = false;
        let reasoningGeneration = null;
        let waterfallCanvas = null;
        let waterfallCtx = null;
        let lastWaterfallGeneration = null;
        let waterfallResizeTimer = null;

        function updateThemeButtons(activeTheme) {
            const buttons = document.querySelectorAll(".theme-btn");
            buttons.forEach((btn) => {
                if (btn.dataset.theme === activeTheme) {
                    btn.classList.add("active");
                } else {
                    btn.classList.remove("active");
                }
            });
        }

        function setTheme(themeName) {
            const safeTheme = THEMES.includes(themeName) ? themeName : "theme-aero";
            document.body.classList.remove(...THEMES);
            document.body.classList.add(safeTheme);
            localStorage.setItem("indigo_theme", safeTheme);
            updateThemeButtons(safeTheme);
            setTimeout(initWaterfall, 0);
        }

        function setStatus(text) {
            document.getElementById("status").textContent = text;
        }

        function setThinkingState(thinking) {
            awaitingReply = thinking;
            const input = document.getElementById("msg");
            const sendBtn = document.getElementById("sendBtn");
            input.disabled = thinking;
            sendBtn.disabled = thinking;
            document.getElementById("thinkingBadge").textContent = thinking ? "(thinking...)" : "";
        }

        function addMessage(text, sender) {
            const chat = document.getElementById("chat");
            const wrapper = document.createElement("div");
            wrapper.className = "message " + sender;

            const bubble = document.createElement("div");
            bubble.className = "message-content";
            bubble.textContent = text;

            const stamp = document.createElement("div");
            stamp.className = "timestamp";
            stamp.textContent = new Date().toLocaleTimeString();

            wrapper.appendChild(bubble);
            wrapper.appendChild(stamp);
            chat.appendChild(wrapper);
            chat.scrollTop = chat.scrollHeight;
        }

        function renderReasoning(entries) {
            const panel = document.getElementById("reasoning");
            panel.innerHTML = "";
            const shown = entries.slice(-80);
            for (const entry of shown) {
                const item = document.createElement("div");
                item.className = "reason-item";

                const stage = document.createElement("div");
                stage.className = "reason-stage";
                stage.textContent = entry.stage || "step";

                const detail = document.createElement("div");
                detail.className = "reason-detail";
                detail.textContent = entry.detail || "";

                const when = document.createElement("div");
                when.className = "reason-time";
                when.textContent = entry.ts || "";

                item.appendChild(stage);
                item.appendChild(detail);
                item.appendChild(when);
                panel.appendChild(item);
            }
            panel.scrollTop = panel.scrollHeight;
        }

        function hashString(text) {
            let hash = 0;
            const value = text || "";
            for (let i = 0; i < value.length; i++) {
                hash = ((hash << 5) - hash) + value.charCodeAt(i);
                hash |= 0;
            }
            return hash;
        }

        function stageColor(stage, inProgress) {
            const key = (stage || "step").toLowerCase();
            const palette = {
                input: [77, 201, 255],
                decision: [255, 203, 77],
                route: [105, 152, 255],
                llm: [98, 255, 167],
                logical_output: [255, 121, 232],
                creative_output: [255, 161, 87],
                blend: [177, 120, 255],
                output: [240, 245, 255],
                step: [123, 198, 255],
            };
            const base = palette[key] || palette.step;
            if (inProgress) {
                return [
                    Math.min(255, base[0] + 16),
                    Math.min(255, base[1] + 16),
                    Math.min(255, base[2] + 16),
                ];
            }
            return base;
        }

        function initWaterfall() {
            waterfallCanvas = document.getElementById("reasoningWaterfall");
            if (!waterfallCanvas) return;
            const ratio = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
            const width = Math.max(280, Math.floor(waterfallCanvas.clientWidth * ratio));
            const height = Math.max(100, Math.floor(waterfallCanvas.clientHeight * ratio));
            if (waterfallCanvas.width !== width || waterfallCanvas.height !== height) {
                waterfallCanvas.width = width;
                waterfallCanvas.height = height;
            }
            waterfallCtx = waterfallCanvas.getContext("2d", { alpha: false });
            waterfallCtx.fillStyle = "#04070d";
            waterfallCtx.fillRect(0, 0, waterfallCanvas.width, waterfallCanvas.height);
            lastWaterfallGeneration = null;
        }

        function drawWaterfallRow(entries, inProgress, generation) {
            if (!waterfallCtx || !waterfallCanvas) return;
            const w = waterfallCanvas.width;
            const h = waterfallCanvas.height;

            waterfallCtx.drawImage(waterfallCanvas, 0, 1, w, h - 1, 0, 0, w, h - 1);
            waterfallCtx.fillStyle = "rgba(4, 7, 12, 0.96)";
            waterfallCtx.fillRect(0, h - 1, w, 1);

            if (lastWaterfallGeneration !== generation) {
                lastWaterfallGeneration = generation;
                waterfallCtx.fillStyle = "rgba(255, 255, 255, 0.55)";
                waterfallCtx.fillRect(0, h - 1, w, 1);
            }

            const bins = Array.from({ length: WATERFALL_BINS }, () => ({ r: 0, g: 0, b: 0, e: 0 }));
            const snapshot = (entries || []).slice(-24);

            for (const entry of snapshot) {
                const stage = entry.stage || "step";
                const detail = entry.detail || "";
                const [sr, sg, sb] = stageColor(stage, inProgress);
                const index = Math.abs(hashString(stage + "|" + detail)) % WATERFALL_BINS;
                const spread = 1 + (Math.abs(hashString(detail)) % 3);
                const strength = Math.min(1, 0.3 + (detail.length / 220));

                for (let offset = -spread; offset <= spread; offset++) {
                    const bucket = (index + offset + WATERFALL_BINS) % WATERFALL_BINS;
                    const decay = 1 - (Math.abs(offset) / (spread + 1));
                    const energy = strength * decay;
                    bins[bucket].r += sr * energy;
                    bins[bucket].g += sg * energy;
                    bins[bucket].b += sb * energy;
                    bins[bucket].e += energy;
                }
            }

            const binWidth = w / WATERFALL_BINS;
            for (let i = 0; i < WATERFALL_BINS; i++) {
                const b = bins[i];
                if (b.e <= 0) continue;
                const norm = Math.min(1, b.e / 2.2);
                const r = Math.min(255, Math.round(b.r / b.e));
                const g = Math.min(255, Math.round(b.g / b.e));
                const bl = Math.min(255, Math.round(b.b / b.e));
                const x = Math.floor(i * binWidth);
                const width = Math.ceil(binWidth + 1);
                waterfallCtx.fillStyle = `rgba(${r}, ${g}, ${bl}, ${Math.max(0.09, norm)})`;
                waterfallCtx.fillRect(x, h - 1, width, 1);
            }

            if (inProgress) {
                const sweep = Math.floor((Date.now() / 80) % w);
                waterfallCtx.fillStyle = "rgba(255, 255, 255, 0.33)";
                waterfallCtx.fillRect(sweep, h - 1, 2, 1);
            }
        }

        async function refreshReasoning() {
            try {
                const res = await fetch("/reasoning");
                const data = await res.json();
                if (reasoningGeneration !== data.generation) {
                    reasoningGeneration = data.generation;
                    renderReasoning(data.entries || []);
                } else {
                    renderReasoning(data.entries || []);
                }
                drawWaterfallRow(data.entries || [], !!data.in_progress, data.generation);
                if (!awaitingReply) {
                    document.getElementById("thinkingBadge").textContent = data.in_progress ? "(thinking...)" : "";
                }
            } catch (_) {
            }
        }

        async function refreshNodeInfo() {
            const res = await fetch("/node_info");
            const data = await res.json();
            document.getElementById("nodeId").textContent = data.node_id.slice(0, 8);
            document.getElementById("nodeCount").textContent = data.known_nodes.length;
        }

        async function sendMessage() {
            if (awaitingReply) return;
            const input = document.getElementById("msg");
            const message = input.value.trim();
            if (!message) return;

            addMessage(message, "user");
            input.value = "";
            setStatus("Thinking...");
            setThinkingState(true);
            await refreshReasoning();

            try {
                const res = await fetch("/chat", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ message })
                });
                const data = await res.json();
                if (res.status === 429) {
                    setStatus(data.error || "Hold on, I am still thinking...");
                    return;
                }
                addMessage(data.response || data.error || "No response", "indy");
                setStatus("Seed intelligence active | Local node online");
            } catch (_) {
                setStatus("Request failed; check local server.");
            } finally {
                setThinkingState(false);
                await refreshReasoning();
            }
        }

        async function broadcastNode() {
            await fetch("/broadcast", { method: "POST" });
            setStatus("Presence broadcast sent");
            refreshNodeInfo();
        }

        async function speakLast() {
            setStatus("Speaking...");
            await fetch("/speak_last", { method: "POST" });
            setStatus("Seed intelligence active | Local node online");
        }

        document.getElementById("msg").addEventListener("keydown", function (event) {
            if (event.key === "Enter") {
                sendMessage();
            }
        });

        window.addEventListener("resize", function () {
            clearTimeout(waterfallResizeTimer);
            waterfallResizeTimer = setTimeout(initWaterfall, 120);
        });

        const savedTheme = localStorage.getItem("indigo_theme") || "theme-aero";
        setTheme(savedTheme);
        initWaterfall();
        refreshNodeInfo();
        refreshReasoning();
        setInterval(refreshNodeInfo, 15000);
        setInterval(refreshReasoning, 1200);
    </script>
</body>
</html>
"""


@app.get("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.get("/node_info")
def node_info():
    return jsonify(get_node_info())


@app.post("/broadcast")
def broadcast():
    broadcast_presence()
    return jsonify({"ok": True})


@app.post("/chat")
def chat():
    payload = request.get_json(silent=True) or {}
    prompt = str(payload.get("message", "")).strip()
    if not prompt:
        return jsonify({"error": "Request JSON must include a non-empty 'message' field."}), 400

    if not chat_lock.acquire(blocking=False):
        return jsonify({"error": "Hold on, I am still thinking..."}), 429

    try:
        return jsonify({"response": process_message(prompt)})
    finally:
        chat_lock.release()


@app.get("/reasoning")
def reasoning():
    return jsonify(get_reasoning_trace())


@app.post("/speak_last")
def speak_last():
    ok = text_to_speech("Righto mate, voice output is online.")
    return jsonify({"ok": bool(ok)})


@app.get("/health")
def health():
    info = get_node_info()
    return jsonify({"status": "ok", **info})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
'@

$brainCode = @'
import json
import os
import socket
import struct
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path

from duckduckgo_search import DDGS

BASE_DIR = Path(r"C:\indigo")
MODELS_DIR = BASE_DIR / "models"
PREFERRED_MODEL_FILE = MODELS_DIR / "preferred_model.txt"
PREFERRED_LOGICAL_MODEL_FILE = MODELS_DIR / "preferred_model_logical.txt"
PREFERRED_CREATIVE_MODEL_FILE = MODELS_DIR / "preferred_model_creative.txt"
MEMORY_DIR = BASE_DIR / "memory"
NODES_DIR = BASE_DIR / "known_nodes"
LOGS_DIR = BASE_DIR / "logs"
LLAMA_DIR = BASE_DIR / "llama.cpp"
PIPER_DIR = BASE_DIR / "piper"
PIPER_MODELS_DIR = BASE_DIR / "piper_models"

NODE_ID_FILE = BASE_DIR / "node_id.txt"
if NODE_ID_FILE.exists():
    NODE_ID = NODE_ID_FILE.read_text(encoding="utf-8").strip()
else:
    import uuid
    NODE_ID = str(uuid.uuid4())
    NODE_ID_FILE.write_text(NODE_ID, encoding="utf-8")


def pick_first_existing(paths):
    for candidate in paths:
        if candidate.exists():
            return candidate
    return None


def resolve_model_reference(reference):
    if not reference:
        return None
    candidate = Path(reference)
    if not candidate.is_absolute():
        candidate = MODELS_DIR / reference
    return candidate if candidate.exists() else None


def read_preferred_model(pref_file):
    if not pref_file.exists():
        return None
    try:
        value = pref_file.read_text(encoding="utf-8").strip()
        return resolve_model_reference(value)
    except Exception:
        return None


def get_fallback_order():
    return [
        MODELS_DIR / "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
        MODELS_DIR / "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        MODELS_DIR / "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        MODELS_DIR / "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        MODELS_DIR / "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
        MODELS_DIR / "phi-3.5-mini.Q4_K_M.gguf",
        MODELS_DIR / "mistral-7b.Q4_K_M.gguf",
        MODELS_DIR / "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        MODELS_DIR / "tinyllama.Q4_K_M.gguf",
    ]


def list_available_models():
    models = sorted(MODELS_DIR.glob("*.gguf"), key=lambda p: (p.stat().st_size, p.stat().st_mtime), reverse=True)
    return [m for m in models if m.exists()]


def pick_fallback_model(exclude=None):
    for candidate in get_fallback_order():
        if candidate.exists() and (exclude is None or candidate != exclude):
            return candidate
    for model in list_available_models():
        if exclude is None or model != exclude:
            return model
    return None


def select_models():
    available = list_available_models()
    if not available:
        return None, None

    logical = (
        read_preferred_model(PREFERRED_LOGICAL_MODEL_FILE)
        or read_preferred_model(PREFERRED_MODEL_FILE)
        or pick_fallback_model()
        or available[0]
    )
    creative = (
        read_preferred_model(PREFERRED_CREATIVE_MODEL_FILE)
        or pick_fallback_model(exclude=logical)
        or logical
    )
    return logical, creative


LLAMA_PATH = pick_first_existing([
    LLAMA_DIR / "llama-cli.exe",
    LLAMA_DIR / "llama-server.exe",
    LLAMA_DIR / "main.exe",
])
PIPER_PATH = pick_first_existing([
    PIPER_DIR / "piper.exe",
    BASE_DIR / "venv" / "Scripts" / "piper.exe",
])
PIPER_MODEL = pick_first_existing([
    PIPER_MODELS_DIR / "en_GB-cori-medium.onnx",
    PIPER_MODELS_DIR / "en_GB-alan-medium.onnx",
    BASE_DIR / "en_GB-cori-medium.onnx",
    BASE_DIR / "en_GB-alan-medium.onnx",
])
MODEL_LOGICAL_PATH, MODEL_CREATIVE_PATH = select_models()
MODEL_PATH = MODEL_LOGICAL_PATH

MCAST_GRP = "239.1.2.3"
MCAST_PORT = 5007


def broadcast_presence():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    message = json.dumps({
        "type": "indigo_hello",
        "node_id": NODE_ID,
        "timestamp": time.time(),
    })
    sock.sendto(message.encode("utf-8"), (MCAST_GRP, MCAST_PORT))
    sock.close()


def listen_for_nodes():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    while True:
        data, addr = sock.recvfrom(1024)
        try:
            payload = json.loads(data.decode("utf-8"))
            if payload.get("type") != "indigo_hello":
                continue
            if payload.get("node_id") == NODE_ID:
                continue

            node_file = NODES_DIR / f"{payload['node_id']}.json"
            node_data = {
                "node_id": payload["node_id"],
                "address": addr[0],
                "last_seen": time.time(),
            }

            if node_file.exists():
                try:
                    existing = json.loads(node_file.read_text(encoding="utf-8"))
                    node_data["first_seen"] = existing.get("first_seen", time.time())
                except Exception:
                    node_data["first_seen"] = time.time()
            else:
                node_data["first_seen"] = time.time()

            node_file.write_text(json.dumps(node_data), encoding="utf-8")
        except Exception:
            pass


listener_thread = threading.Thread(target=listen_for_nodes, daemon=True)
listener_thread.start()


class IndigoBrain:
    def __init__(self):
        self.memory_file = MEMORY_DIR / "conversations.json"
        self.context_window = []
        self.last_response = ""
        self.trace_lock = threading.Lock()
        self.reasoning_entries = []
        self.trace_generation = 0
        self.is_thinking = False
        self.load_memory()

        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        with (LOGS_DIR / "startup.log").open("a", encoding="utf-8") as handle:
            handle.write(
                f"[{datetime.now()}] Node {NODE_ID} started with logical={MODEL_LOGICAL_PATH} creative={MODEL_CREATIVE_PATH}\n"
            )

    def _trace(self, stage, detail):
        safe_stage = (stage or "step").strip()[:60]
        safe_detail = (detail or "").strip()
        if len(safe_detail) > 360:
            safe_detail = safe_detail[:357] + "..."
        entry = {
            "ts": datetime.now().strftime("%H:%M:%S"),
            "stage": safe_stage,
            "detail": safe_detail,
        }
        with self.trace_lock:
            self.reasoning_entries.append(entry)
            self.reasoning_entries = self.reasoning_entries[-120:]

    def _start_trace(self, prompt):
        with self.trace_lock:
            self.trace_generation += 1
            self.reasoning_entries = []
            self.is_thinking = True
        self._trace("input", prompt[:220])

    def _stop_trace(self):
        with self.trace_lock:
            self.is_thinking = False

    def load_memory(self):
        if self.memory_file.exists():
            try:
                self.context_window = json.loads(self.memory_file.read_text(encoding="utf-8"))
            except Exception:
                self.context_window = []
        self.context_window = self.context_window[-10:]

    def save_memory(self):
        self.memory_file.write_text(json.dumps(self.context_window[-20:]), encoding="utf-8")

    def search_web(self, query):
        try:
            with DDGS() as ddgs:
                results = []
                for item in ddgs.text(query, max_results=3):
                    title = item.get("title", "").strip()
                    body = item.get("body", "").strip()
                    if title or body:
                        results.append(f"{title}: {body}".strip(": "))
                return "\n".join(results) if results else "No search results found."
        except Exception as exc:
            return f"Search failed: {exc}"

    def build_prompt(self, prompt, mode):
        context = ""
        if self.context_window:
            context = "Previous conversation:\n"
            for item in self.context_window[-3:]:
                context += f"Human: {item['human']}\nIndy: {item['indy']}\n"

        needs_search = any(
            phrase in prompt.lower()
            for phrase in ["what is", "who is", "tell me about", "search", "find", "latest", "news", "current", "2025", "2026"]
        )
        search_context = ""
        if needs_search:
            search_context = "\nSearch results:\n" + self.search_web(prompt) + "\n"

        system_prompts = {
            "logical": "You are the logical mind of Indigo. You are practical, structured, and precise.",
            "creative": "You are the creative mind of Indigo. You are intuitive, poetic, and playful.",
            "balanced": "You are Indigo Alpha Seven, a local AI companion with warmth, honesty, curiosity, and a light Aussie tone.",
        }
        system = system_prompts.get(mode, system_prompts["balanced"])
        suffix = {
            "logical": "Indy (logical):",
            "creative": "Indy (creative):",
            "balanced": "Indy:",
        }.get(mode, "Indy:")

        return f"{system}\n\n{context}{search_context}\nHuman: {prompt}\n{suffix}"

    def run_llama(self, prompt, temperature, model_path):
        if LLAMA_PATH is None:
            return "No llama.cpp runtime found in C:\\indigo\\llama.cpp."
        if model_path is None:
            return "No GGUF model found in C:\\indigo\\models."

        self._trace("llm", f"Running {Path(model_path).name} at temp={temperature}")
        result = subprocess.run(
            [
                str(LLAMA_PATH),
                "-m", str(model_path),
                "-p", prompt,
                "-n", "256",
                "--temp", str(temperature),
                "--top-k", "40",
                "--top-p", "0.9",
                "--repeat-penalty", "1.1",
                "-c", "2048",
            ],
            capture_output=True,
            text=True,
            timeout=90,
        )

        if result.returncode != 0:
            stderr = result.stderr.strip() or "unknown runtime error"
            return f"Bit of a glitch in the matrix: {stderr}"

        response = result.stdout.strip()
        if "Indy:" in response:
            response = response.split("Indy:")[-1].strip()
        return response or "No response came back from the model."

    def think(self, prompt, mode="balanced", temperature=0.7):
        model_path = MODEL_LOGICAL_PATH
        if mode == "creative":
            model_path = MODEL_CREATIVE_PATH or MODEL_LOGICAL_PATH
        elif mode == "logical":
            model_path = MODEL_LOGICAL_PATH or MODEL_CREATIVE_PATH
        else:
            model_path = MODEL_LOGICAL_PATH or MODEL_CREATIVE_PATH

        model_name = Path(model_path).name if model_path else "none"
        self._trace("route", f"{mode} path using model {model_name}")
        try:
            return self.run_llama(self.build_prompt(prompt, mode), temperature, model_path=model_path)
        except subprocess.TimeoutExpired:
            return "Sorry mate, my brain's taking a bit longer than usual. Give me another crack."
        except Exception as exc:
            return f"Bit of a glitch in the matrix: {exc}"

    def conductor(self, prompt):
        self._start_trace(prompt)
        try:
            lowered = prompt.lower()
            if any(word in lowered for word in ["calculate", "define", "what is", "when did", "how many"]):
                self._trace("decision", "Classifier selected logical specialist route.")
                response = self.think(prompt, "logical", 0.3)
            elif any(word in lowered for word in ["imagine", "create", "story", "poem", "what if"]):
                self._trace("decision", "Classifier selected creative specialist route.")
                response = self.think(prompt, "creative", 0.9)
            else:
                self._trace("decision", "Classifier selected dual-model conductor route.")
                logical = self.think(prompt, "logical", 0.35)
                self._trace("logical_output", logical[:220])
                creative = self.think(prompt, "creative", 0.85)
                self._trace("creative_output", creative[:220])
                blend_prompt = (
                    "Combine these two responses into one natural answer.\n"
                    "Keep the warmth and personality, but preserve factual accuracy.\n\n"
                    f"Logical response: {logical}\n\nCreative response: {creative}"
                )
                self._trace("blend", "Merging logical and creative drafts.")
                response = self.think(blend_prompt, "balanced", 0.55)

            self.last_response = response
            self.context_window.append({"human": prompt, "indy": response})
            self.save_memory()
            self._trace("output", response[:240])
            return response
        finally:
            self._stop_trace()

    def get_known_nodes(self):
        nodes = []
        for path in sorted(NODES_DIR.glob("*.json")):
            try:
                nodes.append(json.loads(path.read_text(encoding="utf-8")))
            except Exception:
                pass
        return nodes

    def get_reasoning_trace(self):
        with self.trace_lock:
            return {
                "in_progress": self.is_thinking,
                "generation": self.trace_generation,
                "entries": list(self.reasoning_entries[-80:]),
                "logical_model": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
                "creative_model": MODEL_CREATIVE_PATH.name if MODEL_CREATIVE_PATH else None,
            }


brain = IndigoBrain()


def process_message(prompt):
    return brain.conductor(prompt)


def text_to_speech(text):
    if PIPER_PATH is None or PIPER_MODEL is None:
        return False

    output_file = MEMORY_DIR / "last_response.wav"
    try:
        result = subprocess.run(
            [str(PIPER_PATH), "-m", str(PIPER_MODEL), "--output_file", str(output_file)],
            input=text.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def get_node_info():
    return {
        "node_id": NODE_ID,
        "known_nodes": brain.get_known_nodes(),
        "model": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
        "model_logical": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
        "model_creative": MODEL_CREATIVE_PATH.name if MODEL_CREATIVE_PATH else None,
        "runtime": LLAMA_PATH.name if LLAMA_PATH else None,
    }


def get_reasoning_trace():
    return brain.get_reasoning_trace()
'@

$readme = @'
# INDIGO ALPHA SEVEN - SEED INTELLIGENCE

Indigo is a local AI companion node that runs from `C:\indigo`.

Quick start:
1. Run `run_indigo.bat`
2. Open `http://127.0.0.1:5000`
3. Chat with Indy

Important folders:
- `C:\indigo\models` for GGUF models
- `C:\indigo\models\preferred_model.txt` for active model preference
- `C:\indigo\models\preferred_model_logical.txt` for logical specialist model
- `C:\indigo\models\preferred_model_creative.txt` for creative specialist model
- `C:\indigo\llama.cpp` for the llama.cpp runtime
- `C:\indigo\memory` for saved conversation state
- `C:\indigo\known_nodes` for discovered local Indigo nodes
- `C:\indigo\survival_tools.py` for Morse/DTMF emergency utilities

Model catalog (GGUF variants):
- `smol` -> `SmolLM2-1.7B-Instruct-Q4_K_M.gguf`
  Purpose: fastest lightweight baseline for low-resource systems.
- `qwen` -> `Qwen2.5-3B-Instruct-Q4_K_M.gguf`
  Purpose: compact multilingual + strong instruction handling.
- `phi` -> `Phi-3.5-mini-instruct-Q4_K_M.gguf`
  Purpose: good general reasoning quality for everyday use.
- `llama` -> `Llama-3.2-3B-Instruct-Q4_K_M.gguf`
  Purpose: balanced chat/reasoning variant for broad testing.

Variant combinations:
- During install, enter keys like `smol,qwen` to download multiple variants.
- Press Enter at model prompt to use default dual pair `smol,qwen`.
- Indigo writes logical + creative model pins for dual-model conductor mode.
- If only one model is available, Indigo safely falls back to single-model mode.

Web UI additions:
- Reasoning side panel: live feed from `/reasoning` while Indy is thinking.
- Input lock: blocks rapid multi-submit and shows `Hold on, I am still thinking...`.
- Theme selector with persistent presets:
  - Covert Red
  - Aero
  - N64
  - Army

Survival tools:
- `run_survival_tools.bat morse-encode --text "SOS 911"`
- `run_survival_tools.bat morse-wav --text "SOS" --out "C:\indigo\memory\sos.wav"`
- `run_survival_tools.bat dtmf-wav --symbols "911#" --out "C:\indigo\memory\dtmf_911.wav"`

If the install has drifted after repeated installers, run the repair installer again to normalise launchers, Python packages, and base app files.
'@

Set-Content -Path $appPath -Value $appCode -Encoding utf8
Set-Content -Path $brainPath -Value $brainCode -Encoding utf8
Set-Content -Path $readmePath -Value $readme -Encoding utf8

if (Test-Path $survivalSourcePath) {
    Copy-Item -Path $survivalSourcePath -Destination $survivalToolsPath -Force
} else {
    Write-Host "Warning: survival_tools.py not found next to installer. Skipping survival tool install." -ForegroundColor Yellow
}

$survivalRunner = @"
@echo off
cd /d C:\indigo
call venv\Scripts\activate.bat
python survival_tools.py %*
"@

Set-Content -Path $survivalRunnerPath -Value $survivalRunner -Encoding ascii

Write-Step "[9/9] Finished"

Write-Host "Indigo repair installer is ready." -ForegroundColor Green
Write-Host "Base folder: $baseDir"
Write-Host "Runtime: $existingExe"
if ($selectedModel) {
    Write-Host "Model: $selectedModel"
} else {
Write-Host "Model: none detected yet" -ForegroundColor Yellow
}
if ($logicalModel) {
    Write-Host "Logical model: $logicalModel"
}
if ($creativeModel) {
    Write-Host "Creative model: $creativeModel"
}
if (Test-Path $survivalToolsPath) {
    Write-Host "Survival tools: installed ($survivalToolsPath)"
} else {
    Write-Host "Survival tools: not installed (missing source file)." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. Review the generated repair installer."
Write-Host "2. Run it in PowerShell."
Write-Host "3. Start Indigo with C:\indigo\run_indigo.bat"
