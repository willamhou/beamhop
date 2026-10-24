import AppKit
import ApplicationServices
import Foundation
import BeamhopCore

/// Kimi Work (Kimi desktop) delivery, mechanism verified by probe 2026-10-18:
///   - App element ACCEPTS AXManualAccessibility (opt-in succeeds — unlike ChatGPT 26.x).
///   - Exactly one AXTextArea/AXTextField in the window tree; AXEditable not exposed
///     (kAXErrorNoValue) — the shared AXComposerFinder two-pass logic handles it.
///   - kAXValueAttribute set-value returns success but does NOT take effect on Kimi's editor
///     (empty composer keeps exposing its placeholder as the AX value; injection appends to a
///     phantom node). So injection = FOCUS the composer, then clipboard-paste (⌘V) — the same
///     §12.3 clipboard-safe protocol, verified clean: pasted text lands exactly, placeholder
///     stays visual-only.
///   - auto_submit = false — user reviews and sends manually (consistent with ChatGPT §7.5 ⑥).
enum KimiDelivery {
    static let bundleIDs = ["com.moonshot.kimichat"]

    /// Returns nil on success, or a user-facing failure reason (caller falls back to clipboard).
    static func deliver(_ handoff: Handoff) -> String? {
        guard let (app, bundleID) = runningApp() else {
            return L10n.s("Kimi Work is not running (open it first, or use the clipboard)")
        }
        guard AppActivator.focus(app, bundleID: bundleID) else { return L10n.s("Could not bring Kimi Work to the front") }

        AXHelper.enableManualAX(pid: app.processIdentifier)
        usleep(150_000)   // let Chromium rebuild the tree

        guard AXComposerFinder.waitForWindow(pid: app.processIdentifier) else {
            return L10n.s("No Kimi Work window is open (open its window and try again)")
        }

        guard let composer = AXComposerFinder.waitForComposer(pid: app.processIdentifier) else {
            return L10n.s("Kimi input box (AXTextArea) not found — the version may have changed; use the clipboard")
        }
        guard AXComposerFinder.isEmpty(composer) else {
            return L10n.s("The input already has a draft or could not be checked. Paste the copied materials when ready.")
        }
        guard AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString,
                                           kCFBooleanTrue) == .success else {
            return L10n.s("Could not focus the Kimi input box")
        }
        usleep(150_000)   // focus settle before the paste lands

        // Kimi has no MCP channel: paste the FULL self-contained markdown (§7.5 pattern).
        let md = handoff.markdown
        do {
            try ClipboardService.safePasteOnly(md)
        } catch {
            return L10n.s("Clipboard could not be protected — automatic paste aborted (paste manually)")
        }
        Notifier.info(L10n.s("Pasted into Kimi Work"), L10n.s("Review the content and send manually (never auto-enters)"))
        return nil
    }

    private static func runningApp() -> (NSRunningApplication, String)? {
        for bid in bundleIDs {
            if let app = AppActivator.runningApp(bundleID: bid) { return (app, bid) }
        }
        return nil
    }
}
