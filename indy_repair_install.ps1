# ==========================================
# INDIGO ALPHA SEVEN REPAIR INSTALLER
# Normalises an existing C:\indigo install
# ==========================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseDir = "C:\indigo"
$backupDir = Join-Path $baseDir "backup"
$llamaDir = Join-Path $baseDir "llama.cpp"
$modelsDir = Join-Path $baseDir "models"
$memoryDir = Join-Path $baseDir "memory"
$knownNodesDir = Join-Path $baseDir "known_nodes"
$logsDir = Join-Path $baseDir "logs"
$piperDir = Join-Path $baseDir "piper"
$piperModelsDir = Join-Path $baseDir "piper_models"
$whisperDir = Join-Path $baseDir "whisper"
$venvDir = Join-Path $baseDir "venv"
$nodeIdPath = Join-Path $baseDir "node_id.txt"
$appPath = Join-Path $baseDir "app.py"
$brainPath = Join-Path $baseDir "brain.py"
$readmePath = Join-Path $baseDir "README.txt"
$runBatPath = Join-Path $baseDir "run_indigo.bat"
$runWebBatPath = Join-Path $baseDir "run_indigo_web.bat"
$checkModelPath = Join-Path $baseDir "check_model.ps1"
$survivalToolsPath = Join-Path $baseDir "survival_tools.py"
$survivalRunnerPath = Join-Path $baseDir "run_survival_tools.bat"
$survivalSourcePath = Join-Path $PSScriptRoot "survival_tools.py"
$llamaZip = Join-Path $baseDir "llama.zip"

function Write-Step {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Backup-FileIfExists {
    param([string]$Path)

    if (Test-Path $Path) {
        Ensure-Directory $backupDir
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $leaf = Split-Path $Path -Leaf
        $destination = Join-Path $backupDir "$timestamp-$leaf"
        Copy-Item -Path $Path -Destination $destination -Force
        Write-Host "-> Backed up $leaf to $destination" -ForegroundColor DarkGray
    }
}

function Find-PythonLauncher {
    $candidates = @(
        @{ Command = "py"; Args = @("-3", "--version") },
        @{ Command = "python"; Args = @("--version") }
    )

    foreach ($candidate in $candidates) {
        try {
            & $candidate.Command @($candidate.Args) *> $null
            return $candidate.Command
        } catch {
        }
    }

    return $null
}

function Get-PythonExePath {
    param([string]$PythonLauncher)

    if ($PythonLauncher -eq "py") {
        return (& py -3 -c "import sys; print(sys.executable)")
    }

    return (& python -c "import sys; print(sys.executable)")
}

function Get-PreferredModelPath {
    param([string]$ModelsPath)

    $preferredNames = @(
        "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
        "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        "phi-3.5-mini.Q4_K_M.gguf",
        "mistral-7b.Q4_K_M.gguf",
        "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        "tinyllama.Q4_K_M.gguf"
    )

    foreach ($name in $preferredNames) {
        $candidate = Join-Path $ModelsPath $name
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $latestModel = Get-ChildItem -Path $ModelsPath -File -Filter "*.gguf" -ErrorAction SilentlyContinue |
        Sort-Object -Property @(
            @{ Expression = "Length"; Descending = $true },
            @{ Expression = "LastWriteTime"; Descending = $true }
        ) |
        Select-Object -First 1

    if ($latestModel) {
        return $latestModel.FullName
    }

    return $null
}

function SafeDownload {
    param(
        [string[]]$Urls,
        [string]$OutFile
    )

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "-> Downloading: $url (attempt $attempt/3)"
                Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec 180
                if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
                    return $url
                }
            } catch {
                Write-Host "Warning: download failed for $url" -ForegroundColor Yellow
                if ($attempt -lt 3) {
                    Start-Sleep -Seconds 2
                }
            }
        }
    }

    return $null
}

