import AppKit
import SwiftUI
import BeamhopCore

/// Owns the NSPanel shell for the capture panel (Week 3 spec §3.1, S5 configuration verbatim).
/// Panel hides — never destroys — so re-shows are instant and hotkeys keep working (S5).
final class CapturePanelController {
    private var panel: NSPanel?
    /// Guard against the confirm → orderOut → didResignKey race (plan Task 2.2): once a
    /// delivery is in flight, a resign triggered by our own hide must not run the cancel path.
    private(set) var isDelivering = false
    /// Set when confirm/cancel already handled this showing, so the resign observer no-ops.
    private var finished = false
    /// Latest cancel handler (resign = Esc); replaced on every show so the observer never
    /// calls a stale closure from a previous capture.
    private var cancelHandler: (() -> Void)?
    private var resignObserver: NSObjectProtocol?

    /// Show (or replace) the panel for a capture. `onConfirm` receives the chosen target
    /// (nil = 仅入 Inbox) and the note; `onCancel` = Esc / focus-loss path.
    func show(capture: Capture,
              defaultTarget: DeliveryTarget?,
              onConfirm: @escaping (DeliveryTarget?, String) -> Void,
              onCancel: @escaping () -> Void) {
        let model = CapturePanelModel(
            capture: capture,
            initialTarget: defaultTarget,
            onConfirm: { [weak self] target, note in
                guard let self else { return }
                self.finished = true
                self.isDelivering = true
                self.hide()
                onConfirm(target, note)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.finished = true
                self.hide()
                onCancel()
            }
        )

        if panel == nil { panel = makePanel() }
        finished = false
        isDelivering = false   // a new showing supersedes any in-flight delivery race guard
        panel?.contentView = NSHostingView(rootView: CapturePanelView(model: model))
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
                self.finished = true
                self.hide()
                self.cancelHandler?()
            }
        }
        self.cancelHandler = onCancel

        // nonactivating panel: explicit activation so keyboard input lands reliably (spec §3.1).
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        // A new showing resets the delivering flag; keep it until then so any late resign is ignored.
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
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
