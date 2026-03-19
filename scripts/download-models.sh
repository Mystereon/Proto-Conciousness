#!/usr/bin/env bash
set -euo pipefail

# Download GGUF models for Indigo
# Usage: ./scripts/download-models.sh [MODEL_DIR] [MODEL_KEYS]
#   MODEL_DIR   - directory to save models (default: ./models)
#   MODEL_KEYS  - comma-separated model keys (default: smol,qwen)

MODEL_DIR="${1:-${INDIGO_MODEL_DIR:-./models}}"
MODEL_KEYS="${2:-${INDIGO_MODEL_KEYS:-smol,qwen}}"

declare -A MODELS
MODELS[smol]="bartowski/SmolLM2-1.7B-Instruct-GGUF|SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
MODELS[qwen]="bartowski/Qwen2.5-3B-Instruct-GGUF|Qwen2.5-3B-Instruct-Q4_K_M.gguf"
MODELS[phi]="bartowski/Phi-3.5-mini-instruct-GGUF|Phi-3.5-mini-instruct-Q4_K_M.gguf"
MODELS[llama]="bartowski/Llama-3.2-3B-Instruct-GGUF|Llama-3.2-3B-Instruct-Q4_K_M.gguf"

mkdir -p "$MODEL_DIR"

IFS=',' read -ra KEYS <<< "$MODEL_KEYS"

FIRST_MODEL=""

for key in "${KEYS[@]}"; do
    key=$(echo "$key" | tr -d ' ')
    if [[ -z "${MODELS[$key]+x}" ]]; then
        echo "WARNING: Unknown model key '$key' (available: smol, qwen, phi, llama)"
        continue
    fi

    IFS='|' read -r repo filename <<< "${MODELS[$key]}"
    dest="$MODEL_DIR/$filename"

    if [[ -f "$dest" ]]; then
        echo "SKIP: $filename already exists"
    else
        url="https://huggingface.co/$repo/resolve/main/$filename"
        echo "Downloading $key: $filename ..."
        curl -fL --progress-bar -o "$dest" "$url"
        echo "OK: $filename"
    fi

    if [[ -z "$FIRST_MODEL" ]]; then
        FIRST_MODEL="$filename"
    fi
done

# Write model preference files
if [[ -n "$FIRST_MODEL" ]]; then
    echo "$FIRST_MODEL" > "$MODEL_DIR/preferred_model.txt"
    echo "Pinned preferred model: $FIRST_MODEL"
fi

if [[ ${#KEYS[@]} -ge 2 ]]; then
    IFS='|' read -r _ logical_file <<< "${MODELS[${KEYS[0]}]}"
    IFS='|' read -r _ creative_file <<< "${MODELS[${KEYS[1]}]}"
    echo "$logical_file" > "$MODEL_DIR/preferred_model_logical.txt"
    echo "$creative_file" > "$MODEL_DIR/preferred_model_creative.txt"
    echo "Dual-model pins: logical=$logical_file, creative=$creative_file"
fi

echo "Done. Models in: $MODEL_DIR"
