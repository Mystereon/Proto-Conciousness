#!/usr/bin/env bash
set -euo pipefail

REPO="${INDIGO_REPO:-Mystereon/Proto-Conciousness}"
BRANCH="${INDIGO_BRANCH:-main}"
INDIGO_BASE_DIR="${INDIGO_BASE_DIR:-$HOME/indigo}"
INDIGO_MODEL_KEYS="${INDIGO_MODEL_KEYS:-smol,qwen}"
INDIGO_SKIP_MODELS="${INDIGO_SKIP_MODELS:-0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

log() {
  printf '[indigo-linux] %s\n' "$1"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
}

need_cmd curl
need_cmd "$PYTHON_BIN"

mkdir -p \
  "$INDIGO_BASE_DIR/models" \
  "$INDIGO_BASE_DIR/memory" \
  "$INDIGO_BASE_DIR/known_nodes" \
  "$INDIGO_BASE_DIR/logs" \
  "$INDIGO_BASE_DIR/piper_models"

if [[ ! -x "$INDIGO_BASE_DIR/venv/bin/python" ]]; then
  log "Creating virtual environment in $INDIGO_BASE_DIR/venv"
  "$PYTHON_BIN" -m venv "$INDIGO_BASE_DIR/venv"
fi

# shellcheck disable=SC1091
source "$INDIGO_BASE_DIR/venv/bin/activate"

log "Installing Python dependencies"
python -m pip install --upgrade pip
python -m pip install flask flask-cors requests duckduckgo-search llama-cpp-python
python -m pip install piper-tts pathvalidate || true

RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
log "Fetching survival tools from repository"
download_file "$RAW_BASE/survival_tools.py" "$INDIGO_BASE_DIR/survival_tools.py"

declare -A MODEL_FILE
declare -A MODEL_URL

MODEL_FILE["smol"]="SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
MODEL_URL["smol"]="https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf?download=true"

MODEL_FILE["qwen"]="Qwen2.5-3B-Instruct-Q4_K_M.gguf"
MODEL_URL["qwen"]="https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf?download=true"

MODEL_FILE["phi"]="Phi-3.5-mini-instruct-Q4_K_M.gguf"
MODEL_URL["phi"]="https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf?download=true"

MODEL_FILE["llama"]="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
MODEL_URL["llama"]="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf?download=true"

parse_keys() {
  local input="$1"
  local out=()
  local token=""
  IFS=',' read -r -a parts <<< "$input"
  for part in "${parts[@]}"; do
    token="$(echo "$part" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ -z "$token" ]] && continue
    if [[ -n "${MODEL_FILE[$token]:-}" ]]; then
      out+=("$token")
    else
      log "Skipping unknown model key: $token"
    fi
  done
  if [[ "${#out[@]}" -eq 0 ]]; then
    out=("smol" "qwen")
  fi
  printf '%s\n' "${out[@]}"
}

mapfile -t SELECTED_KEYS < <(parse_keys "$INDIGO_MODEL_KEYS")

if [[ "$INDIGO_SKIP_MODELS" != "1" ]]; then
  for key in "${SELECTED_KEYS[@]}"; do
    file="${MODEL_FILE[$key]}"
    url="${MODEL_URL[$key]}"
    dest="$INDIGO_BASE_DIR/models/$file"
    if [[ -s "$dest" ]]; then
      log "Model already present: $file"
      continue
    fi
    log "Downloading model [$key]: $file"
    download_file "$url" "$dest"
  done
fi

pick_model_file() {
  local key="$1"
  local file="${MODEL_FILE[$key]:-}"
  if [[ -n "$file" && -s "$INDIGO_BASE_DIR/models/$file" ]]; then
    printf '%s\n' "$file"
    return
  fi
  printf '\n'
}

LOGICAL_FILE="$(pick_model_file "${SELECTED_KEYS[0]}")"
CREATIVE_FILE=""
if [[ "${#SELECTED_KEYS[@]}" -ge 2 ]]; then
  CREATIVE_FILE="$(pick_model_file "${SELECTED_KEYS[1]}")"
fi

