import AppKit
import SwiftUI
import BeamhopCore

struct HandoffResultsView: View {
    @ObservedObject var model: HandoffResultsModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                if model.results.isEmpty {
                    ContentUnavailableView("No handoff conclusions yet", systemImage: "arrow.uturn.backward.circle",
                        description: Text("Enable optional conclusion return before a Hop. The receiving agent needs Beamhop MCP and must choose to write back."))
                } else {
                    List(model.results, selection: $model.selectedID) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.content).lineLimit(2)
                            Text(result.agent).font(.caption).foregroundStyle(.secondary)
                            Text(result.handoffID).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }.tag(result.id)
                    }.listStyle(.inset).accessibilityIdentifier("inbox.handoff-results")
                }
                if model.hasMore { Button("Load earlier conclusions") { model.loadMore() }.padding() }
                if let error = model.error { Text(error).foregroundStyle(.orange).padding() }
            }
            .toolbar { Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if let result = model.selectedResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HandoffConclusionCard(result: result)
                        Text(L10n.f("Handoff ID: %@", result.handoffID)).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Agent-reported conclusion · not verified task completion").font(.caption).foregroundStyle(.secondary)
                        if let record = model.selectedRecord {
                            Text(record.label).font(.callout).foregroundStyle(.secondary)
                            if let detail = record.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            Divider()
                            Text("Frozen handoff copy").font(.headline)
                            Text(record.textFallback).font(.callout).textSelection(.enabled)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a handoff conclusion", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}

private final class HandoffConclusionDisplay: ObservableObject {
    @Published var expanded = false
}

struct HandoffConclusionsList: View {
    @ObservedObject var model: HandoffResultsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent-reported conclusion · not verified task completion").font(.caption2).foregroundStyle(.secondary)
            if model.results.isEmpty && model.error == nil {
                Text("No handoff conclusions yet").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.results) { HandoffConclusionCard(result: $0) }
            if model.hasMore { Button("Load earlier conclusions") { model.loadMore() } }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct HandoffConclusionCard: View {
    let result: HandoffResult
    @StateObject private var display = HandoffConclusionDisplay()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(result.agent, systemImage: "arrow.uturn.backward.circle").font(.callout.weight(.semibold))
                Spacer()
                Text(Date(timeIntervalSince1970: Double(result.createdAt) / 1000), format: .dateTime)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let session = result.sessionID, !session.isEmpty {
                Text(L10n.f("Session: %@", session)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(display.expanded ? result.content : String(result.content.prefix(500)))
                .font(.callout).textSelection(.enabled)
            if result.content.count > 500 {
                Button(L10n.s(display.expanded ? "Show less" : "Show full conclusion")) { display.expanded.toggle() }
                    .font(.caption)
            }
        }
    }
}
