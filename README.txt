INDIGO ALPHA SEVEN
Open Distribution Bundle
Version: v22
Date: March 19, 2026

MISSION STATEMENT
Indigo exists to help build resilient, local-first AI companions that stay useful under stress, run on everyday hardware, and keep people connected when centralized systems are unavailable.

CHIMERA PRINCIPLE
This project treats resilience as synthesis: one system, multiple specialized minds working together.
Like a chimera, Indigo combines distinct capabilities into a single practical organism:
1. Reasoning and local inference (llama.cpp)
2. Voice and interaction layers (Sesame/Piper pathing)
3. Survival communication tooling (Morse and DTMF generation)

Design intent:
- No single dependency should be allowed to collapse the whole node.
- Fallback paths are a feature, not a failure.
- Local-first operation is prioritized over cloud dependence.

WHAT IS IN THIS BUNDLE
1. ProtoConsciousIndigo.ps1
   - Main installer/repair script for C:\indigo
2. survival_tools.py
   - Console survival utility module (Morse + DTMF)
3. README.txt
   - This document

CORE CAPABILITIES (v22)
1. Local Indigo node setup/repair at C:\indigo
2. Python venv bootstrap + dependency install
3. llama.cpp runtime detection (and download fallback)
4. Interactive GGUF model catalog + variant download selection
5. Node identity and launcher generation (run_indigo.bat)
6. Backup of key files before replacement
7. One-prompt-at-a-time guard message:
   "Hold on, I am still thinking..."
8. Survival toolkit deployment:
   - Morse encode/decode
   - Morse WAV tone generation
   - DTMF WAV tone generation
9. Piper voice fallback handling:
   - Accepts piper.exe from C:\indigo\piper OR C:\indigo\venv\Scripts
   - Installs pip fallback deps (piper-tts, pathvalidate) when available
   - Defaults to female Piper voice model (en_GB-cori) when available
10. Hardware-aware runtime recommendation:
   - Detects CPU, RAM, and GPU vendor/VRAM
   - Auto-recommends CUDA (NVIDIA), Vulkan (AMD/Intel), or CPU
   - Falls back CUDA -> Vulkan -> CPU when downloads fail
11. Dual-model conductor pinning:
   - Writes C:\indigo\models\preferred_model.txt
   - Writes role files:
     C:\indigo\models\preferred_model_logical.txt
     C:\indigo\models\preferred_model_creative.txt
   - Indigo can run logical+creative model slots separately
12. Reasoning feed + input lock UI:
   - Side panel shows live staged reasoning feed while thinking
   - Prevents rapid multi-submit; returns hold message during active response
13. Theme selector:
   - Covert Red
   - Aero
   - N64
   - Army
14. Repository bootstrap installers:
   - install.ps1 (Windows one-line bootstrap)
   - install.sh (Linux bootstrap)
   - install-android.sh (Android Termux bootstrap)

MODEL CATALOG (GGUF)
- smol
  File: SmolLM2-1.7B-Instruct-Q4_K_M.gguf
  Purpose: fastest lightweight baseline for low-resource hardware.
- qwen
  File: Qwen2.5-3B-Instruct-Q4_K_M.gguf
  Purpose: compact multilingual + strong instruction behavior.
- phi
  File: Phi-3.5-mini-instruct-Q4_K_M.gguf
  Purpose: strong general instruction-following and reasoning balance.
- llama
  File: Llama-3.2-3B-Instruct-Q4_K_M.gguf
  Purpose: balanced chat/reasoning variant for broad testing.

MODEL VARIANT WORKFLOW
1. During install, enter one key or multiple keys separated by commas:
   - Example: smol,qwen
   - Press Enter for default dual pair: smol,qwen
2. Installer downloads selected variants into C:\indigo\models.
3. First valid selected model is pinned in:
   - C:\indigo\models\preferred_model.txt
4. Dual-role pins are also written:
   - C:\indigo\models\preferred_model_logical.txt
   - C:\indigo\models\preferred_model_creative.txt
5. Indigo uses logical+creative model paths when both are available.

WEB UI THEMES
- Covert Red: low-light red tactical palette.
- Aero: clean Windows-style blue glass tone.
- N64: orange/blue retro console palette.
- Army: subdued field greens.

VERSION CHANGES
v22
- Added README one-line install guidance for Windows, Linux, and Android.
- Added repo bootstrap scripts: install.ps1, install.sh, install-android.sh.
- Added iOS note with recommended browser-client path.