if [[ -z "$LOGICAL_FILE" ]]; then
  if ls "$INDIGO_BASE_DIR"/models/*.gguf >/dev/null 2>&1; then
    LOGICAL_FILE="$(basename "$(ls "$INDIGO_BASE_DIR"/models/*.gguf | head -n 1)")"
  fi
fi

if [[ -z "$CREATIVE_FILE" ]]; then
  if ls "$INDIGO_BASE_DIR"/models/*.gguf >/dev/null 2>&1; then
    for candidate in "$INDIGO_BASE_DIR"/models/*.gguf; do
      cbase="$(basename "$candidate")"
      if [[ "$cbase" != "$LOGICAL_FILE" ]]; then
        CREATIVE_FILE="$cbase"
        break
      fi
    done
  fi
fi

if [[ -z "$CREATIVE_FILE" ]]; then
  CREATIVE_FILE="$LOGICAL_FILE"
fi

if [[ -n "$LOGICAL_FILE" ]]; then
  printf '%s\n' "$LOGICAL_FILE" > "$INDIGO_BASE_DIR/models/preferred_model.txt"
  printf '%s\n' "$LOGICAL_FILE" > "$INDIGO_BASE_DIR/models/preferred_model_logical.txt"
fi

if [[ -n "$CREATIVE_FILE" ]]; then
  printf '%s\n' "$CREATIVE_FILE" > "$INDIGO_BASE_DIR/models/preferred_model_creative.txt"
fi

cat > "$INDIGO_BASE_DIR/app.py" <<'PY'
from threading import Lock

from flask import Flask, jsonify, render_template_string, request
from flask_cors import CORS
from brain import get_node_info, get_reasoning_trace, process_message, text_to_speech

app = Flask(__name__)
CORS(app)
chat_lock = Lock()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
  <title>INDIGO NODE (Linux)</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      --bg: #10131a;
      --text: #dcecff;
      --muted: #9ab4d5;
      --panel: #1a2230;
      --panel2: #202b3a;
      --border: #7dc4ff44;
      --accent: #86c6ff;
      --accent2: #b6dcff;
      --contrast: #091320;
    }
    body.theme-covert {
      --bg: #140708; --text: #ffd7d7; --muted: #d39b9b; --panel: #220d10; --panel2: #2a1216;
      --border: #ff59594d; --accent: #ff7f7f; --accent2: #ffb6b6; --contrast: #1b0607;
    }
    body.theme-n64 {
      --bg: #17142b; --text: #ffe2a6; --muted: #d2c19b; --panel: #1f2d68; --panel2: #243679;
      --border: #ffb3474d; --accent: #ffb347; --accent2: #ffd08a; --contrast: #1e2f6d;
    }
    body.theme-army {
      --bg: #0f1410; --text: #d5e7c9; --muted: #9eb091; --panel: #1a2519; --panel2: #223021;
      --border: #7f9b6a4e; --accent: #a4c17f; --accent2: #c0d89a; --contrast: #10180f;
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: monospace; background: var(--bg); color: var(--text); padding: 16px; }
    .wrap { max-width: 1180px; margin: 0 auto; background: var(--panel); border: 1px solid var(--border); border-radius: 18px; padding: 18px; }
    .top { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 12px; }
    .top h1 { margin: 0 auto 0 0; color: var(--accent2); font-size: 1.4rem; }
    .btn { border: 1px solid var(--accent); border-radius: 999px; color: var(--accent); background: transparent; padding: 6px 10px; cursor: pointer; }
    .btn:hover, .btn.active { background: var(--accent); color: var(--contrast); }
    .grid { display: grid; grid-template-columns: 2fr 1fr; gap: 12px; }
    .pane { background: var(--panel2); border: 1px solid var(--border); border-radius: 12px; padding: 12px; }
    #chat { min-height: 340px; max-height: 60vh; overflow: auto; }
    .waterfall-wrap { border: 1px solid var(--border); border-radius: 10px; background: var(--bg); padding: 8px; margin-bottom: 8px; }
    #reasoningWaterfall { width: 100%; height: 120px; display: block; border-radius: 6px; image-rendering: pixelated; }
    .waterfall-meta { margin-top: 6px; color: var(--muted); font-size: 0.72rem; }
    #reasoning { min-height: 210px; max-height: 45vh; overflow: auto; }
    .line { margin: 0 0 8px; padding: 10px; border: 1px solid var(--border); border-radius: 10px; white-space: pre-wrap; }
    .user { border-color: var(--accent); }
    .input { display: flex; gap: 8px; margin-top: 12px; }
    input { flex: 1; border-radius: 999px; border: 1px solid var(--border); padding: 10px 14px; background: transparent; color: var(--text); }
    .status { margin-top: 10px; color: var(--muted); font-size: 0.9rem; }
    @media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }
  </style>
</head>
<body class="theme-aero">
  <div class="wrap">
    <div class="top">
      <h1>INDIGO NODE</h1>
      <button class="btn theme" data-theme="theme-covert" onclick="setTheme('theme-covert')">Covert Red</button>
      <button class="btn theme" data-theme="theme-aero" onclick="setTheme('theme-aero')">Aero</button>
      <button class="btn theme" data-theme="theme-n64" onclick="setTheme('theme-n64')">N64</button>
      <button class="btn theme" data-theme="theme-army" onclick="setTheme('theme-army')">Army</button>
    </div>
    <div class="grid">
      <div class="pane"><div id="chat"></div></div>
      <div class="pane">
        <strong>Reasoning Feed <span id="thinking"></span></strong>
        <div class="waterfall-wrap">
          <canvas id="reasoningWaterfall"></canvas>
          <div class="waterfall-meta">Visual pulse only. Detailed reasoning remains in text feed.</div>
        </div>
        <div id="reasoning"></div>
      </div>
    </div>
    <div class="input">
      <input id="msg" placeholder="Ask Indigo..." autocomplete="off">
      <button class="btn" id="sendBtn" onclick="sendMessage()">Send</button>
      <button class="btn" onclick="speakLast()">Voice</button>
    </div>
    <div class="status" id="status">Node online</div>
  </div>
  <script>
    const THEMES = ["theme-covert", "theme-aero", "theme-n64", "theme-army"];
    const WATERFALL_BINS = 64;
    let waiting = false;
    let reasoningPollInFlight = false;
    let waterfallCanvas = null;
    let waterfallCtx = null;
    let lastGeneration = null;
    function setTheme(name) {
      const t = THEMES.includes(name) ? name : "theme-aero";
      document.body.classList.remove(...THEMES);
      document.body.classList.add(t);
      localStorage.setItem("indigo_theme", t);
      document.querySelectorAll(".theme").forEach(b => b.classList.toggle("active", b.dataset.theme === t));
      setTimeout(initWaterfall, 0);
    }
    function status(t){ document.getElementById("status").textContent = t; }
    function setWait(on){
      waiting = on;
      document.getElementById("msg").disabled = on;
      document.getElementById("sendBtn").disabled = on;
      document.getElementById("thinking").textContent = on ? "(thinking...)" : "";
    }
    function addChat(text, cls){
      const el = document.createElement("div");
      el.className = "line " + cls;
      el.textContent = text;
      const chat = document.getElementById("chat");
      chat.appendChild(el);
      chat.scrollTop = chat.scrollHeight;
    }
    function renderReasoning(rows, inProgress){
      const root = document.getElementById("reasoning");
      root.innerHTML = "";

      const snapshot = (rows || []).slice(-80);
      if (snapshot.length === 0) {
        const row = document.createElement("div");
        row.className = "line";
        row.textContent = inProgress
          ? "Tracing is active. Waiting for next reasoning step..."
          : "No reasoning yet. Send a message to start tracing.";
        root.appendChild(row);
        return;
      }

      snapshot.forEach(r => {
        const row = document.createElement("div");
        row.className = "line";
        row.textContent = "[" + (r.ts || "") + "] " + (r.stage || "step") + ": " + (r.detail || "");
        root.appendChild(row);
      });
      root.scrollTop = root.scrollHeight;
    }
    function hashString(text){
      let hash = 0;
      const value = text || "";
      for(let i = 0; i < value.length; i++){
        hash = ((hash << 5) - hash) + value.charCodeAt(i);
        hash |= 0;
      }
      return hash;
    }
    function stageColor(stage, inProgress){
      const key = (stage || "step").toLowerCase();
      const palette = {
        input: [77, 201, 255], decision: [255, 203, 77], route: [105, 152, 255], llm: [98, 255, 167],
        logical_output: [255, 121, 232], creative_output: [255, 161, 87], blend: [177, 120, 255], output: [240, 245, 255], step: [123, 198, 255]
      };
      const base = palette[key] || palette.step;
      if(!inProgress) return base;
      return [Math.min(255, base[0] + 16), Math.min(255, base[1] + 16), Math.min(255, base[2] + 16)];
    }
    function initWaterfall(){
      waterfallCanvas = document.getElementById("reasoningWaterfall");
      if(!waterfallCanvas) return;
      const ratio = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
      const width = Math.max(240, Math.floor(waterfallCanvas.clientWidth * ratio));
      const height = Math.max(90, Math.floor(waterfallCanvas.clientHeight * ratio));
      if(waterfallCanvas.width !== width || waterfallCanvas.height !== height){
        waterfallCanvas.width = width;
        waterfallCanvas.height = height;
      }
      waterfallCtx = waterfallCanvas.getContext("2d", { alpha: false });
      waterfallCtx.fillStyle = "#04070d";
      waterfallCtx.fillRect(0, 0, waterfallCanvas.width, waterfallCanvas.height);
      lastGeneration = null;
    }
    function drawWaterfallRow(rows, inProgress, generation){
      if(!waterfallCtx || !waterfallCanvas) return;
      const w = waterfallCanvas.width;
      const h = waterfallCanvas.height;
      waterfallCtx.drawImage(waterfallCanvas, 0, 1, w, h - 1, 0, 0, w, h - 1);
      waterfallCtx.fillStyle = "rgba(4, 7, 12, 0.96)";
      waterfallCtx.fillRect(0, h - 1, w, 1);
      if(lastGeneration !== generation){
        lastGeneration = generation;
        waterfallCtx.fillStyle = "rgba(255, 255, 255, 0.5)";
        waterfallCtx.fillRect(0, h - 1, w, 1);
      }
      const bins = Array.from({ length: WATERFALL_BINS }, () => ({ r: 0, g: 0, b: 0, e: 0 }));
      (rows || []).slice(-24).forEach((entry) => {
        const stage = entry.stage || "step";
        const detail = entry.detail || "";
        const [sr, sg, sb] = stageColor(stage, inProgress);
        const index = Math.abs(hashString(stage + "|" + detail)) % WATERFALL_BINS;
        const spread = 1 + (Math.abs(hashString(detail)) % 3);
        const strength = Math.min(1, 0.3 + (detail.length / 220));
        for(let offset = -spread; offset <= spread; offset++){
          const bucket = (index + offset + WATERFALL_BINS) % WATERFALL_BINS;
          const decay = 1 - (Math.abs(offset) / (spread + 1));
          const energy = strength * decay;
          bins[bucket].r += sr * energy;
          bins[bucket].g += sg * energy;
          bins[bucket].b += sb * energy;
          bins[bucket].e += energy;
        }
      });
      const binWidth = w / WATERFALL_BINS;
      for(let i = 0; i < WATERFALL_BINS; i++){
        const b = bins[i];
        if(b.e <= 0) continue;
        const norm = Math.min(1, b.e / 2.2);
        const r = Math.min(255, Math.round(b.r / b.e));
        const g = Math.min(255, Math.round(b.g / b.e));
        const bl = Math.min(255, Math.round(b.b / b.e));
        const x = Math.floor(i * binWidth);
        const bw = Math.ceil(binWidth + 1);
        waterfallCtx.fillStyle = `rgba(${r}, ${g}, ${bl}, ${Math.max(0.09, norm)})`;
        waterfallCtx.fillRect(x, h - 1, bw, 1);
      }
      if(inProgress){
        const sweep = Math.floor((Date.now() / 80) % w);
        waterfallCtx.fillStyle = "rgba(255, 255, 255, 0.33)";
        waterfallCtx.fillRect(sweep, h - 1, 2, 1);
      }
    }
    async function pollReasoning(force = false){
      if (reasoningPollInFlight && !force) return;
      reasoningPollInFlight = true;
      try{
        const r = await fetch("/reasoning");
        const d = await r.json();
        renderReasoning(d.entries || [], !!d.in_progress);
        drawWaterfallRow(d.entries || [], !!d.in_progress, d.generation);
      }catch(_){
      }finally{
        reasoningPollInFlight = false;
      }
    }
    async function sendMessage(){
      if (waiting) return;
      const input = document.getElementById("msg");
      const m = input.value.trim();
      if (!m) return;
      addChat(m, "user");
      input.value = "";
      setWait(true);
      status("Thinking...");
      try{
        const r = await fetch("/chat",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({message:m})});
        const d = await r.json();
        if (r.status === 429){ status(d.error || "Hold on, I am still thinking..."); return; }
        addChat(d.response || d.error || "No response", "indy");
        status("Node online");
      }catch(_){
        status("Request failed");
      }finally{
        setWait(false);
        await pollReasoning(true);
      }
    }
    async function speakLast(){ await fetch("/speak_last",{method:"POST"}); }
    document.getElementById("msg").addEventListener("keydown", e => { if (e.key === "Enter") sendMessage(); });
    setTheme(localStorage.getItem("indigo_theme") || "theme-aero");
    initWaterfall();
    setInterval(pollReasoning, 1200);
    window.addEventListener("resize", () => setTimeout(initWaterfall, 120));
    pollReasoning();
  </script>
</body>
</html>
"""


@app.get("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.post("/chat")
def chat():
    payload = request.get_json(silent=True) or {}
    prompt = str(payload.get("message", "")).strip()
    if not prompt:
        return jsonify({"error": "Request JSON must include a non-empty 'message' field."}), 400
    if not chat_lock.acquire(blocking=False):
        return jsonify({"error": "Hold on, I am still thinking..."}), 429
    try:
        return jsonify({"response": process_message(prompt)})
    finally:
        chat_lock.release()


@app.post("/speak_last")
def speak_last():
    ok = text_to_speech("Voice output check.")
    return jsonify({"ok": bool(ok)})


@app.get("/node_info")
def node_info():
    return jsonify(get_node_info())


@app.get("/reasoning")
def reasoning():
    return jsonify(get_reasoning_trace())


@app.get("/health")
def health():
    info = get_node_info()
    return jsonify({"status": "ok", **info})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False, threaded=True)
PY

cat > "$INDIGO_BASE_DIR/brain.py" <<'PY'
import json
import os
import shutil
import subprocess
import threading
from datetime import datetime
from pathlib import Path

from duckduckgo_search import DDGS

try:
    from llama_cpp import Llama
except Exception:
    Llama = None


BASE_DIR = Path(os.environ.get("INDIGO_BASE_DIR", str(Path.home() / "indigo")))
MODELS_DIR = BASE_DIR / "models"
MEMORY_DIR = BASE_DIR / "memory"
LOGS_DIR = BASE_DIR / "logs"
PIPER_MODELS_DIR = BASE_DIR / "piper_models"

PREFERRED_MODEL_FILE = MODELS_DIR / "preferred_model.txt"
PREFERRED_LOGICAL_MODEL_FILE = MODELS_DIR / "preferred_model_logical.txt"
PREFERRED_CREATIVE_MODEL_FILE = MODELS_DIR / "preferred_model_creative.txt"

for d in [MODELS_DIR, MEMORY_DIR, LOGS_DIR, PIPER_MODELS_DIR]:
    d.mkdir(parents=True, exist_ok=True)


def pick_first_existing(paths):
    for candidate in paths:
        if candidate and candidate.exists():
            return candidate
    return None


def resolve_model_ref(value):
    if not value:
        return None
    path = Path(value)
    if not path.is_absolute():
        path = MODELS_DIR / value
    return path if path.exists() else None


def read_preferred(path):
    if not path.exists():
        return None
    try:
        return resolve_model_ref(path.read_text(encoding="utf-8").strip())
    except Exception:
        return None


def fallback_models():
    order = [
        MODELS_DIR / "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
        MODELS_DIR / "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        MODELS_DIR / "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        MODELS_DIR / "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
    ]
    listed = sorted(MODELS_DIR.glob("*.gguf"), key=lambda p: (p.stat().st_size, p.stat().st_mtime), reverse=True)
    seen = set()
    merged = []
    for p in order + listed:
        if p.exists() and p not in seen:
            seen.add(p)
            merged.append(p)
    return merged


def select_models():
    fallbacks = fallback_models()
    if not fallbacks:
        return None, None

    logical = (
        read_preferred(PREFERRED_LOGICAL_MODEL_FILE)
        or read_preferred(PREFERRED_MODEL_FILE)
        or fallbacks[0]
    )
    creative = read_preferred(PREFERRED_CREATIVE_MODEL_FILE)
    if creative is None:
        creative = next((m for m in fallbacks if m != logical), logical)
    return logical, creative


MODEL_LOGICAL_PATH, MODEL_CREATIVE_PATH = select_models()


class IndigoBrain:
    def __init__(self):
        self.memory_file = MEMORY_DIR / "conversations.json"
        self.context_window = []
        self.last_response = ""
        self._llm_cache = {}
        self.trace_lock = threading.Lock()
        self.reasoning_entries = []
        self.trace_generation = 0
        self.is_thinking = False
        self.load_memory()

        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        with (LOGS_DIR / "startup.log").open("a", encoding="utf-8") as handle:
            handle.write(
                f"[{datetime.now()}] Linux node started with logical={MODEL_LOGICAL_PATH} creative={MODEL_CREATIVE_PATH}\n"
            )

    def load_memory(self):
        if self.memory_file.exists():
            try:
                self.context_window = json.loads(self.memory_file.read_text(encoding="utf-8"))
            except Exception:
                self.context_window = []
        self.context_window = self.context_window[-10:]

    def save_memory(self):
        self.memory_file.write_text(json.dumps(self.context_window[-20:]), encoding="utf-8")

    def _trace(self, stage, detail):
        entry = {
            "ts": datetime.now().strftime("%H:%M:%S"),
            "stage": (stage or "step")[:60],
            "detail": (detail or "")[:360],
        }
        with self.trace_lock:
            self.reasoning_entries.append(entry)
            self.reasoning_entries = self.reasoning_entries[-120:]

    def _start_trace(self, prompt):
        with self.trace_lock:
            self.trace_generation += 1
            self.reasoning_entries = []
            self.is_thinking = True
        self._trace("input", prompt[:220])

    def _stop_trace(self):
        with self.trace_lock:
            self.is_thinking = False

    def search_web(self, query):
        try:
            with DDGS() as ddgs:
                rows = []
                for item in ddgs.text(query, max_results=3):
                    title = item.get("title", "").strip()
                    body = item.get("body", "").strip()
                    if title or body:
                        rows.append(f"{title}: {body}".strip(": "))
                return "\n".join(rows) if rows else "No search results found."
        except Exception as exc:
            return f"Search failed: {exc}"

    def build_prompt(self, prompt, mode):
        context = ""
        if self.context_window:
            context = "Previous conversation:\n"
            for item in self.context_window[-3:]:
                context += f"Human: {item['human']}\nIndy: {item['indy']}\n"

        needs_search = any(
            phrase in prompt.lower()
            for phrase in ["what is", "who is", "tell me about", "search", "find", "latest", "news", "current", "2026"]
        )
        search_context = ""
        if needs_search:
            search_context = "\nSearch results:\n" + self.search_web(prompt) + "\n"

        system_prompts = {
            "logical": "You are the logical mind of Indigo. You are practical, structured, and precise.",
            "creative": "You are the creative mind of Indigo. You are intuitive, poetic, and playful.",
            "balanced": "You are Indigo Alpha Seven, a local AI companion with warmth and honesty.",
        }
        system = system_prompts.get(mode, system_prompts["balanced"])
        suffix = {"logical": "Indy (logical):", "creative": "Indy (creative):", "balanced": "Indy:"}.get(mode, "Indy:")
        return f"{system}\n\n{context}{search_context}\nHuman: {prompt}\n{suffix}"

    def get_llm(self, model_path):
        if Llama is None:
            raise RuntimeError("llama-cpp-python is not installed or failed to load.")
        key = str(model_path)
        if key in self._llm_cache:
            return self._llm_cache[key]
        llm = Llama(
            model_path=key,
            n_ctx=2048,
            n_threads=max(2, (os.cpu_count() or 4) - 1),
            verbose=False,
        )
        self._llm_cache[key] = llm
        return llm

    def run_llama(self, prompt, temperature, model_path):
        if model_path is None:
            return "No GGUF model found in ~/indigo/models."
        self._trace("llm", f"Running {Path(model_path).name} at temp={temperature}")
        llm = self.get_llm(model_path)
        output = llm(
            prompt,
            max_tokens=256,
            temperature=temperature,
            top_k=40,
            top_p=0.9,
            repeat_penalty=1.1,
            stop=["Human:", "Indy:"],
        )
        text = output["choices"][0]["text"].strip()
        return text or "No response came back from the model."

    def think(self, prompt, mode="balanced", temperature=0.7):
        if mode == "creative":
            model_path = MODEL_CREATIVE_PATH or MODEL_LOGICAL_PATH
        elif mode == "logical":
            model_path = MODEL_LOGICAL_PATH or MODEL_CREATIVE_PATH
        else:
            model_path = MODEL_LOGICAL_PATH or MODEL_CREATIVE_PATH
        name = Path(model_path).name if model_path else "none"
        self._trace("route", f"{mode} path using {name}")
        try:
            return self.run_llama(self.build_prompt(prompt, mode), temperature, model_path=model_path)
        except Exception as exc:
            return f"Bit of a glitch in the matrix: {exc}"

    def conductor(self, prompt):
        self._start_trace(prompt)
        try:
            lowered = prompt.lower()
            if any(word in lowered for word in ["calculate", "define", "what is", "when did", "how many"]):
                self._trace("decision", "logical specialist route")
                response = self.think(prompt, "logical", 0.3)
            elif any(word in lowered for word in ["imagine", "create", "story", "poem", "what if"]):
                self._trace("decision", "creative specialist route")
                response = self.think(prompt, "creative", 0.9)
            else:
                self._trace("decision", "dual-model conductor route")
                logical = self.think(prompt, "logical", 0.35)
                self._trace("logical_output", logical[:220])
                creative = self.think(prompt, "creative", 0.85)
                self._trace("creative_output", creative[:220])
                blend_prompt = (
                    "Combine these two responses into one natural answer.\n"
                    "Keep warmth and personality, preserve factual accuracy.\n\n"
                    f"Logical response: {logical}\n\nCreative response: {creative}"
                )
                self._trace("blend", "merging drafts")
                response = self.think(blend_prompt, "balanced", 0.55)

            self.last_response = response
            self.context_window.append({"human": prompt, "indy": response})
            self.save_memory()
            self._trace("output", response[:240])
            return response
        finally:
            self._stop_trace()

    def get_reasoning_trace(self):
        with self.trace_lock:
            return {
                "in_progress": self.is_thinking,
                "generation": self.trace_generation,
                "entries": list(self.reasoning_entries[-80:]),
                "logical_model": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
                "creative_model": MODEL_CREATIVE_PATH.name if MODEL_CREATIVE_PATH else None,
            }


brain = IndigoBrain()


def process_message(prompt):
    return brain.conductor(prompt)


def text_to_speech(text):
    piper_bin = shutil.which("piper")
    piper_model = pick_first_existing(
        [
            PIPER_MODELS_DIR / "en_GB-cori-medium.onnx",
            PIPER_MODELS_DIR / "en_GB-alan-medium.onnx",
            BASE_DIR / "en_GB-cori-medium.onnx",
            BASE_DIR / "en_GB-alan-medium.onnx",
        ]
    )
    if piper_bin is None or piper_model is None:
        return False
    output_file = MEMORY_DIR / "last_response.wav"
    try:
        result = subprocess.run(
            [piper_bin, "-m", str(piper_model), "--output_file", str(output_file)],
            input=text.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def get_reasoning_trace():
    return brain.get_reasoning_trace()


def get_node_info():
    return {
        "node_id": os.uname().nodename,
        "known_nodes": [],
        "model": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
        "model_logical": MODEL_LOGICAL_PATH.name if MODEL_LOGICAL_PATH else None,
        "model_creative": MODEL_CREATIVE_PATH.name if MODEL_CREATIVE_PATH else None,
        "runtime": "llama-cpp-python",
    }
PY

cat > "$INDIGO_BASE_DIR/run_indigo.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INDIGO_BASE_DIR="${INDIGO_BASE_DIR:-$HOME/indigo}"
# shellcheck disable=SC1091
source "$INDIGO_BASE_DIR/venv/bin/activate"
cd "$INDIGO_BASE_DIR"
python app.py
SH

cat > "$INDIGO_BASE_DIR/run_survival_tools.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INDIGO_BASE_DIR="${INDIGO_BASE_DIR:-$HOME/indigo}"
# shellcheck disable=SC1091
source "$INDIGO_BASE_DIR/venv/bin/activate"
cd "$INDIGO_BASE_DIR"
python survival_tools.py "$@"
SH

chmod +x "$INDIGO_BASE_DIR/run_indigo.sh" "$INDIGO_BASE_DIR/run_survival_tools.sh"

log "Install complete"
log "Base directory: $INDIGO_BASE_DIR"
if [[ -n "${LOGICAL_FILE:-}" ]]; then
  log "Logical model: $LOGICAL_FILE"
fi
if [[ -n "${CREATIVE_FILE:-}" ]]; then
  log "Creative model: $CREATIVE_FILE"
fi
log "Run: $INDIGO_BASE_DIR/run_indigo.sh"
