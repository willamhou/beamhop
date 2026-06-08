import Cocoa
import ApplicationServices

// One-shot variant of AXProbe: no hotkey (so no Input Monitoring needed) — probes the
// CURRENT frontmost app immediately and prints one JSON line, then exits.
// Only needs Accessibility permission for the controlling terminal.
// Usage: ./axprobe_once          (probe frontmost now)
//        ./axprobe_once --trust  (just print AX trust status + exit)

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

// Opt Chrome / Electron / Safari into building their AX tree. Without this, those apps
// expose little-to-nothing over AX unless a screen reader is running.
func enableManualAX(_ app: AXUIElement) {
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

// Prefer the SYSTEM-WIDE focused element (works across apps); fall back to the app element.
func focusedElement(forPID pid: pid_t) -> AXUIElement? {
    let sys = AXUIElementCreateSystemWide()
    if let v = axAttr(sys, kAXFocusedUIElementAttribute as String),
       CFGetTypeID(v) == AXUIElementGetTypeID() {
        return (v as! AXUIElement)
    }
    let app = AXUIElementCreateApplication(pid)
    if let v = axAttr(app, kAXFocusedUIElementAttribute as String),
       CFGetTypeID(v) == AXUIElementGetTypeID() {
        return (v as! AXUIElement)
    }
    return nil
}

// Walk down from an element looking for any populated kAXSelectedText (depth-limited).
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
    let bundleID = app.bundleIdentifier ?? "unknown"
    let name = app.localizedName ?? "unknown"
    let pid = app.processIdentifier
    var result: [String: Any] = [
        "ts": ISO8601DateFormatter().string(from: Date()),
        "bundle_id": bundleID,
        "app_name": name,
        "pid": Int(pid),
    ]
    let appEl = AXUIElementCreateApplication(pid)
    enableManualAX(appEl)
    usleep(150_000)  // give the app a moment to build its AX tree after opt-in
    if let win = axAttr(appEl, kAXFocusedWindowAttribute as String),
       CFGetTypeID(win) == AXUIElementGetTypeID() {
        result["window_title"] = axAttr(win as! AXUIElement, kAXTitleAttribute as String) as? String ?? ""
    } else {
        result["window_title"] = ""
    }
    if let focused = focusedElement(forPID: pid) {
        result["focused_role"] = axAttr(focused, kAXRoleAttribute as String) as? String ?? ""
        result["focused_subrole"] = axAttr(focused, kAXSubroleAttribute as String) as? String ?? ""
        var sel = axAttr(focused, kAXSelectedTextAttribute as String) as? String ?? ""
        if sel.isEmpty, let win = axAttr(appEl, kAXFocusedWindowAttribute as String),
           CFGetTypeID(win) == AXUIElementGetTypeID() {
            sel = findSelectedText(win as! AXUIElement) ?? ""   // traverse window for any selection
        }
        result["selected_text"] = sel
        if let urlVal = axAttr(focused, "AXURL"), CFGetTypeID(urlVal) == CFURLGetTypeID() {
            result["url"] = (urlVal as! NSURL).absoluteString ?? ""
        }
    } else {
        // last resort: traverse the focused window for any selected text
        var sel = ""
        if let win = axAttr(appEl, kAXFocusedWindowAttribute as String),
           CFGetTypeID(win) == AXUIElementGetTypeID() {
            sel = findSelectedText(win as! AXUIElement) ?? ""
        }
        result["selected_text"] = sel
        result["focused_role"] = ""
        result["focused_note"] = "no focused element via AXFocusedUIElement"
    }
    return result
}

let trusted = AXIsProcessTrusted()
if CommandLine.arguments.contains("--trust") {
    print("{\"ax_trusted\": \(trusted)}")
    exit(trusted ? 0 : 3)
}

// --app <bundleid>: self-activate the target, wait until it's actually frontmost (kills
// focus races), send Cmd+A to create a selection, then probe — all in one process.
func sendCmdA() {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) // 0 = 'a'
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

if let i = CommandLine.arguments.firstIndex(of: "--app"), i + 1 < CommandLine.arguments.count {
    let targetBundle = CommandLine.arguments[i + 1]
    let selectAll = CommandLine.arguments.contains("--selectall")
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundle }) else {
        print("{\"error\":\"app not running\",\"bundle_id\":\"\(targetBundle)\"}")
        exit(2)
    }
    app.activate(options: [.activateAllWindows])
    // wait up to 2.5s for it to actually be frontmost
    var frontOK = false
    for _ in 0..<25 {
        usleep(100_000)
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundle { frontOK = true; break }
        app.activate(options: [.activateAllWindows])
    }
    if selectAll && frontOK { usleep(200_000); sendCmdA(); usleep(400_000) }
    var out = probe()
    out["ax_trusted"] = trusted
    out["front_locked"] = frontOK
    if let d = try? JSONSerialization.data(withJSONObject: out), let s = String(data: d, encoding: .utf8) { print(s) }
    exit(0)
}

var out = probe()
out["ax_trusted"] = trusted
if let d = try? JSONSerialization.data(withJSONObject: out),
   let s = String(data: d, encoding: .utf8) {
    print(s)
}
