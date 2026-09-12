import SwiftUI

struct CapturePanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.currentDraft != nil {
            CapturePanelContent(
                draft: Binding(
                    get: { model.currentDraft! },
                    set: { model.currentDraft = $0 }
                )
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CapturePanelContent: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: CaptureDraft
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourcePreview
                    noteEditor
                    targetPicker
                    options
                    if let message = draft.inlineMessage {
                        Label(message, systemImage: draft.isDelivering ? "clock" : "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(draft.isDelivering ? Color.secondary : Color.orange)
                            .textSelection(.enabled)
                    }
                }
                .padding(22)
            }

            Divider()
            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(width: 620, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { noteFocused = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已抓取")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(draft.capture.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(draft.capture.appName)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var sourcePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(draft.capture.previewText)
                .font(.body)
                .lineLimit(4)
                .textSelection(.enabled)
            if let url = draft.capture.url {
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("\(draft.capture.provenance.captureMethod.rawValue) · \(draft.capture.provenance.captureDurationMilliseconds ?? 0)ms · \(draft.capture.id)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("抓取预览")
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("备注（可选）")
                .font(.callout.weight(.medium))
            TextEditor(text: $draft.note)
                .font(.body)
                .focused($noteFocused)
                .frame(minHeight: 62, maxHeight: 82)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityLabel("备注")
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("投递到")
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                ForEach(AppDeliveryTarget.allCases) { target in
                    Button {
                        draft.target = target
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: draft.target == target ? "circle.inset.filled" : "circle")
                            Text(target.title)
                            Text("⌘\(target.shortcutNumber)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(draft.target == target ? .accentColor : nil)
                    .keyboardShortcut(
                        KeyEquivalent(Character(target.shortcutNumber)),
                        modifiers: .command
                    )
                    .accessibilityValue(draft.target == target ? "已选择" : "未选择")
                }
            }
        }
    }

    private var options: some View {
        HStack(spacing: 24) {
            Toggle("附带截图", isOn: $draft.includeScreenshot)
                .help("仅在投递时按需截图；需要屏幕录制权限")
            Toggle("投递后按回车", isOn: $draft.autoSubmit)
                .help("ChatGPT 默认建议关闭，先人工确认内容")
                .disabled(draft.target == .claudeCode || draft.target == .inboxOnly)
            Spacer()
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            Button("取消") { model.cancelCurrentDraft() }
                .keyboardShortcut(.cancelAction)
            Text("Capture 已保存在 Inbox")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(draft.target == .inboxOnly ? "完成" : "投递到 \(draft.target.title)") {
                model.deliverCurrentDraft()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(draft.isDelivering)
        }
    }
}
