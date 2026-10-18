import AppKit
import SwiftUI

/// First-run window (spec §9.4, skeleton): explains what Beamhop does, walks the one REQUIRED
/// permission (Accessibility), and makes optional pieces discoverable instead of blocking.
/// Everything is skippable — AX + local Inbox + clipboard fallback is the minimal usable set.
final class FirstRunWindowController {
    private var window: NSWindow?
    private let permissions: PermissionService
    private let onOpenDiagnostics: () -> Void

    init(permissions: PermissionService, onOpenDiagnostics: @escaping () -> Void) {
        self.permissions = permissions
        self.onOpenDiagnostics = onOpenDiagnostics
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Welcome to Beamhop"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: FirstRunView(
            axGranted: permissions.accessibility() == .granted,
            onOpenAX: { [weak self] in self?.permissions.openAccessibilitySettings() },
            onOpenDiagnostics: onOpenDiagnostics
        ))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FirstRunView: View {
    let axGranted: Bool
    let onOpenAX: () -> Void
    let onOpenDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Beamhop").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Press ⌘⇧Space to capture the frontmost app's context. It is saved to the local Inbox first — you decide which agent gets it.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 22)

            VStack(spacing: 0) {
                FirstRunRow(
                    index: "1", title: "Accessibility permission",
                    detail: "Required: reads the frontmost app's title and selection, and performs clipboard-safe paste.",
                    ready: axGranted,
                    actionTitle: axGranted ? "Enabled" : "Open System Settings",
                    action: onOpenAX)
                Divider().padding(.horizontal, 12)
                FirstRunRow(
                    index: "2", title: "Browser extension & agent registration",
                    detail: "Optional — finish later from the Diagnostics window. AX + local Inbox + clipboard fallback is enough to start.",
                    ready: false, actionTitle: "Open Diagnostics", action: onOpenDiagnostics)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            .padding(.bottom, 22)

            Spacer()
            Text("Once Accessibility is enabled, press ⌘⇧Space to capture your first item.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 420)
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(ready ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                Text(ready ? "✓" : index).font(.callout.weight(.semibold))
            }.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle, action: action).disabled(ready && actionTitle == "Enabled")
        }
        .padding(12)
    }
}
