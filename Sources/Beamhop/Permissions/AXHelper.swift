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

    // Week 2 TODO: selectedText(...), windowTitle(...), url(...) with per-app strategy
    // (native kAXSelectedText / Chromium opt-in / Safari AXSelectedTextMarkerRange / Electron
    //  clipboard fallback — see spec §6.2 + spike S6). Node caps + timeout required.
}
