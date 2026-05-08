import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 200, height: 240)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true
        window.hasShadow = false
        
        // 让 contentView 的 layer 透明
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = .clear
        
        let webView = WKWebView(frame: rect)
        webView.setValue(false, forKey: "drawsBackground")
        
        // 关键：让 WKWebView 的 enclosing scrollview 和它的 layer 也透明
        if let sv = webView.enclosingScrollView {
            sv.drawsBackground = false
            sv.wantsLayer = true
            sv.layer?.backgroundColor = .clear
        }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear
        
        let htmlPath = NSHomeDirectory() + "/.claude-memory/avatar/index.html"
        webView.loadFileURL(URL(fileURLWithPath: htmlPath), 
                           allowingReadAccessTo: URL(fileURLWithPath: htmlPath).deletingLastPathComponent())
        
        window.contentView?.addSubview(webView)
        
        // 状态注入
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let p = NSHomeDirectory() + "/.claude-memory/avatar/state.json"
            if let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let j = String(data: d, encoding: .utf8) {
                webView.evaluateJavaScript("try{setState(\(j))}catch(e){}", completionHandler: nil)
            }
        }
        
        if let s = NSScreen.main {
            let f = s.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - 215, y: f.minY + 40))
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "关闭", action: #selector(closeWindow), keyEquivalent: ""))
        webView.menu = menu
        
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func closeWindow() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
