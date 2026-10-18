import Cocoa
import ApplicationServices

// v26 probe: dump ChatGPT Desktop's AX tree (both old/new bundle ids), with extra
// detail on text-ish roles so we can locate the composer in the new version.

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    guard let v = axAttr(el, kAXChildrenAttribute as String) else { return [] }
    return (v as? [AXUIElement]) ?? []
}

let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]

func describe(_ el: AXUIElement, depth: Int = 0) {
    let role = (axAttr(el, kAXRoleAttribute as String) as? String) ?? "?"
    var extra = ""
    if textRoles.contains(role) || depth < 3 {
        let subrole = (axAttr(el, kAXSubroleAttribute as String) as? String) ?? ""
        let title = (axAttr(el, kAXTitleAttribute as String) as? String) ?? ""
        let id = (axAttr(el, kAXIdentifierAttribute as String) as? String) ?? ""
        if !subrole.isEmpty { extra += " subrole=\(subrole)" }
        if !title.isEmpty { extra += " title=\"\(title)\"" }
        if !id.isEmpty { extra += " id=\"\(id)\"" }
    }
    if textRoles.contains(role) {
        let editable = (axAttr(el, "AXEditable") as? Bool).map { $0 ? "true" : "false" } ?? "?"
        let enabled = (axAttr(el, kAXEnabledAttribute as String) as? Bool).map { $0 ? "true" : "false" } ?? "?"
        let placeholder = (axAttr(el, kAXPlaceholderValueAttribute as String) as? String) ?? ""
        let valueLen = (axAttr(el, kAXValueAttribute as String) as? String).map { "\($0.count)ch" } ?? "nil"
        extra += " editable=\(editable) enabled=\(enabled) placeholder=\"\(placeholder)\" value=\(valueLen)"
    }
    let prefix = String(repeating: "  ", count: depth)
    print("\(prefix)\(role)\(extra)")
    if depth < 24 {
        for c in children(el) { describe(c, depth: depth + 1) }
    }
}

let bids = ["com.openai.chat", "com.openai.codex"]
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    bids.contains($0.bundleIdentifier ?? "") && $0.activationPolicy == .regular
}) else {
    fputs("ChatGPT Desktop not running\n", stderr); exit(1)
}
print("app=\(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)")

let el = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
usleep(400_000)

// Focus the app first so kAXFocusedWindow is the main chat window.
app.activate(options: [.activateAllWindows])
usleep(600_000)

if let wins = axAttr(el, kAXWindowsAttribute as String) as? [AXUIElement] {
    print("windows: \(wins.count)")
    for (i, w) in wins.enumerated() {
        let title = (axAttr(w, kAXTitleAttribute as String) as? String) ?? ""
        print("--- window \(i) title=\"\(title)\" ---")
        describe(w)
    }
} else {
    print("no AXWindows; dumping from app element")
    describe(el)
}
