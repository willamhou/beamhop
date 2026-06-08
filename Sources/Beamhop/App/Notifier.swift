import AppKit
import os

/// User-facing notifications. Codex review: failures must surface a REASON, never a silent beep.
/// Under SwiftPM (no bundle) we log + beep; the Xcode-bundled app will use UNUserNotificationCenter.
enum Notifier {
    private static let log = Logger(subsystem: "com.beamhop.app", category: "notify")

    static func info(_ title: String, _ body: String = "") {
        log.info("\(title, privacy: .public) \(body, privacy: .public)")
    }

    static func error(_ title: String, _ body: String = "") {
        log.error("\(title, privacy: .public) \(body, privacy: .public)")
        NSSound.beep()
        // TODO (Xcode bundle): UNUserNotificationCenter banner with the reason + a fix action.
    }

    static func success(_ title: String, _ body: String = "") {
        log.info("✓ \(title, privacy: .public) \(body, privacy: .public)")
    }
}
