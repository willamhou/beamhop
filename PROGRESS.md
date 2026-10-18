# Beamhop — Progress & Resume Guide (PROGRESS)

> Single entry point for "what's next". Records: where we are, what's verified, what's blocked, how to recover, what to do next.
> Last updated: 2026-10-18 — **Week 3 floating panel + Kimi Work delivery implemented AND user-verified on-device**.

> 🗂 Full pre-2026-10 history (Chinese) is archived at [docs/zh/PROGRESS.zh.md](docs/zh/PROGRESS.zh.md).

---

## 0. Status in one paragraph

Week 0–2 plus integration peripherals are done (CI green). **Week 3 is now implemented and machine-verified**: ⌘⇧Space grabs the frontmost app's context and pops a keyboard-first floating panel (⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork→clipboard / ⌘4 Kimi Work / ⌘0 Inbox-only; Enter delivers; Esc cancels and keeps the capture). Delivery coverage: Claude Code (MCP+paste), ChatGPT Desktop 26.x (set-value), Kimi Work 3.2.17 (clipboard-paste into a fresh chat), Cowork (clipboard fallback). Logic is covered by 86 SelfTest checks (incl. 40+ Week 3 checks). The app still ships as a SwiftPM-assembled `dist/Beamhop.app` (ad-hoc signed); migrating to a real Xcode project is gated on accepting the Xcode license (`sudo xcodebuild -license accept`) so `swift test`/XCTest can run.

**Blockers**: ① Xcode license not accepted → no XCTest, no signed builds; ② ad-hoc signing means every repack needs the Accessibility grant re-enabled in System Settings.

---

## 1. Stage table

| Stage | Status | Verification |
|---|---|---|
| Week 0 spike S1–S6 | ✅ done | on-device + 2 codex review rounds; written back into spec V2.1 |
| Week 1 foundation | ✅ done | `BeamhopSelfTest` green + app boots & creates DB |
| Week 2A golden path | ✅ done | real Claude Code over MCP; rest compile+selftest |
| Week 2B browser bridge | ✅ done | 3-hop bridge + Readability + GitHub, all CDP-automated |
| Integration peripherals | ✅ CI-verified | ChatGPT injection, Inbox/first-run/matrix UI, packaging, CI |
| Review hardening P1/P2 | ✅ merged | PR #2 (off-main capture, FK v2 migration, BFS fix) |
| CI/CD | ✅ in place | 3 required checks, main artifact, `v*` releases, branch protection |
| **Week 3 floating panel** | ✅ **done + verified** | user-verified on-device 2026-10-18 (panel, dedup, Kimi, ChatGPT v26) |
| `swift test` (XCTest) | ⬜ blocked | needs Xcode license accepted |
| Xcode project + signed build | ⬜ blocked | same as above |

---

## 2. Key docs (read in order)

> ⚠️ **Iron rule: `git fetch` and align with origin before starting work on any machine** (lesson of the 2026-09 two-machine divergence; see the engineering-convergence spec §5).

