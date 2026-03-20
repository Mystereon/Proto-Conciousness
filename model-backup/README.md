# Model Chunk Backup

This folder stores chunked backups of local `.gguf` model files so each file stays below GitHub's regular per-file push cap.

## Generate Chunks

From repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\model-backup\chunk_models.ps1
```

Defaults:

- source: `C:\indigo\models`
- chunk size: `95 MB`
- output chunks: `model-backup/chunks/`
- metadata: `model-backup/manifest.json`
- checksums: `model-backup/SHA256SUMS.txt`

## Restore Models

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\model-backup\reassemble_models.ps1
```

Restored files are written to:

- `model-backup/restored/`

The restore script validates chunk hashes and final model hashes unless `-SkipHashCheck` is used.
