import Carbon
import Foundation

enum GlobalHotKeyAction: UInt32, CaseIterable, Codable, Identifiable {
    case capture = 1
    case inbox = 2
    case pasteLatest = 3

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .capture: "抓取当前 App"
        case .inbox: "打开 Inbox"
        case .pasteLatest: "粘贴最近 Capture"
        }
    }
}

enum HotKeyKey: String, Codable, CaseIterable, Identifiable {
    case space, i, v, c, b, p

    var id: String { rawValue }
    var display: String { self == .space ? "Space" : rawValue.uppercased() }
    var keyCode: UInt32 {
        switch self {
        case .space: UInt32(kVK_Space)
        case .i: UInt32(kVK_ANSI_I)
        case .v: UInt32(kVK_ANSI_V)
        case .c: UInt32(kVK_ANSI_C)
        case .b: UInt32(kVK_ANSI_B)
        case .p: UInt32(kVK_ANSI_P)
        }
    }
}

struct HotKeyBinding: Codable, Equatable {
    var key: HotKeyKey
    var command = true
    var shift = true
    var option = false
    var control = false

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if command { value |= UInt32(cmdKey) }
        if shift { value |= UInt32(shiftKey) }
        if option { value |= UInt32(optionKey) }
        if control { value |= UInt32(controlKey) }
        return value
    }

    var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + key.display
    }

    static let defaults: [GlobalHotKeyAction: HotKeyBinding] = [
        .capture: HotKeyBinding(key: .space),
        .inbox: HotKeyBinding(key: .i),
        .pasteLatest: HotKeyBinding(key: .v)
    ]
}

enum GlobalHotKeyError: LocalizedError {
    case eventHandler(OSStatus)
    case registration(GlobalHotKeyAction, OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandler(let status):
            "无法安装全局快捷键事件处理器（OSStatus \(status)）。"
        case .registration(let action, let status):
            "无法注册 \(action) 快捷键（OSStatus \(status)），可能与其他应用冲突。"
        }
    }
}

private func beamhopHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return eventNotHandledErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, let action = GlobalHotKeyAction(rawValue: hotKeyID.id) else {
        return eventNotHandledErr
    }
    GlobalHotKeyCenter.shared.invoke(action)
    return noErr
}

final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var references: [EventHotKeyRef] = []
    private var handlerReference: EventHandlerRef?
    private var callback: (@Sendable (GlobalHotKeyAction) -> Void)?

    private init() {}

    deinit {
        unregisterAll()
    }

    func register(
        bindings: [GlobalHotKeyAction: HotKeyBinding],
        callback: @escaping @Sendable (GlobalHotKeyAction) -> Void
    ) throws {
        unregisterAll()
        self.callback = callback

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            beamhopHotKeyHandler,
            1,
            &eventSpec,
            nil,
            &handlerReference
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.eventHandler(handlerStatus)
        }

        do {
            for action in GlobalHotKeyAction.allCases {
                let binding = bindings[action] ?? HotKeyBinding.defaults[action]!
                try register(action, binding: binding)
            }
        } catch {
            unregisterAll()
            throw error
        }
    }

    func reconfigure(bindings: [GlobalHotKeyAction: HotKeyBinding]) throws {
        guard let callback else { return }
        try register(bindings: bindings, callback: callback)
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
    }

    fileprivate func invoke(_ action: GlobalHotKeyAction) {
        callback?(action)
    }

    private func register(_ action: GlobalHotKeyAction, binding: HotKeyBinding) throws {
        let signature: OSType = 0x42484F50 // "BHOP"
        var reference: EventHotKeyRef?
        var identifier = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            binding.key.keyCode,
            binding.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw GlobalHotKeyError.registration(action, status)
        }
        references.append(reference)
    }
}
