import Cocoa
import ApplicationServices

// Run from a Terminal that has BOTH:
//   - Accessibility permission   (System Settings → Privacy & Security → Accessibility)
//   - Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring)
// Triggers on each Cmd+Shift+P press; logs one JSON line per probe to stdout.

func currentFrontApp() -> (bundleID: String, name: String, pid: pid_t)? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return (app.bundleIdentifier ?? "unknown", app.localizedName ?? "unknown", app.processIdentifier)
}

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

func focusedElement(forPID pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    guard let v = axAttr(app, kAXFocusedUIElementAttribute as String) else { return nil }
    guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func probe() -> [String: Any] {
    guard let front = currentFrontApp() else { return ["error": "no front app"] }
    var result: [String: Any] = [
        "ts": ISO8601DateFormatter().string(from: Date()),
        "bundle_id": front.bundleID,
        "app_name": front.name,
        "pid": Int(front.pid),
    ]
    let appEl = AXUIElementCreateApplication(front.pid)
    if let win = axAttr(appEl, kAXFocusedWindowAttribute as String),
       CFGetTypeID(win) == AXUIElementGetTypeID() {
        let winEl = win as! AXUIElement
        result["window_title"] = axAttr(winEl, kAXTitleAttribute as String) as? String ?? ""
    } else {
        result["window_title"] = ""
    }
    if let focused = focusedElement(forPID: front.pid) {
        result["focused_role"] = axAttr(focused, kAXRoleAttribute as String) as? String ?? ""
        result["focused_subrole"] = axAttr(focused, kAXSubroleAttribute as String) as? String ?? ""
        result["selected_text"] = axAttr(focused, kAXSelectedTextAttribute as String) as? String ?? ""
        // URL — Safari/Chrome expose AXURL on the web area
        if let urlVal = axAttr(focused, "AXURL"), CFGetTypeID(urlVal) == CFURLGetTypeID() {
            result["url"] = (urlVal as! NSURL).absoluteString ?? ""
        }
    } else {
        result["selected_text"] = ""
        result["focused_role"] = ""
    }
    return result
}

// Trap Cmd+Shift+P as the probe hotkey
let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: mask, callback: { _, _, event, _ in
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    // Cmd + Shift + P (keycode 35)
    if keycode == 35 && flags.contains(.maskCommand) && flags.contains(.maskShift) {
        let r = probe()
        if let d = try? JSONSerialization.data(withJSONObject: r),
           let s = String(data: d, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    }
    return Unmanaged.passRetained(event)
}, userInfo: nil)

guard let tap = tap else {
    fputs("event tap failed; grant Input Monitoring + Accessibility permission to this terminal\n", stderr)
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
fputs("[probe] ready — select text in any app, then press Cmd+Shift+P\n", stderr)
CFRunLoopRun()
