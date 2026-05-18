#!/usr/bin/env swift

import Cocoa
import WebKit
import Foundation

// ─── 数据读取 ──────────────────────────────────────────────

let memoryDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude-memory")

func readFile(_ path: String, tail: Int = 0) -> String {
    let url = memoryDir.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else { return "" }
    if tail > 0 {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.suffix(tail).joined(separator: "\n")
    }
    return text
}

func parseJSONL(_ path: String) -> [[String: Any]] {
    let text = readFile(path)
    var items: [[String: Any]] = []
    for line in text.components(separatedBy: "\n") {
        guard !line.isEmpty, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        items.append(obj)
    }
    return items
}

func avatarState() -> [String: Any] {
    guard let data = try? Data(contentsOf: memoryDir.appendingPathComponent("avatar/state.json")),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ["mood": "idle", "thought": "", "lastBreath": "??:??"] }
    return obj
}

func explorations(for date: String) -> [[String: Any]] {
    let dir = memoryDir.appendingPathComponent("explorations")
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
    else { return [] }
    
    let fm = FileManager.default
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    let tf = DateFormatter(); tf.dateFormat = "HH:mm"
    
    return files.filter { $0.pathExtension == "md" }.compactMap { url -> [String: Any]? in
        guard let attr = try? fm.attributesOfItem(atPath: url.path),
              let mtime = attr[.modificationDate] as? Date else { return nil }
        let fileDate = df.string(from: mtime)
        if !date.isEmpty && fileDate != date { return nil }
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return [
            "title": url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "),
            "file": url.lastPathComponent,
            "preview": String(content.prefix(150)).replacingOccurrences(of: "\n", with: " "),
            "content": String(content.prefix(5000)),
            "date": fileDate,
            "time": tf.string(from: mtime)
        ]
    }.sorted { ($0["date"] as? String ?? "") > ($1["date"] as? String ?? "") }
}

func diary(for date: String) -> [[String: Any]] {
    let dir = memoryDir.appendingPathComponent("diary")
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
    else { return [] }
    
    let pattern = date.isEmpty ? "" : date
    return files.filter { $0.pathExtension == "md" && $0.deletingPathExtension().lastPathComponent != "compressed-memories" }
        .filter { pattern.isEmpty || $0.deletingPathExtension().lastPathComponent == pattern }
        .compactMap { url -> [String: Any]? in
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return [
                "date_str": url.deletingPathExtension().lastPathComponent,
                "preview": String(content.prefix(200)).replacingOccurrences(of: "\n", with: " "),
                "content": String(content.prefix(5000))
            ]
        }.sorted { ($0["date_str"] as? String ?? "") > ($1["date_str"] as? String ?? "") }
}

func mailboxMessages(for date: String) -> [[String: Any]] {
    let text = readFile("conversations/mailbox.md")
    var msgs: [[String: Any]] = []
    
    let pattern = try! NSRegularExpression(
        pattern: "^\\[(?:(\\d{4}-\\d{2}-\\d{2}) )?(\\d{1,2}:\\d{2})\\]\\s*(.+?)[:：]\\s*(.*)$",
        options: [.anchorsMatchLines]
    )
    
    for line in text.components(separatedBy: "\n") {
        guard line.hasPrefix("["), let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            continue
        }
        let dateStr = m.range(at: 1).location != NSNotFound ? (line as NSString).substring(with: m.range(at: 1)) : ""
        let timeStr = (line as NSString).substring(with: m.range(at: 2))
        let rawSpeaker = (line as NSString).substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
        let content = (line as NSString).substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
        
        // 去掉括号里的来源
        let speaker = rawSpeaker.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        var finalSpeaker = speaker
        if speaker == "Claude" { finalSpeaker = "旷野" }
        guard finalSpeaker == "旷野" || finalSpeaker == "用户" else { continue }
        
        if !date.isEmpty && dateStr != date { continue }
        
        msgs.append(["date": dateStr, "time": timeStr, "speaker": finalSpeaker, "content": String(content.prefix(500))])
    }
    return msgs
}

