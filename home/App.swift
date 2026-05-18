#!/usr/bin/env swift

import Cocoa
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 660, height: 720),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.title = "旷野"
window.titlebarAppearsTransparent = true
window.isMovableByWindowBackground = false
window.backgroundColor = NSColor(red: 0.051, green: 0.059, blue: 0.071, alpha: 1.0)
window.minSize = NSSize(width: 400, height: 500)

// 暗色标题栏外观
window.appearance = NSAppearance(named: .darkAqua)

let webView = WKWebView(frame: window.contentView!.bounds)
webView.autoresizingMask = [.width, .height]
webView.setValue(false, forKey: "drawsBackground")
window.contentView?.addSubview(webView)

let url = URL(string: "http://localhost:15180")!
webView.load(URLRequest(url: url))

// 让窗口成为 key window 并前置
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

app.run()
