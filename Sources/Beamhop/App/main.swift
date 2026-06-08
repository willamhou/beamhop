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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
