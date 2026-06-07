# S6 — AX selected-text probe

## Status: 🟡 PARTIAL — automated probe run 2026-06-07 (5/8 apps installed)
Accessibility granted to Terminal; ran a race-proof one-shot probe (`axprobe_once`, no
hotkey → no Input Monitoring needed) that self-activates each app, waits until it's truly
frontmost, sends ⌘A, then reads. Slack / Cursor / iTerm were NOT installed → only 5/8 tested.

### ⚠️ Methodology caveat / incident
Synthetic `⌘A` is NOT representative for list-based apps (Mail/Notes list select rows, not
text). Worse: an attempt to type+undo into a live Notes window emptied a real user note;
it was fully recovered from the probe's captured output. **Lesson: never drive synthetic
keystrokes/undo into the user's live apps.** The production capture path is read-only AX
on the user's *own* manual selection (the original `AXProbe` hotkey design is the safe one).

## Findings (what actually works)

| app | bundle_id | app_name | window_title | selected_text | url | focused_role | verdict |
|---|---|---|---|---|---|---|---|
| Chrome | ✓ | ✓ | ✓ | ✅ full page text | ✅ | AXWebArea | **PASS** (needs AXManualAccessibility opt-in) |
| Notes | ✓ | ✓ | ✓ | ✅ full note text (incl. 中文) | – | AXTextArea | **PASS** (native AppKit text) |
| Safari | ✓ | ✓ | ✓ | ❌ empty | ✅ | AXWebArea | **LIMITED** — web selection only via `AXSelectedTextMarkerRange`, not `kAXSelectedText` |
| VS Code | ✓ | ✓ | ✓ | ❌ empty | – | AXTextArea | **LIMITED** — Electron/Monaco selection not exposed via `kAXSelectedText` |
| Mail | ✓ | ✓ | ✓ | ❌ (list) | – | AXTable | **INCONCLUSIVE** — ⌘A hit message list; selecting in a message body (native text) should work |
| (TextEdit, baseline) | ✓ | ✓ | ✓ | ✅ full (incl. 中文) | – | AXTextArea | proves native `kAXSelectedText` works |
| Slack | – | – | – | – | – | – | not installed |
| Cursor | – | – | – | – | – | – | not installed (Electron → expect LIMITED like VS Code) |
| iTerm | – | – | – | – | – | – | not installed |

### Critical implementation details for Beamhop (the real value of this spike)
1. **Query the SYSTEM-WIDE focused element** (`AXUIElementCreateSystemWide()` →
   `kAXFocusedUIElementAttribute`), NOT the app element — the app-element query returned nil
   for most apps.
2. **Chromium/Electron need an AX opt-in**: set `AXManualAccessibility` (and
   `AXEnhancedUserInterface`) = true on the app element, or they expose almost nothing.
   With it, Chrome exposes full `AXWebArea` text + `AXURL`.
3. **Safari is special**: exposes `AXWebArea` + `AXURL` but its text selection is only
   reachable via the `AXSelectedTextMarkerRange` / text-marker API — extra work; plain
   `kAXSelectedText` returns empty.
4. **Native AppKit text fields/areas** (TextEdit, Notes, presumably Mail compose & message
   body, plain `NSTextField`/`NSTextView`): `kAXSelectedText` works directly, Unicode-safe.
5. URL is available via the `AXURL` attribute on web areas (Chrome + Safari confirmed).

## Aggregate (preliminary): 2 clean PASS (Chrome, Notes) + native baseline (TextEdit) proven.
Cannot reach the formal ≥6/8 bar without (a) installing Slack/Cursor/iTerm and (b) testing
with real in-content text selections (not synthetic ⌘A). Safari & Electron need the special
handling noted above to count as full.

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
