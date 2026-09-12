import AppKit
import Foundation

@MainActor
final class TerminalActivityTracker {
    static let shared = TerminalActivityTracker()

    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty"
    ]

    private var lastActivatedProcessID: pid_t?
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        if let app = NSWorkspace.shared.frontmostApplication,
           Self.terminalBundleIDs.contains(app.bundleIdentifier ?? "") {
            lastActivatedProcessID = app.processIdentifier
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  Self.terminalBundleIDs.contains(app.bundleIdentifier ?? "") else { return }
            Task { @MainActor in self?.lastActivatedProcessID = app.processIdentifier }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    func deliveryTerminal() -> NSRunningApplication? {
        let candidates = NSWorkspace.shared.runningApplications.filter {
            Self.terminalBundleIDs.contains($0.bundleIdentifier ?? "") && !$0.isTerminated
        }
        if let lastActivatedProcessID,
           let tracked = candidates.first(where: { $0.processIdentifier == lastActivatedProcessID }) {
            return tracked
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
