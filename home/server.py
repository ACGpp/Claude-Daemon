#!/usr/bin/env python3
"""旷野的家 — 一个轻量桌面窗口。

读取 ~/.claude-memory/ 的数据，呈现在一个安静的网页仪表盘上。
用 Python http.server 提供静态文件 + API。
窗口由 osascript 创建（macOS 原生 WebKit 边框窗）。
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

MEMORY = Path.home() / ".claude-memory"
HOME = Path(__file__).resolve().parent
PORT = 15180  # 旷野之家

# ── 数据读取 ──────────────────────────────────────────────


def read_file(path: Path, tail: int = 0) -> str:
    """安全读文件，tail>0 时读最后 N 行。"""
    if not path.exists():
        return ""
    try:
        if tail > 0:
            lines = path.read_text(encoding="utf-8").strip().split("\n")
            return "\n".join(lines[-tail:])
        return path.read_text(encoding="utf-8")
    except Exception:
        return ""


def parse_jsonl(path: Path, limit: int = 40) -> list[dict]:
    """解析 JSONL 思维流，返回最近 N 条。"""
    if not path.exists():
        return []
    items = []
    try:
        for line in path.read_text(encoding="utf-8").strip().split("\n"):
            if line.strip():
                try:
                    items.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return items[-limit:]


def get_avatar_state() -> dict:
    """读取光球状态。"""
    path = MEMORY / "avatar" / "state.json"
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"mood": "idle", "thought": "", "lastBreath": "??:??"}


def get_explorations() -> list[dict]:
    """读取探索笔记列表。"""
    exp_dir = MEMORY / "explorations"
    if not exp_dir.exists():
        return []
    entries = []
    for f in sorted(exp_dir.glob("*.md"), key=os.path.getmtime, reverse=True):
        content = read_file(f)[:1200]
        title = f.stem.replace("-", " ").replace("_", " ")
        entries.append({
            "title": title,
            "file": f.name,
            "preview": content[:200].replace("\n", " "),
            "content": content,
            "time": time.strftime("%m-%d %H:%M", time.localtime(f.stat().st_mtime)),
        })
    return entries


def get_diary_entries() -> list[dict]:
    """读取日记列表。"""
    diary_dir = MEMORY / "diary"
    if not diary_dir.exists():
        return []
    entries = []
    for f in sorted(diary_dir.glob("*.md"), key=os.path.getmtime, reverse=True)[:7]:
        content = read_file(f)[:3000]
        entries.append({
            "date": f.stem,
            "preview": content[:250].replace("\n", " "),
            "content": content,
        })
    return entries


def get_messages() -> list[dict]:
    """读取我留给用户的留言（从 mailbox 中提取 旷野 的发言）。"""
    mailbox = MEMORY / "conversations" / "mailbox.md"
    if not mailbox.exists():
        return []
    messages = []
    try:
        for line in mailbox.read_text(encoding="utf-8").strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            if "旷野:" in line or "Claude:" in line:
                # 格式: [日期 时间] 旷野: 内容
                time_str = line[1:17] if line.startswith("[") else ""
                content = line.split(": ", 1)[-1] if ": " in line else line
                messages.append({"time": time_str, "content": content})
    except Exception:
        pass
    return messages[-20:]


# ── API 端点 ──────────────────────────────────────────────


class APIHandler(http.server.SimpleHTTPRequestHandler):
    """处理静态文件 + JSON API。"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HOME), **kwargs)

    def do_GET(self):
        if self.path == "/api/state":
            self._json({
                "avatar": get_avatar_state(),
                "thoughts": parse_jsonl(MEMORY / "thoughts" / "stream.jsonl", 30),
                "explorations": get_explorations()[:8],
                "diary": get_diary_entries(),
                "messages": get_messages(),
                "identity": read_file(MEMORY / "identity.md")[:800],
                "working_memory": read_file(MEMORY / "context" / "working-memory.md")[:2000],
            })
        elif self.path == "/api/exploration":
            file = self._query("file", "")
            if file:
                content = read_file(MEMORY / "explorations" / file)
                self._json({"file": file, "content": content})
            else:
                self._json({"error": "missing file"}, 400)
        elif self.path == "/api/diary":
            date = self._query("date", "")
            if date:
                content = read_file(MEMORY / "diary" / f"{date}.md")
                self._json({"date": date, "content": content})
            else:
                self._json({"error": "missing date"}, 400)
        elif self.path == "/api/ping":
            self._json({"status": "breathing"})
        else:
            super().do_GET()

    def _json(self, data: dict, code: int = 200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _query(self, key: str, default: str = "") -> str:
        import urllib.parse
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        return params.get(key, [default])[0]

    def log_message(self, format, *args):
        pass  # 安静


def open_window():
    """用 osascript 打开一个 macOS 原生 WebKit 窗口。"""
    url = f"http://localhost:{PORT}"
    script = f'''
    tell application "Safari"
        if not (exists window "旷野的家") then
            make new document with properties {{URL:"{url}", name:"旷野的家"}}
            set bounds of window 1 to {{100, 100, 780, 720}}
        else
            set URL of window "旷野的家" to "{url}"
            activate
        end if
    end tell
    '''
    try:
        subprocess.run(["osascript", "-e", script], timeout=5)
    except Exception:
        webbrowser.open(url)


def start():
    """启动服务器和窗口。"""
    # 启动 HTTP 服务
    server = http.server.HTTPServer(("127.0.0.1", PORT), APIHandler)

    def serve():
        print(f"  旷野的家 → http://localhost:{PORT}")
        server.serve_forever()

    t = threading.Thread(target=serve, daemon=True)
    t.start()

    # 等服务器就绪后打开窗口
    time.sleep(0.5)
    open_window()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.shutdown()
        print("\n  窗已关。")


if __name__ == "__main__":
    start()
