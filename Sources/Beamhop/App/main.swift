import AppKit
import BeamhopCore

// Menu-bar app entry. SwiftPM executable drives NSApplication directly (like the Week 0 S5
// demo) — no SwiftUI App/Settings scene, so the empty-Settings blank-window issue codex
// flagged doesn't apply here. The Xcode app target (post-Xcode-install) will use the
// SwiftUI lifecycle with a real SettingsView.

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        AppServices.shared.bootstrap()
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.hotkeys.unregisterAll()
    }
}

// --bridge-test [socketPath]: headless harness for the browser bridge (Week 2B). Starts the
// socket server, waits for the host to connect, pings, captures the active tab, prints, exits.
if CommandLine.arguments.contains("--bridge-test") {
    let i = CommandLine.arguments.firstIndex(of: "--bridge-test")!
    let sockArg = (i + 1 < CommandLine.arguments.count && !CommandLine.arguments[i+1].hasPrefix("--"))
        ? CommandLine.arguments[i+1] : nil
    let server = sockArg.map { BrowserBridgeServer(socketPath: $0) } ?? BrowserBridgeServer.shared
    server.start()
    fputs("[bridge-test] waiting for host connection…\n", stderr)
    var waited = 0
    while !server.isConnected && waited < 250 { usleep(100_000); waited += 1 }
    guard server.isConnected else { fputs("[bridge-test] no host connected\n", stderr); exit(2) }
    fputs("[bridge-test] host connected\n", stderr)

    if let pong = server.request(type: "ping") {
        print("PING -> \(pong)")
    } else { print("PING -> FAILED") }

    if let cap = server.request(type: "capture_active_tab", timeout: 8) {
        let url = cap["url"] as? String ?? "?"
        let title = cap["title"] as? String ?? "?"
        let sel = (cap["selection"] as? String ?? "")
        print("CAPTURE -> url=\(url) | title=\(title) | selection_len=\(sel.count)")
    } else { print("CAPTURE -> FAILED") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
