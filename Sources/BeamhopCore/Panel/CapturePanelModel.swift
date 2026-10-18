import Foundation
import Combine

/// View-model for the capture panel (Week 3, spec §2.1). The model holds NO services:
/// confirm/cancel are callbacks injected by AppServices at show time (plan Task 1.3).
/// Lives in BeamhopCore so its presentation logic is unit-testable without AppKit/SwiftUI.
public final class CapturePanelModel: ObservableObject {
    /// nil = "仅入 Inbox" (⌘0): an explicit no-delivery choice, distinct from Esc-cancel.
    @Published public var selectedTarget: DeliveryTarget?
    @Published public var note: String = ""

    public let capture: Capture

    private let onConfirm: (DeliveryTarget?, String) -> Void
    private let onCancel: () -> Void

    public init(capture: Capture,
                initialTarget: DeliveryTarget?,
                onConfirm: @escaping (DeliveryTarget?, String) -> Void,
                onCancel: @escaping () -> Void) {
        self.capture = capture
        self.selectedTarget = initialTarget
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public func confirm() { onConfirm(selectedTarget, note) }
    public func cancel() { onCancel() }

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

    public var confirmLabel: String {
        guard let selectedTarget else { return L10n.s("Save to Inbox only") }
        return L10n.s("Deliver (\(targetLabel(selectedTarget)))")
    }
}
