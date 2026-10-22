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
///   change (confirmLabel asks to use the new app), the second call actually delivers. A
///   similar name can never silently redirect material.
public final class CapturePanelModel: ObservableObject {
    /// nil = "仅入 Inbox" (⌘0): an explicit no-delivery choice, distinct from Esc-cancel.
    @Published public var selectedTarget: DeliveryTarget? {
        didSet {
            if selectedTarget != oldValue { rebindAcknowledged = false }
            if let selectedTarget, visibleTargets.contains(selectedTarget) { unavailableTarget = nil }
            draftChanged()
        }
    }
    @Published public var note: String = "" { didSet { draftChanged() } }
    @Published public var materials: [HopMaterial] = [] { didSet { draftChanged() } }
    @Published public var session: HopRoute.Session = .currentWindow { didSet { draftChanged() } }
    @Published public var draftError: String?
    @Published public var pendingImportCount = 0
    @Published public var savedRoutes: [HopRoute] = []
    @Published public var projects: [String] = []
    @Published public var isCreating = false
    public var creatingProject = false
    /// Legacy named-work fixtures retain rebind behavior; production projects are context.
    public var usesProjectContext = false
    @Published public var additionalText = "" { didSet { draftChanged() } }
    private let additionalID = UUID().uuidString
    public var onDraftChange: ((HopDraft) -> Void)?
    public var onRememberRoute: ((HopRoute) -> Void)?
    public var onOpenPocket: (() -> Void)?
    public var onAttachmentAction: (() -> Void)?
    public var onPasteAttachments: (() -> Void)?
    public var onDropFiles: (([URL]) -> Void)?
    public var onCopyText: (() -> Void)?
    private var draftID = UUID().uuidString
    private var restoring = false
    public var snapshot: HopDraft {
        var allMaterials = materials
        if !additionalText.isEmpty {
            var added = HopMaterial(text: additionalText); added.id = additionalID
            allMaterials.append(added)
        }
        var draft = HopDraft(materials: allMaterials, instruction: note,
                             route: HopRoute(target: unavailableTarget ?? selectedTarget, project: workName, session: session))
        draft.id = draftID
        return draft
    }
    private func draftChanged() { if !restoring { onDraftChange?(snapshot) } }
    public func restore(_ draft: HopDraft) {
        restoring = true
        draftID = draft.id; materials = draft.materials; note = draft.instruction; additionalText = ""
        workName = draft.route.project; session = draft.route.session
        selectedTarget = draft.route.target
        unavailableTarget = draft.route.target.flatMap { visibleTargets.contains($0) ? nil : $0 }
        restoring = false
    }
    public func chooseRoute(_ route: HopRoute) {
        restoring = true
        workName = route.project; session = route.session; selectedTarget = route.target
        unavailableTarget = route.target.flatMap { visibleTargets.contains($0) ? nil : $0 }
        restoring = false; draftChanged()
    }
    public func addText(_ text: String) { materials.append(HopMaterial(text: text)) }
    public var attachmentWarning: String? {
        guard !snapshot.attachments.isEmpty else { return nil }
        return L10n.s("This connection accepts text only. Keep attachments in Pocket, or copy text and add files in the receiving app.")
    }
    @Published public private(set) var unavailableTarget: DeliveryTarget?
    public var canConfirm: Bool {
        !isCreating && pendingImportCount == 0 && draftError == nil && snapshot.hasContent
            && (selectedTarget == nil || session == .newInApp || snapshot.attachments.isEmpty)
            && unavailableTarget == nil && (selectedTarget.map { visibleTargets.contains($0) } ?? true)
    }
    /// Optional named-destination binding (essay 02). Empty = plain tool-level routing.
    @Published public var workName: String = "" {
        didSet { if workName != oldValue { rebindAcknowledged = false }; draftChanged() }
    }

    public let capture: Capture

    /// Targets that actually exist on this machine (AppServices resolves via
    /// TargetAvailability + TargetDetector). Chips outside this list are not rendered
    /// and their shortcuts do nothing — no fake choices. Defaults to everything for tests.
    public let visibleTargets: [DeliveryTarget]

