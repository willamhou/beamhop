import Cocoa
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func firstURL(in element: AXUIElement, depth: Int = 0) -> String? {
    guard depth < 7 else { return nil }
    if let value = attribute(element, "AXURL" as CFString) {
        if let url = value as? URL { return url.absoluteString }
        if let url = value as? String { return url }
    }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        if let url = firstURL(in: child, depth: depth + 1) { return url }
    }
    return nil
}

func probe() -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else { return ["error": "no_frontmost_app"] }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let focused = attribute(root, kAXFocusedUIElementAttribute) as! AXUIElement?
    let window = attribute(root, kAXFocusedWindowAttribute) as! AXUIElement?
    return [
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "bundle_id": app.bundleIdentifier ?? "",
        "app_name": app.localizedName ?? "",
        "pid": Int(app.processIdentifier),
        "window_title": window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? "",
        "focused_role": focused.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? "",
        "selected_text": focused.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "",
        "url": focused.flatMap { firstURL(in: $0) } ?? firstURL(in: root) ?? ""
    ]
}

guard AXIsProcessTrusted() else { fputs("Accessibility permission is required.\n", stderr); exit(2) }
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
let callback: CGEventTapCallBack = { _, _, event, _ in
    if event.getIntegerValueField(.keyboardEventKeycode) == 35,
       event.flags.contains(.maskCommand), event.flags.contains(.maskShift),
       let data = try? JSONSerialization.data(withJSONObject: probe()),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
    return Unmanaged.passUnretained(event)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                  eventsOfInterest: mask, callback: callback, userInfo: nil) else {
    fputs("Input Monitoring permission is required.\n", stderr); exit(3)
}
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
fputs("Ready. Select text and press Command-Shift-P.\n", stderr)
CFRunLoopRun()

