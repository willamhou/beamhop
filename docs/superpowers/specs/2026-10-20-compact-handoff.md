# Compact handoff — October 20, 2026

The user chose to retain a compact shortcut-invoked panel. Its default question is where this material should go. Other destinations are available through a native menu. A note is optional. Holding material is a secondary action, and opening the corner shelf is always deliberate.

## Behavior

- Source and a short excerpt lead to one destination row. The row shows a remembered work name where available, the receiving app, and the actual action: copy or fill for review. The name field is disclosed through “Remember with a name”.
- The capture panel takes keyboard focus while leaving the source application active. Notes and explanatory text grow the panel without moving its top edge; the corner shelf preserves its bottom edge. Replacing a capture saves the previous note.
- Recent names resolve their own bindings. Choosing an app directly leaves the named work. Changing a target or work invalidates an earlier acknowledgment. An unavailable remembered receiver never becomes another app automatically. Its intent remains available for holding, while delivery requires an explicit replacement. A delayed receipt cannot confirm a binding changed during delivery.
- The corner shelf is a transient utility panel, without app activation or a separate document window. Escape, outside click, and its close control hide it. Selection survives hiding and failures during the running app session. Adding or removing materials with the same original intent retains an explicitly chosen receiver.
- The shelf preserves text, source, note, hold order and intended work/app across launches. Materials for different original destinations cannot be silently included in the same handoff. Select a subset, choose a receiver when undecided, and hand off only that subset.
- A handoff becomes one payload: one clipboard write or one composer insertion. Every material has its own source and note. MCP triggers reference each original capture separately. Pending rows stay visible; failure preserves selection; successful preparation removes only those held rows, never the originals.
- Delivery is serialized across the panel, Inbox and shelf. Existing/unreadable composer drafts take the copy fallback. Kimi no longer creates a new conversation. Terminal submission is manual until a specific session can be verified.
- Receipts distinguish copied, prepared (waiting for the user's send), failed and legacy success. None implies that an agent has received or completed the work. Notes are also saved in the original capture for Inbox recovery.

## Limits that the interface must show

A named work currently binds an application enum, not a conversation ID. Names help people recall intent but do not locate a specific session. Background routing and verified session registration require a receiving-side protocol; they are not implemented by this UI pass. AX adapters still activate the receiving application, so the action says “Fill & review”. Clipboard and holding return to the source. Unknown AX composer state falls back to copying; Kimi's placeholder/value behavior needs a fresh on-device check.

## Verification

Core regression tests cover acknowledgment invalidation, Inbox-only confirmation, work switching, unavailable named receivers, memory reset, ordered payloads with notes and sources, v6 database upgrades, partial selection, distinct work isolation, duplicate submit prevention, and failure recovery. The CLT self-test mirrors the principal flow regressions. No UI snapshot on Windows can validate AppKit behavior.

Mac acceptance before merging:

1. In Safari, PDF and an editor, invoke the panel, open its destination menu, press Escape, add a note, and use destination shortcuts. Check dynamic sizing, menu focus, Chinese/English labels, VoiceOver and full-screen behavior.
2. Hold multiple materials. The existing document must keep its scroll position; only the corner count changes. Open and dismiss the shelf without activating Beamhop as a normal app. Check two displays and short screen heights.
3. Select two out of three materials. Copy once and verify both sources and notes in order, with the third material remaining held. Fail an app handoff and verify the same selection remains retryable. Reopen the app and check held intent is still present.
4. With empty and nonempty receiving drafts, check ChatGPT and Kimi. Existing text must never be overwritten; Kimi must stay in the current conversation. Check whether Kimi exposes a readable empty value or needs the explicit copy fallback.
5. In a terminal, verify the entire trigger contains every selected capture and no Return is synthesized. Receipts must say prepared, not completed. Check that Inbox can reopen originals and their notes.

macOS CI passed on implementation commit `fde3a97`: build, XCTest, CLT SelfTest, MCP smoke, native messaging host and manifest smoke, and app packaging. Extension and shell checks passed. Native AppKit/SwiftUI checks ran on macOS 15.7.9: 152/152 assertions passed across English/Chinese and light/dark, with 20 PNGs visually reviewed. This covers panel focus, native editor input, native destination-menu selection, dismissal and draft recovery, sizing, and shelf selection/retry behavior. Evidence: https://github.com/willamhou/beamhop/actions/runs/39360579032 . See [native UI verification](../../native-ui-verification.md) for artifacts and scope.

The hosted run does not verify actual logged-in agent delivery, VoiceOver speech, TCC capture, fullscreen, Stage Manager or multiple displays. Record those integration results separately before merging to main.
