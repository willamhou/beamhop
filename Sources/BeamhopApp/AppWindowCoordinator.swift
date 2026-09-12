import AppKit
import SwiftUI

private final class BeamhopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var capturePanel: BeamhopPanel?
    private var inboxController: NSWindowController?
    private var diagnosticsController: NSWindowController?
    private var compatibilityController: NSWindowController?
    private var onboardingController: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func showCapturePanel() {
        let panel = capturePanel ?? makeCapturePanel()
        capturePanel = panel
        position(panel, near: NSEvent.mouseLocation)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func closeCapturePanel() {
        capturePanel?.orderOut(nil)
    }

    func showInbox() {
        if inboxController == nil {
            inboxController = makeWindow(
                title: "Beamhop Inbox",
                size: NSSize(width: 980, height: 650),
                rootView: InboxView().environmentObject(model)
            )
        }
        Task { await model.refreshInbox() }
        show(inboxController)
    }

    func showDiagnostics() {
        if diagnosticsController == nil {
            diagnosticsController = makeWindow(
                title: "Permission Diagnostics",
                size: NSSize(width: 720, height: 590),
                rootView: DiagnosticsView().environmentObject(model)
            )
        }
        Task { await model.diagnostics.refresh() }
        show(diagnosticsController)
    }

    func showCompatibility() {
        if compatibilityController == nil {
            compatibilityController = makeWindow(
                title: "Compatibility Matrix",
                size: NSSize(width: 760, height: 620),
                rootView: CompatibilityView().environmentObject(model)
            )
        }
        model.compatibility.reload()
        show(compatibilityController)
    }

    func showOnboarding() {
        if onboardingController == nil {
            let controller = makeWindow(
                title: "开始使用 Beamhop",
                size: NSSize(width: 690, height: 590),
                rootView: FirstRunView().environmentObject(model)
            )
            controller.window?.styleMask.remove(.resizable)
            onboardingController = controller
        }
        show(onboardingController)
    }

    func closeOnboarding() {
        onboardingController?.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? BeamhopPanel,
              panel == capturePanel else { return }
        panel.orderOut(nil)
    }

    private func makeCapturePanel() -> BeamhopPanel {
        let panel = BeamhopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Beamhop Capture"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: CapturePanelView().environmentObject(model)
        )
        return panel
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: min(560, size.width), height: min(440, size.height))
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        return NSWindowController(window: window)
    }

    private func show(_ controller: NSWindowController?) {
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    private func position(_ panel: NSWindow, near mouse: NSPoint) {
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mouse, screen.frame, false)
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let origin = NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
