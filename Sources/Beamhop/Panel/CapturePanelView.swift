import SwiftUI
import BeamhopCore

/// Keyboard-first capture panel (Week 3 spec §2.1). Cursor lands in the note field on open;
/// ⌘1/2/3/4 pick the target, Enter delivers, Esc cancels (capture stays in the Inbox),
/// ⌘5 「先留着」parks it in the pocket (essay 01), ⌘0 saves to Inbox only.
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

            // 工作名（可选，essay 02）：给这个去处起个名字，下次认出这件工作
            TextField("Work name (optional), e.g. 让发送不打断阅读", text: $model.workName)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.boundWork != nil {
                destinationCard
            }

            Divider()

            // 目标行：⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork / ⌘4 Kimi Work / ⌘5 先留着 / ⌘0 仅入 Inbox
            // （键位映射唯一来源是 PanelShortcut，按钮与键盘路由不会漂移）
            VStack(alignment: .leading, spacing: 6) {
                Text("Deliver to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(PanelShortcut.allCases.filter { $0.target != nil }, id: \.self) { sc in
                        targetButton(sc)
                    }
                }
                HStack(spacing: 10) {
                    holdButton
                    inboxButton
                }
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

    /// Essay 02 的两层去处卡：上面是人认得的工作名，下面是当前接收会话；
    /// 换绑未确认时副标题用警示色提示「接收会话已更换」。
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(model.destinationTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            if let subtitle = model.destinationSubtitle {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(model.workNeedsConfirmation && !model.rebindAcknowledged
                                         ? Color.orange : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(model.workNeedsConfirmation && !model.rebindAcknowledged
                                         ? Color.orange : .secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 20)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func targetButton(_ sc: PanelShortcut) -> some View {
        let target = sc.target!   // 过滤后必有 target（PanelShortcut 测试约束）
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

    /// 「先留着」(⌘5, essay 01)：不进 Inbox-only 也不投递，放入口袋；只有暂存材料存在时
    /// 口袋界面才需要出现 —— 默认形态仍是原地路由。
    private var holdButton: some View {
        Button {
            model.hold()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(PanelShortcut.hold.badge) 先留着")
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.canHold)
        .keyboardShortcut(KeyEquivalent(Character(PanelShortcut.hold.rawValue)), modifiers: .command)
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
