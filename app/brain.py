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
MODELS_DIR = Path(os.environ.get("INDIGO_MODEL_DIR", str(BASE_DIR / "models")))
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
            n_ctx=int(os.environ.get("INDIGO_CTX_SIZE", "2048")),
            n_threads=max(2, (os.cpu_count() or 4) - 1),
            verbose=False,
        )
        self._llm_cache[key] = llm
        return llm

    def run_llama(self, prompt, temperature, model_path):
        if model_path is None:
            return f"No GGUF model found in {MODELS_DIR}"
        self._trace("llm", f"Running {Path(model_path).name} at temp={temperature}")
        llm = self.get_llm(model_path)
        output = llm(
            prompt,
            max_tokens=int(os.environ.get("INDIGO_MAX_TOKENS", "256")),
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
