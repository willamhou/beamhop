# Week 0 Spike — Status (2026-06-07)

| # | Spike | Status | What's left |
|---|---|---|---|
| S1 | Claude Code MCP register | ✅ **PASS** (verified end-to-end) | nothing — done |
| S4 | Chrome native messaging | 🟡 built + process-verified | load extension in Chrome + click buttons |
| S5 | Floating window | 🟡 built | run app + walk 5 scenarios |
| S6 | AX selected-text | 🟡 built | grant permissions + select text in 8 apps |
| S3 | ChatGPT Desktop AX | 🚧 blocked | `brew install --cask chatgpt`, then run probes |
| S2 | Cowork connector | 🚧 research done, runtime blocked | `brew install --cask claude`, verify `.mcpb` flow |

Everything in `spike/` is throw-away (per spec §14.3).

## S1 headline findings (already written back-ready)
- Registration works one-shot, but **two spec corrections** were needed and are baked into
  the spike code:
  1. CLI syntax is `claude mcp add <name> -- <abs-bin>` — there is **no `--command` flag**.
  2. The stdio server must speak **newline-delimited JSON** (not Content-Length framing)
     and must use a **non-blocking read** (POSIX `read`, not `FileHandle.read(upToCount:)`),
     or Claude's client times out at 30s. Both native hosts (S1, S4) now do this.
- Local-scope config is keyed by the **git repo root** and stores an **absolute** binary
  path → the real product needs a stable install location.

## Remaining manual steps (when you're at the Mac)

### S6 — AX probe (do this first; it's core to capture)
1. System Settings → Privacy & Security → **Accessibility** AND **Input Monitoring** →
   enable your terminal; quit & reopen it.
2. `cd spike/s6-ax-selected-text && swiftc -O AXProbe.swift -o axprobe -framework Cocoa -framework ApplicationServices`
3. `./axprobe | tee results.jsonl`, then follow `test_protocol.md` (select text + Cmd+Shift+P in each of 8 apps).
4. Fill the table in `s6-ax-selected-text/notes.md`.

### S4 — Chrome native messaging
1. `cd spike/s4-chrome-native-messaging/host && swiftc -O main.swift -o beamhop-bridge`
2. Chrome → chrome://extensions/ → Developer mode → Load unpacked → `extension/`; copy the ext ID.
3. `./install.sh <EXT_ID>` (from `host/`), reload the extension, click Ping / 900KB / benchmark.
4. Fill `s4-chrome-native-messaging/notes.md`.

### S5 — Floating window
1. `cd spike/s5-floating-window/FloatingDemo && swift build -c release && ./.build/release/FloatingDemo &`
2. Toggle with Cmd+Shift+Space across: normal desktop, full-screen Safari, full-screen VS Code,
   Stage Manager, dual-display. Fill `s5-floating-window/notes.md`. `pkill FloatingDemo` when done.

### S3 — ChatGPT Desktop (after install)
`brew install --cask chatgpt`, then see `s3-chatgpt-ax/notes.md` "To unblock".

### S2 — Cowork (after install)
`brew install --cask claude`, then see `s2-cowork-connector/notes.md` "To unblock";
verify the `.mcpb` desktop-extension install flow described in `research.md`.

## Then: Task 7 (synthesis)
Once the manual results are in, run plan Task 7 → write `spike/results.md` +
`spike/compatibility-matrix-v0.json` + the V2.1 spec/roadmap edits.
