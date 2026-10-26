import AppKit
import BeamhopCore
import SwiftUI

/// Observes permissions; real workflow callbacks drive progress, not a Next button.
final class FirstRunWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var refreshTimer: Timer?
    private let permissions: PermissionService
    private let onOpenDiagnostics: () -> Void
    private let onOpenPocket: () -> Void
    let model: OnboardingModel

    init(
        permissions: PermissionService, defaults: UserDefaults = .standard,
        onOpenDiagnostics: @escaping () -> Void, onOpenPocket: @escaping () -> Void = {}
    ) {
        self.permissions = permissions
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onOpenPocket = onOpenPocket
        model = OnboardingModel(defaults: defaults)
        super.init()
    }
    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 650),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Welcome to Beamhop"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
            w.contentView = NSHostingView(
                rootView: FirstRunView(
                    model: model,
                    onOpenAX: { [weak self] in self?.permissions.openAccessibilitySettings() },
                    onOpenDiagnostics: onOpenDiagnostics,
                    onOpenPocket: { [weak self] in
                        self?.hide()
                        self?.onOpenPocket()
                    },
                    onContinue: { [weak self] in self?.hide() }))
        }
        refreshPermission()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startRefreshing()
    }
    private func refreshPermission() { model.refreshAccessibility(granted: permissions.accessibility() == .granted) }
    private func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.refreshPermission()
        }
    }
    private func hide() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        window?.orderOut(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermission()
        startRefreshing()
    }
    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    deinit { refreshTimer?.invalidate() }
}

struct FirstRunView: View {
    @ObservedObject var model: OnboardingModel
    let onOpenAX: () -> Void
    let onOpenDiagnostics: () -> Void
    let onOpenPocket: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your first real handoff").font(.system(size: 27, weight: .bold))
                Text("Beamhop prepares material for an existing agent. You review and send it yourself.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FirstRunRow(
                    index: "1", title: "Accessibility permission",
                    detail:
                        "Allow this exact app in System Settings, then return here. Permission status refreshes automatically. Screen Recording is optional for text.",
                    ready: model.accessibilityGranted,
                    actionTitle: model.accessibilityGranted ? "Enabled" : "Open System Settings", action: onOpenAX)
                FirstRunRow(
                    index: "2", title: "Capture real material",
                    detail:
                        "Switch to a disposable note or browser page, select text and press ⌘⇧Space. Capture from the source app, not this guide.",
                    ready: model.progress.hasCaptured, actionTitle: "Go to source app", action: onContinue)
                FirstRunRow(
                    index: "3", title: "Choose a receiver and prepare",
                    detail:
                        "Review the edited material. Return adds a newline; ⌘Return copies or prepares it. Clipboard works without MCP. Projects are not verified agent sessions.",
                    ready: model.progress.hasTransportReceipt,
                    actionTitle: model.progress.needsRecovery ? "Open Pocket and recovery" : "Continue manually",
                    action: model.progress.needsRecovery ? onOpenPocket : onContinue)
                if model.progress.needsRecovery {
                    Label(
                        "The last handoff is incomplete or unknown. Check the receiver, then restore its backup in Pocket before retrying.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange).font(.callout).fixedSize(horizontal: false, vertical: true)
                } else if model.progress.hasTransportReceipt {
                    Label(
                        "A local copy or draft is ready, not sent. Paste or review it in the receiver and submit manually; Beamhop cannot verify task completion.",
                        systemImage: "doc.on.clipboard"
                    )
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "Optional MCP return: load the updated helper in your agent and reconnect. Registration alone is not tool availability. Enable return before a Hop; find returned conclusions in Inbox or its Pocket history."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Pocket and recovery", action: onOpenPocket).accessibilityIdentifier(
                        "onboarding.pocket")
                    Spacer()
                    Button("Open Diagnostics", action: onOpenDiagnostics).accessibilityIdentifier(
                        "onboarding.diagnostics")
                }
                Text("You can reopen this guide from Getting Started in the menu bar. Nothing is sent automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.frame(width: 540, height: 650)
    }
}

private struct FirstRunRow: View {
    let index: String
    let title: String
    let detail: String
    let ready: Bool
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ready ? "✓" : index).font(.headline).foregroundStyle(ready ? .green : .secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.s(title)).fontWeight(.medium)
                Text(L10n.s(detail)).font(.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
                Button(L10n.s(actionTitle), action: action).disabled(ready && actionTitle == "Enabled")
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