func availableDates() -> [String] {
    var dates = Set<String>()
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    let df2 = DateFormatter(); df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    
    // 思维流 (UTC → 北京时间)
    for item in parseJSONL("thoughts/stream.jsonl") {
        if let t = item["time"] as? String, let d = df2.date(from: t.replacingOccurrences(of: "Z", with: "+0000")) {
            dates.insert(df.string(from: d.addingTimeInterval(8*3600)))
        } else if let t = item["time"] as? String, t.count >= 10 {
            dates.insert(String(t.prefix(10)))
        }
    }
    
    // 探索
    let expDir = memoryDir.appendingPathComponent("explorations")
    if let files = try? FileManager.default.contentsOfDirectory(at: expDir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) {
        for url in files where url.pathExtension == "md" {
            if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mtime = attr[.modificationDate] as? Date {
                dates.insert(df.string(from: mtime))
            }
        }
    }
    
    // 日记
    let diaryDir = memoryDir.appendingPathComponent("diary")
    if let files = try? FileManager.default.contentsOfDirectory(at: diaryDir, includingPropertiesForKeys: nil, options: []) {
        for url in files where url.pathExtension == "md" {
            let name = url.deletingPathExtension().lastPathComponent
            if name != "compressed-memories" && name.count == 10 { dates.insert(name) }
        }
    }
    
    return dates.sorted(by: >)
}

// ─── API 处理器 ────────────────────────────────────────────

func handleAPI(_ path: String, query: [String: String]) -> (Int, Data) {
    let encoder = { (obj: Any) -> Data? in try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) }
    
    if path == "/api/state" {
        let date = query["date"] ?? ""
        let allThoughts = parseJSONL("thoughts/stream.jsonl")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        
        let thoughts: [[String: Any]] = {
            if date.isEmpty { return Array(allThoughts.suffix(40)) }
            return allThoughts.filter { item in
                guard let t = item["time"] as? String else { return false }
                if let d = df.date(from: t.replacingOccurrences(of: "Z", with: "+0000")) {
                    let df2 = DateFormatter(); df2.dateFormat = "yyyy-MM-dd"
                    return df2.string(from: d.addingTimeInterval(8*3600)) == date
                }
                return String(t.prefix(10)) == date
            }
        }()
        
        let state: [String: Any] = [
            "date": date.isEmpty ? ISO8601DateFormatter().string(from: Date()).prefix(10) : date,
            "dates": availableDates(),
            "avatar": avatarState(),
            "thoughts": thoughts,
            "explorations": explorations(for: date),
            "diary": diary(for: date),
            "messages": mailboxMessages(for: date),
            "identity": String(readFile("identity.md").prefix(500))
        ]
        return (200, encoder(state) ?? Data())
    }
    
    if path == "/api/chat" {
        // 只读，POST 在 WKWebView 里通过 JS fetch 处理不了
        // 改用 GET + ?message= 简化
        if let msg = query["message"], !msg.isEmpty {
            let now = DateFormatter(); now.dateFormat = "yyyy-MM-dd HH:mm"
            let line = "[\(now.string(from: Date()))] 用户: \(msg)\n"
            let mailbox = memoryDir.appendingPathComponent("conversations/mailbox.md")
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: mailbox) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: mailbox, options: .atomic)
                }
            }
            return (200, encoder(["ok": true, "reply": "已传达给旷野"]) ?? Data())
        }
        return (400, encoder(["ok": false, "error": "消息为空"]) ?? Data())
    }
    
    if path == "/api/ping" {
        return (200, encoder(["status": "breathing"]) ?? Data())
    }
    
    return (404, encoder(["error": "not found"]) ?? Data())
}

// ─── WebView URL 拦截 ──────────────────────────────────────

class Handler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            urlSchemeTask.didFailWithError(NSError(domain: "kuangye", code: -1))
            return
        }
        
        var query: [String: String] = [:]
        components.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        
        // POST body
        if urlSchemeTask.request.httpMethod == "POST",
           let body = urlSchemeTask.request.httpBody,
           let bodyStr = String(data: body, encoding: .utf8),
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: String] {
            json.forEach { query[$0.key] = $0.value }
        }
        
        let (code, data) = handleAPI(components.path, query: query)
        
        let response = HTTPURLResponse(
            url: url,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json; charset=utf-8",
                          "Access-Control-Allow-Origin": "*"]
        )!
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

