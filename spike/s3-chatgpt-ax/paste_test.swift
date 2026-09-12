import Cocoa
import ApplicationServices

typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func findEditableTextArea(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth <= 14 else { return nil }
    let role = attribute(element, kAXRoleAttribute) as? String
    let enabled = attribute(element, kAXEnabledAttribute) as? Bool ?? false
    if enabled, role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) { return element }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        if let result = findEditableTextArea(child, depth: depth + 1) { return result }
    }
    return nil
}

func snapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot? {
    guard let items = pasteboard.pasteboardItems else { return [] }
    var result: PasteboardSnapshot = []
    for item in items {
        var copy: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            guard let data = item.data(forType: type) else { return nil }
            copy[type] = data
        }
        result.append(copy)
    }
    return result
}

func restore(_ value: PasteboardSnapshot, to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let items = value.map { values -> NSPasteboardItem in
        let item = NSPasteboardItem()
        values.forEach { item.setData($0.value, forType: $0.key) }
        return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

guard AXIsProcessTrusted() else { fputs("Accessibility permission is required.\n", stderr); exit(2) }
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.openai.chat" }) else {
    fputs("ChatGPT Desktop is not running.\n", stderr); exit(3)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
guard let input = findEditableTextArea(root) else { fputs("No enabled text input found.\n", stderr); exit(4) }
let pasteboard = NSPasteboard.general
guard let backup = snapshot(pasteboard) else { fputs("Clipboard cannot be safely serialized; refusing paste.\n", stderr); exit(5) }
defer { restore(backup, to: pasteboard) }

app.activate(options: [.activateIgnoringOtherApps])
AXUIElementSetAttributeValue(input, kAXFocusedAttribute, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.15)
let payload = "SPIKE_S3_PASTE_TEST_\(Int(Date().timeIntervalSince1970))"
pasteboard.clearContents()
guard pasteboard.setString(payload, forType: .string) else { exit(6) }
let source = CGEventSource(stateID: .hidSystemState)
for isDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown)
    event?.flags = .maskCommand
    event?.post(tap: .cghidEventTap)
}
Thread.sleep(forTimeInterval: 0.15)
let value = attribute(input, kAXValueAttribute) as? String ?? ""
print("payload=\(payload)")
print("input_contains_payload=\(value.contains(payload))")
print("clipboard_restore_scheduled=true")

