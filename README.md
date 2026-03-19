# Proto-Conciousness

Indigo is a local-first AI companion stack with dual-model conductor logic, survival comms tooling, and a resilient offline-oriented runtime philosophy.

## Getting Started

See the **[Getting Started Guide](docs/getting-started.md)** for full setup instructions.

**Docker Compose** (quickest):
```bash
./scripts/download-models.sh ./models smol,qwen
docker compose up --build
```

**Tilt + KinD** (Kubernetes dev):
```bash
kind create cluster --name indigo
./scripts/download-models.sh ./models smol,qwen
tilt up
```

**Native install**: See [One-Line Installs](#one-line-installs) below.

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
Client launcher mode (recommended):
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh)
```

Lite local node mode (experimental):
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mystereon/Proto-Conciousness/main/install-android.sh) lite-local
```

## Mobile Notes

- iOS does not support this kind of native shell-style local installer flow.
- Recommended iOS path is to run Indigo on desktop/Linux and open the node URL from Safari on the phone.
- Android can use the Termux scripts above.

## What You Get

- Dual-model conductor model pins:
  - `preferred_model_logical.txt`
  - `preferred_model_creative.txt`
- UI protections:
  - one-prompt lock (`Hold on, I am still thinking...`)
  - live reasoning feed side panel
- Theme presets:
  - Covert Red
  - Aero
  - N64
  - Army
- Survival tools:
  - Morse encode/decode
  - Morse WAV generation
  - DTMF WAV generation

## Default Models

- `smol` -> `SmolLM2-1.7B-Instruct-Q4_K_M.gguf`
- `qwen` -> `Qwen2.5-3B-Instruct-Q4_K_M.gguf`
- `phi` -> `Phi-3.5-mini-instruct-Q4_K_M.gguf`
- `llama` -> `Llama-3.2-3B-Instruct-Q4_K_M.gguf`

Defaults aim for dual-model conductor pairing (`smol,qwen`).

## Run After Install

Windows:
```powershell
C:\indigo\run_indigo.bat
```

Linux:
```bash
~/indigo/run_indigo.sh
```
