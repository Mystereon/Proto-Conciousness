#!/usr/bin/env bash
set -euo pipefail

REPO="${INDIGO_REPO:-Mystereon/Proto-Conciousness}"
BRANCH="${INDIGO_BRANCH:-main}"
MODE="${1:-client}"

log() {
  printf '[indigo-android] %s\n' "$1"
}

if [[ "$MODE" == "client" ]]; then
  if command -v pkg >/dev/null 2>&1; then
    pkg install -y curl termux-tools >/dev/null 2>&1 || true
  fi

  cat > "$HOME/connect_indigo.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  printf 'Usage: %s http://<indigo-node-ip>:5000\n' "$0"
  exit 1
fi
if command -v termux-open-url >/dev/null 2>&1; then
  termux-open-url "$TARGET"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$TARGET"
else
  printf 'Open this URL manually:\n%s\n' "$TARGET"
fi
SH
  chmod +x "$HOME/connect_indigo.sh"
  log "Client launcher installed: $HOME/connect_indigo.sh"
  log "Use: ~/connect_indigo.sh http://<indigo-node-ip>:5000"
  exit 0
fi

if [[ "$MODE" == "lite-local" ]]; then
  if ! command -v pkg >/dev/null 2>&1; then
    printf 'lite-local mode is intended for Termux on Android.\n' >&2
    exit 1
  fi

  log "Installing Termux build dependencies"
  pkg update -y
  pkg install -y git python clang cmake make pkg-config

  export INDIGO_BASE_DIR="${INDIGO_BASE_DIR:-$HOME/indigo}"
  export INDIGO_MODEL_KEYS="${INDIGO_MODEL_KEYS:-smol}"

  log "Launching Linux installer in lite-local mode"
  bash <(curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/install.sh")
  log "Done. Start Indigo with: $INDIGO_BASE_DIR/run_indigo.sh"
  exit 0
fi

printf 'Unknown mode: %s\n' "$MODE" >&2
printf 'Usage: %s [client|lite-local]\n' "$0" >&2
exit 1
