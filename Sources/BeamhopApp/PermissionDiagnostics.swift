import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class PermissionDiagnosticsStore: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var integrations: [IntegrationDiagnostic] = []
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var actionMessage: String?

    private let compatibility: CompatibilityMatrixStore
    private let integrationService = IntegrationDiagnosticsService()

    init(compatibility: CompatibilityMatrixStore) {
        self.compatibility = compatibility
    }

    func refresh() async {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        integrations = await integrationService.probe(matrix: compatibility.snapshot)
        lastCheckedAt = Date()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess()
    }

    func openAccessibilitySettings() {
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func openScreenRecordingSettings() {
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func performRecovery(for diagnostic: IntegrationDiagnostic) async {
        switch diagnostic.id {
        case "claude-code-mcp" where diagnostic.state != .ready:
            actionMessage = integrationService.copyClaudeRegistrationCommand()
                ? "已复制 Claude Code MCP 注册命令"
                : "无法写入剪贴板"
        case "chrome-native-host" where diagnostic.state != .ready:
            do {
                let count = try integrationService.repairBrowserManifests()
                actionMessage = count > 0 ? "已修复 \(count) 份 manifest" : "没有可修复的已安装 manifest"
                await refresh()
            } catch {
                actionMessage = "修复失败：\(error.localizedDescription)"
            }
        case "chatgpt-matrix", "cowork-matrix":
            AppModel.shared.windows.showCompatibility()
        default:
            await refresh()
        }
    }

    private func openSettings(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
