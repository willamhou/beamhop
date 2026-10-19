import Foundation
import AppKit
import ApplicationServices
import BeamhopCore

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
    /// `timeout` comes from the caller's AXDeadline budget (default 0.8s).
    static func systemFocusedElement(timeout: Double = 0.8) -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, Float(timeout))
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let el = v as! AXUIElement
        AXUIElementSetMessagingTimeout(el, Float(timeout))   // codex: bound subsequent reads on this element
        return el
    }

    // MARK: low-level reads

    private static func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
    }

    private static func string(_ el: AXUIElement, _ key: String) -> String? {
        attr(el, key) as? String
    }

    /// Focused window title for a pid. `timeout` comes from the caller's AXDeadline budget.
    static func windowTitle(pid: pid_t, timeout: Double = 0.8) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Float(timeout))
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

    /// Per-app selected-text + url extraction (S6 strategy / spec §6.2). The whole sequence
    /// runs inside `deadline` (default 800ms, PROGRESS §7.D): each step checks expiry and
    /// per-call timeouts shrink to the remaining budget — a slow app gets partial results,
    /// never a multi-second hang.
    static func read(front: FrontApp, deadline: AXDeadline = AXDeadline()) -> Read {
        var r = Read(windowTitle: nil, url: nil, selectedText: nil,
                     isSecure: false, method: "ax-native")
        if deadline.expired { r.method = "ax-deadline"; return r }
        r.windowTitle = windowTitle(pid: front.pid, timeout: deadline.callTimeout(default: 0.8))

        let isChromiumOrElectron = needsManualAX(bundleID: front.bundleID)
        let isSafari = front.bundleID == "com.apple.Safari"
        if isChromiumOrElectron {
            enableManualAX(pid: front.pid)
            usleep(UInt32(min(120_000, deadline.remaining * 1_000_000)))   // wait, capped by budget
        }
        if deadline.expired { r.method = "ax-deadline"; return r }

        guard let focused = systemFocusedElement(timeout: deadline.callTimeout(default: 0.8)) else { return r }
        r.isSecure = isSecure(focused)
        r.url = url(focused)

        if r.isSecure { r.method = "ax-secure-skipped"; return r }   // never read secure text
        if deadline.expired { r.method = "ax-deadline"; return r }

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
