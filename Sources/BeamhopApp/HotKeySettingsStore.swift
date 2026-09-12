import Combine
import Foundation

@MainActor
final class HotKeySettingsStore: ObservableObject {
    static let shared = HotKeySettingsStore()

    @Published var bindings: [GlobalHotKeyAction: HotKeyBinding]
    @Published private(set) var message: String?

    private var savedBindings: [GlobalHotKeyAction: HotKeyBinding]
    private let defaultsKey = "hotkeys.bindings.v1"

    private init() {
        let loaded = Self.load(key: defaultsKey) ?? HotKeyBinding.defaults
        bindings = loaded
        savedBindings = loaded
    }

    func binding(for action: GlobalHotKeyAction) -> HotKeyBinding {
        bindings[action] ?? HotKeyBinding.defaults[action]!
    }

    func set(_ binding: HotKeyBinding, for action: GlobalHotKeyAction) {
        bindings[action] = binding
    }

    func apply() {
        guard Set(bindings.values.map { "\($0.key.rawValue)-\($0.carbonModifiers)" }).count
                == GlobalHotKeyAction.allCases.count else {
            message = "快捷键不能重复"
            return
        }
        do {
            try GlobalHotKeyCenter.shared.reconfigure(bindings: bindings)
            let encoded = try JSONEncoder().encode(Self.persisted(bindings))
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
            savedBindings = bindings
            message = "快捷键已生效"
        } catch {
            bindings = savedBindings
            try? GlobalHotKeyCenter.shared.reconfigure(bindings: savedBindings)
            message = "快捷键冲突，已恢复原设置：\(error.localizedDescription)"
        }
    }

    private static func load(key: String) -> [GlobalHotKeyAction: HotKeyBinding]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: HotKeyBinding].self, from: data) else {
            return nil
        }
        var bindings: [GlobalHotKeyAction: HotKeyBinding] = [:]
        for action in GlobalHotKeyAction.allCases {
            guard let binding = stored[String(action.rawValue)] else { return nil }
            bindings[action] = binding
        }
        return bindings
    }

    private static func persisted(
        _ bindings: [GlobalHotKeyAction: HotKeyBinding]
    ) -> [String: HotKeyBinding] {
        Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key.rawValue), $0.value) })
    }
}
