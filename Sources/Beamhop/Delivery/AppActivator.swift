import AppKit
import BeamhopCore

/// Shared app-focusing logic (code review P3-1): ClaudeCodeDelivery and ChatGPTDelivery
/// duplicated the same activate-and-poll loop. Deadline-based, callable from any thread
/// (NSWorkspace/NSRunningApplication are thread-safe; callers run delivery off the main thread).
enum AppActivator {
    /// Reuse a running receiver, or launch its installed bundle without blocking the UI.
    /// URL/configuration injection lets the native harness use only a temporary fixture app.
    static func open(bundleIDs: [String],
                     applicationURL: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
                     configuration: NSWorkspace.OpenConfiguration = .init(),
                     completion: @escaping (String?) -> Void) {
        if let app = bundleIDs.compactMap({ runningApp(bundleID: $0) }).first {
            completion(app.activate(options: [.activateAllWindows]) ? nil : L10n.s("Could not open the receiving app."))
            return
        }
        guard let url = bundleIDs.compactMap(applicationURL).first else {
            completion(L10n.s("Could not open the receiving app."))
            return
        }
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                completion(app != nil && error == nil ? nil : L10n.s("Could not open the receiving app."))
            }
        }
    }

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
