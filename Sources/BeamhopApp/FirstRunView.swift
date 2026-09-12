import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    @State private var includeDemo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Beamhop")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("抓取当前工作上下文，先保存到本地 Inbox，再由你决定投给哪个 agent。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 26)

            Divider()

            VStack(spacing: 0) {
                OnboardingPermissionRow(
                    index: "1",
                    title: "Accessibility",
                    detail: "必需：读取前台 App 的标题与选中文本，并执行 clipboard-safe paste。",
                    ready: model.diagnostics.accessibilityGranted,
                    actionTitle: model.diagnostics.accessibilityGranted ? "已开启" : "开启"
                ) {
                    model.diagnostics.requestAccessibility()
                }
                Divider()
                OnboardingPermissionRow(
                    index: "2",
                    title: "Screen Recording",
                    detail: "可选：只有勾选“附带截图”时使用。现在可跳过。",
                    ready: model.diagnostics.screenRecordingGranted,
                    actionTitle: model.diagnostics.screenRecordingGranted ? "已开启" : "可选开启"
                ) {
                    model.diagnostics.requestScreenRecording()
                }
                Divider()
                OnboardingPermissionRow(
                    index: "3",
                    title: "浏览器与 Agent",
                    detail: "均可稍后连接。仅用 AX + 本地 Inbox 已经可以开始。",
                    ready: false,
                    actionTitle: "查看诊断"
                ) {
                    model.windows.showDiagnostics()
                }
            }
            .padding(.vertical, 10)

            Spacer()

            Toggle("加入一条演示 Capture，先体验浮窗与 Inbox", isOn: $includeDemo)
                .toggleStyle(.checkbox)
                .padding(.bottom, 16)

            HStack {
                Button("跳过设置") {
                    model.completeOnboarding()
                }
                Spacer()
                Text("⌘⇧Space 随时抓取")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Button("开始使用") {
                    model.completeOnboarding()
                    if includeDemo { model.showDemoCapture() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(34)
        .frame(width: 690, height: 590)
        .task { await model.diagnostics.refresh() }
    }
}

private struct OnboardingPermissionRow: View {
    let index: String
    let title: String
    let detail: String
    let ready: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(index)
                .font(.title3.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    if ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("已开启")
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button(actionTitle, action: action)
                .disabled(ready)
                .frame(minWidth: 88)
        }
        .padding(.vertical, 15)
    }
}
