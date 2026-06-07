import Cocoa
import ApplicationServices
import Carbon

// SAFE read-only AX probe. You select text yourself, then press ⌘⇧P — the probe reads the
// frontmost app's app/window/selection via AX and prints one JSON line. It NEVER synthesizes
// keystrokes into your apps.
//
// Permissions: only Accessibility (System Settings → Privacy & Security → Accessibility).
// The hotkey uses Carbon RegisterEventHotKey, so NO Input Monitoring is needed.
//
// Incorporates the 2026-06-07 spike findings:
//  - query the SYSTEM-WIDE focused element (app-element query returns nil for most apps)
//  - opt Chromium/Electron into AX with AXManualAccessibility / AXEnhancedUserInterface
//  - fall back to traversing the focused window for any populated kAXSelectedText
//  - read AXURL on web areas (Safari/Chrome)

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

func enableManualAX(_ app: AXUIElement) {
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

func systemFocusedElement() -> AXUIElement? {
    let sys = AXUIElementCreateSystemWide()
    guard let v = axAttr(sys, kAXFocusedUIElementAttribute as String),
          CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func findSelectedText(_ el: AXUIElement, depth: Int = 0) -> String? {
    if let s = axAttr(el, kAXSelectedTextAttribute as String) as? String, !s.isEmpty { return s }
    if depth > 8 { return nil }
    if let kids = axAttr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
        for k in kids { if let s = findSelectedText(k, depth: depth + 1) { return s } }
    }
    return nil
}

func probe() -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else { return ["error": "no front app"] }
    let pid = app.processIdentifier
    var result: [String: Any] = [
        "ts": ISO8601DateFormatter().string(from: Date()),
        "bundle_id": app.bundleIdentifier ?? "unknown",
        "app_name": app.localizedName ?? "unknown",
        "pid": Int(pid),
    ]
    let appEl = AXUIElementCreateApplication(pid)
    enableManualAX(appEl)
    usleep(120_000)  // let Chromium/Electron build its AX tree after opt-in

    var focusedWindow: AXUIElement?
    if let win = axAttr(appEl, kAXFocusedWindowAttribute as String),
       CFGetTypeID(win) == AXUIElementGetTypeID() {
        focusedWindow = (win as! AXUIElement)
        result["window_title"] = axAttr(focusedWindow!, kAXTitleAttribute as String) as? String ?? ""
    } else {
        result["window_title"] = ""
    }

    let focused = systemFocusedElement()
    if let focused = focused {
        result["focused_role"] = axAttr(focused, kAXRoleAttribute as String) as? String ?? ""
        result["focused_subrole"] = axAttr(focused, kAXSubroleAttribute as String) as? String ?? ""
        var sel = axAttr(focused, kAXSelectedTextAttribute as String) as? String ?? ""
        if sel.isEmpty, let win = focusedWindow { sel = findSelectedText(win) ?? "" }
        result["selected_text"] = sel
        if let urlVal = axAttr(focused, "AXURL"), CFGetTypeID(urlVal) == CFURLGetTypeID() {
            result["url"] = (urlVal as! NSURL).absoluteString ?? ""
        }
    } else {
        var sel = ""
        if let win = focusedWindow { sel = findSelectedText(win) ?? "" }
        result["selected_text"] = sel
        result["focused_role"] = ""
        result["focused_note"] = "no system-wide focused element"
    }
    return result
}

func emit() {
    let r = probe()
    if let d = try? JSONSerialization.data(withJSONObject: r),
       let s = String(data: d, encoding: .utf8) {
        print(s)
        fflush(stdout)
    }
}

// Global hotkey ⌘⇧P via Carbon (no Input Monitoring needed).
let hotKeyID = EventHotKeyID(signature: OSType(0x42484F50), id: 1) // 'BHOP'
var hotKeyRef: EventHotKeyRef?
let mods = UInt32(cmdKey | shiftKey)
let keyP: UInt32 = 35 // 'p'
RegisterEventHotKey(keyP, mods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    emit()
    return noErr
}, 1, &spec, nil, nil)

if !AXIsProcessTrusted() {
    fputs("[probe] WARNING: Accessibility not granted to this terminal — selections will read empty.\n", stderr)
}
fputs("[probe] ready — select text in any app, then press ⌘⇧P. Ctrl+C to stop.\n", stderr)
RunLoop.current.run()
