import AppKit
import ApplicationServices
import Foundation
import BeamhopCore

/// ChatGPT Desktop delivery (spec §7.5), implemented per Week 0 S3 MEASURED facts
/// (spike/compatibility-matrix-v0.json → chatgpt_desktop):
///   - ChatGPT exposes NOTHING via AX until the app element opts in via
///     AXManualAccessibility + AXEnhancedUserInterface (already in AXHelper for capture).
///   - The composer is an AXTextArea under the focused window.
///   - Injection is kAXValueAttribute SET-VALUE (not simulated typing); Cmd+V is only a fallback.
///   - auto_submit = false — we inject and let the user review + press send (spec §7.5 ⑥).
enum ChatGPTDelivery {
    static let bundleID = "com.openai.chat"

    /// Returns nil on success, or a user-facing failure reason (caller falls back to clipboard).
    static func deliver(_ capture: Capture, userNote: String?) -> String? {
        guard let app = AppActivator.runningApp(bundleID: bundleID) else {
            return "ChatGPT Desktop 未运行(先打开它,或改用剪贴板)"
        }
        guard AppActivator.focus(app, bundleID: bundleID) else { return "无法把 ChatGPT Desktop 切到前台" }

        // S3: without this opt-in the AX tree of com.openai.chat is unusable.
        AXHelper.enableManualAX(pid: app.processIdentifier)
        usleep(150_000)   // S3/S6: give Chromium a beat to (re)build the tree

        guard let composer = findComposer(pid: app.processIdentifier) else {
            return "未找到 ChatGPT 输入框(AXTextArea)——版本可能已变化,请用剪贴板"
        }

        // ChatGPT has no MCP channel, so we inject the FULL self-contained markdown (§7.5).
        // set-value REPLACES the composer's current draft; drafts are usually empty at delivery
        // time, and preserving an in-progress draft across injection has no reliable AX story.
        let md = PromptRenderer.fullMarkdown(capture, userNote: userNote)
        guard AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString,
                                           md as CFString) == .success else {
            return "AX set-value 注入失败(输入框可能只读或版本已变化)"
        }
        // S3 measured: send button exists (MessageInputPrimaryButtonContainerPart.PrimaryButton)
        // but auto-submit stays OFF by spec — surface an explicit review step instead.
        Notifier.info("已注入 ChatGPT Desktop", "请检查内容后手动发送(不自动回车)")
        return nil
    }

    /// Bounded BFS over the focused window's AX tree for the composer AXTextArea.
    /// AX trees are trees (not DAGs), so no visited-set is needed — and one keyed by
    /// `ObjectIdentifier` would be WRONG anyway: each AX query can return a new CF instance for
    /// the same element, so identity-based dedup silently fails on deep Electron trees
    /// (code review P2-2). Bound the walk by depth + visit count only (S6 timeout discipline).
    private static func findComposer(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.8)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        let window = winRef as! AXUIElement

        var queue: [(el: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        let maxVisits = 800
        let maxDepth = 40
        while !queue.isEmpty, visited < maxVisits {
            let (el, depth) = queue.removeFirst()
            visited += 1

            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
               let roleRef, CFGetTypeID(roleRef) == CFStringGetTypeID() {
                let role = roleRef as! CFString as String
                if role == (kAXTextAreaRole as String) {
                    // Only an editable area is the composer; read-only transcript areas are not.
                    // ("AXEditable" — no imported constant name for this attribute.)
                    var editableRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editableRef) == .success,
                       let editableRef, CFEqual(editableRef, kCFBooleanTrue) {
                        return el
                    }
                }
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
        return nil
    }
}
