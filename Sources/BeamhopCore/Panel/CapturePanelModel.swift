import Foundation
import Combine

/// View-model for the capture panel (Week 3, spec §2.1). The model holds NO services:
/// confirm/cancel/hold are callbacks injected by AppServices at show time (plan Task 1.3).
/// Lives in BeamhopCore so its presentation logic is unit-testable without AppKit/SwiftUI.
///
/// 2026-10-19 — the two product-essay ideas live here:
/// - 原地路由 + 「先留着」(essay 01): hold() parks the capture in the pocket instead of
///   delivering; the pocket only accumulates what the user CHOSE to hold.
/// - 两层去处 + 换会话确认 (essay 02): an optional work name binds this destination to a
///   named work. If that work was REBOUND to a different receiver elsewhere and the user has
///   not confirmed the new address, confirm() is two-step: the first call only surfaces the
///   change (confirmLabel flips to "确认新地址"), the second call actually delivers. A
///   similar name can never silently redirect material.
public final class CapturePanelModel: ObservableObject {
    /// nil = "仅入 Inbox" (⌘0): an explicit no-delivery choice, distinct from Esc-cancel.
    @Published public var selectedTarget: DeliveryTarget?
    @Published public var note: String = ""
    /// Optional named-destination binding (essay 02). Empty = plain tool-level routing.
    @Published public var workName: String = ""

    public let capture: Capture

    /// Targets that actually exist on this machine (AppServices resolves via
    /// TargetAvailability + TargetDetector). Chips outside this list are not rendered
    /// and their shortcuts do nothing — no fake choices. Defaults to everything for tests.
    public let visibleTargets: [DeliveryTarget]

    /// The work this panel's destination resolves to (nil when workName is empty/unknown).
    /// `workNeedsConfirmation` is derived from it; injected by AppServices at show time.
    public let boundWork: Work?

    /// true = the bound work's receiving session changed since the user last confirmed it.
    public var workNeedsConfirmation: Bool { boundWork?.needsConfirmation ?? false }

    /// 换绑闸（essay 02）: fires when EITHER the stored work was rebound elsewhere and not
    /// yet confirmed, OR the user picked a DIFFERENT receiver for a bound work in this panel
    /// (choosing a new receiver under a work's name IS a rebind — the work outlives sessions,
    /// so its address must be verified, not silently switched). Inbox-only (nil target) never
    /// gates: nothing is routed.
    public var receiverChanged: Bool {
        guard let boundWork else { return false }
        if workNeedsConfirmation { return true }
        guard let selectedTarget else { return false }
        return selectedTarget != boundWork.boundTarget
    }

    /// Set by the first confirm press when workNeedsConfirmation; arms the second press.
    @Published public private(set) var rebindAcknowledged = false

    private let onConfirm: (DeliveryTarget?, String) -> Void
    private let onCancel: () -> Void
    /// 「先留着」: park this capture (+ note + intended target) in the hold stack.
    private let onHold: ((DeliveryTarget?, String) -> Void)?

    public init(capture: Capture,
                initialTarget: DeliveryTarget?,
                visibleTargets: [DeliveryTarget] = DeliveryTarget.allCases,
                boundWork: Work? = nil,
                workName: String = "",
                onConfirm: @escaping (DeliveryTarget?, String) -> Void,
                onCancel: @escaping () -> Void,
                onHold: ((DeliveryTarget?, String) -> Void)? = nil) {
        self.capture = capture
        self.visibleTargets = visibleTargets
        self.selectedTarget = TargetAvailability.usable(initialTarget, among: visibleTargets)
        self.boundWork = boundWork
        self.workName = workName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onHold = onHold
    }

    /// Deliver. Two-step when a rebound work is unacknowledged: first press only acknowledges
    /// (the label already shows the NEW receiver), second press fires the real callback.
    public func confirm() {
        if receiverChanged && !rebindAcknowledged {
            rebindAcknowledged = true
            return
        }
        onConfirm(selectedTarget, note)
    }

    public func cancel() { onCancel() }

    /// 「先留着」— essay 01: keep the material (with note + current target choice) in the
    /// pocket; nothing is delivered, the reading position stays put.
    public func hold() { onHold?(selectedTarget, note) }

    public var canHold: Bool { onHold != nil }

    // MARK: presentation helpers

    public var summaryLine: String {
        var parts: [String] = [capture.appName]
        if let t = capture.windowTitle, !t.isEmpty { parts.append(t) }
        let chars = (capture.selectedText?.count ?? 0) + (capture.extractedBody?.count ?? 0)
        if chars > 0 { parts.append("\(chars / 10 * 10) \(L10n.s("chars"))") }
        return parts.joined(separator: " · ")
    }

    public var previewText: String? {
        let body = capture.selectedText ?? capture.extractedBody
        guard let body, !body.isEmpty else { return nil }
        return String(body.prefix(200))
    }

    /// Target button label; Cowork stays honest about its clipboard degradation (spec §2.1).
    public func targetLabel(_ target: DeliveryTarget) -> String {
        switch target {
        case .claudeCode: return L10n.s("Claude Code")
        case .chatgptDesktop: return L10n.s("ChatGPT")
        case .cowork: return L10n.s("Cowork → clipboard")
        case .clipboard: return L10n.s("Clipboard")
        case .kimiWork: return L10n.s("Kimi Work")
        }
    }

    /// Essay 02 two-layer display: work name on top, receiving session below.
    /// With no bound work this degrades to the plain tool label.
    public var destinationTitle: String {
        if let boundWork, !boundWork.name.isEmpty { return boundWork.name }
        if let selectedTarget { return targetLabel(selectedTarget) }
        return L10n.s("Inbox")
    }

    public var destinationSubtitle: String? {
        guard boundWork != nil, let selectedTarget else { return nil }
        let label = targetLabel(selectedTarget)
        return receiverChanged && !rebindAcknowledged
            ? L10n.f("接收会话已更换 → %@", label)
            : label
    }

    public var confirmLabel: String {
        // Unacknowledged rebind: the first press is an ACK, not a delivery — say so (essay 02:
        // 状态必须照实说; a pretty "Send" that actually just acknowledges would be a lie).
        if receiverChanged && !rebindAcknowledged {
            guard let selectedTarget else {
                return L10n.s("确认新地址后存入 Inbox")
            }
            return L10n.f("确认新地址并发送到 %@", targetLabel(selectedTarget))
        }
        guard let selectedTarget else { return L10n.s("Save to Inbox only") }
        return L10n.f("Deliver (%@)", targetLabel(selectedTarget))
    }
}