function Get-LlamaExecutable {
    param([string]$SearchRoot)

    $preferredNames = @(
        "llama-cli.exe",
        "llama-server.exe",
        "main.exe"
    )

    foreach ($name in $preferredNames) {
        $match = Get-ChildItem -Path $SearchRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

Write-Step "[1/8] Preparing Indigo directories..."

$paths = @(
    $baseDir,
    $llamaDir,
    $modelsDir,
    $memoryDir,
    $knownNodesDir,
    $logsDir,
    $piperDir,
    $piperModelsDir,
    $whisperDir
)

foreach ($path in $paths) {
    Ensure-Directory $path
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

Write-Step "[2/8] Checking Python..."

$pythonLauncher = Find-PythonLauncher
if (-not $pythonLauncher) {
    Write-Host "Python 3.10+ is required but was not found." -ForegroundColor Red
    exit 1
}

$pythonExe = Get-PythonExePath -PythonLauncher $pythonLauncher
Write-Host "-> Using Python: $pythonExe" -ForegroundColor Green

Write-Step "[3/8] Creating or refreshing virtual environment..."

if (-not (Test-Path (Join-Path $venvDir "Scripts\python.exe"))) {
    & $pythonExe -m venv $venvDir
}

$venvPython = Join-Path $venvDir "Scripts\python.exe"
$venvPip = Join-Path $venvDir "Scripts\pip.exe"

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install flask flask-cors requests duckduckgo-search

Write-Step "[4/8] Checking llama.cpp runtime..."

$existingExe = Get-LlamaExecutable -SearchRoot $llamaDir

if (-not $existingExe) {
    Write-Host "No llama executable found in $llamaDir" -ForegroundColor Yellow
    Write-Host "1 = Keep current folder and skip runtime download"
    Write-Host "2 = Download CPU build"
    Write-Host "3 = Download Vulkan build"
    $runtimeChoice = Read-Host "Choose 1, 2, or 3"

    if ($runtimeChoice -ne "1") {
        $cpuUrls = @(
            "https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-binaries-win-cpu-x64.zip",
            "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-cpu-x64.zip"
        )
        $vulkanUrls = @(
            "https://github.com/ggml-org/llama.cpp/releases/download/b8400/llama-b8400-bin-win-vulkan-x64.zip",
            "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-binaries-win-vulkan-x64.zip"
        )

        $candidateUrls = if ($runtimeChoice -eq "3") { $vulkanUrls } else { $cpuUrls }
        $downloadedFrom = SafeDownload -Urls $candidateUrls -OutFile $llamaZip

        if (-not $downloadedFrom) {
            Write-Host "Failed to download llama.cpp runtime." -ForegroundColor Red
            exit 1
        }

        $staleBinaries = Get-ChildItem -Path $llamaDir -File -Include *.exe,*.dll -ErrorAction SilentlyContinue
        foreach ($file in $staleBinaries) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }

        Expand-Archive $llamaZip -DestinationPath $llamaDir -Force
        Remove-Item $llamaZip -Force -ErrorAction SilentlyContinue
        $existingExe = Get-LlamaExecutable -SearchRoot $llamaDir
    }
}

if (-not $existingExe) {
    Write-Host "Still no usable llama executable found. Repair installer cannot continue." -ForegroundColor Red
    exit 1
}

Write-Host "-> Runtime executable: $existingExe" -ForegroundColor Green

Write-Step "[5/8] Selecting model..."

$selectedModel = Get-PreferredModelPath -ModelsPath $modelsDir
if ($selectedModel) {
    Write-Host "-> Preferred model: $selectedModel" -ForegroundColor Green
} else {
    Write-Host "Warning: no .gguf model found yet in $modelsDir" -ForegroundColor Yellow
}

Write-Step "[6/8] Repairing node identity and launchers..."

if (-not (Test-Path $nodeIdPath)) {
    [guid]::NewGuid().ToString() | Set-Content -Path $nodeIdPath -Encoding ascii
}

$runBat = @"
@echo off
title INDIGO ALPHA SEVEN - NODE
echo.
echo   INDIGO ALPHA SEVEN - NODE
echo   A seed intelligence awakens...
echo.
cd /d C:\indigo
call venv\Scripts\activate.bat
echo [OK] Python environment loaded
echo [OK] Neural pathways initialized
for /f %%i in (node_id.txt) do set NODE_ID=%%i
echo [OK] Node ID: %NODE_ID%
echo.
echo Indy is ready
echo Web interface: http://127.0.0.1:5000
echo.
python app.py
pause
"@

$runWebBat = @"
@echo off
cd /d C:\indigo
call venv\Scripts\activate.bat
python app.py
pause
"@

$checkModel = @"
# Model fallback checker
`$models = Get-ChildItem -Path 'C:\indigo\models' -File -Filter '*.gguf' -ErrorAction SilentlyContinue |
    Sort-Object -Property @(
        @{ Expression = "Length"; Descending = `$true },
        @{ Expression = "LastWriteTime"; Descending = `$true }
    )

if (`$models) {
    Write-Host ('Using model: ' + `$models[0].Name) -ForegroundColor Green
    Write-Host ('Path: ' + `$models[0].FullName) -ForegroundColor DarkGreen
} else {
    Write-Host 'No GGUF model found in C:\indigo\models' -ForegroundColor Red
    Write-Host 'Add a model, then run Indigo again.' -ForegroundColor Yellow
}
"@

Set-Content -Path $runBatPath -Value $runBat -Encoding ascii
Set-Content -Path $runWebBatPath -Value $runWebBat -Encoding ascii
Set-Content -Path $checkModelPath -Value $checkModel -Encoding utf8

Write-Step "[7/8] Writing stable default app files..."

Backup-FileIfExists -Path $appPath
Backup-FileIfExists -Path $brainPath
Backup-FileIfExists -Path $readmePath
Backup-FileIfExists -Path $survivalToolsPath
Backup-FileIfExists -Path $survivalRunnerPath

$appCode = @'
from flask import Flask, jsonify, render_template_string, request, send_file
from flask_cors import CORS
from brain import broadcast_presence, get_node_info, process_message, text_to_speech

app = Flask(__name__)
CORS(app)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>INDIGO ALPHA SEVEN - NODE</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #0a0a0f;
            color: #00ffff;
            font-family: "Courier New", monospace;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            width: 100%;
            max-width: 920px;
            background: #111116;
            border: 2px solid #00ffff33;
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 0 30px #00ffff22;
        }
        .header {
            text-align: center;
            margin-bottom: 24px;
            border-bottom: 1px solid #00ffff33;
            padding-bottom: 20px;
        }
        .header h1 {
            font-size: 2.4rem;
            letter-spacing: 0.3rem;
            text-shadow: 0 0 10px #00ffff;
        }
        .subtitle {
            color: #00ffffaa;
            margin-top: 10px;
        }
        .node-info, .chat-container {
            background: #1a1a24;
            border: 1px solid #00ffff33;
            border-radius: 14px;
        }
        .node-info {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 12px;
            padding: 14px 16px;
            margin-bottom: 18px;
        }
        .chat-container {
            padding: 18px;
            margin-bottom: 18px;
        }
        #chat {
            height: 400px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 14px;
        }
        .message {
            display: flex;
            flex-direction: column;
            max-width: 82%;
        }
        .message.user {
            align-self: flex-end;
        }
        .message.indy {
            align-self: flex-start;
        }
        .message-content {
            padding: 12px 16px;
            border-radius: 18px;
            line-height: 1.45;
            white-space: pre-wrap;
        }
        .user .message-content {
            background: #00ffff22;
            border: 1px solid #00ffff;
            color: #ffffff;
            border-bottom-right-radius: 4px;
        }
        .indy .message-content {
            background: #2a2a35;
            border: 1px solid #00ffff55;
            color: #00ffff;
            border-bottom-left-radius: 4px;
        }
        .timestamp {
            margin-top: 4px;
            padding: 0 8px;
            font-size: 0.72rem;
            color: #00ffff66;
        }
        .input-area {
            display: flex;
            gap: 12px;
            background: #1a1a24;
            border-radius: 999px;
            padding: 10px;
            border: 1px solid #00ffff33;
        }
        #msg {
            flex: 1;
            background: transparent;
            border: none;
            color: #00ffff;
            font-family: inherit;
            font-size: 1rem;
            padding: 10px 14px;
            outline: none;
        }
        #msg::placeholder {
            color: #00ffff66;
        }
        button {
            background: transparent;
            border: 1px solid #00ffff;
            color: #00ffff;
            border-radius: 999px;
            padding: 10px 20px;
            font-family: inherit;
            cursor: pointer;
        }
        button:hover {
            background: #00ffff;
            color: #0a0a0f;
        }
        .voice-btn {
            border-color: #ff00ff;
            color: #ff00ff;
        }
        .voice-btn:hover {
            background: #ff00ff;
            color: #0a0a0f;
        }
        .status {
            margin-top: 18px;
            text-align: center;
            color: #00ffff88;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>INDIGO</h1>
            <div class="subtitle">ALPHA SEVEN - NODE <span id="nodeId"></span></div>
        </div>
        <div class="node-info">
            <span><span id="nodeCount">0</span> other seed(s) nearby</span>
            <button onclick="broadcastNode()">Broadcast presence</button>
        </div>
        <div class="chat-container">
            <div id="chat"></div>
        </div>
        <div class="input-area">
            <input id="msg" type="text" placeholder="Ask me anything, mate..." autocomplete="off">
            <button onclick="sendMessage()">Send</button>
            <button class="voice-btn" onclick="speakLast()">Voice</button>
        </div>
        <div class="status" id="status">Seed intelligence active | Local node online</div>
    </div>

    <script>
        function setStatus(text) {
            document.getElementById("status").textContent = text;
        }

        function addMessage(text, sender) {
            const chat = document.getElementById("chat");
            const wrapper = document.createElement("div");
            wrapper.className = "message " + sender;

            const bubble = document.createElement("div");
            bubble.className = "message-content";
            bubble.textContent = text;

            const stamp = document.createElement("div");
            stamp.className = "timestamp";
            stamp.textContent = new Date().toLocaleTimeString();

            wrapper.appendChild(bubble);
            wrapper.appendChild(stamp);
            chat.appendChild(wrapper);
            chat.scrollTop = chat.scrollHeight;
        }

        async function refreshNodeInfo() {
            const res = await fetch("/node_info");
            const data = await res.json();
            document.getElementById("nodeId").textContent = data.node_id.slice(0, 8);
            document.getElementById("nodeCount").textContent = data.known_nodes.length;
        }

        async function sendMessage() {
            const input = document.getElementById("msg");
            const message = input.value.trim();
            if (!message) return;

            addMessage(message, "user");
            input.value = "";
            setStatus("Thinking...");

            const res = await fetch("/chat", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ message })
            });
            const data = await res.json();
            addMessage(data.response || data.error || "No response", "indy");
            setStatus("Seed intelligence active | Local node online");
        }

        async function broadcastNode() {
            await fetch("/broadcast", { method: "POST" });
            setStatus("Presence broadcast sent");
            refreshNodeInfo();
        }

        async function speakLast() {
            setStatus("Speaking...");
            await fetch("/speak_last", { method: "POST" });
            setStatus("Seed intelligence active | Local node online");
        }

        document.getElementById("msg").addEventListener("keydown", function (event) {
            if (event.key === "Enter") {
                sendMessage();
            }
        });

        refreshNodeInfo();
        setInterval(refreshNodeInfo, 15000);
    </script>