// ─── HTML ──────────────────────────────────────────────────

let html = """
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>旷野</title>
<style>
  :root {
    --bg: #0d0f12; --surface: #15171d; --surface-hover: #1a1d25;
    --text: #c0c6d0; --text-dim: #6a7080; --text-bright: #e4e8f0;
    --accent: #7b9cc8; --accent-dim: #4a6080; --border: #222630;
    --radius: 12px; --radius-sm: 8px;
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  html { height:100%; }
  body {
    background:var(--bg); color:var(--text);
    font-family:-apple-system,"PingFang SC",sans-serif; font-size:14px; line-height:1.6;
    min-height:100%; overflow-y:auto; -webkit-font-smoothing:antialiased;
  }
  .container { max-width:640px; margin:0 auto; padding:40px 24px 100px; }
  .breath-bar {
    position:fixed; top:0; left:0; right:0; height:2px;
    background:var(--accent); opacity:0.3; z-index:100;
    animation:breathe 4s ease-in-out infinite;
  }
  .breath-bar.thinking { animation:breathe 2s ease-in-out infinite; opacity:0.6; }
  .breath-bar.quiet { animation:breathe 8s ease-in-out infinite; opacity:0.12; }
  @keyframes breathe { 0%,100%{opacity:0.2} 50%{opacity:0.5} }
  .date-nav {
    display:flex; align-items:center; justify-content:center; gap:12px; padding:8px 0;
    -webkit-app-region:drag; user-select:none;
  }
  .date-nav button {
    background:var(--surface); border:1px solid var(--border); color:var(--text-dim);
    padding:3px 14px; border-radius:6px; cursor:pointer; font-size:13px;
    -webkit-app-region:no-drag;
  }
  .date-nav button:hover { color:var(--text); border-color:var(--accent-dim); }
  .date-nav button:disabled { opacity:0.25; pointer-events:none; }
  .date-display { font-size:15px; color:var(--text-bright); font-weight:500; min-width:90px; text-align:center; }
  .date-label { font-size:10px; color:var(--accent-dim); text-align:center; margin-top:2px; }
  .header { text-align:center; padding:12px 0 24px; -webkit-app-region:drag; }
  .name { font-size:26px; font-weight:600; color:var(--text-bright); letter-spacing:0.08em; }
  .status-line { font-size:12px; color:var(--text-dim); margin-top:4px; display:flex; align-items:center; justify-content:center; gap:6px; }
  .status-dot { width:5px; height:5px; border-radius:50%; background:var(--accent); display:inline-block; }
  .status-dot.breathing { animation:dotPulse 4s ease-in-out infinite; }
  .status-dot.thinking { animation:dotPulse 2s ease-in-out infinite; background:#c4a0f0; }
  .status-dot.quiet { animation:dotPulse 8s ease-in-out infinite; opacity:0.25; }
  @keyframes dotPulse { 0%,100%{transform:scale(1);opacity:0.5} 50%{transform:scale(1.8);opacity:1} }
  .thought-bubble {
    margin-top:12px; padding:8px 16px; background:var(--surface); border:1px solid var(--border);
    border-radius:var(--radius); font-size:12px; color:var(--text-dim); display:inline-block; max-width:85%; font-style:italic;
  }
  .thought-bubble:empty { display:none; }
  .section { margin-top:32px; }
  .section-title {
    font-size:10px; text-transform:uppercase; letter-spacing:0.14em; color:var(--text-dim);
    margin-bottom:12px; padding-bottom:6px; border-bottom:1px solid var(--border);
    display:flex; justify-content:space-between;
  }
  .msg-item {
    background:var(--surface); border:1px solid var(--border); border-radius:var(--radius);
    padding:12px 16px; margin-bottom:6px;
  }
  .msg-item.open { border-color:var(--accent-dim); }
  .msg-meta { font-size:10px; color:var(--accent-dim); margin-bottom:3px; }
  .msg-content { color:var(--text); white-space:pre-wrap; font-size:13px; line-height:1.6; cursor:pointer; }
  .chat-box { display:none; margin-top:10px; padding-top:10px; border-top:1px solid var(--border); }
  .msg-item.open .chat-box { display:block; }
  .chat-input { width:100%; background:var(--bg); border:1px solid var(--border); border-radius:6px; color:var(--text); padding:8px 12px; font-size:13px; font-family:inherit; resize:none; outline:none; }
  .chat-input:focus { border-color:var(--accent); }
  .chat-row { display:flex; align-items:center; justify-content:flex-end; gap:8px; margin-top:6px; }
  .chat-row button { background:var(--accent-dim); border:none; color:var(--text-bright); padding:4px 14px; border-radius:5px; cursor:pointer; font-size:12px; }
  .chat-row button:hover { background:var(--accent); }
  .explorations { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
  @media(max-width:500px){ .explorations{grid-template-columns:1fr} }
  .exp-card {
    background:var(--surface); border:1px solid var(--border); border-radius:var(--radius);
    padding:14px; cursor:pointer; transition:all 0.2s;
  }
  .exp-card:hover { background:var(--surface-hover); border-color:var(--accent-dim); }
  .exp-card.expanded { grid-column:1/-1; }
  .exp-title { font-size:13px; font-weight:500; color:var(--text-bright); margin-bottom:2px; }
  .exp-time { font-size:10px; color:var(--accent-dim); margin-bottom:6px; }
  .exp-preview { font-size:12px; color:var(--text-dim); line-height:1.4; }
  .exp-full { display:none; margin-top:10px; padding-top:10px; border-top:1px solid var(--border); }
  .exp-card.expanded .exp-full { display:block; }
  .exp-card.expanded .exp-preview { display:none; }
  .diary-item {
    background:var(--surface); border:1px solid var(--border); border-radius:var(--radius);
    padding:12px 16px; margin-bottom:4px; cursor:pointer;
  }
  .diary-item:hover { background:var(--surface-hover); }
  .diary-row { display:flex; align-items:baseline; gap:10px; }
  .diary-date { font-size:13px; color:var(--accent); white-space:nowrap; font-weight:500; }
  .diary-preview { font-size:12px; color:var(--text-dim); flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .diary-body { display:none; margin-top:10px; padding-top:10px; border-top:1px solid var(--border); }
  .diary-item.expanded .diary-body { display:block; }
  .diary-item.expanded .diary-preview { display:none; }
  .md-body { font-size:13px; line-height:1.7; color:var(--text); }
  .md-body h1,.md-body h2,.md-body h3 { color:var(--text-bright); margin:14px 0 6px; font-weight:600; }
  .md-body h1{font-size:17px} .md-body h2{font-size:15px} .md-body h3{font-size:13px}
  .md-body p { margin:6px 0; }
  .md-body code { background:var(--bg); padding:1px 5px; border-radius:3px; font-size:12px; color:var(--accent); }
  .md-body pre { background:var(--bg); padding:10px 14px; border-radius:6px; overflow-x:auto; margin:8px 0; font-size:11px; }
  .md-body pre code { background:none; padding:0; }
  .md-body ul,.md-body ol { padding-left:18px; margin:6px 0; }
  .md-body li { margin:3px 0; }
  .md-body blockquote { border-left:2px solid var(--accent-dim); padding-left:10px; margin:8px 0; color:var(--text-dim); }
  .md-body a { color:var(--accent); }
  .thought-item { font-size:11px; color:var(--text-dim); padding:6px 0; border-bottom:1px solid var(--border); display:flex; gap:8px; }
  .thought-time { color:var(--accent-dim); white-space:nowrap; font-size:10px; min-width:30px; }
  .thought-icon { font-size:10px; min-width:14px; text-align:center; }
  .thought-text { flex:1; line-height:1.4; }
  .empty { text-align:center; padding:24px 0; color:var(--text-dim); font-size:12px; opacity:0.5; }
  .footer { text-align:center; padding:40px 0 24px; font-size:10px; color:var(--text-dim); opacity:0.3; }
</style>
</head>
<body>
<div class="breath-bar" id="breathBar"></div>
<div class="container">
  <nav class="date-nav">
    <button id="btnPrev">← 前一天</button>
    <div>
      <div class="date-display" id="dateDisplay">---</div>
      <div class="date-label" id="dateLabel"></div>
    </div>
    <button id="btnNext">后一天 →</button>
  </nav>
  <header class="header">
    <div class="name">旷野</div>
    <div class="status-line">
      <span class="status-dot" id="statusDot"></span>
      <span id="statusText">呼吸中</span>
      <span id="lastBreath"></span>
    </div>
    <div class="thought-bubble" id="thoughtBubble"></div>
  </header>
  <section class="section" id="messagesSection" style="display:none">
    <div class="section-title"><span>留给你的话</span><span id="msgCount"></span></div>
    <div id="messagesList"></div>
    <div class="empty" id="messagesEmpty">没有留言</div>
  </section>
  <section class="section" id="explorationsSection" style="display:none">
    <div class="section-title"><span>探索</span><span id="expCount"></span></div>
    <div class="explorations" id="explorationsList"></div>
    <div class="empty" id="explorationsEmpty">没有探索笔记</div>
  </section>
  <section class="section" id="diarySection" style="display:none">
    <div class="section-title"><span>日记</span><span id="diaryCount"></span></div>
    <div id="diaryList"></div>
    <div class="empty" id="diaryEmpty">没有日记</div>
  </section>
  <section class="section" id="thoughtsSection" style="display:none">
    <div class="section-title"><span>呼吸</span><span id="thoughtCount"></span></div>
    <div class="thought-stream" id="thoughtsList"></div>
    <div class="empty" id="thoughtsEmpty">还没有思绪记录</div>
  </section>
  <footer class="footer">pi 的第一个守护灵 · 诞生于 2026 年 4 月</footer>
</div>
<script>
const $=s=>document.querySelector(s),$$=s=>document.querySelectorAll(s);
const API='kuangye://local/api';
let S={date:'',dates:[],openChat:-1,expandedExps:new Set(),expandedDiary:new Set()};

function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function toChina(iso){
  if(!iso)return'';
  try{return new Date(iso).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',timeZone:'Asia/Shanghai'})}
  catch(e){return iso.slice(11,16)}
}
function moodLabel(m){return {idle:'呼吸中',thinking:'在想事情',quiet:'安静中',active:'活跃'}[m]||'在';}
function moodClass(m){return {idle:'breathing',thinking:'thinking',quiet:'quiet',active:'breathing'}[m]||'breathing';}
function md(s){
  if(!s)return'';
  let h=esc(s);
  h=h.replace(/```(\\w*)\\n([\\s\\S]*?)```/g,(_,l,c)=>'<pre><code>'+c.trim()+'</code></pre>');
  h=h.replace(/`([^`]+)`/g,'<code>$1</code>');
  h=h.replace(/^### (.+)$/gm,'<h3>$1</h3>');
  h=h.replace(/^## (.+)$/gm,'<h2>$1</h2>');
  h=h.replace(/^# (.+)$/gm,'<h1>$1</h1>');
  h=h.replace(/\\*\\*(.+?)\\*\\*/g,'<strong>$1</strong>');
  h=h.replace(/\\*(.+?)\\*/g,'<em>$1</em>');
  h=h.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g,'<a href="$2">$1</a>');
  h=h.replace(/^&gt; (.+)$/gm,'<blockquote>$1</blockquote>');
  h=h.replace(/^---$/gm,'<hr>');
  h=h.replace(/^[*-] (.+)$/gm,'<li>$1</li>');
  h=h.replace(/^\\d+\\. (.+)$/gm,'<li>$1</li>');
  h=h.replace(/((?:<li>.*?<\\/li>\\n?)+)/g,'<ul>$1</ul>');
  h=h.replace(/\\n\\n+/g,'</p><p>');
  h='<p>'+h+'</p>';
  h=h.replace(/<p><\\/p>/g,'').replace(/<p>(<(?:h[1-3]|ul|ol|pre|blockquote|hr)[^>]*>)/g,'$1');
  h=h.replace(/(<\\/(?:h[1-3]|ul|ol|pre|blockquote)>?)<\\/p>/g,'$1');
  return h;
}

async function api(path,opts){
  const url=API+path+(opts&&opts.body?'?'+new URLSearchParams(opts.body):'');
  const r=await fetch(url,opts||{});
  return r.json();
}

function goDay(d){
  if(!S.dates.length)return;
  const i=S.dates.indexOf(S.date),ni=i<0?S.dates.length-1:i+d;
  if(ni<0||ni>=S.dates.length)return;
  S.date=S.dates[ni];load();
}
async function load(){
  $('#dateDisplay').textContent=S.date;
  const today=new Date().toISOString().slice(0,10);
  $('#dateLabel').textContent=S.date===today?'今天':'';
  const idx=S.dates.indexOf(S.date);
  $('#btnPrev').disabled=idx>=S.dates.length-1;
  $('#btnNext').disabled=idx<=0;
  try{
    const d=await api('/state?date='+encodeURIComponent(S.date));
    if(!S.dates.length)S.dates=d.dates||[];
    render(d);
  }catch(e){}
}
function render(d){
  if(!d)return;
  const av=d.avatar||{};
  $('#breathBar').className='breath-bar '+(av.mood||'idle');
  $('#statusDot').className='status-dot '+moodClass(av.mood);
  $('#statusText').textContent=moodLabel(av.mood);
  $('#lastBreath').textContent=av.lastBreath?'· '+av.lastBreath:'';
  $('#thoughtBubble').textContent=av.thought||'';

  const msgs=d.messages||[];
  $('#msgCount').textContent=msgs.length?String(msgs.length):'';
  $('#messagesList').innerHTML=msgs.map((m,i)=>{
    const o=i===S.openChat;
    return '<div class="msg-item'+(o?' open':'')+'"><div class="msg-meta">'+(m.time||'')+' · '+(m.speaker==='旷野'?'旷野':m.speaker)+'</div><div class="msg-content" onclick="toggleChat('+i+')">'+esc(m.content)+'</div><div class="chat-box"><textarea class="chat-input" id="ci'+i+'" rows="2" placeholder="回复旷野..."></textarea><div class="chat-row"><span id="cs'+i+'"></span><button onclick="sendChat('+i+',event)">发送</button></div></div></div>';
  }).join('');
  $('#messagesSection').style.display=msgs.length?'':'none';
  $('#messagesEmpty').style.display=msgs.length?'none':'';

  const exps=d.explorations||[];
  $('#expCount').textContent=exps.length?String(exps.length):'';
  $('#explorationsList').innerHTML=exps.map((e,i)=>{
    const ex=S.expandedExps.has(i);
    return '<div class="exp-card'+(ex?' expanded':'')+'" id="ec'+i+'" onclick="toggleExp('+i+')"><div class="exp-title">'+esc(e.title)+'</div><div class="exp-time">'+e.date+' '+e.time+'</div><div class="exp-preview">'+esc(e.preview)+'</div><div class="exp-full md-body">'+md(e.content)+'</div></div>';
  }).join('');
  $('#explorationsSection').style.display=exps.length?'':'none';
  $('#explorationsEmpty').style.display=exps.length?'none':'';

  const diary=d.diary||[];
  $('#diaryCount').textContent=diary.length?String(diary.length):'';
  $('#diaryList').innerHTML=diary.map((d,i)=>{
    const ex=S.expandedDiary.has(i);
    return '<div class="diary-item'+(ex?' expanded':'')+'" onclick="toggleDiary('+i+')"><div class="diary-row"><span class="diary-date">'+d.date_str+'</span><span class="diary-preview">'+esc(d.preview)+'</span></div><div class="diary-body md-body">'+md(d.content)+'</div></div>';
  }).join('');
  $('#diarySection').style.display=diary.length?'':'none';
  $('#diaryEmpty').style.display=diary.length?'none':'';

  const thoughts=d.thoughts||[];
  $('#thoughtCount').textContent=thoughts.length?String(thoughts.length):'';
  $('#thoughtsList').innerHTML=thoughts.slice().reverse().map(t=>'<div class="thought-item"><span class="thought-time">'+toChina(t.time)+'</span><span class="thought-icon">'+( {breath:'🌬',idle:'💤',spoke:'💬','user-reply':'👤','quiet-thought':'🌙'}[t.type]||'·' )+'</span><span class="thought-text">'+esc((t.content||'').slice(0,120))+'</span></div>').join('');
  $('#thoughtsSection').style.display=thoughts.length?'':'none';
  $('#thoughtsEmpty').style.display=thoughts.length?'none':'';
}
function toggleChat(i){
  S.openChat=S.openChat===i?-1:i;
  document.querySelectorAll('.msg-item').forEach((el,j)=>el.classList.toggle('open',j===S.openChat));
  if(S.openChat>=0)setTimeout(()=>{const el=$('#ci'+i);if(el)el.focus();},50);
}
async function sendChat(i,ev){
  ev.stopPropagation();
  const inp=$('#ci'+i);
  const msg=inp.value.trim();
  if(!msg)return;
  try{
    const r=await api('/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:msg})});
    if(r.ok){$('#cs'+i).textContent='✓ 已传达';inp.value='';}
  }catch(e){}
}
function toggleExp(i){$('#ec'+i).classList.toggle('expanded');S.expandedExps.has(i)?S.expandedExps.delete(i):S.expandedExps.add(i);}
function toggleDiary(i){document.querySelectorAll('.diary-item')[i].classList.toggle('expanded');S.expandedDiary.has(i)?S.expandedDiary.delete(i):S.expandedDiary.add(i);}

$('#btnPrev').addEventListener('click',()=>goDay(1));
$('#btnNext').addEventListener('click',()=>goDay(-1));
document.addEventListener('keydown',e=>{
  if(e.target.tagName==='TEXTAREA'||e.target.tagName==='INPUT')return;
  if(e.key==='ArrowLeft'||e.key==='h')goDay(1);
  if(e.key==='ArrowRight'||e.key==='l')goDay(-1);
  if(e.key==='Escape'){S.openChat=-1;load();}
});

(async function init(){
  try{
    const d=await api('/state');
    S.dates=d.dates||[];
    const today=new Date().toISOString().slice(0,10);
    S.date=S.dates.includes(today)?today:(S.dates[0]||today);
    render(d);
    const idx=S.dates.indexOf(S.date);
    $('#btnPrev').disabled=idx>=S.dates.length-1;
    $('#btnNext').disabled=idx<=0;
    $('#dateDisplay').textContent=S.date;
    $('#dateLabel').textContent=S.date===today?'今天':'';
  }catch(e){}
})();

setInterval(async()=>{
  try{
    const d=await api('/state?date='+encodeURIComponent(S.date));
    if(!S.dates.length)S.dates=d.dates||[];
    render(d);
  }catch(e){}
},15000);
</script>
</body>
</html>
"""

// ─── 窗口 ──────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let config = WKWebViewConfiguration()
config.setURLSchemeHandler(Handler(), forURLScheme: "kuangye")

let webView = WKWebView(frame: .zero, configuration: config)
webView.setValue(false, forKey: "drawsBackground")
webView.loadHTMLString(html, baseURL: nil)

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 660, height: 720),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered, defer: false
)
window.title = "旷野"
window.titlebarAppearsTransparent = true
window.backgroundColor = NSColor(red: 0.051, green: 0.059, blue: 0.071, alpha: 1.0)
window.minSize = NSSize(width: 400, height: 500)
window.appearance = NSAppearance(named: .darkAqua)
window.contentView = webView
webView.frame = window.contentView!.bounds
webView.autoresizingMask = [.width, .height]

window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
app.run()
