import Cocoa
import ApplicationServices

// Test: locate ChatGPT Desktop's input (AXTextArea), write payload to NSPasteboard,
// simulate Cmd+V, verify text landed, then restore the original clipboard.
// Requires Accessibility permission for the terminal running this.

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

func findInput(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if let role = axAttr(el, kAXRoleAttribute as String) as? String, role == "AXTextArea" { return el }
    if depth > 14 { return nil }
    if let cs = axAttr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
        for c in cs { if let f = findInput(c, depth: depth + 1) { return f } }
    }
    return nil
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.openai.chat" }) else {
    fputs("ChatGPT not running\n", stderr); exit(1)
}
app.activate(options: [])
Thread.sleep(forTimeInterval: 0.3)

let appEl = AXUIElementCreateApplication(app.processIdentifier)
// ChatGPT Desktop exposes its AX tree (incl. the input AXTextArea) only after this opt-in.
AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.4)
guard let input = findInput(appEl) else { fputs("input (AXTextArea) not found\n", stderr); exit(2) }

// SAFEST path first: set the AXTextArea value directly via AX (no clipboard, no keystrokes).
let axSetResult = AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "SPIKE_S3_AXSET_TEST" as CFString)
Thread.sleep(forTimeInterval: 0.15)
let axSetReadback = axAttr(input, kAXValueAttribute as String) as? String ?? "<nil>"
print("AX set-value result: \(axSetResult == .success ? "success" : "\(axSetResult.rawValue)")")
print("AX set-value readback contains marker: \(axSetReadback.contains("SPIKE_S3_AXSET_TEST"))")
// clear it before the paste test
AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "" as CFString)
Thread.sleep(forTimeInterval: 0.1)
AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.1)

// Save clipboard
let pb = NSPasteboard.general
let backup: [[NSPasteboard.PasteboardType: Data]]? = pb.pasteboardItems?.compactMap { item in
    item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { acc, t in
        if let d = item.data(forType: t) { acc[t] = d }
    }
}
// Write payload
pb.clearContents()
let payload = "SPIKE_S3_PASTE_TEST_\(Int(Date().timeIntervalSince1970))"
pb.setString(payload, forType: .string)

// Cmd+V via CGEvent (virtualKey 9 = 'v')
let src = CGEventSource(stateID: .hidSystemState)
let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
vDown?.flags = .maskCommand
vUp?.flags = .maskCommand
vDown?.post(tap: .cghidEventTap)
vUp?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.15)

// Read back input value
let val = axAttr(input, kAXValueAttribute as String) as? String ?? "<nil>"
print("paste payload: \(payload)")
print("input value contains payload: \(val.contains(payload))")

// Restore clipboard
pb.clearContents()
if let backup = backup, let first = backup.first {
    let item = NSPasteboardItem()
    for (t, d) in first { item.setData(d, forType: t) }
    pb.writeObjects([item])
}
print("clipboard restored")
