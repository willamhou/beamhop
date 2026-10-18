import AppKit
import SwiftUI
import BeamhopCore

/// Inbox window (spec §9.2): every capture lands here; searchable (dual FTS5), inspectable
/// (full provenance), re-deliverable. Skeleton port of the Week 3 UI onto the Mac-version
/// services — list + search + detail + failure reasons are the non-negotiable core (§12.4).
/// Not @MainActor-annotated: AppServices wires this from nonisolated bootstrap code; every
/// call site (window show / search / toolbar) runs on the main thread in practice.
final class InboxModel: ObservableObject {
    @Published var captures: [Capture] = []
    @Published var deliveries: [String: [Delivery]] = [:]
    @Published var selectedID: String?
    @Published var searchQuery = ""

    var selected: Capture? { captures.first { $0.id == selectedID } }

    private var store: CaptureStore?
    private var onDeliver: ((Capture, DeliveryTarget) -> Void)?

    func configure(store: CaptureStore, onDeliver: @escaping (Capture, DeliveryTarget) -> Void) {
        self.store = store
        self.onDeliver = onDeliver
    }

    func reload() {
        guard let store else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = query.isEmpty ? try? store.recent(limit: 200) : try? store.search(query)
        captures = result ?? []
        if selectedID != nil, !captures.contains(where: { $0.id == selectedID }) { selectedID = nil }
        loadDeliveries()
    }

    func runSearch() { reload() }

    func deliver(_ capture: Capture, to target: DeliveryTarget) {
        onDeliver?(capture, target)
        // delivery runs off-main (AX activation sleeps); pick up the recorded row shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.reload() }
    }

    func softDelete(_ capture: Capture) {
        guard let store else { return }
        try? store.softDelete(id: capture.id)
        if selectedID == capture.id { selectedID = nil }
        reload()
    }

    private func loadDeliveries() {
        guard let store else { return }
        var map: [String: [Delivery]] = [:]
        for c in captures.prefix(50) {
            if let ds = try? store.deliveries(captureID: c.id), !ds.isEmpty { map[c.id] = ds }
        }
        deliveries = map
    }
}

/// Window follows the Diagnostics pattern: created once, hidden not destroyed (S5), content
/// refreshed on each show.
final class InboxWindowController {
    private var window: NSWindow?
    let model = InboxModel()

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Beamhop Inbox"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.reload()
        window?.contentView = NSHostingView(rootView: InboxView(model: model))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct InboxView: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        NavigationSplitView {
            Group {
                if model.captures.isEmpty {
                    ContentUnavailableView {
                        Label("Inbox is empty", systemImage: "tray")
                    } description: {
                        Text(model.searchQuery.isEmpty ? "Press ⌘⇧Space to capture the frontmost app. Every capture is saved locally first."
                                                       : "No results for \"\(model.searchQuery)\"")
                    }
                } else {
                    List(model.captures, selection: $model.selectedID) { capture in
                        CaptureRow(capture: capture, latest: model.deliveries[capture.id]?.first)
                            .tag(capture.id)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Inbox")
            .searchable(text: $model.searchQuery, prompt: "Search title, body, notes")
            .onSubmit(of: .search) { model.runSearch() }
            .onChange(of: model.searchQuery) { _, q in
                if q.isEmpty { model.reload() }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button {
                        if let c = model.selected { model.softDelete(c) }
                    } label: {
                        Label("Move to Recently Deleted", systemImage: "trash")
                    }
                    .disabled(model.selectedID == nil)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            if let capture = model.selected {
                CaptureDetail(model: model, capture: capture)
            } else {
                ContentUnavailableView("Select a capture", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

private struct CaptureRow: View {
    let capture: Capture
    let latest: Delivery?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(capture.windowTitle ?? capture.appName)
                    .font(.body.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                Text(Date(timeIntervalSince1970: Double(capture.createdAt) / 1000),
                     format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(capture.appName)
                if let url = capture.url, let host = URL(string: url)?.host { Text("· \(host)") }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)

            if let latest {
                Label(latest.status == .success
                      ? "Delivered \(latest.target.rawValue)"
                      : "Delivery failed: \(latest.errorMessage ?? "unknown reason")",
                      systemImage: latest.status == .success ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(latest.status == .success ? Color.green : Color.orange)
            } else {
                Text("Not delivered").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CaptureDetail: View {
    @ObservedObject var model: InboxModel
    let capture: Capture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // actions first: re-deliver from Inbox (spec §9.2 right-rail)
                HStack {
                    Button("Deliver to Claude Code") { model.deliver(capture, to: .claudeCode) }
                    Button("Deliver to ChatGPT") { model.deliver(capture, to: .chatgptDesktop) }
                    Button("Deliver to Kimi") { model.deliver(capture, to: .kimiWork) }
                    Button("Copy to clipboard") { model.deliver(capture, to: .clipboard) }
                    Spacer()
                    Text(capture.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }

                section("Source") {
                    kv("App", "\(capture.appName) (\(capture.appBundleID))")
                    kv("Window title", capture.windowTitle)
                    kv("URL", capture.url)
                    kv("Captured at", Date(timeIntervalSince1970: Double(capture.createdAt) / 1000)
                        .formatted(.dateTime))
                    if let note = capture.userNote, !note.isEmpty { kv("Instruction", note) }
                }

                section("Provenance (where it came from)") {
                    kv("Capture channel", capture.captureMethod)
                    kv("Duration", capture.captureDurationMs.map { "\($0) ms" })
                    kv("Source app version", capture.appVersion)
                    kv("macOS", capture.osVersion)
                    kv("Beamhop", capture.beamhopVersion)
                    kv("AX snapshot", capture.axTreeSnapshot == nil ? "none" : "saved")
                    if capture.truncated { kv("Truncated", "yes (overlong body truncated; original in this database)") }
                }

                if let sel = capture.selectedText, !sel.isEmpty {
                    section("Selected text") { Text(sel).font(.callout).textSelection(.enabled) }
                }
                if let body = capture.extractedBody, !body.isEmpty {
                    section("Body (first 2000 chars)") {
                        Text(String(body.prefix(2000)))
                            .font(.callout.monospaced()).textSelection(.enabled)
                    }
                }

                let history = model.deliveries[capture.id] ?? []
                if !history.isEmpty {
                    section("Delivery history") {
                        ForEach(history) { d in
                            HStack(alignment: .top) {
                                Image(systemName: d.status == .success
                                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(d.status == .success ? Color.green : Color.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(d.target.rawValue) · \(d.status.rawValue)")
                                        .font(.callout)
                                    if let err = d.errorMessage {
                                        Text(err).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Date(timeIntervalSince1970: Double(d.deliveredAt) / 1000),
                                     format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
            Divider()
        }
    }

    private func kv(_ k: String, _ v: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(v ?? "—").font(.callout).textSelection(.enabled)
        }
    }
}
