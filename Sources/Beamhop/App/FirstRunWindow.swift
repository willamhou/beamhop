import AppKit
import SwiftUI

/// First-run window (spec §9.4, skeleton): explains what Beamhop does, walks the one REQUIRED
/// permission (Accessibility), and makes optional pieces discoverable instead of blocking.
/// Everything is skippable — AX + local Inbox + clipboard fallback is the minimal usable set.
final class FirstRunWindowController {
    private var window: NSWindow?
    private let permissions: PermissionService
    private let onOpenDiagnostics: () -> Void

    init(permissions: PermissionService, onOpenDiagnostics: @escaping () -> Void) {
        self.permissions = permissions
        self.onOpenDiagnostics = onOpenDiagnostics
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "欢迎使用 Beamhop"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: FirstRunView(
            axGranted: permissions.accessibility() == .granted,
            onOpenAX: { [weak self] in self?.permissions.openAccessibilitySettings() },
            onOpenDiagnostics: onOpenDiagnostics
        ))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FirstRunView: View {
    let axGranted: Bool
    let onOpenAX: () -> Void
    let onOpenDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Beamhop").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("按 ⌘⇧Space 抓取当前 App 的上下文,先安全保存到本地 Inbox,再由你决定投给哪个 agent。")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 22)

            VStack(spacing: 0) {
                FirstRunRow(
                    index: "1", title: "辅助功能(Accessibility)",
                    detail: "必需:读取前台 App 的标题与选中文本,并执行 clipboard-safe 粘贴。",
                    ready: axGranted,
                    actionTitle: axGranted ? "已开启" : "打开系统设置",
                    action: onOpenAX)
                Divider().padding(.horizontal, 12)
                FirstRunRow(
                    index: "2", title: "浏览器扩展与 Agent 注册",
                    detail: "可选,可稍后在诊断面板完成。仅用 AX + 本地 Inbox + 剪贴板兜底即可开始。",
                    ready: false, actionTitle: "查看诊断", action: onOpenDiagnostics)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            .padding(.bottom, 22)

            Spacer()
            Text("开启辅助功能后,按 ⌘⇧Space 试试抓取第一条 Capture。")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 420)
    }
}

private struct FirstRunRow: View {
    let index: String
    let title: String
    let detail: String
    let ready: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(ready ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                Text(ready ? "✓" : index).font(.callout.weight(.semibold))
            }.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle, action: action).disabled(ready && actionTitle == "已开启")
        }
        .padding(12)
    }
}
