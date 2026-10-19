import AppKit
import SwiftUI
import BeamhopCore

/// Pocket window — the 「先留着」 hold stack made visible (product essay 01/02).
/// The pocket only accumulates what the user CHOSE to hold; it shows the stack in hold
/// order (组合本身在表达"这几段需要一起理解"), each item with its note and intended
/// destination, and hands the whole stack over in one ordered batch.
/// Like Inbox/Diagnostics: created once, hidden not destroyed (S5), refreshed on each show.
final class PocketModel: ObservableObject {
    @Published var items: [(PocketItem, Capture)] = []

    private var store: PocketStore?
    private var onDeliverBatch: (([(PocketItem, Capture)]) -> Void)?
    /// Fired after every reload with the live count — drives the bottom-right HUD.
    private var onCountChange: ((Int) -> Void)?

    func configure(store: PocketStore,
                   onDeliverBatch: @escaping ([(PocketItem, Capture)]) -> Void,
                   onCountChange: ((Int) -> Void)? = nil) {
        self.store = store
        self.onDeliverBatch = onDeliverBatch
        self.onCountChange = onCountChange
    }

    func reload() {
        items = (try? store?.liveStack()) ?? []
        onCountChange?(items.count)
    }

    var count: Int { items.count }

    func remove(_ pair: (PocketItem, Capture)) {
        try? store?.remove(id: pair.0.id)
        reload()
    }

    /// 整批按序送出：次序就是交代的一部分，不做重排。
    func deliverAll() {
        guard !items.isEmpty else { return }
        onDeliverBatch?(items)
        items = []
    }
}

final class PocketWindowController {
    private var window: NSWindow?
    let model = PocketModel()

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Beamhop Pocket"
            w.isReleasedWhenClosed = false
            window = w
        }
        model.reload()
        window?.contentView = NSHostingView(rootView: PocketView(model: model))
        // bottom-right, next to the HUD chip — the pocket lives in that corner now
        if let window, let sf = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: sf.maxX - size.width - 16,
                                          y: sf.minY + 16))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PocketView: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Pocket is empty", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("在投递面板按 ⌘5「先留着」，材料会带着出处、交代和打算给的去处暂存在这里。")
                }
            } else {
                List(Array(model.items.enumerated()), id: \.element.0.id) { idx, pair in
                    PocketRow(index: idx + 1, item: pair.0, capture: pair.1) {
                        model.remove(pair)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .toolbar {
            ToolbarItemGroup {
                Text("\(model.count) held")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.deliverAll()
                } label: {
                    Label("Send all in order", systemImage: "paperplane")
                }
                .disabled(model.items.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

/// Human-readable receiver label for pocket rows (same vocabulary as the capture panel).
private func pocketTargetLabel(_ target: DeliveryTarget) -> String {
    switch target {
    case .claudeCode: return L10n.s("Claude Code")
    case .chatgptDesktop: return L10n.s("ChatGPT")
    case .cowork: return L10n.s("Cowork → clipboard")
    case .clipboard: return L10n.s("Clipboard")
    case .kimiWork: return L10n.s("Kimi Work")
    }
}

private struct PocketRow: View {
    let index: Int
    let item: PocketItem
    let capture: Capture
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(capture.windowTitle ?? capture.appName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let target = item.intendedTarget {
                        Text(pocketTargetLabel(target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    } else {
                        Text("未决定去处在收件时选择")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                let body = capture.selectedText ?? capture.extractedBody
                if let body, !body.isEmpty {
                    Text(String(body.prefix(160)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    Text(capture.appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = capture.url, let host = URL(string: url)?.host {
                        Text("· \(host)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("· \(Date(timeIntervalSince1970: Double(capture.createdAt) / 1000), format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let note = item.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.blue)
                            .lineLimit(2)
                    }
                }
            }
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from pocket (capture stays in Inbox)")
        }
        .padding(.vertical, 4)
    }
}
