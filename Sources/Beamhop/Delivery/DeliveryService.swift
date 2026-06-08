import AppKit
import Foundation
import BeamhopCore

/// Single delivery entry point (spec §7.1 / §12.4). Routes to a target channel; on ANY failure
/// it falls back to the clipboard handoff — never a silent failure. Records a Delivery row.
final class DeliveryService {
    private let store: CaptureStore
    init(store: CaptureStore) { self.store = store }

    func deliver(_ capture: Capture, to target: DeliveryTarget, userNote: String? = nil) {
        switch target {
        case .claudeCode:
            if let reason = ClaudeCodeDelivery.deliver(capture, userNote: userNote) {
                record(capture, .claudeCode, .failed, reason)
                Notifier.error("Claude Code 投递失败 → 已复制到剪贴板", reason)
                clipboardFallback(capture, userNote: userNote, reason: reason)
            } else {
                record(capture, .claudeCode, .success, nil)
                Notifier.success("已投递到 Claude Code", capture.appName)
            }
        case .clipboard:
            clipboardFallback(capture, userNote: userNote, reason: "用户选择剪贴板")
        case .cowork, .chatgptDesktop:
            // Week 4-5; for now degrade to clipboard handoff.
            clipboardFallback(capture, userNote: userNote, reason: "\(target.rawValue) 投递 Week 4-5,先用剪贴板")
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
        Notifier.info("内容已复制,请在目标里粘贴", reason)
    }

    private func record(_ capture: Capture, _ target: DeliveryTarget, _ status: DeliveryStatus, _ err: String?) {
        let d = Delivery(captureID: capture.id, target: target, status: status, errorMessage: err)
        try? store.recordDelivery(d)
    }
}