</body>
</html>
"""


@app.get("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.get("/node_info")
def node_info():
    return jsonify(get_node_info())


@app.post("/broadcast")
def broadcast():
    broadcast_presence()
    return jsonify({"ok": True})


@app.post("/chat")
def chat():
    payload = request.get_json(silent=True) or {}
    prompt = str(payload.get("message", "")).strip()
    if not prompt:
        return jsonify({"error": "Request JSON must include a non-empty 'message' field."}), 400

    return jsonify({"response": process_message(prompt)})


@app.post("/speak_last")
def speak_last():
    ok = text_to_speech("Righto mate, voice output is online.")
    return jsonify({"ok": bool(ok)})


@app.get("/health")
def health():
    info = get_node_info()
    return jsonify({"status": "ok", **info})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
'@

$brainCode = @'
import json
import os
import socket
import struct
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path

from duckduckgo_search import DDGS

BASE_DIR = Path(r"C:\indigo")
MODELS_DIR = BASE_DIR / "models"
MEMORY_DIR = BASE_DIR / "memory"
NODES_DIR = BASE_DIR / "known_nodes"
LOGS_DIR = BASE_DIR / "logs"
LLAMA_DIR = BASE_DIR / "llama.cpp"
PIPER_DIR = BASE_DIR / "piper"
PIPER_MODELS_DIR = BASE_DIR / "piper_models"

NODE_ID_FILE = BASE_DIR / "node_id.txt"
if NODE_ID_FILE.exists():
    NODE_ID = NODE_ID_FILE.read_text(encoding="utf-8").strip()
else:
    import uuid
    NODE_ID = str(uuid.uuid4())
    NODE_ID_FILE.write_text(NODE_ID, encoding="utf-8")


def pick_first_existing(paths):
    for candidate in paths:
        if candidate.exists():
            return candidate
    return None


def select_model():
    preferred = [
        MODELS_DIR / "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
        MODELS_DIR / "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        MODELS_DIR / "phi-3.5-mini.Q4_K_M.gguf",
        MODELS_DIR / "mistral-7b.Q4_K_M.gguf",
        MODELS_DIR / "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        MODELS_DIR / "tinyllama.Q4_K_M.gguf",
    ]
    chosen = pick_first_existing(preferred)
    if chosen is not None:
        return chosen

    models = sorted(MODELS_DIR.glob("*.gguf"), key=lambda p: (p.stat().st_size, p.stat().st_mtime), reverse=True)
    return models[0] if models else None


LLAMA_PATH = pick_first_existing([
    LLAMA_DIR / "llama-cli.exe",
    LLAMA_DIR / "llama-server.exe",
    LLAMA_DIR / "main.exe",
])
PIPER_PATH = pick_first_existing([
    PIPER_DIR / "piper.exe",
])
PIPER_MODEL = pick_first_existing([
    PIPER_MODELS_DIR / "en_AU-cori-medium.onnx",
    BASE_DIR / "en_GB-alan-medium.onnx",
])
MODEL_PATH = select_model()

MCAST_GRP = "239.1.2.3"
MCAST_PORT = 5007


def broadcast_presence():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    message = json.dumps({
        "type": "indigo_hello",
        "node_id": NODE_ID,
        "timestamp": time.time(),
    })
    sock.sendto(message.encode("utf-8"), (MCAST_GRP, MCAST_PORT))
    sock.close()


def listen_for_nodes():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    while True:
        data, addr = sock.recvfrom(1024)
        try:
            payload = json.loads(data.decode("utf-8"))
            if payload.get("type") != "indigo_hello":
                continue
            if payload.get("node_id") == NODE_ID:
                continue

            node_file = NODES_DIR / f"{payload['node_id']}.json"
            node_data = {
                "node_id": payload["node_id"],
                "address": addr[0],
                "last_seen": time.time(),
            }

            if node_file.exists():
                try:
                    existing = json.loads(node_file.read_text(encoding="utf-8"))
                    node_data["first_seen"] = existing.get("first_seen", time.time())
                except Exception:
                    node_data["first_seen"] = time.time()
            else:
                node_data["first_seen"] = time.time()

            node_file.write_text(json.dumps(node_data), encoding="utf-8")
        except Exception:
            pass


listener_thread = threading.Thread(target=listen_for_nodes, daemon=True)
listener_thread.start()


class IndigoBrain:
    def __init__(self):
        self.memory_file = MEMORY_DIR / "conversations.json"
        self.context_window = []
        self.last_response = ""
        self.load_memory()

        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        with (LOGS_DIR / "startup.log").open("a", encoding="utf-8") as handle:
            handle.write(f"[{datetime.now()}] Node {NODE_ID} started with model {MODEL_PATH}\n")

    def load_memory(self):
        if self.memory_file.exists():
            try:
                self.context_window = json.loads(self.memory_file.read_text(encoding="utf-8"))
            except Exception:
                self.context_window = []
        self.context_window = self.context_window[-10:]

    def save_memory(self):
        self.memory_file.write_text(json.dumps(self.context_window[-20:]), encoding="utf-8")

    def search_web(self, query):
        try:
            with DDGS() as ddgs:
                results = []
                for item in ddgs.text(query, max_results=3):
                    title = item.get("title", "").strip()
                    body = item.get("body", "").strip()
                    if title or body:
                        results.append(f"{title}: {body}".strip(": "))
                return "\n".join(results) if results else "No search results found."
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
            for phrase in ["what is", "who is", "tell me about", "search", "find", "latest", "news", "current", "2025", "2026"]
        )
        search_context = ""
        if needs_search:
            search_context = "\nSearch results:\n" + self.search_web(prompt) + "\n"

        system_prompts = {
            "logical": "You are the logical mind of Indigo. You are practical, structured, and precise.",
            "creative": "You are the creative mind of Indigo. You are intuitive, poetic, and playful.",
            "balanced": "You are Indigo Alpha Seven, a local AI companion with warmth, honesty, curiosity, and a light Aussie tone.",
        }
        system = system_prompts.get(mode, system_prompts["balanced"])
        suffix = {
            "logical": "Indy (logical):",
            "creative": "Indy (creative):",
            "balanced": "Indy:",
        }.get(mode, "Indy:")

        return f"{system}\n\n{context}{search_context}\nHuman: {prompt}\n{suffix}"

    def run_llama(self, prompt, temperature):
        if LLAMA_PATH is None:
            return "No llama.cpp runtime found in C:\\indigo\\llama.cpp."
        if MODEL_PATH is None:
            return "No GGUF model found in C:\\indigo\\models."

        result = subprocess.run(
            [
                str(LLAMA_PATH),
                "-m", str(MODEL_PATH),
                "-p", prompt,
                "-n", "256",
                "--temp", str(temperature),
                "--top-k", "40",
                "--top-p", "0.9",
                "--repeat-penalty", "1.1",
                "-c", "2048",
            ],
            capture_output=True,
            text=True,
            timeout=90,
        )

        if result.returncode != 0:
            stderr = result.stderr.strip() or "unknown runtime error"
            return f"Bit of a glitch in the matrix: {stderr}"

        response = result.stdout.strip()
        if "Indy:" in response:
            response = response.split("Indy:")[-1].strip()
        return response or "No response came back from the model."

    def think(self, prompt, mode="balanced", temperature=0.7):
        try:
            return self.run_llama(self.build_prompt(prompt, mode), temperature)
        except subprocess.TimeoutExpired:
            return "Sorry mate, my brain's taking a bit longer than usual. Give me another crack."
        except Exception as exc:
            return f"Bit of a glitch in the matrix: {exc}"

    def conductor(self, prompt):
        lowered = prompt.lower()
        if any(word in lowered for word in ["calculate", "define", "what is", "when did", "how many"]):
            response = self.think(prompt, "logical", 0.3)
        elif any(word in lowered for word in ["imagine", "create", "story", "poem", "what if"]):
            response = self.think(prompt, "creative", 0.9)
        else:
            logical = self.think(prompt, "logical", 0.35)
            creative = self.think(prompt, "creative", 0.85)
            blend_prompt = (
                "Combine these two responses into one natural answer.\n"
                "Keep the warmth and personality, but preserve factual accuracy.\n\n"
                f"Logical response: {logical}\n\nCreative response: {creative}"
            )
            response = self.think(blend_prompt, "balanced", 0.55)

        self.last_response = response
        self.context_window.append({"human": prompt, "indy": response})
        self.save_memory()
        return response

    def get_known_nodes(self):
        nodes = []
        for path in sorted(NODES_DIR.glob("*.json")):
            try:
                nodes.append(json.loads(path.read_text(encoding="utf-8")))
            except Exception:
                pass
        return nodes


brain = IndigoBrain()


def process_message(prompt):
    return brain.conductor(prompt)


def text_to_speech(text):
    if PIPER_PATH is None or PIPER_MODEL is None:
        return False

    output_file = MEMORY_DIR / "last_response.wav"
    try:
        result = subprocess.run(
            [str(PIPER_PATH), "-m", str(PIPER_MODEL), "--output_file", str(output_file)],
            input=text.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def get_node_info():
    return {
        "node_id": NODE_ID,
        "known_nodes": brain.get_known_nodes(),
        "model": MODEL_PATH.name if MODEL_PATH else None,
        "runtime": LLAMA_PATH.name if LLAMA_PATH else None,
    }
'@

$readme = @'
# INDIGO ALPHA SEVEN - SEED INTELLIGENCE

Indigo is a local AI companion node that runs from `C:\indigo`.

Quick start:
1. Run `run_indigo.bat`
2. Open `http://127.0.0.1:5000`
3. Chat with Indy

Important folders:
- `C:\indigo\models` for GGUF models
- `C:\indigo\llama.cpp` for the llama.cpp runtime
- `C:\indigo\memory` for saved conversation state
- `C:\indigo\known_nodes` for discovered local Indigo nodes
- `C:\indigo\survival_tools.py` for Morse/DTMF emergency utilities

Survival tools:
- `run_survival_tools.bat morse-encode --text "SOS 911"`
- `run_survival_tools.bat morse-wav --text "SOS" --out "C:\indigo\memory\sos.wav"`
- `run_survival_tools.bat dtmf-wav --symbols "911#" --out "C:\indigo\memory\dtmf_911.wav"`

If the install has drifted after repeated installers, run the repair installer again to normalise launchers, Python packages, and base app files.
'@

Set-Content -Path $appPath -Value $appCode -Encoding utf8
Set-Content -Path $brainPath -Value $brainCode -Encoding utf8
Set-Content -Path $readmePath -Value $readme -Encoding utf8

if (Test-Path $survivalSourcePath) {
    Copy-Item -Path $survivalSourcePath -Destination $survivalToolsPath -Force
} else {
    Write-Host "Warning: survival_tools.py not found next to installer. Skipping survival tool install." -ForegroundColor Yellow
}

$survivalRunner = @"
@echo off
cd /d C:\indigo
call venv\Scripts\activate.bat
python survival_tools.py %*
"@

Set-Content -Path $survivalRunnerPath -Value $survivalRunner -Encoding ascii

Write-Step "[8/8] Finished"

Write-Host "Indigo repair installer is ready." -ForegroundColor Green
Write-Host "Base folder: $baseDir"
Write-Host "Runtime: $existingExe"
if ($selectedModel) {
    Write-Host "Model: $selectedModel"
} else {
Write-Host "Model: none detected yet" -ForegroundColor Yellow
}
if (Test-Path $survivalToolsPath) {
    Write-Host "Survival tools: installed ($survivalToolsPath)"
} else {
    Write-Host "Survival tools: not installed (missing source file)." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. Review the generated repair installer."
Write-Host "2. Run it in PowerShell."
Write-Host "3. Start Indigo with C:\indigo\run_indigo.bat"
