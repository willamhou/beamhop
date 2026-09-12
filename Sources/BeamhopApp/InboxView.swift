import BeamhopCore
import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            Group {
                if model.captures.isEmpty {
                    ContentUnavailableView {
                        Label("Inbox 为空", systemImage: "tray")
                    } description: {
                        Text("按 ⌘⇧Space 抓取当前 App。每次抓取都会先安全保存到本机。")
                    } actions: {
                        Button("抓取当前 App") { model.captureAndShow() }
                    }
                } else {
                    List(model.captures, selection: $model.selectedCaptureID) { capture in
                        CaptureRow(
                            capture: capture,
                            delivery: model.latestDelivery(for: capture.id)
                        )
                        .tag(capture.id)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Inbox")
            .searchable(text: $model.searchQuery, prompt: "搜索标题、正文、备注")
            .onSubmit(of: .search) { model.runSearch() }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.captureAndShow()
                    } label: {
                        Label("新建 Capture", systemImage: "plus")
                    }
                    Button {
                        model.softDeleteSelectedCapture()
                    } label: {
                        Label("移到最近删除", systemImage: "trash")
                    }
                    .disabled(model.selectedCaptureID == nil)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
            .navigationSplitViewColumnWidth(min: 330, ideal: 390)
        } detail: {
            if let capture = model.selectedCapture {
                CaptureDetailView(
                    capture: capture,
                    deliveries: model.deliveriesByCaptureID[capture.id] ?? []
                )
            } else {
                ContentUnavailableView("选择一条 Capture", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .task { await model.refreshInbox() }
    }
}

private struct CaptureRow: View {
    let capture: CaptureRecord
    let delivery: DeliveryRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(capture.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(capture.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(capture.appName)
                if let host = capture.url?.host {
                    Text("·")
                    Text(host)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let delivery {
                Label(
                    delivery.status == .success
                        ? "已投 \(delivery.target.displayTitle)"
                        : "投递失败，点击查看原因",
                    systemImage: delivery.status == .success ? "checkmark.circle" : "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(delivery.status == .success ? Color.green : Color.orange)
            } else {
                Text("未投递")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct CaptureDetailView: View {
    @EnvironmentObject private var model: AppModel
    let capture: CaptureRecord
    let deliveries: [DeliveryRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(capture.displayTitle)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(capture.appName)
                        Text(capture.createdAt.formatted(date: .abbreviated, time: .standard))
                        Text(capture.provenance.captureMethod.rawValue)
                    }
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                }

                if let url = capture.url {
                    Link(url.absoluteString, destination: url)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("内容")
                        .font(.headline)
                    Text(capture.previewText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Provenance")
                        .font(.headline)
                    ProvenanceLine(label: "Capture ID", value: capture.id)
                    ProvenanceLine(label: "Bundle", value: capture.appBundleID)
                    ProvenanceLine(label: "PID", value: String(capture.provenance.processID))
                    ProvenanceLine(label: "Source version", value: capture.provenance.appVersion ?? "unknown")
                    ProvenanceLine(label: "macOS", value: capture.provenance.operatingSystemVersion)
                    ProvenanceLine(label: "Beamhop", value: capture.provenance.beamhopVersion)
                    ProvenanceLine(label: "Duration", value: "\(capture.provenance.captureDurationMilliseconds ?? 0)ms")
                    if let path = capture.provenance.accessibilityTreeSnapshot {
                        DisclosureGroup("AX path snapshot") {
                            Text(path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                }

                if !deliveries.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("投递记录")
                            .font(.headline)
                        ForEach(deliveries) { delivery in
                            DeliveryHistoryRow(delivery: delivery)
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Claude Code") { model.redeliver(capture, to: .claudeCode) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("ChatGPT") { model.redeliver(capture, to: .chatGPTDesktop) }
                    .keyboardShortcut("3", modifiers: .command)
                Spacer()
                Button("Compatibility") { model.windows.showCompatibility() }
            }
            .padding(14)
            .background(.bar)
        }
    }
}

private struct ProvenanceLine: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct DeliveryHistoryRow: View {
    let delivery: DeliveryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    delivery.target.displayTitle,
                    systemImage: delivery.status == .success ? "checkmark.circle" : "exclamationmark.circle"
                )
                .foregroundStyle(delivery.status == .success ? Color.green : Color.orange)
                Spacer()
                Text(delivery.deliveredAt, style: .relative)
                    .foregroundStyle(.secondary)
            }
            if let error = delivery.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension BeamhopCore.DeliveryTarget {
    var displayTitle: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeCowork: "Claude Cowork"
        case .chatGPTDesktop: "ChatGPT"
        case .clipboard: "Clipboard"
        }
    }
}
