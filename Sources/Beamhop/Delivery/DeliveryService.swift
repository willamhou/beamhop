import AppKit
import Foundation
import BeamhopCore

/// Single delivery entry point (spec §7.1 / §12.4). Routes to a target channel; on ANY failure
/// it falls back to the clipboard handoff — never a silent failure. Records a Delivery row.
final class DeliveryService {
    private let store: CaptureStore
    init(store: CaptureStore) { self.store = store }

    /// `completion` reports whether the CHOSEN target succeeded (clipboard fallback ≠ success).
    func deliver(_ capture: Capture, to target: DeliveryTarget, userNote: String? = nil,
                 completion: ((DeliveryTarget, Bool) -> Void)? = nil) {
        switch target {
        case .claudeCode:
            if let reason = ClaudeCodeDelivery.deliver(capture, userNote: userNote) {
                record(capture, .claudeCode, .failed, reason)
                Notifier.error(L10n.s("Claude Code delivery failed → copied to clipboard"), reason)
                clipboardFallback(capture, userNote: userNote, reason: reason)
                completion?(.claudeCode, false)
            } else {
                record(capture, .claudeCode, .success, nil)
                Notifier.success(L10n.s("Delivered to Claude Code"), capture.appName)
                completion?(.claudeCode, true)
            }
        case .clipboard:
            clipboardFallback(capture, userNote: userNote, reason: L10n.s("User chose clipboard"))
            completion?(.clipboard, true)
        case .chatgptDesktop:
            // S3 verified path: AX opt-in + kAXValueAttribute set-value, no auto-submit.
            if let reason = ChatGPTDelivery.deliver(capture, userNote: userNote) {
                record(capture, .chatgptDesktop, .failed, reason)
                Notifier.error(L10n.s("ChatGPT Desktop delivery failed → copied to clipboard"), reason)
                clipboardFallback(capture, userNote: userNote, reason: reason)
                completion?(.chatgptDesktop, false)
            } else {
                record(capture, .chatgptDesktop, .success, nil)
                completion?(.chatgptDesktop, true)
            }
        case .cowork:
            // S2: .mcpb mechanism confirmed (see cowork-extension/), end-to-end install still
            // fast-follow — degrade to clipboard until then.
            clipboardFallback(capture, userNote: userNote, reason: L10n.s("Cowork integration awaits S2 end-to-end acceptance — clipboard for now"))
            completion?(.cowork, true)
        case .kimiWork:
            // Verified 2026-10-18: AX-locate the composer, focus it, clipboard-paste (no auto-send).
            if let reason = KimiDelivery.deliver(capture, userNote: userNote) {
                record(capture, .kimiWork, .failed, reason)
                Notifier.error(L10n.s("Kimi Work delivery failed → copied to clipboard"), reason)
                clipboardFallback(capture, userNote: userNote, reason: reason)
                completion?(.kimiWork, false)
            } else {
                record(capture, .kimiWork, .success, nil)
                completion?(.kimiWork, true)
            }
        }
    }

    /// Universal fallback (golden line, spec §4.1/§7.1). Writes the full rendered prompt to the
    /// clipboard + notifies. NOTE: this proactively OWNS the clipboard — it does NOT restore
    /// (only ClaudeCodeDelivery's safe-paste restores). codex review.
    private func clipboardFallback(_ capture: Capture, userNote: String?, reason: String) {
        let md = PromptRenderer.fullMarkdown(capture, userNote: userNote)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        record(capture, .clipboard, .success, reason)
        Notifier.info(L10n.s("Content copied — paste it into your target"), reason)
    }

    private func record(_ capture: Capture, _ target: DeliveryTarget, _ status: DeliveryStatus, _ err: String?) {
        let d = Delivery(captureID: capture.id, target: target, status: status, errorMessage: err)
        try? store.recordDelivery(d)
    }
}
