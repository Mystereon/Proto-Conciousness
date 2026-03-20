#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DIST="${DIST:-bookworm}"
ARCH="${ARCH:-amd64}"
LIVE_USER="${LIVE_USER:-indigo}"
HOSTNAME_VALUE="${HOSTNAME_VALUE:-indigo-kiosk}"
LOCALE_VALUE="${LOCALE_VALUE:-en_GB.UTF-8}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-gb}"
IMAGE_BASENAME="${IMAGE_BASENAME:-indigo-kiosk-live-${DIST}-${ARCH}}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/tmp/kiosk-iso-build}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/output/iso}"
MIRROR_URL="${MIRROR_URL:-http://deb.debian.org/debian/}"
INDIGO_SNAPSHOT_DIR="${INDIGO_SNAPSHOT_DIR:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (for example: sudo ./kiosk-iso/build-kiosk-iso.sh)" >&2
  exit 1
fi

require_cmd lb
require_cmd rsync
require_cmd curl
require_cmd sha256sum

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
rm -rf "${WORK_DIR:?}"/*
cd "${WORK_DIR}"

lb config \
  --mode debian \
  --distribution "${DIST}" \
  --architectures "${ARCH}" \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer live \
  --mirror-bootstrap "${MIRROR_URL}" \
  --mirror-chroot "${MIRROR_URL}" \
  --mirror-binary "${MIRROR_URL}" \
  --bootappend-live "boot=live components username=${LIVE_USER} hostname=${HOSTNAME_VALUE} locales=${LOCALE_VALUE} keyboard-layouts=${KEYBOARD_LAYOUT} quiet splash"

mkdir -p config/package-lists
mkdir -p config/includes.chroot/etc/live/config.conf.d
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
mkdir -p config/includes.chroot/etc/xdg/openbox
mkdir -p config/includes.chroot/etc/systemd/system
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/opt/indigo/source
mkdir -p config/includes.chroot/opt/indigo/staged-models
mkdir -p config/hooks/normal

cat > config/package-lists/indigo-kiosk.list.chroot <<'EOF'
live-boot
live-config
systemd-sysv
network-manager
xorg
openbox
lightdm
lightdm-gtk-greeter
chromium
unclutter
dbus-x11
python3
python3-venv
python3-pip
git
curl
ca-certificates
pulseaudio
alsa-utils
fonts-dejavu
EOF

cat > config/includes.chroot/etc/live/config.conf.d/10-indigo-user.conf <<EOF
LIVE_USERNAME="${LIVE_USER}"
LIVE_HOSTNAME="${HOSTNAME_VALUE}"
EOF

cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-indigo-kiosk.conf <<EOF
[Seat:*]
autologin-user=${LIVE_USER}
autologin-user-timeout=0
user-session=openbox
greeter-hide-users=true
greeter-show-manual-login=false
allow-guest=false
EOF

cat > config/includes.chroot/etc/xdg/openbox/autostart <<'EOF'
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.5 -root &
/usr/local/bin/indigo-kiosk-browser.sh &
EOF

cat > config/includes.chroot/usr/local/bin/indigo-kiosk-browser.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

URL="${INDIGO_KIOSK_URL:-http://127.0.0.1:5000}"
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || true)"

if [[ -z "${BROWSER_BIN}" ]]; then
  echo "Chromium is not installed; kiosk browser cannot start." >&2
  exit 1
fi

until curl -fsS "${URL}/health" >/dev/null 2>&1; do
  sleep 1
done

while true; do
  "${BROWSER_BIN}" \
    --kiosk \
    --incognito \
    --no-first-run \
    --no-default-browser-check \
    --disable-session-crashed-bubble \
    --disable-infobars \
    "${URL}" || true
  sleep 1
done
EOF

cat > config/includes.chroot/usr/local/bin/indigo-bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="/opt/indigo/source"
RUNTIME_DIR="/opt/indigo/runtime"
STAGED_MODELS_DIR="/opt/indigo/staged-models"
STAMP_FILE="${RUNTIME_DIR}/.bootstrap_ok"

mkdir -p "${RUNTIME_DIR}"
if [[ -f "${STAMP_FILE}" ]]; then
  exit 0
fi

if [[ ! -f "${SOURCE_DIR}/install.sh" ]]; then
  echo "Missing ${SOURCE_DIR}/install.sh" >&2
  exit 1
fi

if [[ -d "${STAGED_MODELS_DIR}" ]]; then
  mkdir -p "${RUNTIME_DIR}/models"
  cp -f "${STAGED_MODELS_DIR}"/*.gguf "${RUNTIME_DIR}/models/" 2>/dev/null || true
  cp -f "${STAGED_MODELS_DIR}"/preferred_model*.txt "${RUNTIME_DIR}/models/" 2>/dev/null || true
fi

export INDIGO_BASE_DIR="${RUNTIME_DIR}"
export INDIGO_MODEL_KEYS="${INDIGO_MODEL_KEYS:-smol,qwen}"
export INDIGO_SKIP_MODELS="${INDIGO_SKIP_MODELS:-1}"

/usr/bin/bash "${SOURCE_DIR}/install.sh"
touch "${STAMP_FILE}"
EOF

cat > config/includes.chroot/usr/local/bin/indigo-run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export INDIGO_BASE_DIR="/opt/indigo/runtime"
if [[ ! -x "${INDIGO_BASE_DIR}/run_indigo.sh" ]]; then
  echo "Indigo runtime is not ready yet (missing run_indigo.sh)." >&2
  exit 1
fi

exec "${INDIGO_BASE_DIR}/run_indigo.sh"
EOF

cat > config/includes.chroot/etc/systemd/system/indigo-bootstrap.service <<'EOF'
[Unit]
Description=Indigo bootstrap service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=INDIGO_SKIP_MODELS=1
Environment=INDIGO_MODEL_KEYS=smol,qwen
ExecStart=/usr/local/bin/indigo-bootstrap.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

cat > config/includes.chroot/etc/systemd/system/indigo-app.service <<'EOF'
[Unit]
Description=Indigo app service
After=network-online.target indigo-bootstrap.service
Wants=network-online.target
Requires=indigo-bootstrap.service

[Service]
Type=simple
ExecStart=/usr/local/bin/indigo-run.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > config/hooks/normal/090-enable-indigo-services.chroot <<'EOF'
#!/bin/sh
set -eu

mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/indigo-bootstrap.service /etc/systemd/system/multi-user.target.wants/indigo-bootstrap.service
ln -sf /etc/systemd/system/indigo-app.service /etc/systemd/system/multi-user.target.wants/indigo-app.service
EOF

chmod +x config/includes.chroot/usr/local/bin/indigo-kiosk-browser.sh
chmod +x config/includes.chroot/usr/local/bin/indigo-bootstrap.sh
chmod +x config/includes.chroot/usr/local/bin/indigo-run.sh
chmod +x config/hooks/normal/090-enable-indigo-services.chroot

rsync -a \
  --exclude ".git" \
  --exclude "tmp" \
  --exclude "output" \
  --exclude "__pycache__" \
  "${REPO_ROOT}/" \
  config/includes.chroot/opt/indigo/source/

if [[ -n "${INDIGO_SNAPSHOT_DIR}" ]]; then
  if [[ ! -d "${INDIGO_SNAPSHOT_DIR}" ]]; then
    echo "INDIGO_SNAPSHOT_DIR does not exist: ${INDIGO_SNAPSHOT_DIR}" >&2
    exit 1
  fi

  SNAPSHOT_MODELS_DIR="${INDIGO_SNAPSHOT_DIR}"
  if [[ -d "${INDIGO_SNAPSHOT_DIR}/models" ]]; then
    SNAPSHOT_MODELS_DIR="${INDIGO_SNAPSHOT_DIR}/models"
  fi

  echo "Staging models from snapshot: ${SNAPSHOT_MODELS_DIR}"
  shopt -s nullglob
  for file in "${SNAPSHOT_MODELS_DIR}"/*.gguf "${SNAPSHOT_MODELS_DIR}"/preferred_model*.txt; do
    cp -f "${file}" config/includes.chroot/opt/indigo/staged-models/
  done
  shopt -u nullglob
fi

lb build

ISO_CANDIDATE="$(find . -maxdepth 1 -type f -name "*.iso" | head -n 1 || true)"
if [[ -z "${ISO_CANDIDATE}" ]]; then
  echo "Build finished but no ISO was found in ${WORK_DIR}." >&2
  exit 1
fi

FINAL_ISO="${OUT_DIR}/${IMAGE_BASENAME}.iso"
cp -f "${ISO_CANDIDATE}" "${FINAL_ISO}"
sha256sum "${FINAL_ISO}" | tee "${FINAL_ISO}.sha256"

echo "ISO build complete:"
echo "  ${FINAL_ISO}"
