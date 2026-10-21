import AppKit
import SwiftUI
import BeamhopCore

/// A transient corner shelf. Opening is deliberate; capture only updates the HUD count.
final class PocketWindowController {
    private(set) var panel: HandoffPanel?
    private var resignObserver: NSObjectProtocol?
    let model = PocketModel()
    var library: HopLibrary?
    var onOpenDraft: (() -> Void)?
    var onPrepareChange: (() -> Bool)?

    func show() {
        if panel?.isVisible == true { hide(); return }
        if panel == nil {
            let p = HandoffPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
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
            p.onEscape = { [weak self] in self?.hide() }
            let content: AnyView
            if let library {
                content = AnyView(HopPocketView(library: library, onClose: { [weak self] in self?.hide() },
                    prepareChange: { [weak self] in self?.onPrepareChange?() ?? true },
                    onOpen: { [weak self] in self?.onOpenDraft?() }))
            } else {
                content = AnyView(PocketView(model: model, onClose: { [weak self] in self?.hide() }))
            }
            p.contentView = NSHostingView(rootView: content
                .fixedSize(horizontal: false, vertical: true)
                .modifier(PanelSizeReader { [weak p] size in
                    DispatchQueue.main.async { p?.fitContent(size, keepingBottom: true) }
                }))
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

struct HopPocketView: View {
    @ObservedObject var library: HopLibrary
    let onClose: () -> Void
    let prepareChange: () -> Bool
    let onOpen: () -> Void
    @State private var error: String?

    private func perform(_ action: () throws -> Void) {
        guard prepareChange() else { return }
        do { try action(); error = nil; onOpen() }
        catch { self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pocket", systemImage: "tray").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let active = library.state.active, active.hasContent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current draft").font(.caption).foregroundStyle(.secondary)
                            summary(active)
                            Button("Resume editing") { perform {} }
                        }
                        Divider()
                    }
                    if library.state.pocket.isEmpty {
                        Text("Save materials, instructions and destination together with Save to Pocket.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(library.state.pocket) { draft in
                        VStack(alignment: .leading, spacing: 6) {
                            summary(draft)
                            HStack {
                                Button(library.state.active?.hasContent == true ? L10n.s("Save current and restore") : L10n.s("Restore to panel")) {
                                    perform { try library.restore(draft.id) }
                                }
                                Button("Add materials only") { perform { try library.addMaterials(from: draft) } }
                            }.font(.caption)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !library.state.records.isEmpty {
                        Text("Recent handoffs · backups retained").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(library.state.records.reversed()) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.label).font(.callout)
                            summary(record.draft)
                            if let detail = record.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            DisclosureGroup("View handoff content") {
                                Text(record.draft.textFallback).font(.caption).textSelection(.enabled)
                            }.font(.caption)
                            Button(library.state.active?.hasContent == true ? L10n.s("Save current and restore backup") : L10n.s("Restore backup")) {
                                perform { try library.recover(record) }
                            }.font(.caption)
                            Text("Restores the Beamhop copy. Later edits in the receiving app are not synchronized.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.padding(10).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(maxHeight: 380)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(16).frame(width: 390).background(.regularMaterial)
    }
    private func summary(_ draft: HopDraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text([draft.route.project, draft.route.target?.displayName ?? L10n.s("Inbox"), draft.route.sessionLabel]
                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            Text(draft.instruction.isEmpty ? draft.materials.map { $0.kind == .text ? $0.text : $0.name }.joined(separator: " · ") : draft.instruction)
                .font(.system(size: 12)).lineLimit(2)
            Text(L10n.f("Materials · %lld", Int64(draft.materials.count))).font(.caption2).foregroundStyle(.secondary)
        }
    }
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
