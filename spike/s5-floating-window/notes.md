# S5 — Floating window across Spaces

## Status: ⏳ BUILT, AWAITING MANUAL RUN
`FloatingDemo` compiles clean. Run it, then walk the 5 scenarios below at the keyboard.

```bash
cd spike/s5-floating-window/FloatingDemo
./.build/release/FloatingDemo &
# A "✦" appears in the menu bar. Toggle the overlay with Cmd+Shift+Space.
# When done: pkill FloatingDemo
```
Note: macOS may prompt for **Accessibility / Input Monitoring** the first time the global
hotkey is registered — grant it. If Cmd+Shift+Space collides with another shortcut, use the
menu-bar "Show overlay" item to test visibility instead.

## Hypothesis
A window with `level=.floating` + `collectionBehavior=[.canJoinAllSpaces,
.fullScreenAuxiliary, .stationary]` is visible AND keyboard-focusable in: full-screen
apps, Stage Manager on, and multi-display.

## Test matrix (fill after run)
| Scenario | Visible | Keyboard focus | Hotkey toggles | Notes |
|---|---|---|---|---|
| A: normal desktop | ? | ? | ? | |
| B: full-screen Safari | ? | ? | ? | |
| C: full-screen VS Code | ? | ? | ? | |
| D: Stage Manager | ? | ? | ? | |
| E: dual display | ? | ? | ? | |

## Conclusion
[ ] PASS (all 5)  [ ] PARTIAL (specify)  [ ] FAIL

## Spec patch
- §9.1 浮窗 window-level 配置: confirm chosen flags; if any scenario fails, add degradation note.
- §11 边界情况清单: append observed edge cases.
