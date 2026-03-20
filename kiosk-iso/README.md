# Indigo Kiosk ISO Builder

This folder builds a Debian-based live ISO that:

- boots as a Live USB image (`iso-hybrid`)
- includes a kiosk desktop session (Openbox + Chromium full-screen)
- auto-starts Indigo locally on `http://127.0.0.1:5000`
- includes the Debian installer entry (`--debian-installer live`) for install-capable media

## What You Need On The Build Host

Use a Debian/Ubuntu Linux machine (or VM), then install:

```bash
sudo apt-get update
sudo apt-get install -y live-build debootstrap xorriso squashfs-tools rsync curl coreutils
```

`sha256sum` is provided by `coreutils`.

## Build

From repo root:

```bash
sudo ./kiosk-iso/build-kiosk-iso.sh
```

Default output:

- ISO: `output/iso/indigo-kiosk-live-bookworm-amd64.iso`
- Checksum: `output/iso/indigo-kiosk-live-bookworm-amd64.iso.sha256`

## Optional Build Variables

```bash
sudo DIST=bookworm ARCH=amd64 LIVE_USER=indigo HOSTNAME_VALUE=indigo-kiosk ./kiosk-iso/build-kiosk-iso.sh
```

Also supported:

- `WORK_DIR` (default `tmp/kiosk-iso-build`)
- `OUT_DIR` (default `output/iso`)
- `IMAGE_BASENAME`
- `MIRROR_URL`
- `INDIGO_SNAPSHOT_DIR` (optional path to preloaded Indigo files/models)

## Runtime Notes

- Indigo bootstrap runs on first boot from `/opt/indigo/source/install.sh`.
- By default models are skipped at bootstrap (`INDIGO_SKIP_MODELS=1`) so first boot is faster.
- Kiosk browser waits for `http://127.0.0.1:5000/health`, then opens full-screen Chromium.

## Use Existing `C:\indigo` Content

Yes, you can seed the ISO from an existing Indigo directory.

Example from WSL/Linux builder host:

```bash
sudo INDIGO_SNAPSHOT_DIR=/mnt/c/indigo ./kiosk-iso/build-kiosk-iso.sh
```

The builder will stage:

- `*.gguf`
- `preferred_model*.txt`

from either:

- `${INDIGO_SNAPSHOT_DIR}/models` (if present), or
- `${INDIGO_SNAPSHOT_DIR}` directly.

Important:

- Full Windows runtime files are not Linux-runnable as-is.
- Model files and model pin files are portable and are the intended preload path.

If you want models pulled at first boot, edit:

- `kiosk-iso/build-kiosk-iso.sh` service block for `indigo-bootstrap.service`

and set `INDIGO_SKIP_MODELS=0`.
