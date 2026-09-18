import AppKit

/// Shared app-focusing logic (code review P3-1): ClaudeCodeDelivery and ChatGPTDelivery
/// duplicated the same activate-and-poll loop. Deadline-based, callable from any thread
/// (NSWorkspace/NSRunningApplication are thread-safe; callers run delivery off the main thread).
enum AppActivator {
    /// The running app for a bundle id (regular policy only; skips agents/background daemons).
    static func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }
    }

    /// Activate and wait until the app is actually frontmost, bounded by a deadline.
    /// Returns false on timeout (caller degrades to clipboard handoff — never block forever).
    @discardableResult
    static func focus(_ app: NSRunningApplication, bundleID: String, timeout: TimeInterval = 1.2) -> Bool {
        app.activate(options: [.activateAllWindows])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(80_000)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return true }
            app.activate(options: [.activateAllWindows])
        }
        return false
    }
}
