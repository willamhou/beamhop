import Foundation
import AppKit
import BeamhopCore

enum CaptureOutcome {
    case captured(Capture)
    case rejected(reason: String)   // user-facing; never silent (spec §7.7)
    case duplicate                  // <500ms same window re-press: silent by design (spec §11 / W3-4)
}

/// Turns the frontmost app + AX reads into a Capture with full provenance (spec §6.5 / §12.1),
/// honoring the blacklist, secure-field skip, 800ms budget, and truncation.
final class CaptureService {
    private let store: CaptureStore
    private let maxBodyChars = 100_000   // spec §11

    /// W3-4 duplicate-press guard: last capture key + time; same (bundleID, windowTitle) within
    /// 500ms means the user double-tapped the hotkey — the second press must not create a row.
    private var duplicateGate = DuplicateGate()

    init(store: CaptureStore) { self.store = store }

    func captureFrontmost() -> CaptureOutcome {
        let t0 = Date()

        guard AXIsProcessTrusted() else {
            return .rejected(reason: L10n.s("Accessibility permission not granted — cannot capture (enable it in the Diagnostics window)"))
        }
        guard let front = AXHelper.frontmostApp() else {
            return .rejected(reason: L10n.s("Cannot identify the frontmost app"))
        }
        if AppBlacklist.isBlocked(front.bundleID) {
            return .rejected(reason: "\(front.name) is on the blacklist (passwords/banking) — capture refused")
        }

        var read = AXHelper.read(front: front)

        // W3-4: same window re-pressed within 500ms → duplicate, decided BEFORE any expensive
        // extension/insert work below (the AX read above already happened; that's the cheap part).
        if duplicateGate.isDuplicate(bundleID: front.bundleID, title: read.windowTitle) {
            return .duplicate
        }

        // Week 2B: if the front app is a browser and the extension bridge is connected, ask it for
        // the active tab (more reliable url/selection + Readability body than AX for web content).
        var extractedBody: String? = nil
        var extVersion: String? = nil
        if isBrowser(front.bundleID), BrowserBridgeServer.shared.isConnected,
           let tab = BrowserBridgeServer.shared.request(type: "capture_active_tab", timeout: 3) {
            if let u = tab["url"] as? String, !u.isEmpty { read.url = u }
            if let s = tab["selection"] as? String, !s.isEmpty {
                read.selectedText = s; read.method = "browser-extension"
            }
            if let title = tab["title"] as? String, !title.isEmpty, (read.windowTitle?.isEmpty ?? true) {
                read.windowTitle = title
            }
            extractedBody = tab["body"] as? String          // Readability body (added next step)
            extVersion = tab["ext_version"] as? String
        }

        let durationMs = Int(Date().timeIntervalSince(t0) * 1000)

        // DB keeps full text; `truncated` flags that delivery/preview layers must cut. Check BOTH
        // selected text AND the (browser) extracted body (codex).
        let truncated = (read.selectedText?.count ?? 0) > maxBodyChars
            || (extractedBody?.count ?? 0) > maxBodyChars
        let body = read.selectedText

        let source: Source = isBrowser(front.bundleID) ? .browser : .ax
        let capture = Capture(
            source: source,
            appBundleID: front.bundleID,
            appName: front.name,
            windowTitle: read.windowTitle,
            url: read.url,
            selectedText: body,
            extractedBody: extractedBody,       // Readability body from the extension (Week 2B)
            domainHint: domainHint(url: read.url),
            userNote: nil,                      // Week 3: floating window note
            pid: Int(front.pid),
            appVersion: appVersion(pid: front.pid),
            captureMethod: read.method,
            extensionVersion: extVersion,
            isPrivate: read.isSecure,
            truncated: truncated,
            captureDurationMs: durationMs
        )

        do {
            try store.insert(capture)
            return .captured(capture)
        } catch {
            return .rejected(reason: L10n.s("Failed to write to the Inbox: \(error)"))
        }
    }

    // MARK: helpers

    private func isBrowser(_ bundleID: String) -> Bool {
        ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
         "com.brave.Browser", "com.microsoft.edgemac"].contains(bundleID)
    }

    private func appVersion(pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL,
              let info = Bundle(url: url)?.infoDictionary else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    private func domainHint(url: String?) -> DomainHint? {
        guard let url, let comps = URLComponents(string: url), let host = comps.host else { return nil }
        let path = comps.path
        if host.contains("github.com") {
            if path.contains("/pull/") { return .githubPR }
            if path.contains("/issues/") { return .githubIssue }
            if path.contains("/blob/") || path.contains("/tree/") { return .githubCode }
            return .githubRepo
        }
        if host.contains("stackoverflow.com") { return .stackoverflow }
        return .generic
    }
}
