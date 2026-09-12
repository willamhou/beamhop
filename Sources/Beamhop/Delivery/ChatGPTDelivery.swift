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
        guard let app = runningApp() else { return "ChatGPT Desktop 未运行(先打开它,或改用剪贴板)" }

        app.activate(options: [.activateAllWindows])
        var front = false
        for _ in 0..<15 {
            usleep(80_000)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { front = true; break }
            app.activate(options: [.activateAllWindows])
        }
        guard front else { return "无法把 ChatGPT Desktop 切到前台" }

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

    private static func runningApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }
    }

    /// Bounded BFS over the focused window's AX tree for the composer AXTextArea.
    /// Depth/visit caps keep a pathological tree from stalling delivery (S6 timeout discipline).
    private static func findComposer(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.8)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        let window = winRef as! AXUIElement

        var queue: [AXUIElement] = [window]
        var visited = 0
        let maxVisits = 800
        let maxDepth = 40
        var depthOf: [ObjectIdentifier: Int] = [ObjectIdentifier(window): 0]
        while !queue.isEmpty, visited < maxVisits {
            let el = queue.removeFirst()
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

            guard let depth = depthOf[ObjectIdentifier(el)], depth < maxDepth else { continue }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let childrenRef, CFGetTypeID(childrenRef) == CFArrayGetTypeID() else { continue }
            // kAXChildren yields AXUIElements by contract (compiler: downcast always succeeds).
            for child in (childrenRef as! CFArray as NSArray) {
                let c = child as! AXUIElement
                let key = ObjectIdentifier(c)
                if depthOf[key] == nil {
                    depthOf[key] = depth + 1
                    queue.append(c)
                }
            }
        }
        return nil
    }
}
