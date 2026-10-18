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
    /// Known bundle ids: ≤25.x = com.openai.chat; 26.x (Codex-era, verified on this machine
    /// 2026-10-18, v26.1007.71326) = com.openai.codex. Try both.
    static let bundleIDs = ["com.openai.chat", "com.openai.codex"]

    /// Returns nil on success, or a user-facing failure reason (caller falls back to clipboard).
    static func deliver(_ capture: Capture, userNote: String?) -> String? {
        guard let (app, bundleID) = runningApp() else {
            return L10n.s("ChatGPT Desktop is not running (open it first, or use the clipboard)")
        }
        guard AppActivator.focus(app, bundleID: bundleID) else { return L10n.s("Could not bring ChatGPT Desktop to the front") }

        // S3: without this opt-in the AX tree of com.openai.chat is unusable.
        AXHelper.enableManualAX(pid: app.processIdentifier)
        usleep(150_000)   // S3/S6: give Chromium a beat to (re)build the tree

        // A running app with no open window has no composer — say so instead of blaming the version.
        // Polling: the AX window publishes lazily after activation (measured race on Kimi).
        guard AXComposerFinder.waitForWindow(pid: app.processIdentifier) else {
            return L10n.s("No ChatGPT window is open (open a chat window and try again)")
        }

        guard let composer = AXComposerFinder.findComposer(pid: app.processIdentifier) else {
            return L10n.s("ChatGPT input box (AXTextArea) not found — the version may have changed; use the clipboard")
        }

        // ChatGPT has no MCP channel, so we inject the FULL self-contained markdown (§7.5).
        // set-value REPLACES the composer's current draft; drafts are usually empty at delivery
        // time, and preserving an in-progress draft across injection has no reliable AX story.
        let md = PromptRenderer.fullMarkdown(capture, userNote: userNote)
        guard AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString,
                                           md as CFString) == .success else {
            return L10n.s("AX set-value injection failed (the input box may be read-only or the version changed)")
        }
        // S3 measured: send button exists (MessageInputPrimaryButtonContainerPart.PrimaryButton)
        // but auto-submit stays OFF by spec — surface an explicit review step instead.
        Notifier.info(L10n.s("Injected into ChatGPT Desktop"), L10n.s("Review the content and send manually (never auto-enters)"))
        return nil
    }

    /// First running ChatGPT Desktop app across the known bundle ids.
    private static func runningApp() -> (NSRunningApplication, String)? {
        for bid in bundleIDs {
            if let app = AppActivator.runningApp(bundleID: bid) { return (app, bid) }
        }
        return nil
    }
}