v21
- Added dual-model conductor role pins (logical + creative model files).
- Added live reasoning feed panel endpoint + UI rendering.
- Added input lock behavior to prevent multi-submit request storms.
- Added theme selector with persistent Covert Red / Aero / N64 / Army presets.

v20
- Added install-time GGUF model catalog with purpose text (smol, qwen, phi, llama).
- Added multi-select variant downloads using comma-separated keys.
- Added preferred model pinning via C:\indigo\models\preferred_model.txt.
- Updated generated Indigo README with model matrix and variant instructions.

v19
- Added distribution packaging for survival_tools.py with installer integration.
- Installer now deploys C:\indigo\survival_tools.py and run_survival_tools.bat.
- Added backup support for survival tool files during repair/update.
- Added survival tool usage notes in generated Indigo README.
- Hardened Piper setup with fallback and dependency recovery.
- Added hardware profile detection and auto runtime recommendation (CPU/Vulkan).

v18 to v19 direction
- Shifted from "fresh only" install behavior to "repair + normalize" for cumulative installs.
- Improved compatibility with existing C:\indigo environments.
- Added practical field tools for low-infrastructure communication workflows.

SURVIVAL TOOLS QUICK COMMANDS
From cmd/powershell after install:

C:\indigo\run_survival_tools.bat morse-encode --text "SOS 911"
C:\indigo\run_survival_tools.bat morse-decode --code "... --- ... / ----. .---- .----"
C:\indigo\run_survival_tools.bat morse-wav --text "SOS" --out "C:\indigo\memory\sos.wav"
C:\indigo\run_survival_tools.bat dtmf-wav --symbols "911#" --out "C:\indigo\memory\dtmf_911.wav"

SURVIVAL TOOLS REFERENCE
1. Launch methods
   - Preferred: C:\indigo\run_survival_tools.bat <command> <args>
   - Direct Python: C:\indigo\venv\Scripts\python.exe C:\indigo\survival_tools.py <command> <args>
2. Morse encode
   - Command: morse-encode --text "<plain text>"
   - Output: Morse sequence printed to terminal
   - Word separator: "/"
3. Morse decode
   - Command: morse-decode --code "<morse code>"
   - Input format: dots/dashes separated by spaces, words separated by "/"
4. Morse WAV generation
   - Command: morse-wav --text "<plain text>" --out "<path>.wav"
   - Optional tuning:
   --wpm 18
   --freq 700
   --sample-rate 44100
   --volume 0.45
   - Output: mono PCM16 WAV file
5. DTMF WAV generation
   - Command: dtmf-wav --symbols "<digits>" --out "<path>.wav"
   - Supported symbols: 0-9, *, #, A, B, C, D
   - Optional tuning:
   --tone-ms 140
   --gap-ms 70
   --sample-rate 44100
   --volume 0.45
6. Suggested outputs
   - Save generated files under C:\indigo\memory for quick retrieval and testing
7. Verification tips
   - Confirm file exists and has non-zero size
   - Open WAV in any local player to verify audibility
8. Troubleshooting
   - If command not found, run through run_survival_tools.bat so venv is activated
   - If output file is missing, ensure --out path is writeable
   - If waveform sounds clipped, lower --volume
   - If Morse is too fast/slow, adjust --wpm

SHAREABLE INSTALL STEPS
1. Place this README.txt, ProtoConsciousIndigo.ps1, and survival_tools.py in the same folder.
2. Open PowerShell in that folder.
3. Run:
   powershell -NoProfile -ExecutionPolicy Bypass -File ".\ProtoConsciousIndigo.ps1"
4. Start Indigo:
   C:\indigo\run_indigo.bat

REPOSITORY ONE-LINE INSTALLS
Windows PowerShell:
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install.ps1 | iex"

Linux bash:
curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install.sh | bash

Android Termux (recommended client launcher):
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh)

Android Termux (experimental lite-local node):
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh) lite-local

iOS note:
- Native shell-style local install is not supported.
- Recommended path: run Indigo node on desktop/Linux and open the node URL in Safari.

NOTES FOR ENGINEERING TESTERS
1. Keep tests local first (health route, chat route, model load timing).
2. Validate one-prompt lock under rapid repeated submits.
3. Validate survival WAV output is generated and playable.
4. Confirm behavior on both CPU-only and Vulkan-enabled machines.
