import AppKit
import SwiftUI
import BeamhopCore

/// A transient corner shelf. Opening is deliberate; capture only updates the HUD count.
final class PocketWindowController {
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?
    let model = PocketModel()

    func show() {
        if panel?.isVisible == true { hide(); return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isReleasedWhenClosed = false
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.contentView = NSHostingView(rootView: PocketView(model: model) { [weak self] in self?.hide() })
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: p, queue: .main
            ) { [weak self] _ in self?.hide() }
            panel = p
        }
        model.reload()
        if let panel, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.minY + 64))
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

struct PocketView: View {
    @ObservedObject var model: PocketModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Held for later", systemImage: "tray")
                    .font(.headline)
                Text("\(model.count)").foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }
            if model.items.isEmpty {
                Text("When a destination can wait, hold the material here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                Text("Choose what belongs in this handoff.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.items, id: \.0.id) { pair in
                            row(pair.0, capture: pair.1)
                        }
                    }
                }
                .frame(height: min(CGFloat(model.count) * 96, 240))
                Divider()
                if model.hasMixedDestinations {
                    Text("These materials belong to different destinations. Hand them off separately.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Menu {
                        ForEach(TargetDetector.availableTargets(), id: \.self) { target in
                            Button(target.displayName) { model.selectedTarget = target }
                        }
                    } label: {
                        Text(model.selectedTarget?.displayName ?? L10n.s("Choose destination"))
                            .font(.callout)
                    }
                    .disabled(model.isDelivering || model.selection.isEmpty)
                    Spacer()
                    Button(model.selectedTarget?.handoffAction ?? L10n.s("Choose destination")) {
                        model.deliverSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canDeliver)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                if let target = model.selectedTarget {
                    Text(target.handoffDetail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if model.isDelivering { ProgressView().controlSize(.small) }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private func row(_ item: PocketItem, capture: Capture) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.toggle(item.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.selectedIDs.contains(item.id) ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(capture.selectedText ?? capture.extractedBody ?? capture.windowTitle ?? capture.appName)
                            .font(.system(size: 12)).lineLimit(2)
                        Text(capture.appName + " · " + (item.workName?.isEmpty == false ? item.workName! : item.intendedTarget?.displayName ?? L10n.s("Undecided")))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        if let note = item.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isDelivering)
            .accessibilityLabel(L10n.f("Select material from %@", capture.appName))
            Button { model.remove(item.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                .disabled(model.isDelivering)
                .help("Remove from pocket (capture stays in Inbox)")
        }
        .padding(10)
        .background(model.selectedIDs.contains(item.id) ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
