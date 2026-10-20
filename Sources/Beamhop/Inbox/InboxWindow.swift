import AppKit
import SwiftUI
import BeamhopCore

/// Window follows the Diagnostics pattern: created once, hidden not destroyed (S5), content
/// refreshed on each show and when it regains focus after an agent writes via MCP.
final class InboxWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var refreshTimer: Timer?
    let model = InboxModel()

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Beamhop Inbox"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        model.logOpened()
        model.reload()
        window?.contentView = NSHostingView(rootView: InboxView(model: model))
        // Opening the Inbox is an explicit application switch. A nonactivating capture
        // panel can make NSApp appear active while another process remains foreground.
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.model.refreshSelectedDetails()
        }
    }

    func windowDidResignKey(_ notification: Notification) { stopRefreshing() }
    func windowWillClose(_ notification: Notification) { stopRefreshing() }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit { refreshTimer?.invalidate() }
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
                        CaptureRow(capture: capture, latest: model.deliveries[capture.id]?.first,
                                   resultCount: model.resultCounts[capture.id] ?? 0)
                            .tag(capture.id)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Inbox")
            .safeAreaInset(edge: .bottom) {
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange).padding()
                }
            }
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
    let resultCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(capture.windowTitle ?? capture.appName)
                    .font(.body.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                if resultCount > 0 {
                    Label("\(resultCount)", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption).foregroundStyle(.blue)
                        .accessibilityLabel(Text(L10n.f("%d agent conclusions", resultCount)))
                }
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
                Label("\(latest.status.displayName) · \(latest.target.displayName)",
                      systemImage: latest.status.isSuccessful ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(latest.status.isSuccessful ? Color.green : Color.orange)
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

                if let error = model.detailErrorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                let history = TimelineBuilder.entries(
                    deliveries: model.deliveries[capture.id] ?? [], results: model.selectedResults)
                if !history.isEmpty {
                    section(L10n.s("Delivery and agent conclusions")) {
                        ForEach(history, id: \.stableID) { entry in
                            switch entry {
                            case .delivery(let d):
                                HStack(alignment: .top) {
                                    Image(systemName: d.status.isSuccessful
                                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(d.status.isSuccessful ? Color.green : Color.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(d.target.displayName) · \(d.status.displayName)")
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
                            case .result(let result):
                                AgentConclusionView(result: result)
                            }
                        }
                        if model.hasMoreResults {
                            Button("Load earlier conclusions") { model.loadMoreResults() }
                        }
                    }
                } else if model.detailErrorMessage == nil {
                    section(L10n.s("Delivery and agent conclusions")) {
                        Text("No deliveries or agent conclusions yet.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
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

private final class ConclusionExpansion: ObservableObject {
    @Published var expanded = false
}

private struct AgentConclusionView: View {
    let result: CaptureResult
    @StateObject private var expansion = ConclusionExpansion()

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.agent).font(.callout.weight(.semibold))
                    Spacer()
                    Text(Date(timeIntervalSince1970: Double(result.createdAt) / 1000),
                         format: .dateTime).font(.caption).foregroundStyle(.secondary)
                }
                if let session = result.sessionID, !session.isEmpty {
                    Text(L10n.f("Session: %@", session))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(expansion.expanded ? result.content : String(result.content.prefix(500)))
                    .font(.callout).textSelection(.enabled)
                if result.content.count > 500 {
                    Button(L10n.s(expansion.expanded ? "Show less" : "Show full conclusion")) { expansion.expanded.toggle() }
                        .buttonStyle(.link)
                }
            }
        }
    }
}
