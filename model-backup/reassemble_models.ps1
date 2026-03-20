param(
    [string]$ManifestPath = ".\model-backup\manifest.json",
    [string]$ChunksDir = ".\model-backup\chunks",
    [string]$OutputDir = ".\model-backup\restored",
    [switch]$SkipHashCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$manifest = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
if (-not $manifest.models) {
    throw "No models listed in manifest: $ManifestPath"
}

$chunksPath = (Resolve-Path $ChunksDir).Path
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$outPath = (Resolve-Path $OutputDir).Path

foreach ($model in $manifest.models) {
    $target = Join-Path $outPath $model.model_file
    Write-Host "Reassembling $($model.model_file) -> $target"

    $writer = [System.IO.File]::Open($target, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        foreach ($part in $model.parts) {
            $partPath = Join-Path $chunksPath $part.name
            if (-not (Test-Path $partPath)) {
                throw "Missing chunk: $partPath"
            }

            if (-not $SkipHashCheck) {
                $actualPartHash = (Get-FileHash -Path $partPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualPartHash -ne $part.sha256) {
                    throw "Chunk hash mismatch: $($part.name)"
                }
            }

            $reader = [System.IO.File]::Open($partPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $reader.CopyTo($writer)
            }
            finally {
                $reader.Dispose()
            }
        }
    }
    finally {
        $writer.Dispose()
    }

    if (-not $SkipHashCheck) {
        $restoredHash = (Get-FileHash -Path $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($restoredHash -ne $model.sha256) {
            throw "Restored file hash mismatch for $($model.model_file)"
        }
    }
}

Write-Host "All models reassembled successfully in $outPath"
