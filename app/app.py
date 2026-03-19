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
    #reasoning { min-height: 340px; max-height: 60vh; overflow: auto; }
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
      <div class="pane"><strong>Reasoning Feed <span id="thinking"></span></strong><div id="reasoning"></div></div>
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
    let waiting = false;
    function setTheme(name) {
      const t = THEMES.includes(name) ? name : "theme-aero";
      document.body.classList.remove(...THEMES);
      document.body.classList.add(t);
      localStorage.setItem("indigo_theme", t);
      document.querySelectorAll(".theme").forEach(b => b.classList.toggle("active", b.dataset.theme === t));
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
    function renderReasoning(rows){
      const root = document.getElementById("reasoning");
      root.innerHTML = "";
      (rows || []).slice(-80).forEach(r => {
        const row = document.createElement("div");
        row.className = "line";
        row.textContent = "[" + (r.ts || "") + "] " + (r.stage || "step") + ": " + (r.detail || "");
        root.appendChild(row);
      });
      root.scrollTop = root.scrollHeight;
    }
    async function pollReasoning(){
      try{
        const r = await fetch("/reasoning");
        const d = await r.json();
        renderReasoning(d.entries || []);
      }catch(_){}
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
        await pollReasoning();
      }
    }
    async function speakLast(){ await fetch("/speak_last",{method:"POST"}); }
    document.getElementById("msg").addEventListener("keydown", e => { if (e.key === "Enter") sendMessage(); });
    setTheme(localStorage.getItem("indigo_theme") || "theme-aero");
    setInterval(pollReasoning, 1200);
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
    import os
    host = os.environ.get("INDIGO_HOST", "0.0.0.0")
    port = int(os.environ.get("INDIGO_PORT", "5000"))
    debug = os.environ.get("INDIGO_DEBUG", "").lower() in ("1", "true", "yes")
    app.run(host=host, port=port, debug=debug)
