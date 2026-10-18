import ApplicationServices

/// Shared composer locator for Electron/Chromium desktop apps (ChatGPT Desktop, Kimi Work, …).
///
/// v26-era realities, measured 2026-10-18 (probe scripts in spike/s3-chatgpt-ax/):
///   - composer sits at depth ~30 in ChatGPT 26.x (old version: ~6) → depth bound 40,
///     visit bound 4000 (BFS, breadth-first so shallow wins on ties)
///   - "AXEditable" is NO LONGER exposed on ChatGPT 26.x / Kimi Work composers
///     (read = kAXErrorNoValue) → pass 1 honors an explicit true; pass 2 accepts candidates
///     that are not EXPLICITLY false; the caller's injection result is the final arbiter
///   - focused window can be momentarily absent right after activation → fall back to the
///     first window in AXWindows
enum AXComposerFinder {
    static func findComposer(pid: pid_t) -> AXUIElement? {
        guard let window = resolveWindow(pid: pid) else { return nil }

        var textAreas: [AXUIElement] = []
        var queue: [(el: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        let maxVisits = 4000
        let maxDepth = 40
        while !queue.isEmpty, visited < maxVisits {
            let (el, depth) = queue.removeFirst()
            visited += 1

            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
               let roleRef, CFGetTypeID(roleRef) == CFStringGetTypeID() {
                let role = roleRef as! CFString as String
                if role == (kAXTextAreaRole as String) { textAreas.append(el) }
            }

            guard depth < maxDepth else { continue }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let childrenRef, CFGetTypeID(childrenRef) == CFArrayGetTypeID() else { continue }
            // kAXChildren yields AXUIElements by contract (compiler: downcast always succeeds).
            for child in (childrenRef as! CFArray as NSArray) {
                queue.append((child as! AXUIElement, depth + 1))
            }
        }

        // Pass 1 (classic behavior): only an explicitly editable area is the composer; read-only
        // transcript areas are not. ("AXEditable" — no imported constant name for this attribute.)
        for el in textAreas {
            var editableRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editableRef) == .success,
               let editableRef, CFEqual(editableRef, kCFBooleanTrue) { return el }
        }
        // Pass 2 (v26+/Kimi): AXEditable may be gone from the tree — keep any candidate that is
        // not EXPLICITLY read-only.
        for el in textAreas {
            var editableRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editableRef) == .success,
               let editableRef, CFEqual(editableRef, kCFBooleanFalse) { continue }
            return el
        }
        return nil
    }

    /// Resolve the app's chat window: focused window first, then main window, then the first
    /// entry of AXWindows. ⚠️ Electron 43 (Kimi 3.2.17) keeps AXWindows EMPTY even with a
    /// visible window — only AXFocusedWindow/AXMainWindow expose it (measured 2026-10-18).
    static func resolveWindow(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.8)
        for key in [kAXFocusedWindowAttribute as String, kAXMainWindowAttribute as String] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, key as CFString, &ref) == .success,
               let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                return ref as! AXUIElement
            }
        }
        var arrRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &arrRef) == .success,
           let arrRef, CFGetTypeID(arrRef) == CFArrayGetTypeID() {
            let ns = arrRef as! CFArray as NSArray
            if let first = ns.firstObject, CFGetTypeID(first as AnyObject) == AXUIElementGetTypeID() {
                return first as! AXUIElement
            }
        }
        return nil
    }

    /// True when the app exposes at least one AX window (Electron 43: via focused/main window —
    /// see resolveWindow). A running app with no open chat window has no composer.
    static func hasWindow(pid: pid_t) -> Bool {
        resolveWindow(pid: pid) != nil
    }

    /// Poll until the app publishes at least one AX window. Chromium apps publish LAZILY right
    /// after activation — a single immediate hasWindow races the publication and misreports
    /// "窗口未打开" (measured: Kimi false at t=0ms, true at t=200ms after activate). Bounded wait.
    static func waitForWindow(pid: pid_t, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if hasWindow(pid: pid) { return true }
            usleep(100_000)
        } while Date() < deadline
        return hasWindow(pid: pid)
    }
}
