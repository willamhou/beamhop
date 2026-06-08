import Foundation
import AppKit
import ApplicationServices

/// Accessibility foundation, hardened with Week 0 findings. Week 1 implements only the pieces
/// needed for the smoke (frontmost app + a system-wide focused-element probe); selectedText/url/
/// windowTitle full extraction is Week 2.
///
/// Week 0 lessons baked in:
///  - query the SYSTEM-WIDE focused element, not the app element (S6)
///  - opt Chromium/Electron/ChatGPT into AX via AXManualAccessibility before reading (S3/S6)
///  - set an AX messaging timeout so a hung app can't block us (S6 codex)
enum AXHelper {
    struct FrontApp { let bundleID: String; let name: String; let pid: pid_t }

    static func frontmostApp() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontApp(bundleID: app.bundleIdentifier ?? "unknown",
                        name: app.localizedName ?? "unknown",
                        pid: app.processIdentifier)
    }

    /// Bundle-id prefixes whose AX tree must be force-built before reading (S3/S6).
    static func needsManualAX(bundleID: String) -> Bool {
        let chromiumOrElectron = ["com.google.Chrome", "com.microsoft.VSCode",
                                  "com.todesktop.", "com.tinyspeck.slackmacgap",
                                  "com.openai.chat", "company.thebrowser.Browser",
                                  "com.brave.Browser", "com.microsoft.edgemac"]
        return chromiumOrElectron.contains { bundleID.hasPrefix($0) }
    }

    static func enableManualAX(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.8)   // S6 codex: never hang
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// System-wide focused element (S6: app-element query returns nil for most apps).
    static func systemFocusedElement() -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.8)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    // MARK: low-level reads

    private static func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
    }

    private static func string(_ el: AXUIElement, _ key: String) -> String? {
        attr(el, key) as? String
    }

    /// Focused window title for a pid.
    static func windowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.8)
        guard let win = attr(app, kAXFocusedWindowAttribute as String),
              CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return string(win as! AXUIElement, kAXTitleAttribute as String)
    }

    /// Is the focused element a secure (password) field? (spec §6.6 / §11 — skip + mark private.)
    static func isSecure(_ focused: AXUIElement) -> Bool {
        (string(focused, kAXSubroleAttribute as String)) == (kAXSecureTextFieldSubrole as String)
    }

    /// URL of the focused web area (Safari/Chrome expose AXURL).
    static func url(_ focused: AXUIElement) -> String? {
        guard let v = attr(focused, "AXURL"), CFGetTypeID(v) == CFURLGetTypeID() else { return nil }
        return (v as! NSURL).absoluteString
    }

    /// Result of an AX read, with the channel actually used (→ Capture.capture_method).
    struct Read {
        var windowTitle: String?
        var url: String?
        var selectedText: String?
        var isSecure: Bool
        var method: String       // "ax-native" | "ax-chromium" | "ax-safari" | "ax-electron-limited"
    }

    /// Per-app selected-text + url extraction (S6 strategy / spec §6.2).
    static func read(front: FrontApp) -> Read {
        var r = Read(windowTitle: windowTitle(pid: front.pid), url: nil, selectedText: nil,
                     isSecure: false, method: "ax-native")

        let isChromiumOrElectron = needsManualAX(bundleID: front.bundleID)
        let isSafari = front.bundleID == "com.apple.Safari"
        if isChromiumOrElectron { enableManualAX(pid: front.pid); usleep(120_000) }

        guard let focused = systemFocusedElement() else { return r }
        r.isSecure = isSecure(focused)
        r.url = url(focused)

        if r.isSecure { r.method = "ax-secure-skipped"; return r }   // never read secure text

        let sel = string(focused, kAXSelectedTextAttribute as String)
        if let sel, !sel.isEmpty {
            r.selectedText = sel
            r.method = isChromiumOrElectron ? "ax-chromium" : (isSafari ? "ax-safari" : "ax-native")
        } else if isSafari {
            // S6: Safari web selection needs AXSelectedTextMarkerRange (Phase 1.5 PoC); url still ok.
            r.method = "ax-safari-no-selection"
        } else if isChromiumOrElectron {
            // Electron editors (VS Code/Cursor) don't expose Monaco selection via kAXSelectedText.
            r.method = "ax-electron-limited"
        }
        return r
    }
}
