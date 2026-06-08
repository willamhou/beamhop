import AppKit
import Foundation

/// Locates a terminal to deliver into (spec §7.3 ③④).
enum TerminalLocator {
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp", "com.mitchellh.ghostty",
    ]

    struct Target { let app: NSRunningApplication; let bundleID: String; let wasFrontmost: Bool }

    /// Prefer the frontmost terminal (so auto-Enter targets the window the user is looking at);
    /// otherwise any running terminal but flagged `wasFrontmost=false` so the caller won't auto-Enter
    /// into a window the user can't see (codex: avoid sending ⏎ to the wrong terminal).
    static func locate() -> Target? {
        if let front = NSWorkspace.shared.frontmostApplication,
           let b = front.bundleIdentifier, terminalBundleIDs.contains(b) {
            return Target(app: front, bundleID: b, wasFrontmost: true)
        }
        for app in NSWorkspace.shared.runningApplications {
            if let b = app.bundleIdentifier, terminalBundleIDs.contains(b) {
                return Target(app: app, bundleID: b, wasFrontmost: false)
            }
        }
        return nil
    }

    /// Coarse signal that a `claude` CLI is running. ⚠️ codex review: this can't map to the
    /// FOREGROUND tab precisely → callers must treat `false`/uncertain as "don't auto-Enter".
    static func claudeLikelyRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-fl", "claude"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // crude: a line that looks like the claude code CLI, not our own processes
        return out.split(separator: "\n").contains { line in
            line.contains("claude") && !line.contains("Beamhop") && !line.contains("beamhop")
        }
    }
}
