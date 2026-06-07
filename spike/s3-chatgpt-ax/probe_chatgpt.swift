import Cocoa
import ApplicationServices

// Dumps the AX tree of ChatGPT Desktop so we can locate the input element's path.
// Requires Accessibility permission for the terminal running this.

func axAttr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, key as CFString, &v)
    return r == .success ? v : nil
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    guard let v = axAttr(el, kAXChildrenAttribute as String) else { return [] }
    return (v as? [AXUIElement]) ?? []
}

func describe(_ el: AXUIElement, depth: Int = 0) {
    let role = (axAttr(el, kAXRoleAttribute as String) as? String) ?? "?"
    let subrole = (axAttr(el, kAXSubroleAttribute as String) as? String) ?? ""
    let title = (axAttr(el, kAXTitleAttribute as String) as? String) ?? ""
    let id = (axAttr(el, kAXIdentifierAttribute as String) as? String) ?? ""
    let prefix = String(repeating: "  ", count: depth)
    print("\(prefix)\(role) subrole=\(subrole) title=\"\(title)\" id=\"\(id)\"")
    if depth < 12 {
        for c in children(el) { describe(c, depth: depth + 1) }
    }
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.openai.chat" }) else {
    fputs("ChatGPT Desktop not running (bundle id com.openai.chat)\n", stderr); exit(1)
}
let el = AXUIElementCreateApplication(app.processIdentifier)
describe(el)
