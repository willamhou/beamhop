import AppKit
import SwiftUI
import BeamhopCore

/// A transient corner shelf. Opening is deliberate; capture only updates the HUD count.
final class PocketWindowController {
    private(set) var panel: HandoffPanel?
    private var resignObserver: NSObjectProtocol?
    let model = PocketModel()
    var library: HopLibrary? { didSet { hopModel = library.map(HopPocketModel.init) } }
    private(set) var hopModel: HopPocketModel?
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
            if let library, let hopModel {
                content = AnyView(HopPocketView(library: library, model: hopModel, onClose: { [weak self] in self?.hide() },
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
        hopModel?.availableTargets = TargetDetector.availableTargets()
        if let panel, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.minY + 64))
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

private final class HopPocketViewState: ObservableObject {
    @Published var expandedID: String?
    @Published var confirmingHistoryDeletion = false
}

private final class PocketNativeButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}

/// Keep shelf commands as native controls: dependable accessibility and key equivalents
/// in a nonactivating NSPanel, including under the Command Line Tools SwiftUI runtime.
private struct PocketActionButton: NSViewRepresentable {
    let title: String
    var symbol: String? = nil
    let identifier: String
    var key: String = ""
    var bordered = false
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func invoke(_ sender: NSButton) { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = PocketNativeButton(title: title, target: context.coordinator, action: #selector(Coordinator.invoke(_:)))
        button.setAccessibilityElement(true)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        button.imagePosition = symbol == nil ? .noImage : .imageOnly
        button.isBordered = bordered; button.bezelStyle = .rounded; button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.keyEquivalent = key; button.keyEquivalentModifierMask = .command
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: max(symbol == nil ? 0 : 20, nsView.fittingSize.width), height: 22)
    }
}

struct HopPocketView: View {
    @ObservedObject var library: HopLibrary
    @ObservedObject var model: HopPocketModel
    let onClose: () -> Void
    let prepareChange: () -> Bool
    let onOpen: () -> Void
    @StateObject private var viewState = HopPocketViewState()

