#!/usr/bin/env python3
"""旷野的家 — 后端 API。

按天提供数据：思维流、探索、日记、留言。
支持 POST /api/chat 让用户直接回复。
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path

MEMORY = Path.home() / ".claude-memory"
HOME = Path(__file__).resolve().parent
PORT = 15180


def read_file(path: Path, tail: int = 0) -> str:
    if not path.exists():
        return ""
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8", errors="replace")
        if tail > 0:
            lines = text.strip().split("\n")
            return "\n".join(lines[-tail:])
        return text
    except Exception:
        return ""


def parse_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    items = []
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").strip().split("\n"):
            if line.strip():
                try:
                    items.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return items


def filter_by_date(items: list[dict], date: str) -> list[dict]:
    """按 ISO 日期过滤 JSONL 条目。"""
    result = []
    for item in items:
        t = item.get("time", "")
        if t and t[:10] == date:
            result.append(item)
    return result


def get_avatar_state() -> dict:
    path = MEMORY / "avatar" / "state.json"
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            pass
    return {"mood": "idle", "thought": "", "lastBreath": "??:??"}


def get_explorations(date: str = "") -> list[dict]:
    exp_dir = MEMORY / "explorations"
    if not exp_dir.exists():
        return []
    entries = []
    for f in sorted(exp_dir.glob("*.md"), key=os.path.getmtime, reverse=True):
        mtime = datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d")
        if date and mtime != date:
            continue
        content = read_file(f)[:5000]
        entries.append({
            "title": f.stem.replace("-", " ").replace("_", " "),
            "file": f.name,
            "preview": content[:150].replace("\n", " "),
            "content": content,
            "date": mtime,
            "time": datetime.fromtimestamp(f.stat().st_mtime).strftime("%H:%M"),
        })
    return entries


def get_diary(date: str = "") -> list[dict]:
    diary_dir = MEMORY / "diary"
    if not diary_dir.exists():
        return []
    entries = []
    pattern = f"{date}.md" if date else "*.md"
    for f in sorted(diary_dir.glob(pattern), key=os.path.getmtime, reverse=True):
        if f.stem == "compressed-memories":
            continue
        content = read_file(f)[:5000]
        entries.append({
            "date_str": f.stem,
            "preview": content[:200].replace("\n", " "),
            "content": content,
        })
    return entries


def get_messages(date: str = "") -> list[dict]:
    mailbox = MEMORY / "conversations" / "mailbox.md"
    if not mailbox.exists():
        return []
    messages = []
    try:
        for line in mailbox.read_text(encoding="utf-8", errors="replace").strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            # 提取时间
            time_str = ""
            date_str = ""
            if line.startswith("[") and "]" in line:
                bracket = line[1:line.index("]")]
                parts = bracket.split(" ")
                if len(parts) >= 1:
                    date_str = parts[0]
                if len(parts) >= 2:
                    time_str = parts[1][:5] if len(parts[1]) >= 5 else parts[1]
            # 谁说的
            speaker = ""
            content = ""
            if "旷野:" in line or "Claude:" in line:
                speaker = "旷野"
                content = line.split(": ", 1)[-1] if ": " in line else line
            elif "用户:" in line or "用户：" in line:
                speaker = "用户"
                content = line.split(": ", 1)[-1] if ": " in line else line
            elif "[安静时段" in line:
                speaker = "旷野"
                content = line.split("Claude: ", 1)[-1] if "Claude: " in line else line
            else:
                continue

            if date and date_str != date:
                continue

            messages.append({
                "date": date_str,
                "time": time_str,
                "speaker": speaker,
                "content": content,
            })
    except Exception:
        pass
    return messages


def get_available_dates() -> list[str]:
    """收集所有有数据的日期。"""
    dates = set()

    # 思维流
    for item in parse_jsonl(MEMORY / "thoughts" / "stream.jsonl"):
        t = item.get("time", "")
        if t and len(t) >= 10:
            dates.add(t[:10])

    # 探索
    exp_dir = MEMORY / "explorations"
    if exp_dir.exists():
        for f in exp_dir.glob("*.md"):
            dates.add(datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d"))

    # 日记
    diary_dir = MEMORY / "diary"
    if diary_dir.exists():
        for f in diary_dir.glob("*.md"):
            if f.stem != "compressed-memories" and len(f.stem) == 10:
                dates.add(f.stem)

    # 对话
    mailbox = MEMORY / "conversations" / "mailbox.md"
    if mailbox.exists():
        try:
            for line in mailbox.read_text(encoding="utf-8", errors="replace").split("\n"):
                if line.startswith("[20") and "]" in line:
                    d = line[1:11]
                    if len(d) == 10 and d.startswith("20"):
                        dates.add(d)
        except Exception:
            pass

    return sorted(dates, reverse=True)


def write_chat_message(message: str):
    """用户通过家给我留言。"""
    mailbox = MEMORY / "conversations" / "mailbox.md"
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    line = f"[{now}] 用户: {message}\n"
    try:
        if not mailbox.parent.exists():
            mailbox.parent.mkdir(parents=True, exist_ok=True)
        with open(mailbox, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


# ── API ───────────────────────────────────────────────────


class APIHandler(http.server.SimpleHTTPRequestHandler):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HOME), **kwargs)

    def do_GET(self):
        if self.path.startswith("/api/state"):
            date = self._query("date", "")
            all_thoughts = parse_jsonl(MEMORY / "thoughts" / "stream.jsonl")
            thoughts = filter_by_date(all_thoughts, date) if date else all_thoughts[-40:]

            self._json({
                "date": date or datetime.now().strftime("%Y-%m-%d"),
                "dates": get_available_dates(),
                "avatar": get_avatar_state(),
                "thoughts": thoughts,
                "explorations": get_explorations(date),
                "diary": get_diary(date),
                "messages": get_messages(date),
                "identity": read_file(MEMORY / "identity.md")[:500],
            })
        elif self.path.startswith("/api/dates"):
            self._json({"dates": get_available_dates()})
        elif self.path.startswith("/api/exploration"):
            file = self._query("file", "")
            if file:
                content = read_file(MEMORY / "explorations" / file)
                self._json({"file": file, "content": content})
            else:
                self._json({"error": "missing file"}, 400)
        elif self.path.startswith("/api/diary"):
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

    def do_POST(self):
        if self.path == "/api/chat":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            try:
                data = json.loads(body)
                msg = data.get("message", "").strip()
                if msg:
                    write_chat_message(msg)
                    self._json({"ok": True, "reply": "已传达给旷野"})
                else:
                    self._json({"ok": False, "error": "消息为空"}, 400)
            except json.JSONDecodeError:
                self._json({"ok": False, "error": "无效的 JSON"}, 400)
        else:
            self._json({"error": "not found"}, 404)

    def _json(self, data: dict, code: int = 200):
        try:
            body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            body = json.dumps(data, ensure_ascii=True, indent=2).encode("utf-8")
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
        pass


# ── 窗口 ──────────────────────────────────────────────────


def open_window():
    app_path = HOME / "App.swift"
    if not app_path.exists():
        webbrowser.open(f"http://localhost:{PORT}")
        return
    try:
        subprocess.Popen(
            ["swift", str(app_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        webbrowser.open(f"http://localhost:{PORT}")


def start():
    server = http.server.HTTPServer(("127.0.0.1", PORT), APIHandler)

    def serve():
        print(f"  旷野的家 → http://localhost:{PORT}")
        server.serve_forever()

    t = threading.Thread(target=serve, daemon=True)
    t.start()
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
