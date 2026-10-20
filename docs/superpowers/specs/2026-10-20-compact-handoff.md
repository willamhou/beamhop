# Compact handoff — October 20, 2026

The user chose to retain a compact shortcut-invoked panel. Its default question is where this material should go. Other destinations are available through a native menu. A note is optional. Holding material is a secondary action, and opening the corner shelf is always deliberate.

## Behavior

- Source and a short excerpt lead to one destination row. The row shows a remembered work name where available, the receiving app, and the actual action: copy or fill for review. The name field is disclosed through “Remember with a name”.
- Recent names resolve their own bindings. Choosing an app directly leaves the named work. Changing a target or work invalidates an earlier acknowledgment. An unavailable named receiver never becomes another app automatically.
- The corner shelf is a transient utility panel, without app activation or a separate document window. Escape, outside click, and its close control hide it. Selection survives hiding and failures during the running app session.
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

CI compiles/tests/packages on macOS. On-device results must be recorded separately before merge to main.
