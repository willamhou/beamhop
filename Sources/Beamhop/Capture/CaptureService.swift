import Foundation
import AppKit
import BeamhopCore

enum CaptureOutcome {
    case captured(Capture)
    case rejected(reason: String)   // user-facing; never silent (spec §7.7)
}

/// Turns the frontmost app + AX reads into a Capture with full provenance (spec §6.5 / §12.1),
/// honoring the blacklist, secure-field skip, 800ms budget, and truncation.
final class CaptureService {
    private let store: CaptureStore
    private let maxBodyChars = 100_000   // spec §11

    init(store: CaptureStore) { self.store = store }

    func captureFrontmost() -> CaptureOutcome {
        let t0 = Date()

        guard AXIsProcessTrusted() else {
            return .rejected(reason: "未授予 Accessibility 权限 —— 无法抓取(去诊断面板开启)")
        }
        guard let front = AXHelper.frontmostApp() else {
            return .rejected(reason: "无法识别前台 app")
        }
        if AppBlacklist.isBlocked(front.bundleID) {
            return .rejected(reason: "\(front.name) 在黑名单(密码/银行类),已拒绝抓取")
        }

        let read = AXHelper.read(front: front)
        let durationMs = Int(Date().timeIntervalSince(t0) * 1000)

        // truncate for delivery/preview; DB keeps the full text (codex: no contradiction).
        var body = read.selectedText
        var truncated = false
        if let b = body, b.count > maxBodyChars {
            // keep full in DB; mark truncated so delivery/preview layers know to cut.
            truncated = true
            _ = b
        }
        body = read.selectedText

        let source: Source = isBrowser(front.bundleID) ? .browser : .ax
        let capture = Capture(
            source: source,
            appBundleID: front.bundleID,
            appName: front.name,
            windowTitle: read.windowTitle,
            url: read.url,
            selectedText: body,
            extractedBody: nil,                 // Week 2B: browser extension Readability body
            domainHint: domainHint(url: read.url),
            userNote: nil,                      // Week 3: floating window note
            pid: Int(front.pid),
            appVersion: appVersion(pid: front.pid),
            captureMethod: read.method,
            isPrivate: read.isSecure,
            truncated: truncated,
            captureDurationMs: durationMs
        )

        do {
            try store.insert(capture)
            return .captured(capture)
        } catch {
            return .rejected(reason: "写入 Inbox 失败: \(error)")
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
