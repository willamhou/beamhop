import AppKit
import SwiftUI
import BeamhopCore

/// Owns the NSPanel shell for the capture panel (Week 3 spec §3.1, S5 configuration verbatim).
/// Panel hides — never destroys — so re-shows are instant and hotkeys keep working (S5).
final class CapturePanelController {
    enum FinishAction { case confirm, hold, cancel }
    private(set) var panel: HandoffPanel?
    /// Guard against the confirm → orderOut → didResignKey race (plan Task 2.2): once a
    /// delivery is in flight, a resign triggered by our own hide must not run the cancel path.
    private(set) var isDelivering = false
    /// Set when confirm/cancel already handled this showing, so the resign observer no-ops.
    private var finished = false
    /// Latest cancel handler (resign = Esc); replaced on every show so the observer never
    /// calls a stale closure from a previous capture.
    private var cancelHandler: (() -> Void)?
    private var resignObserver: NSObjectProtocol?
    private var sourceApp: NSRunningApplication?
    private var captureID: String?
    private var presentation = 0
    private(set) var currentModel: CapturePanelModel?

    /// Show (or replace) the panel for a capture. `onConfirm` receives the chosen target
    /// (nil = 仅入 Inbox) and the note; `onCancel` = Esc / focus-loss path; `onHold` = 「先留着」
    /// (essay 01) — park in the pocket instead of delivering.
    func show(capture: Capture,
              defaultTarget: DeliveryTarget?,
              visibleTargets: [DeliveryTarget] = DeliveryTarget.allCases,
              boundWork: Work? = nil,
              workName: String = "",
              availableWorks: [Work] = [],
              draft: HopDraft? = nil,
              configure: ((CapturePanelModel) -> Void)? = nil,
              beforeFinish: ((CapturePanelModel, FinishAction) -> Bool)? = nil,
              onConfirm: @escaping (DeliveryTarget?, String) -> Void,
              onCancel: @escaping () -> Void,
              onHold: ((DeliveryTarget?, String) -> Void)? = nil) {
        // A new capture replaces the previous one only after its draft has been saved.
        if isVisible && !finished {
            currentModel?.cancel()
            if !finished { return }
        }
        // Keep the running-app object rather than resolving the PID on close (PID reuse).
        sourceApp = NSRunningApplication(processIdentifier: pid_t(capture.pid))
        captureID = capture.id
        presentation += 1
        let presentation = self.presentation
        let model = CapturePanelModel(
            capture: capture,
            initialTarget: defaultTarget,
            visibleTargets: visibleTargets,
            boundWork: boundWork,
            workName: workName,
            availableWorks: availableWorks,
            onConfirm: { [weak self] target, note in
                guard let self, !self.finished, self.presentation == presentation else { return }
                guard let model = self.currentModel, beforeFinish?(model, .confirm) != false else { return }
                self.finished = true
                self.isDelivering = true
                self.hide()
                // No target activation follows these choices. Native deliveries own focus
                // until their completion callback; do not race them by activating the source.
                if target == nil || target == .clipboard || target == .cowork {
                    self.restoreSourceIfStillActive(captureID: capture.id)
                }
                onConfirm(target, note)
            },
            onCancel: { [weak self] in
                guard let self, !self.finished, self.presentation == presentation else { return }
                guard let model = self.currentModel, beforeFinish?(model, .cancel) != false else { return }
                self.finished = true
                self.hide()
                self.restoreSourceIfStillActive(captureID: capture.id)
                onCancel()
            },
            onHold: onHold.map { handler in
                { [weak self] target, note in
                    guard let self, !self.finished, self.presentation == presentation else { return }
                    guard let model = self.currentModel, beforeFinish?(model, .hold) != false else { return }
                    self.finished = true
                    self.hide()
                    self.restoreSourceIfStillActive(captureID: capture.id)
                    handler(target, note)
                }
            }
        )

        if panel == nil { panel = makePanel() }
        finished = false
        isDelivering = false   // a new showing supersedes any in-flight delivery race guard
        currentModel = model
        if let draft { model.restore(draft) }
        configure?(model)
        panel?.onEscape = { [weak model] in model?.cancel() }
        panel?.onShortcut = { [weak model] key in model?.handleShortcut(key) ?? false }
        panel?.onReturn = { [weak model] in model?.confirm() }
        panel?.contentView = NSHostingView(rootView: CapturePanelView(model: model)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(PanelSizeReader { [weak self] size in
                DispatchQueue.main.async {
                    guard let self, self.presentation == presentation, !self.finished else { return }
                    self.panel?.fitContent(size)
                }
            }))
        panel?.standardWindowButton(.closeButton)?.isHidden = true
        panel?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel?.standardWindowButton(.zoomButton)?.isHidden = true
        panel?.center()

        // 失焦 = Esc（验收 §2.2 第 5 条）。Panel listens to its own notification (plan Task 2.2).
        if resignObserver == nil, let panel {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                guard let self, !self.isDelivering, !self.finished else { return }
                // App activation and window-key changes arrive separately. On a rapid reopen
                // an old resign may arrive just before this panel becomes key again. Resolve
                // on the next main-loop turn and cancel only if it is still non-key.
                let presentation = self.presentation
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isDelivering, !self.finished,
                          self.presentation == presentation,
                          self.panel?.isKeyWindow == false,
                          self.panel?.attachedSheet == nil else { return }
                    self.currentModel?.isCreating = false
                    self.currentModel?.cancel()
                }
            }
        }
        self.cancelHandler = onCancel

        // Key input belongs to the panel; the source application remains active.
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        // A new showing resets the delivering flag; keep it until then so any late resign is ignored.
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Delivery completion may arrive after another capture has opened. Never restore that
    /// older source, steal focus from the destination, or leave the Inbox while it is in use.
    func restoreSourceIfStillActive(captureID: String) {
        guard self.captureID == captureID, let sourceApp else { return }
        // A document window can already be opening while AppKit still reports the outgoing
        // panel (or nil) as key. Do not let source restoration overtake that activation.
        let hasOtherWindow = NSApp.windows.contains {
            $0 !== panel && $0.isVisible && ($0.canBecomeMain || $0.isKeyWindow)
        }
        guard CaptureFocusPolicy.shouldRestore(
            sourcePID: sourceApp.processIdentifier,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            sourceTerminated: sourceApp.isTerminated,
            hasVisibleBeamhopWindow: isVisible || hasOtherWindow
        ) else { return }
        sourceApp.activate(options: [])
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    private func makePanel() -> HandoffPanel {
        let p = HandoffPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.level = .floating                                    // above fullscreen apps (S5)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false                         // S5: hide, not destroy
        p.hidesOnDeactivate = false                            // resign handling is ours (=Esc)
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = false                       // must take key for the note field
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        return p
    }
}
