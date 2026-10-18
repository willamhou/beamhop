import SwiftUI
import BeamhopCore

/// Keyboard-first capture panel (Week 3 spec §2.1). Cursor lands in the note field on open;
/// ⌘1/2/3/0 pick the target, Enter delivers, Esc cancels (capture stays in the Inbox).
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：已抓取摘要 + 正文预览 + URL（只读，避开顶部拖拽区没有——panel 无标题栏拖拽问题）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                    Text("Captured  \(model.summaryLine)")
                        .font(.headline)
                        .lineLimit(1)
                }
                if let preview = model.previewText {
                    Text(preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = model.capture.url, let host = URL(string: url)?.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Divider()

            // 指令框：出现即 focus（验收 §2.2 第 1 条）
            TextField("Instruction (optional), e.g. summarize this…", text: $model.note)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($noteFocused)

            Divider()

            // 目标行：⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork / ⌘4 Kimi Work / ⌘0 仅入 Inbox
            // （键位映射唯一来源是 PanelShortcut，按钮与键盘路由不会漂移）
            VStack(alignment: .leading, spacing: 6) {
                Text("Deliver to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(PanelShortcut.allCases.filter { $0 != .inboxOnly }, id: \.self) { sc in
                        targetButton(sc)
                    }
                }
                inboxButton
            }

            HStack {
                Button("Esc cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("⏎ \(model.confirmLabel)") { model.confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear { noteFocused = true }
    }

    private func targetButton(_ sc: PanelShortcut) -> some View {
        let target = sc.target!   // 非 inboxOnly 的 shortcut 必有 target（PanelShortcut 测试约束）
        let selected = model.selectedTarget == target
        return Button {
            model.selectedTarget = target
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text("\(sc.badge) \(model.targetLabel(target))")
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(sc.rawValue)), modifiers: .command)
    }

    private var inboxButton: some View {
        let selected = model.selectedTarget == nil
        return Button {
            model.selectedTarget = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text("\(PanelShortcut.inboxOnly.badge) Inbox only")
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(PanelShortcut.inboxOnly.rawValue)), modifiers: .command)
    }
}