- **MVP design spec (source of truth, V2.1)**: [docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — Chinese original, translation pending
- **Week 3 floating-window spec + plan**: [docs/superpowers/specs/2026-09-18-week-3-floating-window.md](docs/superpowers/specs/2026-09-18-week-3-floating-window.md) + [docs/superpowers/plans/2026-09-18-week-3-implementation.md](docs/superpowers/plans/2026-09-18-week-3-implementation.md)
- **Engineering convergence (2026-09)**: [docs/superpowers/specs/2026-09-14-engineering-convergence.md](docs/superpowers/specs/2026-09-14-engineering-convergence.md) — branch model / two-machine split / acceptance gates
- **Evolution decisions (2026-09)**: [docs/superpowers/specs/2026-09-14-evolution-decisions.md](docs/superpowers/specs/2026-09-14-evolution-decisions.md) — Xcode timing / Phase 2 memory / Phase 3 triggers
- **Roadmap**: [docs/superpowers/roadmap.md](docs/superpowers/roadmap.md)
- **Spike results + compatibility matrix**: [spike/results.md](spike/results.md) + [spike/compatibility-matrix-v0.json](spike/compatibility-matrix-v0.json)

---

## 3. Recover / quick verify (SwiftPM, Command Line Tools)

```bash
cd /Users/leo/Documents/Kimi/Workspaces/beamhop
export DEVELOPER_DIR=/Library/Developer/CommandLineTools   # needed while Xcode license is unaccepted
swift build                 # build all targets (incl. GRDB)
swift run BeamhopSelfTest   # 86 checks, expect ALL PASS ✅
./packaging/build-app.sh    # assemble dist/Beamhop.app
open dist/Beamhop.app       # grant Accessibility again after every repack (ad-hoc signature)
```

**MCP server smoke (real protocol):**
```bash
DB=/tmp/x.sqlite; swift run BeamhopSelfTest --seed "$DB"
BIN=$(swift build --show-bin-path)/BeamhopMCP
claude mcp add beamhop -s user -- "$BIN" --db "$DB"   # ✓ Connected
claude mcp remove beamhop -s user
```

**Perf numbers (Week 3 acceptance)**: `capture_ms` and `panel_ms` are logged with fixed field names; P95 = `log show --predicate 'subsystem == "com.beamhop.app"' | grep panel_ms` over 20 consecutive presses, take the 95th percentile (spec budget: panel_ms P95 ≤ 300ms).

---

## 4. Code structure (SwiftPM)

```
Package.swift
Sources/
  BeamhopCore/                 # testable logic (no AppKit; depends on GRDB)
    Models/      Capture, Delivery, Source/DomainHint/DeliveryTarget
    Storage/     Database (WAL + openReadOnly + corruption recovery), migrations (dual FTS5+triggers),
                 CaptureStore (CRUD+search), CaptureReader (read-only)
    Capture/     AppBlacklist, DuplicateGate (W3-4 <500ms same-window re-press guard)
    Delivery/    PromptRenderer (trigger/full markdown) — moved from app for testability
    Panel/       CapturePanelModel, PanelShortcut (⌘0-4 single source), TargetMemory
    Support/     AppPaths, Version, ULID
  Beamhop/                     # menu-bar app (AppKit)
    App/         main.swift (incl. --bridge-test), AppDelegate, AppServices (DI + panel wiring),
                 MenuBarController, Notifier, FirstRunWindow
    Hotkeys/     HotkeyManager (Carbon RegisterEventHotKey — no Input Monitoring needed)
    Permissions/ PermissionService, AXHelper (system-wide focus + AXManualAccessibility + timeouts)
    Capture/     CaptureService (assembles Capture + provenance + per-app policy + blacklist + dedup)
    Delivery/    AXComposerFinder (shared Electron composer locator, Electron-43 aware),
                 AppActivator, ChatGPTDelivery (v26 dual bundle-id), KimiDelivery (AX+paste),
                 ClaudeCodeDelivery, ClipboardService (§12.3 safe paste + safePasteOnly),
                 DeliveryService (routing + clipboard fallback + completion callback)
    Panel/       CapturePanelController (NSPanel), CapturePanelView (SwiftUI keyboard-first)
    Bridge/      BrowserBridgeServer (unix socket)
    Diagnostics/ DiagnosticsService, DiagnosticsWindow
    Inbox/       InboxWindow
    Compatibility/ CompatibilityMatrix
  BeamhopMCP/    main.swift    # own MCP server (stdio, read-only on inbox.sqlite, --db override)
  BeamhopSelfTest/ main.swift  # XCTest-free runner + --seed helper (CLT has no XCTest)
Tests/BeamhopCoreTests/        # XCTest mirror (runs once Xcode license is accepted)
host/            main.swift     # native messaging host, pure frame relay Chrome<->app socket
extension/       manifest.json, background.js, vendor/readability.js, build/ (esbuild source)
```

---

## 5. Verified vs pending

**Verified:**
- ✅ Data layer: dual FTS5 (unicode61+trigram), soft delete, corruption recovery, 10k ULID uniqueness (`BeamhopSelfTest`)
- ✅ MCP server against real Claude Code (`fetch_capture` returns a real capture)
- ✅ 3-hop browser bridge end-to-end; Readability body extraction (CDP-automated)
- ✅ **Week 3 on-device (2026-10-18, user-verified)**: panel appears on ⌘⇧Space; target shortcuts; Enter/Esc semantics; <500ms same-window dedup (silent); Kimi Work paste-into-fresh-chat; ChatGPT v26 set-value injection; Inbox-only (⌘0) keeps capture
- ✅ Logic: 86 SelfTest checks green (DuplicateGate, PanelShortcut, TargetMemory, PromptRenderer, panel model, raw values)

**Pending:**
- ⬜ `swift test` / XCTest (blocked on Xcode license)
- ⬜ Cowork MCPB end-to-end (S2 mechanism confirmed only)
- ⬜ AX word-grab re-test across 8 apps (per-app policy from S6)
- ⬜ Week 3 perf P95 measurement session (20 presses, method in §3)

---

## 6. Pitfalls & decisions (do NOT re-learn these)

From Week 0 spikes + 4 codex review rounds + 2026-10 on-device debugging, all encoded in code:
- **MCP stdio = newline-delimited JSON + non-blocking POSIX reads** (`FileHandle.read(upToCount:)` times out at 30s). Register with `claude mcp add <name> -s user -- <abs-bin>` (no `--command`, `-s user` is mandatory, path must be stable — not `.build`).
- **Native messaging: host→extension ~1MB hard cap**; browser→host→app is allowed up to 4GB, so capture itself needs no chunking. app→extension >1MB chunking is a defensive TODO.
- **Custom `--user-data-dir`: native host manifest must also go into `<profile>/NativeMessagingHosts/`**. Chrome 137+ blocks `--load-extension` → automate via CDP pipe + `Extensions.loadUnpacked`.
- **WAL must be set with `writeOutsideTransaction`** (errors inside a transaction); WAL data lives in `-wal` — corruption simulation must delete `-wal/-shm` too. MCP uses `Database.openReadOnly` (no migration/recovery/creation).
- **AX: query the system-wide focused element** (`AXUIElementCreateSystemWide`); Chromium/Electron apps need `AXManualAccessibility` opt-in first; always `AXUIElementSetMessagingTimeout`.
- **Electron 43 (Kimi 3.2.17, 2026-10): `AXWindows` stays EMPTY even with a visible window — and the app element's subtree exposes only menu bars.** Resolve the window via `AXFocusedWindow`/`AXMainWindow` and BFS from there (`AXComposerFinder.resolveWindow`). Activating the app publishes the window lazily (~200ms) — poll, don't check once (`waitForWindow`).
- **ChatGPT 26.x: composer at AX depth ~30, `AXEditable` no longer exposed** (two-pass candidate logic in `AXComposerFinder`); bundle ids are now `com.openai.chat`/`com.openai.codex` (dual match). Set-value injection still works.
- **Kimi editor: kAXValueAttribute set-value returns success but does NOT take effect** (placeholder pollution) → inject by focusing the composer + clipboard paste (`safePasteOnly`, no Enter). New chat via sidebar button `desc="新建会话"`.
- **Windows/panels: `isReleasedWhenClosed = false`** (the red close destroys the window and the hotkey can never reopen it — S5).
- **Global hotkeys: Carbon `RegisterEventHotKey`** (no Input Monitoring permission; check the OSStatus for conflicts).
- **TCC binds signature identity + path**: ad-hoc-signed rebuilds change the cdhash → the Accessibility grant silently drops. Every `./packaging/build-app.sh` + restart requires re-enabling Beamhop in System Settings. A self-signed codesigning cert would stabilize this but openssl-generated certs would not pair into a usable identity in the login keychain (attempted 2026-10-18, reverted).
- **Clipboard safe paste (§12.3)**: store raw Data per item/per type, refuse if unreadable; only ClaudeCodeDelivery restores; the clipboard fallback handoff does not.
- **auto-Enter only when "the located terminal is frontmost + claude is running"**, else let the user confirm (never Enter into the wrong window).
- ⚠️ **Incident**: during S6 testing, scripted synthetic keystrokes + undo were sent into the user's real Notes and wiped one note (recovered). **Never send synthetic keys/undo into the user's real apps**; capture is read-only AX.
- **`plutil -lint` only accepts XML/binary plists, exits 1 on JSON** — validate JSON with `plutil -convert json -o /dev/null <file>`. Swift has no imported constant for `"AXEditable"` — use the raw string.
- **`.build/release` is a symlink to the triplet dir** — `find` doesn't follow a symlinked start point; use `find -H`. CI's `TMPDIR` has a trailing slash → `//` paths; normalize with the same `cd+pwd` on both sides of path assertions.
- **`pbpaste` in a `LANG=C` shell mangles UTF-8** (looks like an encoding bug, is only terminal display) — use `LANG=en_US.UTF-8 pbpaste` before debugging "corruption".
- **"Hotkey sometimes works" symptom checklist**: check the log for which PID logged the failure (old process vs current), and whether presses landed in a restart gap (`log show --predicate 'processID == <pid>'`).

---

## 7. Next steps (dependency-ordered)

**A. Unblock formal engineering (user action, ~2 min)**
1. `sudo xcodebuild -license accept` → unlocks `swift test`, XCTest mirror, real signing.
2. Then: Developer ID signing for `dist/Beamhop.app` (kills the repack-regrant cycle).

**B. Perf & acceptance closure (Week 3 leftovers)**
- 20-press P95 measurement for `capture_ms`/`panel_ms` (method in §3) → record in this file.
- Re-run AX word-grab spot checks on the 8 S6 apps.

**C. Product candidates (pick after a week of dogfood)**
- Prompt-injection language: panel chrome is now English; the injected prompt text (`PromptRenderer`) is still Chinese — decide per target/agent.
- Wire `zh-Hans` UI translation back into the app bundle (translations archived at `packaging/lproj/zh-Hans.lproj/`) behind a language toggle.
- Cowork MCPB end-to-end.

**D. Phase 2 prerequisite (after Week 3 + acceptance + two weeks of dogfood)**
- One-hour evaluation per the evolution-decisions spec §2.3 (personal-model review + dogfood signals) → pick the memory route → kick off.

---

## 8. Week 3 acceptance record (2026-10-18, on-device)

User-verified this session:
1. ⌘⇧Space pops the panel (after Accessibility re-grant on the fresh build) ✅
2. Target shortcuts ⌘1–⌘4 + ⌘0 present and selectable ✅
3. Enter delivers, Esc cancels (capture kept in Inbox) ✅
4. Kimi Work: paste lands in a fresh conversation, placeholder untouched ✅
5. ChatGPT Desktop v26: set-value injection into composer ✅
6. Failure fallback → clipboard + notification (Kimi/ChatGPT window closed case) ✅
7. Duplicate <500ms same-window press swallowed silently ✅

Perf P95: ⬜ pending a 20-press session (method in §3).

Compatibility matrix updated: `spike/compatibility-matrix-v0.json` — chatgpt_desktop versions_tested += 26.1007.71326 (dual bundle id, AXEditable gone, composer depth ~30, set-value OK); kimi_work added (paste-injection mechanism, new-chat button desc).
