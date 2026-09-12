import AppKit
import SwiftUI

@MainActor
final class BeamhopApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LaunchAtLoginStore.shared.ensureDefaultRegistration()
        TerminalActivityTracker.shared.start()
        do {
            try GlobalHotKeyCenter.shared.register(bindings: HotKeySettingsStore.shared.bindings) { action in
                Task { @MainActor in
                    AppModel.shared.handleHotKey(action)
                }
            }
        } catch {
            AppModel.shared.lastActionMessage = error.localizedDescription
        }
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyCenter.shared.unregisterAll()
        TerminalActivityTracker.shared.stop()
    }
}

@main
struct BeamhopApplication: App {
    @NSApplicationDelegateAdaptor(BeamhopApplicationDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Label("Beamhop", systemImage: "arrow.up.forward.app")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environmentObject(model)
        }
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var hotKeys = HotKeySettingsStore.shared

    var body: some View {
        Button(model.isCapturing ? "正在抓取…" : "抓取当前 App  \(hotKeys.binding(for: .capture).display)") {
            model.captureAndShow()
        }
        .disabled(model.isCapturing)

        Button("打开 Inbox  \(hotKeys.binding(for: .inbox).display)") {
            model.windows.showInbox()
        }

        Button("粘贴最近一次 Capture  \(hotKeys.binding(for: .pasteLatest).display)") {
            model.pasteLatestAtCursor()
        }

        Divider()

        Button("Permission Diagnostics…") {
            model.windows.showDiagnostics()
        }
        Button("Compatibility Matrix…") {
            model.windows.showCompatibility()
        }

        if let message = model.lastActionMessage {
            Divider()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()
        Button("退出 Beamhop") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct SettingsRootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var hotKeys = HotKeySettingsStore.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginStore.shared

    var body: some View {
        Form {
            Section("快捷键") {
                ForEach(GlobalHotKeyAction.allCases) { action in
                    HotKeyEditorRow(
                        action: action,
                        binding: Binding(
                            get: { hotKeys.binding(for: action) },
                            set: { hotKeys.set($0, for: action) }
                        )
                    )
                }
                HStack {
                    if let message = hotKeys.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.contains("生效") ? Color.green : Color.orange)
                    }
                    Spacer()
                    Button("应用快捷键") { hotKeys.apply() }
                }
            }
            Section("本地优先") {
                Text("Capture 与投递记录保存在本机。Beamhop 不会在后台自动截图。")
                    .foregroundStyle(.secondary)
                Toggle(
                    "登录时启动 Beamhop",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if let message = launchAtLogin.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("打开诊断") { model.windows.showDiagnostics() }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 340)
        .padding()
    }
}

private struct HotKeyEditorRow: View {
    let action: GlobalHotKeyAction
    @Binding var binding: HotKeyBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(action.title)
                Spacer()
                Text(binding.display)
                    .font(.callout.monospaced().weight(.semibold))
                Picker("按键", selection: $binding.key) {
                    ForEach(HotKeyKey.allCases) { key in Text(key.display).tag(key) }
                }
                .labelsHidden()
                .frame(width: 90)
            }
            HStack(spacing: 16) {
                Toggle("⌘", isOn: $binding.command)
                Toggle("⇧", isOn: $binding.shift)
                Toggle("⌥", isOn: $binding.option)
                Toggle("⌃", isOn: $binding.control)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.vertical, 3)
    }
}
