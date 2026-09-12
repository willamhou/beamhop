import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    static let shared = LaunchAtLoginStore()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var message: String?
    private let configuredKey = "launchAtLogin.configured.v1"

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func ensureDefaultRegistration() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else {
            refresh()
            return
        }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: configuredKey)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: configuredKey)
            refresh()
            message = enabled ? "已设为登录时启动" : "已关闭登录时启动"
        } catch {
            refresh()
            message = "登录项更新失败：\(error.localizedDescription)"
        }
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
