# Focus recovery and Inbox conclusion regression

Date: 2026-10-19. Base: `main` at `1bb64e1`. Branch: `codex/focus-inbox-results`. Validation below is local; real-device acceptance and merge are still pending.

## Behavior

- Capture rejects its own PID (SwiftPM as well as bundled app) or `com.beamhop.app` before AX reads and DB inserts.
- Esc, Inbox-only and clipboard choices return to the source if Beamhop still owns foreground focus. Exited sources, open Inbox/new panels, and the user's other foreground apps are left alone.
- Native delivery retains target focus. If delivery ends before any target activates, completion releases Beamhop's focus without racing another capture.
- The panel uses normal activating-window semantics alongside explicit app activation. Late resign-key notifications are checked against the current presentation and key-window state; repeat confirm/cancel callbacks are ignored.
- Capture requests are serialized at the app entry so asynchronous hotkeys do not race the duplicate gate.
- Inbox displays a chronological delivery/conclusion timeline, with result author, session, timestamp and verbatim text. Long conclusions show a 500-character preview with an explicit full-text expansion.
- List rows show result counts from one batched query. Selecting a capture beyond row 50 still loads its history and conclusions. The newest 100 conclusions load first; older results remain available through a load-more button.
- Selected detail refreshes every 2 seconds while the Inbox is key and on selection; gaining focus/manual Refresh reloads the list. Polling does not add visits/searches/views to dogfood metrics. Read errors are visible instead of leaving another selection's result behind.

## Verification

| Check | Outcome |
| --- | --- |
| `swift build` | Passed under local CLT / Swift 6.4 |
| `BeamhopSelfTest` | Passed, including new focus, external-write, selection, pagination, read-error and timeline cases |
| `scripts/mcp-smoke.sh` | Passed: initialize, fetch/search, save/fetch results, bad-origin FK rejection |
| Native `--ui-regression` | Passed with isolated temporary fixture processes and database |
| 20 consecutive native panel open/cancel cycles | Passed; source focus restored each time |
| Own-app capture | Rejected; seeded DB row count unchanged |
| Inbox-only / clipboard / Cowork clipboard | Source restored |
| Native destination / user click-away | Destination retained focus; cancel callback exactly once |
| Delayed older completion / Inbox key window | New panel and Inbox retained focus |
| External MCP process + second result writer, visible Inbox | Two distinct agents appeared through the refresh timer; badge updated |
| `swift test` | Blocked on this CLT-only Mac: missing `XCTest` module; mirror tests added for full Xcode/CI |
| `git diff --check` | Passed |

The fixture calls the actual panel model callbacks and AppKit activation APIs. It does not synthesize keyboard input, paste into real applications, register hotkeys, modify MCP configuration, or open the user's real Inbox. The repeated-window test waits for both NSWorkspace and NSApplication to complete each activation before beginning the next cycle; queuing redundant asynchronous fixture activations can otherwise interfere with the next cycle.

Reproduce after a debug build:

```bash
swift build
.build/debug/BeamhopSelfTest
scripts/mcp-smoke.sh
.build/debug/Beamhop --ui-regression /tmp/beamhop-focus-inbox-regression
```

The native harness writes `inbox-results.png` into the supplied preview directory and cleans its temporary database and fixture processes. It is compiled only in debug builds.

## Still requires real-device acceptance

- Chrome/IDE/Notes capture and delivery in a freshly packaged app with current Accessibility permission.
- Fullscreen, Stage Manager and multiple displays after the panel activation change.
- Real-source hotkey→visible-panel P95 and hotkey→agent timing. The historical 211ms result mostly sampled self-capture; current `panel_ms` excludes capture time. This regression does not claim to close that performance gate.
- XCTest/CI validation on a full-Xcode machine and formal signed distribution.

The unmerged remote `feat/phase15-detail-chain` branch was inspected for related timeline work. Its Pocket/Work, signing and target-selection changes were not merged as part of this fix.