    /// The work this panel's destination resolves to (nil when workName is empty/unknown).
    /// `workNeedsConfirmation` is derived from it; injected by AppServices at show time.
    public let availableWorks: [Work]
    public var boundWork: Work? {
        let name = workName.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableWorks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func chooseWork(_ work: Work) {
        workName = work.name
        // An unavailable receiver must not silently become a different app.
        selectedTarget = visibleTargets.contains(work.boundTarget) ? work.boundTarget : nil
        unavailableTarget = visibleTargets.contains(work.boundTarget) ? nil : work.boundTarget
        rebindAcknowledged = false
    }

    public func chooseTool(_ target: DeliveryTarget?) {
        if !usesProjectContext { workName = "" }
        session = .currentWindow
        selectedTarget = target
        unavailableTarget = target.flatMap { visibleTargets.contains($0) ? nil : $0 }
    }

    /// Menu contents are lazy in SwiftUI. Keep shortcuts available while that menu is closed.
    @discardableResult
    public func handleShortcut(_ key: String) -> Bool {
        guard let shortcut = PanelShortcut(rawValue: key) else { return false }
        if shortcut.isHold {
            guard canHold else { return false }
            hold()
        } else if let target = shortcut.target {
            guard visibleTargets.contains(target) else { return false }
            chooseTool(target)
        } else {
            chooseTool(nil)
        }
        return true
    }

    /// true = the bound work's receiving app changed since the user last confirmed it.
    public var workNeedsConfirmation: Bool { boundWork?.needsConfirmation ?? false }

    /// 换绑闸（essay 02）: fires when EITHER the stored work was rebound elsewhere and not
    /// yet confirmed, OR the user picked a DIFFERENT receiver for a bound work in this panel
    /// (choosing a new receiver under a work's name IS a rebind — the work outlives sessions,
    /// so its address must be verified, not silently switched). Inbox-only (nil target) never
    /// gates: nothing is routed.
    public var receiverChanged: Bool {
        guard selectedTarget != nil, let boundWork else { return false }
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
                workName: String? = nil,
                availableWorks: [Work] = [],
                onConfirm: @escaping (DeliveryTarget?, String) -> Void,
                onCancel: @escaping () -> Void,
                onHold: ((DeliveryTarget?, String) -> Void)? = nil) {
        self.capture = capture
        self.materials = [HopMaterial(capture: capture)]
        self.visibleTargets = visibleTargets
        self.selectedTarget = boundWork != nil && !visibleTargets.contains(boundWork!.boundTarget)
            ? nil : TargetAvailability.usable(initialTarget, among: visibleTargets)
        self.availableWorks = availableWorks + (boundWork.map { work in
            availableWorks.contains(where: { $0.id == work.id }) ? [] : [work]
        } ?? [])
        self.workName = workName ?? boundWork?.name ?? ""
        let intended = boundWork?.boundTarget ?? initialTarget
        self.unavailableTarget = intended.flatMap { visibleTargets.contains($0) ? nil : $0 }
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onHold = onHold
    }

    /// Deliver. Two-step when a rebound work is unacknowledged: first press only acknowledges
    /// (the label already shows the NEW receiver), second press fires the real callback.
    public func confirm() {
        guard canConfirm else { return }
        if receiverChanged && !rebindAcknowledged {
            rebindAcknowledged = true
            return
        }
        onConfirm(selectedTarget, note)
    }

    public func cancel() {
        if isCreating { isCreating = false; return }
        onCancel()
    }

    /// 「先留着」— essay 01: keep the material (with note + current target choice) in the
    /// pocket; nothing is delivered, the reading position stays put.
    public func hold() {
        guard canHold else { return }
        onHold?(unavailableTarget ?? selectedTarget, note)
    }

    public var canHold: Bool { onHold != nil && !isCreating && pendingImportCount == 0 && snapshot.hasContent }

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

    /// Essay 02 two-layer display: work name on top, receiving app below.
    /// With no bound work this degrades to the plain tool label.
    public var destinationTitle: String {
        let name = workName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let unavailableTarget { return targetLabel(unavailableTarget) }
        if let selectedTarget { return targetLabel(selectedTarget) }
        return L10n.s("Inbox")
    }

    public var destinationSubtitle: String? {
        guard boundWork != nil, let selectedTarget else { return nil }
        let label = targetLabel(selectedTarget)
        return receiverChanged && !rebindAcknowledged
            ? L10n.f("Receiving app changed to %@", label)
            : label
    }

    public var confirmLabel: String {
        if unavailableTarget != nil { return L10n.s("Choose destination") }
        // Unacknowledged rebind: the first press is an ACK, not a delivery — say so (essay 02:
        // 状态必须照实说; a pretty "Send" that actually just acknowledges would be a lie).
        if receiverChanged && !rebindAcknowledged {
            return L10n.f("Use %@ for this work", targetLabel(selectedTarget!))
        }
        guard let selectedTarget else { return L10n.s(usesProjectContext ? "Save local draft" : "Save to Inbox only") }
        if session == .newInApp { return L10n.f("Create session in %@", selectedTarget.displayName) }
        return selectedTarget.handoffAction
    }
}
