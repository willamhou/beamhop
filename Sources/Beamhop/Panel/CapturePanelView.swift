import SwiftUI
import BeamhopCore

/// Keyboard-first capture panel (Week 3 spec §2.1), slimmed 2026-10-19 after dogfood
/// feedback: one glance = source + preview, one row of inputs (instruction + work name),
/// one row of REAL destinations (filtered by TargetDetector — no fake choices), Enter /
/// Esc / ⌘5 先留着. Cursor lands in the note field on open.
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部：已抓取摘要（一行）+ 正文预览 + URL（只读）
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                    Text("Captured  \(model.summaryLine)")
                        .font(.headline)
                        .lineLimit(1)
                }
                if let preview = model.previewText {
                    HStack(spacing: 4) {
                        Text(preview)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = model.capture.url, let host = URL(string: url)?.host {
                            Text("· \(host)")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let url = model.capture.url, let host = URL(string: url)?.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Divider()

            // 输入行：指令（主）+ 工作名（次，essay 02）并排，省掉一个大字段的高度
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Instruction (optional), e.g. summarize this…", text: $model.note)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($noteFocused)
                TextField("Work name…", text: $model.workName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 140)
            }

            // 两层去处（essay 02）：一行小字，换绑未确认时警示色；未绑定工作则不占空间
            if model.boundWork != nil {
                destinationLine
            }

            Divider()

            // 目标行：只渲染这台机器上真实存在的去处（AppServices 注入 visibleTargets）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    // 按键位序渲染（⌘1→⌘4），可用性只决定"显不显示"
                    ForEach(PanelShortcut.allCases.filter { sc in
                        sc.target != nil && model.visibleTargets.contains(sc.target!)
                    }, id: \.self) { sc in
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
        .padding(14)
        .frame(width: 460)
        .onAppear { noteFocused = true }
    }

    /// Essay 02 的两层去处：一行小字「工作名 ⇢ 接收会话」，换绑未确认时警示色。
    private var destinationLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.destinationTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(gateActive ? Color.orange : .secondary)
            if let subtitle = model.destinationSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(gateActive ? Color.orange : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private var gateActive: Bool { model.receiverChanged && !model.rebindAcknowledged }

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
