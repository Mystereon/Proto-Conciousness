# Getting Started with Indigo

Indigo is a local-first AI companion. You can run it natively, with Docker Compose, or with Tilt and KinD (Kubernetes).

## Prerequisites

All methods require downloading at least one GGUF model (~500MB-2GB each).

### Docker Compose

- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2

### Tilt + KinD (Kubernetes)

- [Docker](https://docs.docker.com/get-docker/)
- [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Tilt](https://docs.tilt.dev/install.html)

## Quick Start: Docker Compose

### 1. Download models

```bash
./scripts/download-models.sh ./models smol,qwen
```

This downloads the default model pair into `./models/`. Available keys: `smol`, `qwen`, `phi`, `llama`.

### 2. Start Indigo

```bash
docker compose up --build
```

Indigo will be available at **http://localhost:5000**.

### 3. Configuration

Set environment variables in a `.env` file or pass them to `docker compose`:

| Variable | Default | Description |
|----------|---------|-------------|
| `INDIGO_PORT` | `5000` | Port to expose |
| `INDIGO_CTX_SIZE` | `2048` | LLM context window size |
| `INDIGO_MAX_TOKENS` | `256` | Max tokens per response |

## Quick Start: Tilt + KinD

### 1. Create a cluster

```bash
kind create cluster --name indigo
```

### 2. Download models

```bash
./scripts/download-models.sh ./models smol,qwen
```

### 3. Start Tilt

```bash
tilt up
```

Tilt will build the image, deploy to KinD, and port-forward **http://localhost:5000**.

Code changes in `app/` will live-reload automatically.

### 4. Tear down

```bash
tilt down
kind delete cluster --name indigo
```

## Quick Start: Native Install

See the [README](../README.md) for native one-line installers for Windows, Linux, and Android.

## Model Management

### Available Models

| Key | Model | Size | Best For |
|-----|-------|------|----------|
| `smol` | SmolLM2-1.7B-Instruct | ~500MB | Low-resource hardware |
| `qwen` | Qwen2.5-3B-Instruct | ~2GB | Multilingual tasks |
| `phi` | Phi-3.5-mini-instruct | ~2GB | General reasoning |
| `llama` | Llama-3.2-3B-Instruct | ~2GB | Balanced chat |

### Dual-Model Conductor

Indigo supports running two models simultaneously -- one for logical reasoning and one for creative responses. The default pair is `smol` (logical) and `qwen` (creative).

To select different models:

```bash
./scripts/download-models.sh ./models phi,llama
```

## Survival Tools

The survival tools module provides offline communication utilities:

```bash
# Inside the container
docker compose exec indigo python survival_tools.py morse-encode --text "SOS"
docker compose exec indigo python survival_tools.py dtmf-wav --symbols "911#" --out /tmp/dtmf.wav
```

## Troubleshooting

### Model not loading
Ensure models are downloaded and the volume is mounted correctly. Check logs:
```bash
docker compose logs indigo
```

### Out of memory
Reduce context size: `INDIGO_CTX_SIZE=1024`

### Port conflict
Change the exposed port: `INDIGO_PORT=5001 docker compose up`
