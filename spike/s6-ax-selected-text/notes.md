# S6 — AX selected-text probe

## Status: 🟡 PARTIAL — full 8-app sweep done 2026-06-08
Accessibility granted to Terminal; race-proof read-only probe (`axprobe_once`: self-activate
→ wait until frontmost → one ⌘A → read; no Input Monitoring needed). All 8 apps installed.
Result: app/window/url captured 8/8; selected_text 4 clean PASS + Mail conditional + 3 LIMITED.
See the full table + per-app strategy below.

### ⚠️ Methodology caveat / incident
Synthetic `⌘A` is NOT representative for list-based apps (Mail/Notes list select rows, not
text). Worse: an attempt to type+undo into a live Notes window emptied a real user note;
it was fully recovered from the probe's captured output. **Lesson: never drive synthetic
keystrokes/undo into the user's live apps.** The production capture path is read-only AX
on the user's *own* manual selection (the original `AXProbe` hotkey design is the safe one).

## Findings — full 8-app sweep (2026-06-08, all 8 installed)

Method: race-proof read-only probe (self-activate → wait until frontmost → one ⌘A → read).
The 4 scored fields = app_name, bundle_id, window_title, selected_text.

| app | app_name | bundle_id | window_title | selected_text | url | role | score | verdict |
|---|---|---|---|---|---|---|---|---|
| Chrome  | ✓ | ✓ | ✓ | ✅ 4911 chars | ✅ | AXWebArea | 4/4 | **PASS** (needs AXManualAccessibility opt-in) |
| Notes   | ✓ | ✓ | ✓ | ✅ full (中文) | – | AXTextArea | 4/4 | **PASS** (native AppKit) |
| iTerm   | ✓ | ✓ | ✓ | ✅ 83 chars | – | AXTextArea | 4/4 | **PASS** (terminal text) |
| Slack   | ✓ | ✓ | ✓ | ✅ 191 chars (on sign-in page) | – | AXWebArea* | 4/4 | **PASS (capability)** — Chromium exposes it; tested signed-out |
| Mail    | ✓ | ✓ | ✓ | ❌ (⌘A hit message list) | – | AXTable | 3/4 | **CONDITIONAL** — list selected, not body; a body selection is native text → should pass |
| Safari  | ✓ | ✓ | ✓ | ❌ empty | ✅ | AXWebArea | 3/4 | **LIMITED** — web selection only via `AXSelectedTextMarkerRange`, not `kAXSelectedText` |
| VS Code | ✓ | ✓ | ✓ | ❌ empty | – | AXTextArea | 3/4 | **LIMITED** — Electron/Monaco not via `kAXSelectedText` |
| Cursor  | ✓ | ✓ | ✓ | ❌ empty | – | (welcome) | 3/4 | **LIMITED** — Electron/Monaco, same as VS Code |
| (TextEdit baseline) | ✓ | ✓ | ✓ | ✅ full (中文) | – | AXTextArea | — | proves native `kAXSelectedText` works |

### Aggregate
- **app_name + bundle_id + window_title: 8/8 reliably captured** (the core provenance fields).
- **selected_text via plain `kAXSelectedText`: 4 clean PASS** (Chrome, Notes, iTerm, Slack) +
  Mail conditional (needs body-not-list selection) + 3 LIMITED (Safari, VS Code, Cursor).
- vs the ≥6/8 bar: **strictly 4–5/8 out of the box → PARTIAL.** The shortfall is concentrated
  and has known fixes: Safari needs the text-marker API; Electron editors (VS Code/Cursor)
  need a different strategy (or clipboard fallback); Mail needs body-vs-list focus handling.

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

## Conclusion
[x] **PARTIAL** (4–5/8 full via plain `kAXSelectedText`; below the ≥6/8 bar but with a
concentrated, fixable shortfall). Per the plan's fail-handling, the LIMITED apps go to the
Compatibility Matrix as "limited" — this does NOT block the MVP gold path (Chrome capture is
a clean PASS).

### Per-app strategy for Beamhop (the actionable output)
- **Native AppKit (Notes, Mail body, TextEdit, most fields) + terminals (iTerm):** plain
  `kAXSelectedText` — ship as-is.
- **Chromium (Chrome, Slack, Arc/Brave/Edge):** set `AXManualAccessibility` first, then
  `kAXSelectedText` on the `AXWebArea` — works; also yields `AXURL`.
- **Safari:** provenance (app/window/url) works; for selected text use the
  `AXSelectedTextMarkerRange` text-marker API (extra work) OR fall back to clipboard.
- **Electron editors (VS Code, Cursor):** `kAXSelectedText` does NOT reflect Monaco's
  selection → fall back to clipboard handoff for these.
- **Mail:** ensure focus is the message body (native text), not the message list/table.

## Spec patch
- §6.2 AX 能力表: replace the per-app columns with the measured verdicts above + the
  per-app strategy; add an "AX 取词策略" note (native / Chromium-opt-in / Safari-marker /
  Electron-clipboard).
- Compatibility Matrix v0: per-app `selected_text` support = full / via-opt-in / limited.
- §6.x impl notes: query SYSTEM-WIDE focused element; set AXManualAccessibility on Chromium/Electron.

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
