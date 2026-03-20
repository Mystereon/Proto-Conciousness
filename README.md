# INDIGO ALPHA SEVEN
Open Distribution Bundle  
Version: v22  
Last Updated: March 20, 2026

## Mission Statement
Indigo is built to create resilient, local-first AI companions that keep running under stress, work on everyday hardware, and preserve human connection when centralized systems fail.

This is more than a chatbot project. It is a continuity-first framework for adaptable local intelligence.

## Chimera Principle
Indigo is designed as a chimeric system: one practical organism made from specialized subsystems that cooperate.

- Local reasoning and inference (GGUF + llama runtime pathing)
- Voice interaction pathways (Piper / Sesame-compatible flow)
- Signal communication tools (Morse + DTMF generation)

### Design Philosophy
- No single failure should collapse the node
- Redundancy is intentional
- Fallback paths are features, not errors
- Local-first takes priority over cloud reliance

## What “Proto-Consciousness” Means Here
This project does not claim sentience. In Indigo, proto-consciousness means a system that can:

- Preserve state and memory across sessions
- Reference internal status and runtime context
- Adapt output flow based on route/response outcomes
- Expand capabilities via tools, modules, and configuration

Core idea: **a stable core mind with an evolving toolbox**.

## Core Capabilities (v22)
- Local Indigo node setup and repair
- One-prompt lock to prevent request storming
- Live reasoning feed panel in web UI
- Multi-theme interface (Covert Red, Aero, N64, Army)
- Dual-model conductor support:
  - `preferred_model_logical.txt`
  - `preferred_model_creative.txt`
- Survival tools:
  - Morse encode/decode
  - Morse WAV generation
  - DTMF WAV generation

## Model Variants
- `smol` -> `SmolLM2-1.7B-Instruct-Q4_K_M.gguf`
- `qwen` -> `Qwen2.5-3B-Instruct-Q4_K_M.gguf`
- `phi` -> `Phi-3.5-mini-instruct-Q4_K_M.gguf`
- `llama` -> `Llama-3.2-3B-Instruct-Q4_K_M.gguf`

Default pairing is dual-model conductor mode (`smol,qwen`).

## One-Line Installs

### Windows (PowerShell)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install.ps1 | iex"
```

### Linux (bash)
```bash
curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install.sh | bash
```

### Android (Termux)
Recommended client launcher mode:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh)
```

Experimental lite local-node mode:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh) lite-local
```

## Live USB / Kiosk ISO

Need a distributable kiosk image with Indigo auto-running?  
Use the ISO builder in:

- `kiosk-iso/build-kiosk-iso.sh`
- `kiosk-iso/README.md`

This generates an install-capable live ISO under `output/iso/` for USB imaging.

## Model Chunk Backup

To back up local GGUF models in GitHub-safe chunk sizes:

- `model-backup/chunk_models.ps1`
- `model-backup/reassemble_models.ps1`
- `model-backup/README.md`

## Mobile Notes
- iOS does not support a native shell-style local installer flow.
- Recommended iOS path: run Indigo on desktop/Linux, then access from Safari over LAN.
- Android support is provided via Termux scripts.

## Post-Install Run Commands

### Windows
```powershell
C:\indigo\run_indigo.bat
```

### Linux
```bash
~/indigo/run_indigo.sh
```

### Survival Tools
Windows:
```powershell
C:\indigo\run_survival_tools.bat morse-encode --text "SOS 911"
```

Linux:
```bash
~/indigo/run_survival_tools.sh morse-encode --text "SOS 911"
```

## Bundle Contents
- `ProtoConsciousIndigo.ps1` - main Windows installer/repair script for `C:\indigo`
- `install.ps1` - one-line Windows bootstrap installer
- `install.sh` - Linux bootstrap installer
- `install-android.sh` - Android Termux bootstrap (client + lite-local modes)
- `survival_tools.py` - Morse/DTMF utility module
- `README.txt` - distribution notes

## Configurable Intelligence (Planned Direction)
Indigo is designed to support modular runtime expansion via editable configuration and capability toggles.

Example concept:
```json
{
  "modules": {
    "vision": false,
    "sdr": false,
    "voice": true
  },
  "libraries": [
    "opencv-python",
    "numpy"
  ],
  "permissions": {
    "install_packages": true
  }
}
```

## Roadmap
- Vision module integration
- SDR/signal toolkit expansion
- Stronger self-evaluation loop
- Community module ecosystem

## Final Note
Indigo is an open, modular experiment in resilient local intelligence, distributed operation, and long-horizon human-AI companionship.
