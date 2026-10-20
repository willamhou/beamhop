import AppKit
import Foundation
import BeamhopCore

/// Single delivery entry point (spec §7.1 / §12.4). Routes to a target channel; on ANY failure
/// it falls back to the clipboard handoff — never a silent failure. Records a Delivery row.
final class DeliveryService {
    private let queue = DispatchQueue(label: "com.beamhop.delivery", qos: .userInitiated)
    private let store: CaptureStore
    init(store: CaptureStore) { self.store = store }

    /// `completion` reports whether the CHOSEN target succeeded (clipboard fallback ≠ success).
    func deliver(_ capture: Capture, to target: DeliveryTarget, userNote: String? = nil,
                 completion: ((DeliveryTarget, Bool) -> Void)? = nil) {
        deliver(Handoff(items: [.init(capture: capture, note: userNote ?? capture.userNote)]), to: target, completion: completion)
    }

    /// Serial across capture, Inbox and pocket: concurrent clipboard/AX writes fight for focus.
    func deliver(_ handoff: Handoff, to target: DeliveryTarget,
                 completion: ((DeliveryTarget, Bool) -> Void)? = nil) {
        guard !handoff.items.isEmpty else { completion?(target, false); return }
        queue.async { self.perform(handoff, to: target, completion: completion) }
    }

    private func perform(_ handoff: Handoff, to target: DeliveryTarget,
                         completion: ((DeliveryTarget, Bool) -> Void)?) {
        let t0 = Date()
        switch target {
        case .claudeCode:
            if let reason = ClaudeCodeDelivery.deliver(handoff) {
                record(handoff, .claudeCode, .failed, reason, t0: t0)
                Notifier.error(L10n.f("Could not prepare materials for %@", "Claude Code"), reason)
                clipboardFallback(handoff, reason: reason, t0: t0)
                completion?(.claudeCode, false)
            } else {
                record(handoff, .claudeCode, .prepared, nil, t0: t0)
                Notifier.info(L10n.s("Prepared in the terminal"), L10n.s("Review the content and send manually (never auto-enters)"))
                completion?(.claudeCode, true)
            }
        case .clipboard:
            let copied = clipboardFallback(handoff, reason: L10n.s("User chose clipboard"), t0: t0)
            completion?(.clipboard, copied)
        case .chatgptDesktop:
            // S3 verified path: AX opt-in + kAXValueAttribute set-value, no auto-submit.
            if let reason = ChatGPTDelivery.deliver(handoff) {
                record(handoff, .chatgptDesktop, .failed, reason, t0: t0)
                Notifier.error(L10n.f("Could not prepare materials for %@", "ChatGPT"), reason)
                clipboardFallback(handoff, reason: reason, t0: t0)
                completion?(.chatgptDesktop, false)
            } else {
                record(handoff, .chatgptDesktop, .prepared, nil, t0: t0)
                completion?(.chatgptDesktop, true)
            }
        case .cowork:
            // S2: .mcpb mechanism confirmed (see cowork-extension/), end-to-end install still
            // fast-follow — degrade to clipboard until then.
            let copied = clipboardFallback(handoff, reason: L10n.s("Cowork integration awaits S2 end-to-end acceptance — clipboard for now"), t0: t0)
            completion?(.cowork, copied)
        case .kimiWork:
            // Verified 2026-10-18: AX-locate the composer, focus it, clipboard-paste (no auto-send).
            if let reason = KimiDelivery.deliver(handoff) {
                record(handoff, .kimiWork, .failed, reason, t0: t0)
                Notifier.error(L10n.f("Could not prepare materials for %@", "Kimi Work"), reason)
                clipboardFallback(handoff, reason: reason, t0: t0)
                completion?(.kimiWork, false)
            } else {
                record(handoff, .kimiWork, .prepared, nil, t0: t0)
                completion?(.kimiWork, true)
            }
        }
    }

    /// Universal fallback (golden line, spec §4.1/§7.1). Writes the full rendered prompt to the
    /// clipboard + notifies. NOTE: this proactively OWNS the clipboard — it does NOT restore
    /// (only ClaudeCodeDelivery's safe-paste restores). codex review.
    @discardableResult
    private func clipboardFallback(_ handoff: Handoff, reason: String, t0: Date) -> Bool {
        let md = handoff.markdown
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(md, forType: .string) else {
            record(handoff, .clipboard, .failed, L10n.s("Could not copy materials"), t0: t0)
            Notifier.error(L10n.s("Could not copy materials"))
            return false
        }
        record(handoff, .clipboard, .copied, reason, t0: t0)
        Notifier.info(L10n.s("Content copied — paste it into your target"), reason)
        return true
    }

    private func record(_ handoff: Handoff, _ target: DeliveryTarget, _ status: DeliveryStatus,
                        _ err: String?, t0: Date) {
        for item in handoff.items {
            let d = Delivery(captureID: item.capture.id, target: target, status: status, errorMessage: err,
                             durationMs: Int(Date().timeIntervalSince(t0) * 1000))
            try? store.recordDelivery(d)
        }
    }
}
