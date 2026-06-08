# S5 — Floating window across Spaces

## Status: ✅ PASS — manual scenarios run 2026-06-08 (4/5; dual-display N/A, no external monitor)
The `.floating` + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` config works as
hypothesized: the overlay shows ABOVE full-screen apps and takes keyboard focus, including
Stage Manager. Carbon global hotkey ⌘⇧Space (no Input Monitoring needed). No permission prompts.

## Hypothesis
A window with `level=.floating` + `collectionBehavior=[.canJoinAllSpaces,
.fullScreenAuxiliary, .stationary]` is visible AND keyboard-focusable in: full-screen
apps, Stage Manager on, and multi-display.

## Test matrix (measured)
| Scenario | Visible | Keyboard focus | Hotkey toggles | Notes |
|---|---|---|---|---|
| A: normal desktop | ✓ | ✓ | ✓ | |
| B: full-screen Safari | ✓ | ✓ | ✓ | overlay composites above the full-screen space |
| C: full-screen VS Code | ✓ | ✓ | ✓ | Electron full-screen behaves same as native |
| D: Stage Manager | ✓ | ✓ | ✓ | shows across stages |
| E: dual display | — | — | — | not tested — only the built-in display present |

## Conclusion
[x] **PASS** (all 4 testable scenarios). Dual-display deferred (no external monitor).
The chosen window level + collection behaviors are validated for full-screen + Stage Manager;
no "exit full-screen first" degradation is needed for these cases.

## ⚠️ Implementation finding (codex + manual)
- **Close button must hide, not destroy.** The demo initially used `styleMask:[.titled,.closable]`
  with NSWindow's default `isReleasedWhenClosed = true`: clicking the red X released the window,
  and the hotkey could no longer re-show it. Fix = `isReleasedWhenClosed = false` (or intercept
  close → orderOut, or drop `.closable`). The real overlay must HIDE on close, never deallocate.
- Other codex notes for the real impl: check `RegisterEventHotKey` return (surface hotkey
  conflicts); implement the advertised Esc-to-dismiss; avoid `NSApp.activate(ignoringOtherApps:)`
  stealing focus — prefer an `NSPanel` (nonactivating where appropriate) + window-mode state machine.

## Spec patch
- §9.1 浮窗 window-level 配置: confirm flags `.floating` + `[.canJoinAllSpaces,
  .fullScreenAuxiliary, .stationary]` — validated for full-screen Safari/VS Code + Stage Manager.
- §11 边界情况清单: add "overlay close = hide not destroy (isReleasedWhenClosed=false)";
  "dual-display behavior unverified — test on multi-monitor before GA".
