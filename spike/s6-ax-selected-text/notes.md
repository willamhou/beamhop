# S6 — AX selected-text probe

## Status: ⏳ BUILT, AWAITING MANUAL RUN
`axprobe` compiles clean (Mach-O arm64). Verification needs a human at the keyboard:
Accessibility + Input Monitoring permissions must be granted to the terminal, then
text selected in each of the 8 apps + Cmd+Shift+P pressed. See `test_protocol.md`.

## Hypothesis
AX API reliably reads app name, bundle id, window title, and selected text from
≥ 6 of 8 target apps (Safari, Chrome, Notes, Mail, Slack, VS Code, Cursor, iTerm).

## Pass criterion
≥ 6/8 return all four fields populated when text is selected in the foreground window.

## Result table (fill after run)
| app | bundle_id | window_title | selected_text | url | score /4 |
|---|---|---|---|---|---|
| Safari | com.apple.Safari | ? | ? | ? | ? |
| Chrome | com.google.Chrome | ? | ? | ? | ? |
| Notes | com.apple.Notes | ? | ? | – | ? |
| Mail | com.apple.mail | ? | ? | – | ? |
| Slack | com.tinyspeck.slackmacgap | ? | ? | – | ? |
| VS Code | com.microsoft.VSCode | ? | ? | – | ? |
| Cursor | com.todesktop.230313mzl4w4u92 | ? | ? | – | ? |
| iTerm | com.googlecode.iterm2 | ? | ? | – | ? |

## Aggregate: <X>/8 pass.

## Conclusion
[ ] PASS (≥6/8)  [ ] FAIL

## Spec patch
- §6.2 AX 能力表: update '可取得性' columns with measured values.
- Compatibility Matrix v0: per-app entries (apps that fail → "limited").