    private func perform(open: Bool = false, _ action: () throws -> Void) {
        guard !model.isDelivering, prepareChange() else { return }
        do { try action(); model.error = nil; if open { onOpen() } }
        catch { model.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Pocket", systemImage: "tray").font(.headline)
                Text("\(library.state.pocket.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                PocketActionButton(title: L10n.s("New draft"), symbol: "square.and.pencil", identifier: "pocket.new", key: "n") {
                    perform(open: true) { try library.start(HopDraft(materials: [], route: library.state.lastRoute)) }
                }.help("New draft").disabled(model.isDelivering)
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Close")
            }.buttonStyle(.plain)
            Picker("Pocket section", selection: $model.section) {
                Text("Drafts").tag(HopPocketModel.Section.drafts)
                Text("Handoff history").tag(HopPocketModel.Section.history)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("pocket.section")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search materials, instructions or projects", text: $model.query)
                    .textFieldStyle(.plain).font(.callout).accessibilityIdentifier("pocket.search").disabled(model.isDelivering)
            }.padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            if model.section == .drafts {
                drafts
            } else {
                history
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(12).frame(width: 380).background(.regularMaterial)
            .onChange(of: model.section) { _ in viewState.expandedID = nil; viewState.confirmingHistoryDeletion = false }
    }
    private var drafts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = library.state.active, active.hasContent {
                Button { perform(open: true) {} } label: {
                    HStack {
                        Image(systemName: "pencil.line")
                        Text("Continue current draft")
                        Text(title(active)).lineLimit(1).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }.font(.caption)
                }.buttonStyle(.plain).accessibilityIdentifier("pocket.resume")
            }
            if model.drafts.isEmpty {
                Text(L10n.s(model.query.isEmpty ? "Save a draft here, then select materials to hand off together." : "No matching drafts"))
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 64)
            } else {
                HStack {
                    PocketActionButton(title: model.selectedIDs == Set(model.drafts.map(\.id)) ? L10n.s("Deselect all") : L10n.s("Select all"),
                                       identifier: "pocket.select-all", key: "a") { model.selectAll() }
                    Spacer()
                    Text(L10n.f("%lld selected", Int64(model.selectedIDs.count))).foregroundStyle(.secondary)
                }.font(.caption).buttonStyle(.plain).disabled(model.isDelivering)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.drafts) { draft in draftRow(draft); Divider() }
                    }
                }.frame(height: min(CGFloat(model.drafts.count) * 58 + (viewState.expandedID == nil ? 0 : 110), 240))
            }
            if !(library.state.deletedDrafts ?? []).isEmpty {
                HStack {
                    Text("Drafts deleted").foregroundStyle(.secondary)
                    Spacer()
                    PocketActionButton(title: L10n.s("Undo delete"), identifier: "pocket.undo", key: "z") { perform { try library.undoDeleteDrafts() } }
                }.font(.caption)
            }
            if !model.selection.isEmpty { batchActions }
        }
    }
    private func draftRow(_ draft: HopDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PocketActionButton(title: L10n.f("Select draft: %@", title(draft)),
                                   symbol: model.selectedIDs.contains(draft.id) ? "checkmark.circle.fill" : "circle",
                                   identifier: "pocket.select.\(draft.id)") { model.toggle(draft.id) }
                Button { viewState.expandedID = viewState.expandedID == draft.id ? nil : draft.id } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title(draft)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(metadata(draft)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.accessibilityLabel(L10n.f("Preview draft: %@", title(draft)))
                PocketActionButton(title: L10n.s("Edit draft"), symbol: "pencil", identifier: "pocket.edit.\(draft.id)") {
                    perform(open: true) { try library.restore(draft.id) }
                }.help("Edit draft")
                Menu {
                    Button("Duplicate draft") { perform { try library.duplicate(draft) } }
                    Button("Add materials to current draft") { perform(open: true) { try library.addMaterials(from: draft) } }
                    Divider()
                    Button("Delete draft", role: .destructive) { perform { try library.deleteDrafts([draft.id]) } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Draft actions").accessibilityIdentifier("pocket.actions.\(draft.id)")
            }.buttonStyle(.plain).disabled(model.isDelivering || model.blockedDraftIDs.contains(draft.id) || library.inFlightIDs.contains(draft.id))
            if viewState.expandedID == draft.id {
                ScrollView { Text(draft.textFallback).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 100).padding(.leading, 24)
            }
        }.padding(.vertical, 9).padding(.horizontal, 4)
            .background(model.selectedIDs.contains(draft.id) ? Color.accentColor.opacity(0.06) : Color.clear)
    }
    private var batchActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if model.mixedRoutes && model.route == nil {
                Text("Different destinations. Choose where to hand off this selection.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(library.state.routes.indices, id: \.self) { index in
                        let route = library.state.routes[index]
                        if let target = route.target, model.availableTargets.contains(target) {
                            Button(routeLabel(route)) { model.chooseRoute(route) }
                        }
                    }
                    Divider()
                    ForEach(model.availableTargets, id: \.self) { target in
                        Button(target.displayName) { model.chooseRoute(HopRoute(target: target, project: model.mixedRoutes ? "" : model.selection.first?.route.project ?? "")) }
                    }
                } label: {
                    Text(model.route.map(routeLabel) ?? L10n.s("Choose destination")).lineLimit(1).truncationMode(.middle)
                }.menuStyle(.borderlessButton).accessibilityIdentifier("pocket.destination").disabled(model.isDelivering)
                Spacer(minLength: 0)
                PocketActionButton(title: L10n.s("Delete selected drafts"), symbol: "trash", identifier: "pocket.delete") {
                    perform { try model.deleteSelection() }
                }.help("Delete selected drafts").disabled(model.isDelivering || model.blockedSelection)
                PocketActionButton(title: batchActionLabel, identifier: "pocket.deliver", key: "\r", bordered: true) {
                    if prepareChange() { model.deliverSelection() }
                }.disabled(!model.canDeliver)
            }.font(.callout)
            if model.isDelivering { ProgressView().controlSize(.small) }
            if model.hasAttachments {
                Text("Attachments stay here. Edit a draft to copy text and add its files in the receiving app.").font(.caption2).foregroundStyle(.secondary)
            } else if let target = model.route?.target {
                Text(target.handoffDetail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.records.isEmpty {
                Text("No handoff records").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 64)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.records.prefix(model.historyLimit))) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                Button { viewState.expandedID = viewState.expandedID == record.id ? nil : record.id } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(title(record.draft)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Text(record.label).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.caption2)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if viewState.expandedID == record.id {
                                    Text(metadata(record.draft)).font(.caption2).foregroundStyle(.secondary)
                                    if let detail = record.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                    ScrollView { Text(record.draft.textFallback).font(.caption).textSelection(.enabled) }.frame(height: 90)
                                    HStack {
                                        Button("Restore backup") { perform(open: true) { try library.recover(record) } }
                                        Spacer()
                                        Button("Delete record", role: .destructive) { perform { try library.deleteRecords([record.id]) } }
                                    }.font(.caption).disabled(record.status == .preparing)
                                }
                            }.padding(.vertical, 9)
                            Divider()
                        }
                        if model.records.count > model.historyLimit {
                            Button("Show older records") { model.historyLimit += 20 }.font(.caption).padding(.vertical, 6)
                        }
                    }
                }.frame(height: min(CGFloat(min(model.records.count, model.historyLimit)) * 55 + (viewState.expandedID == nil ? 0 : 150), 290))
                if viewState.confirmingHistoryDeletion {
                    Text("Delete these handoff backups? Drafts and Inbox materials stay intact.").font(.caption)
                    HStack {
                        Button("Cancel") { viewState.confirmingHistoryDeletion = false }
                        Spacer()
                        Button("Delete records", role: .destructive) {
                            perform { try library.deleteRecords(Set(model.records.map(\.id))) }
                            viewState.confirmingHistoryDeletion = false
                        }
                    }.font(.caption)
                } else {
                    HStack {
                        Text(L10n.f("%lld records", Int64(model.records.count))).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear history…") { viewState.confirmingHistoryDeletion = true }
                    }.font(.caption)
                }
            }
        }
    }
    private func title(_ draft: HopDraft) -> String {
        if !draft.instruction.isEmpty { return draft.instruction }
        return draft.materials.first.map { $0.kind == .text ? $0.text : $0.name } ?? L10n.s("Empty draft")
    }
    private var batchActionLabel: String {
        let copies = model.route?.session == .newInApp || model.route?.target == .clipboard
            || model.route?.target == .cowork || model.route?.target == .claudeCode
        return L10n.f(copies ? "Copy (%lld)" : "Fill draft (%lld)", Int64(model.selection.count))
    }
    private func routeLabel(_ route: HopRoute) -> String {
        [route.project, route.target?.displayName ?? L10n.s("Keep on this Mac"), route.session == .newInApp ? L10n.s("New session · create in app") : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private func metadata(_ draft: HopDraft) -> String {
        let types = draft.materials.map { $0.kind == .text ? L10n.s("Text") : $0.name }.prefix(2).joined(separator: ", ")
        return routeLabel(draft.route) + " · " + L10n.f("Materials · %lld", Int64(draft.materials.count)) + " · " + types
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
