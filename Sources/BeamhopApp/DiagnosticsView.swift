import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permission Diagnostics")
                        .font(.largeTitle.weight(.semibold))
                    Text("这里回答“为什么不工作”，并给出可执行的修复动作。")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    PermissionRow(
                        title: "Accessibility",
                        detail: model.diagnostics.accessibilityGranted
                            ? "已允许读取前台应用的轻量元数据，并执行安全粘贴。"
                            : "抓取选中文本和自动粘贴需要此权限。",
                        state: model.diagnostics.accessibilityGranted ? .ready : .needsAction,
                        actionTitle: model.diagnostics.accessibilityGranted ? "打开设置" : "请求权限"
                    ) {
                        if model.diagnostics.accessibilityGranted {
                            model.diagnostics.openAccessibilitySettings()
                        } else {
                            model.diagnostics.requestAccessibility()
                        }
                    }
                    Divider()
                    PermissionRow(
                        title: "Screen Recording（可选）",
                        detail: model.diagnostics.screenRecordingGranted
                            ? "按需截图可用；Beamhop 不会在后台自动截图。"
                            : "仅“附带截图”需要，可跳过。",
                        state: model.diagnostics.screenRecordingGranted ? .ready : .warning,
                        actionTitle: model.diagnostics.screenRecordingGranted ? "打开设置" : "请求权限"
                    ) {
                        if model.diagnostics.screenRecordingGranted {
                            model.diagnostics.openScreenRecordingSettings()
                        } else {
                            model.diagnostics.requestScreenRecording()
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !model.diagnostics.integrations.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("集成")
                            .font(.headline)
                            .padding(.bottom, 8)
                        ForEach(Array(model.diagnostics.integrations.enumerated()), id: \.element.id) { index, item in
                            PermissionRow(
                                title: item.title,
                                detail: item.detail,
                                state: item.state,
                                actionTitle: item.recoveryTitle
                            ) {
                                Task { await model.diagnostics.performRecovery(for: item) }
                            }
                            if index < model.diagnostics.integrations.count - 1 { Divider() }
                        }
                    }
                }

                HStack {
                    Button("Compatibility Matrix") { model.windows.showCompatibility() }
                    Spacer()
                    if let checked = model.diagnostics.lastCheckedAt {
                        Text("检查于 \(checked.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("重新检查") {
                        Task { await model.diagnostics.refresh() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if let message = model.diagnostics.actionMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task { await model.diagnostics.refresh() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: IntegrationDiagnostic.State
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.color)
                .font(.title3)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if let actionTitle {
                Button(actionTitle, action: action)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.accessibilityLabel)
    }
}

private extension IntegrationDiagnostic.State {
    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .needsAction: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "minus.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .needsAction: .red
        case .warning: .orange
        case .unavailable, .unknown: .secondary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready: "已就绪"
        case .needsAction: "待操作"
        case .warning: "需要注意"
        case .unavailable: "不可用"
        case .unknown: "状态未知"
        }
    }
}
