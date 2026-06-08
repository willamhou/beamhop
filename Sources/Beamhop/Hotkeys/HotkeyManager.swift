import Foundation
import Carbon
import os

/// One global hotkey spec.
struct Hotkey {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32     // Carbon mod flags (cmdKey | shiftKey ...)
    let name: String
    let handler: () -> Void
}

/// Global hotkeys via Carbon RegisterEventHotKey — Week 0 S5 verified this needs NO Input
/// Monitoring permission. Codex review hardening: check OSStatus per registration, install the
/// event handler exactly once, isolate per-key failures, and unregister everything on teardown.
final class HotkeyManager {
    private let log = Logger(subsystem: "com.beamhop.app", category: "hotkeys")
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private(set) var failed: [String] = []     // names that failed to register (conflicts)
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = {
        // 'BHOP'
        let s = "BHOP".utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
        return OSType(s)
    }()

    func installHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData = userData, let event = event else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { mgr.handlers[hkID.id]?() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    /// Register one hotkey. Returns false (and records the name in `failed`) on conflict.
    @discardableResult
    func register(_ hk: Hotkey) -> Bool {
        installHandlerOnce()
        let hkID = EventHotKeyID(signature: HotkeyManager.signature, id: hk.id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hk.keyCode, hk.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref = ref else {
            log.warning("hotkey '\(hk.name, privacy: .public)' failed to register (status \(status)) — likely a conflict")
            failed.append(hk.name)
            return false
        }
        handlers[hk.id] = hk.handler
        refs[hk.id] = ref
        log.info("registered hotkey '\(hk.name, privacy: .public)'")
        return true
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        if let h = eventHandler { RemoveEventHandler(h); eventHandler = nil }
    }

    deinit { unregisterAll() }
}
