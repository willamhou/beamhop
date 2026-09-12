import Cocoa
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

func describe(_ element: AXUIElement, depth: Int, path: [String]) {
    guard depth <= 14 else { return }
    let role = attribute(element, kAXRoleAttribute) as? String ?? "?"
    let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
    let title = attribute(element, kAXTitleAttribute) as? String ?? ""
    let nextPath = path + [identifier.isEmpty ? role : "\(role)#\(identifier)"]
    print("\(String(repeating: "  ", count: depth))\(nextPath.joined(separator: " > ")) title=\"\(escaped(title))\"")
    children(of: element).forEach { describe($0, depth: depth + 1, path: nextPath) }
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required.\n", stderr)
    exit(2)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.openai.chat" }) else {
    fputs("ChatGPT Desktop is not running.\n", stderr)
    exit(3)
}
describe(AXUIElementCreateApplication(app.processIdentifier), depth: 0, path: [])

