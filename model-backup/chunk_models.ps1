param(
    [string]$SourceDir = "C:\indigo\models",
    [string]$OutputRoot = ".\model-backup",
    [int]$ChunkSizeMB = 95
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path ".").Path
$sourcePath = (Resolve-Path $SourceDir).Path
$backupRoot = Join-Path $repoRoot $OutputRoot
$chunksDir = Join-Path $backupRoot "chunks"
$manifestPath = Join-Path $backupRoot "manifest.json"
$checksumsPath = Join-Path $backupRoot "SHA256SUMS.txt"

if ($ChunkSizeMB -lt 1) {
    throw "ChunkSizeMB must be >= 1"
}

$chunkSizeBytes = $ChunkSizeMB * 1MB

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $chunksDir -Force | Out-Null

$models = Get-ChildItem -Path $sourcePath -File -Filter "*.gguf" | Sort-Object Name
if (-not $models) {
    throw "No .gguf files found in $sourcePath"
}

# Clean old generated chunks/checksum files for deterministic output.
Get-ChildItem -Path $chunksDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
if (Test-Path $checksumsPath) { Remove-Item -Force $checksumsPath }

$manifestModels = @()
$checksumLines = New-Object System.Collections.Generic.List[string]

foreach ($model in $models) {
    Write-Host "Chunking $($model.Name) ..."
    $modelHash = (Get-FileHash -Path $model.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    $reader = [System.IO.File]::Open($model.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $buffer = New-Object byte[] $chunkSizeBytes
        $partIndex = 0
        $partEntries = @()

        while ($true) {
            $bytesRead = $reader.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -le 0) { break }

            $partIndex++
            $partName = "{0}.part{1:D4}" -f $model.Name, $partIndex
            $partPath = Join-Path $chunksDir $partName

            $writer = [System.IO.File]::Open($partPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $writer.Write($buffer, 0, $bytesRead)
            }
            finally {
                $writer.Dispose()
            }

            $partHash = (Get-FileHash -Path $partPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $checksumLines.Add("$partHash  chunks/$partName")

            $partEntries += [ordered]@{
                name = $partName
                bytes = $bytesRead
                sha256 = $partHash
            }
        }

        $manifestModels += [ordered]@{
            model_file = $model.Name
            source_path = $model.FullName
            bytes = $model.Length
            sha256 = $modelHash
            chunk_size_bytes = $chunkSizeBytes
            parts = $partEntries
        }

        $checksumLines.Add("$modelHash  original/$($model.Name)")
    }
    finally {
        $reader.Dispose()
    }
}

$manifest = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    source_dir = $sourcePath
    chunk_size_mb = $ChunkSizeMB
    models = $manifestModels
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
$checksumLines | Set-Content -Path $checksumsPath -Encoding ASCII

Write-Host "Done."
Write-Host "Manifest: $manifestPath"
Write-Host "Checksums: $checksumsPath"
Write-Host "Chunks: $chunksDir"
