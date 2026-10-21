import AppKit
import BeamhopCore

// Headless provenance inspection: no NSApplication, user DB, hotkeys or permission checks.
if CommandLine.arguments.contains("--build-info") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(BuildInfo.load()), let json = String(data: data, encoding: .utf8) {
        print(json)
        exit(0)
    }
    exit(1)
}

if let index = CommandLine.arguments.firstIndex(of: "--trial-ui-smoke"),
   CommandLine.arguments.count > index + 1 {
    do {
        try TrialEngineeringSmoke.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                                      chinese: CommandLine.arguments.contains("--zh"),
                                      dark: CommandLine.arguments.contains("--dark"))
        exit(0)
    } catch {
        fputs("Trial engineering offscreen smoke failed\n", stderr)
        exit(1)
    }
}

// An opt-in native UI harness for hosted Macs. It uses isolated fixtures and never
// bootstraps hotkeys, permissions, external agent delivery, or the user's Inbox.
if let index = CommandLine.arguments.firstIndex(of: "--ui-smoke"),
   CommandLine.arguments.count > index + 1 {
    let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let language = CommandLine.arguments.contains("--zh") ? "zh-Hans" : "en"
    do {
        let passed = try NativeUISmoke.run(output: output, language: language,
                                           dark: CommandLine.arguments.contains("--dark"))
        exit(passed ? 0 : 1)
    } catch {
        fputs("[native-ui] \(error)\n", stderr)
        exit(1)
    }
}

#if DEBUG
// Isolated fixtures only: no real DB, hotkeys, MCP registration, paste or synthetic key events.
if CommandLine.arguments.contains("--focus-fixture") {
    UIRegression.fixture()
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--ui-regression") {
    guard i + 1 < CommandLine.arguments.count else {
        fputs("Usage: Beamhop --ui-regression <preview-directory>\n", stderr)
        exit(2)
    }
    exit(UIRegression.run(output: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
}
#endif

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
        let body = (cap["body"] as? String ?? "")
        let gh = (cap["github"] as? [String: Any]).map { "\($0["kind"] ?? "?"):\($0["title"] ?? "")" } ?? "—"
        print("CAPTURE -> url=\(url) | title=\(title) | selection_len=\(sel.count) | body_len=\(body.count) | github=\(gh)")
    } else { print("CAPTURE -> FAILED") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
