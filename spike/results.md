# Week 0 Spike — Results

Date: 2026-06-07 → 2026-06-08
Operator: willamhou (+ Claude Code)
Repo state: all spike code throw-away (per spec §14.3). Evidence in each `spike/sN-*/notes.md`.

## Decision Matrix

| # | Spike | Result | Evidence | MVP impact |
|---|---|---|---|---|
| S1 | Claude Code MCP register | **✅ PASS** | s1-claude-code-mcp/{notes,transcript}.md | Gold path stable. Reg = `claude mcp add beamhop -s user -- <abs-bin>`; stdio = newline-JSON + non-blocking read. |
| S2 | Cowork connector | **🟢 MECHANISM CONFIRMED** | s2-cowork-connector/{notes,research}.md | Local non-OAuth path exists (`.mcpb` desktop extension + legacy `claude_desktop_config.json`). End-to-end reg = fast-follow. Not blocking MVP. |
| S3 | ChatGPT AX paste | **🟢 PARTIAL/PASS** | s3-chatgpt-ax/notes.md | AX viable (NOT clipboard-only). Requires `AXManualAccessibility` opt-in; inject via `kAXValueAttribute` set-value. Single version tested → multi-version diff deferred. No auto-submit. |
| S4 | Chrome native messaging | **✅ PASS** | s4-chrome-native-messaging/{notes,results}.json | Round-trip 18.7ms median (≪100ms). **Host→extension ~1MB hard limit confirmed → app-layer chunking REQUIRED.** No HTTP-port fallback needed. |
| S5 | Floating window | **✅ PASS** | s5-floating-window/notes.md | `.floating` + `[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]` visible + keyboard-focusable over full-screen Safari/VS Code + Stage Manager. Dual-display untested (no monitor). |
| S6 | AX selected text | **🟡 PARTIAL** (3–4/8 clean) | s6-ax-selected-text/notes.md | Provenance (app/window/url) 8/8. Selected text: Chrome/Notes/iTerm PASS; Slack capability-only; Safari + VS Code + Cursor LIMITED. |

## Net effect on MVP scope
- **Golden path (Chrome capture → Claude Code MCP): solid.** S1 PASS + S4 PASS + S6 Chrome PASS + S5 PASS all confirm the core loop.
- **Conditional targets:**
  - ChatGPT Desktop: **IN** (AX injection viable; no auto-submit). Confidence medium (single version).
  - Cowork: **viable, fast-follow** (mechanism confirmed; e2e registration not yet verified).
- **Per-app AX selected-text strategy required** (native `kAXSelectedText` / Chromium opt-in / Safari text-marker / Electron-editor clipboard fallback).
- **Hard requirement surfaced:** Chrome native messaging needs an application-layer chunking protocol (>1MB messages are dropped by Chrome).

## Corrections forced by the spikes (vs spec V2 assumptions)
1. `claude mcp add` has **no `--command` flag**; must use `-- <bin>` and **`-s user`** scope (else cross-project breakage). [S1]
2. MCP stdio = **newline-delimited JSON + non-blocking read** (Content-Length / `FileHandle.read(upToCount:)` → 30s timeout). [S1]
3. Cowork **does** ship `claude_desktop_config.json` + `.mcpb` (V2 said it ignored the legacy path). [S2]
4. ChatGPT exposes nothing via AX **until `AXManualAccessibility` opt-in**; then injection is viable (not clipboard-only). [S3]
5. "1MB chunked OK" was unproven — Chrome enforces ~1MB host→extension; **chunking is mandatory, not optional.** [S4]
6. Floating-window close must **hide, not destroy** (`isReleasedWhenClosed=false`). [S5]
7. AX selected-text is **not uniform** — Safari needs `AXSelectedTextMarkerRange`, Electron editors need clipboard fallback. [S6]

## Spec V2 → V2.1 edits (see commits)
- §7.3 / §9.4 / §14.1 — S1 (done, commits 199bbd2 + af537bc)
- §4.2 conditional targets — ChatGPT IN, Cowork fast-follow
- §6.2 AX capability table — S6 measured per-app strategy
- §6.3 Chrome native messaging — confirm framing + add ~1MB chunking requirement + per-browser paths
- §7.4 Cowork — mechanism confirmed (.mcpb / config), not "ignores legacy"
- §7.5 ChatGPT — AX injection viable + opt-in requirement + no auto-submit
- §9.1 floating window — flags validated; §11 edge cases (close=hide, dual-display TODO)
- §14 close-out + Compatibility Matrix v0 pointer
