# Beamhop — Progress & Resume Guide (PROGRESS)

> Single entry point for "what's next". Records: where we are, what's verified, what's blocked, how to recover, what to do next.
> Last updated: 2026-10-20 — active development on `feat/phase15-detail-chain`; compact handoff and native macOS verification from Windows. See the current follow-up below for present behavior; older acceptance records are historical.

> 🗂 Full pre-2026-10 history (Chinese) is archived at [docs/zh/PROGRESS.zh.md](docs/zh/PROGRESS.zh.md).

---


## Current follow-up: compact handoff (2026-10-20)

**Signing credential remediation:** GitGuardian found a fixed default password in the earlier development-keychain setup and packaging scripts. The current scripts require hidden interactive input or an explicitly supplied secret, do not trace/export it to child commands, and stop on explicit unlock failure. Seven isolated command-stub regression cases cover these paths. The owner approved feature-history cleanup: 23 of 25 commits were rewritten, with the final file tree unchanged. [GitGuardian on `97ea92e`](https://github.com/willamhou/beamhop/pull/7/checks?check_run_id=118436760729) scanned all 25 commits and reported **No secrets detected**. The signing regression tests and ShellCheck also passed in hosted CI. Mac-side password rotation has not been performed from this Windows session and is still required wherever the former default was used. See [remediation instructions](docs/dev-signing-security.md).

Active development branch: `feat/phase15-detail-chain`. On 2026-10-20 the user directed the compact-handoff fixes from `codex/refine-capture-workflow` to be integrated here and further development to continue on this feature branch. Refine and validate it before opening a PR to `main`. The fixes originated from `4007bc0` and were integrated by fast-forward through `c5fab72`. User selected a compact shortcut panel with destinations disclosed on demand. The corner pocket remains optional.

Implemented: nonactivating keyboard-capable panels; content-driven sizing; full destination label with a native menu; explicit handling of unavailable receivers; preserved manual shelf destinations; protection against stale binding confirmations; compact destination menu and optional naming; recent named destinations; selection-based corner panel; a single combined payload per handoff; work-intent preservation (v7 migration); recovery without clearing pending selections; serialized delivery; draft protection; no automatic Kimi new chat or terminal Enter; separate copied/prepared receipts; corrected destination acknowledgment and memory. Details and Mac acceptance: [compact handoff](docs/superpowers/specs/2026-10-20-compact-handoff.md).

Validation: macOS CI passed for `fde3a97` ([run 39360579032](https://github.com/willamhou/beamhop/actions/runs/39360579032)): build, XCTest, SelfTest, MCP/native-host smoke checks, app packaging, extension and shell checks. The production app also ran on macOS 15.7.9: **152/152 native UI assertions passed** (38 each in English/Chinese, light/dark), with 20 PNGs reviewed. Evidence covers actual key focus and editor input, the accessible destination button opening its native menu, menu selection without dismissal, source-app nonactivation, replacement-draft recovery, selection retention and failed/successful handoff state. CI provides the gallery/reports and a downloadable development app; see [native verification](docs/native-ui-verification.md).

Integration acceptance remains pending for logged-in agent apps, TCC capture, VoiceOver speech, fullscreen/Stage Manager and multiple displays. Named works still bind apps, not exact agent sessions; app injection still brings the receiver forward for manual review. Earlier “machine-verified” claims below describe the October 19 implementation, not the current integration paths.

## 0. Historical baseline before the October 20 compact-handoff changes

Week 0–2 plus integration peripherals are done (CI green). **Week 3 is now implemented and machine-verified**: ⌘⇧Space grabs the frontmost app's context and pops a keyboard-first floating panel (⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork→clipboard / ⌘4 Kimi Work / ⌘0 Inbox-only; Enter delivers; Esc cancels and keeps the capture). Delivery coverage: Claude Code (MCP+paste), ChatGPT Desktop 26.x (set-value), Kimi Work 3.2.17 (clipboard-paste into a fresh chat), Cowork (clipboard fallback). Logic is covered by 198 SelfTest checks. **MCP write-back (plan A) + search dedup merged 2026-10-18** (stage table below). **Product essays 01/02 implemented 2026-10-19** (from the pages branch thinking): essay 01 「先留着」 — ⌘5 parks capture+note+intended target in a `pocket_items` stack (`PocketStore`), ⌘⇧P pocket window delivers the stack in hold order (serial, failure keeps the item); essay 02 two-layer destinations — named works (`works` table: work name over a bound receiving session) with `⌘5 先留着` / two-step rebind confirmation: an in-panel receiver change under a confirmed work, or a stored unconfirmed rebind, makes the first Enter acknowledge the new address and only the second deliver. Both machine-verified 2026-10-19. **UI pass 2026-10-19 (dogfood feedback)**: panel slimmed (460pt, single-row instruction+work-name inputs, inline two-layer destination line, no "Deliver to" caption); ⌘3 is Clipboard (the self-deceiving "Cowork → clipboard" is gone — `.cowork` keeps API-level existence for S2 but no panel slot); the panel only offers destinations that are REAL on the machine (`TargetAvailability` + `TargetDetector`: Claude CLI / ChatGPT (either bundle id) / Kimi / clipboard-always), with graceful fallback when a remembered target vanishes; held items now surface as a bottom-right HUD chip (「口袋 · N ⌘⇧P」, hides when empty, click opens the pocket window, which itself anchors bottom-right). SelfTest 206 checks. **Dogfood instrumentation (Phase 1.5)**: an append-only local `events` table + `deliveries.duration_ms` feed `scripts/dogfood-metrics.sh`, which prints the evolution-decisions §3 gate table (press frequency, delivery success, Inbox accumulation/revisits, readable failures, panel P95) — all local, never leaves the machine. The app still ships as a SwiftPM-assembled `dist/Beamhop.app` (ad-hoc signed); `swift test`/XCTest work on machines with the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, CI runs them on macos-15); the original dev Mac still has CLT only.

**Blockers**: ① signed distribution needs a machine with Xcode + Developer ID signing; ② ~~ad-hoc signing means every repack needs the Accessibility grant re-enabled~~ **SOLVED 2026-10-19** — repacks now sign with the stable self-signed "Beamhop Sign" identity (TCC anchors the grant to the certificate, verified DR-stable across repacks); the remaining one-time grant uses `scripts/tcc-grant-runbook.md` (needs the screen unlocked once).

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
| **MCP write-back (plan A)** | ✅ **done + on-device verified** | `save_result`/`fetch_results`/`search_captures` + `results` table (v4 migration, FK cascade — renumbered from v3 at merge, see Migrations.swift note); decision record `docs/superpowers/specs/2026-10-18-memory-mcp-decision.md`; SelfTest + mcp-smoke green; real Claude Desktop session e2e 2026-10-18: fetch_capture → search_captures(deduped) → save_result → conclusion in Inbox, agent=claude_desktop |
| **MCP search dedup** | ✅ implemented + verified on real Inbox | `search_captures` collapses re-captures by `contentIdentity` (app+title+url+text, exact); each hit = newest of group + `duplicate_count`/`first_seen_at`/`last_seen_at`; `include_duplicates=true` for raw list. Real Inbox: "beamhop" 10 raw hits → 4 groups |
| `swift test` (XCTest) | ✅ unblocked (2026-10-18) | works locally with the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`) — the "license" blocker was stale; mirror kept in sync with SelfTest from now on |
| **Inbox detail chain (Timeline)** | ✅ implemented + tested (visual check pending unlock) | spec `docs/superpowers/specs/2026-10-19-inbox-detail-chain.md`; `TimelineBuilder` (Core, pure) merges deliveries+results ascending, tie → delivery first; Inbox detail renders unified Timeline, list rows show `↩ N` badge; SelfTest +7 / XCTest mirror +1 (29 total) |
| **Stable dev signing ("Beamhop Sign")** | ✅ done, fully headless | `scripts/setup-dev-signing.sh` (dedicated keychain + self-signed cert + partition list) + `packaging/build-app.sh` auto-detect; DR = `certificate leaf H"a1eff22c…"` identical across repacks → TCC grant survives rebuilds; app launches and runs (pid-verified); Accessibility grant itself pending an unlocked screen (`scripts/tcc-grant-runbook.md`) |
| §7-C focus-restore fix | ✅ merged into working tree | pre-panel frontmost app re-activated on Esc / ⌘0 / clipboard-degraded paths only (never steals focus from a successful delivery); orphan-safe (never captures Beamhop-on-Beamhop) |
| Xcode project + signed build | ⬜ blocked | same as above |

---

## 2. Key docs (read in order)

> ⚠️ **Iron rule: `git fetch` and align with origin before starting work on any machine** (lesson of the 2026-09 two-machine divergence; see the engineering-convergence spec §5).
>
> **Remote layout (2026-10-18)**: development moved to the main repo — `origin` = `willamhou/beamhop` (push target, main is protected: PR + 3 required checks), `fork` = `AuSmith-hub/beamhop` (legacy, read-only archive). `upstream/main` history was squash-merged (PR #5); local pre-squash commits were rebased away on 2026-10-18 — if you see "ahead/behind" drift vs `fork`, that is expected.

- **MVP design spec (source of truth, V2.1)**: [docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — Chinese original, translation pending
- **Week 3 floating-window spec + plan**: [docs/superpowers/specs/2026-09-18-week-3-floating-window.md](docs/superpowers/specs/2026-09-18-week-3-floating-window.md) + [docs/superpowers/plans/2026-09-18-week-3-implementation.md](docs/superpowers/plans/2026-09-18-week-3-implementation.md)
- **Engineering convergence (2026-09)**: [docs/superpowers/specs/2026-09-14-engineering-convergence.md](docs/superpowers/specs/2026-09-14-engineering-convergence.md) — branch model / two-machine split / acceptance gates
- **Evolution decisions (2026-09)**: [docs/superpowers/specs/2026-09-14-evolution-decisions.md](docs/superpowers/specs/2026-09-14-evolution-decisions.md) — Xcode timing / Phase 2 memory / Phase 3 triggers
- **Product positioning (2026-08-24)**: [docs/product-positioning.md](docs/product-positioning.md) — external-agent-native local context router; the "why not X" anchor
- **Roadmap**: [docs/superpowers/roadmap.md](docs/superpowers/roadmap.md)
- **Spike results + compatibility matrix**: [spike/results.md](spike/results.md) + [spike/compatibility-matrix-v0.json](spike/compatibility-matrix-v0.json)

---

## 3. Recover / quick verify (SwiftPM, Command Line Tools)

```bash
cd /Users/leo/Documents/Kimi/Workspaces/beamhop
export DEVELOPER_DIR=/Library/Developer/CommandLineTools   # needed while Xcode license is unaccepted
swift build                 # build all targets (incl. GRDB)
swift run BeamhopSelfTest   # 206 checks, expect ALL PASS ✅
./packaging/build-app.sh    # assemble dist/Beamhop.app (auto-signs "Beamhop Sign" if set up)
open dist/Beamhop.app       # first grant only: scripts/tcc-grant-runbook.md (stable identity ⇒ no re-grant after repacks)
```

**Dogfood gate report (evolution-decisions §3) — run this weekly during the dogfood window:**
```bash
scripts/dogfood-metrics.sh                 # default: 14-day window on the real inbox.sqlite
scripts/dogfood-metrics.sh --days 7        # shorter window
```
Backed by migration v3: append-only `events` (capture outcomes, panel ms, Inbox engagement) + `deliveries.duration_ms`. All local; no telemetry.

**Dogfood protocol (started 2026-10-19):**
1. On the acceptance Mac: `git pull` → `./packaging/build-app.sh` → `open dist/Beamhop.app`
   → re-grant Accessibility (ad-hoc signature, TCC drops per repack) → Diagnostics →
   "Register now" (points MCP at the real `inbox.sqlite`).
2. Use `⌘⇧Space` for real work daily (gate: ≥10/day). No script ever sends synthetic keys
   into real apps (incident rule, §6).
3. Every Friday: run `scripts/dogfood-metrics.sh` and paste the gate table into the dogfood
   log (this file §9). Two clean weeks → run the evolution-decisions §2.3 memory-route
   evaluation (plan A already landed; confirm or correct with data).

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
    Models/      Capture, Delivery, CaptureResult, Source/DomainHint/DeliveryTarget,
                 TimelineEntry+TimelineBuilder (detail-chain merge, pure/testable)
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
- ✅ Logic: 206 SelfTest checks green (incl. DuplicateGate, PanelShortcut, TargetMemory, PromptRenderer, panel model + **essay-02 receiver-change two-step gate**, raw values, **EventStore + DogfoodReport + v5 reconcile + zh-Hans strings + AXDeadline**, MCP dedup + plan-A write-back, **TimelineBuilder detail chain**, **PocketStore + WorkStore v6 migrations**)
- ✅ Dogfood instrumentation: events table (v3) + delivery durations wired into capture/panel/inbox/delivery paths; `scripts/dogfood-metrics.sh` verified end-to-end against a seeded DB

**Pending:**
- ⬜ `swift test` / XCTest on a dev machine (needs Xcode; CI runs it on macos-15)
- ⬜ Cowork MCPB end-to-end (S2 mechanism confirmed only)
- ⬜ AX word-grab re-test across 8 apps (per-app policy from S6)
- ⬜ Week 3 perf P95 measurement session (20 presses, method in §3) — ongoing tracking now automated via `scripts/dogfood-metrics.sh`

---

## 6. Pitfalls & decisions (do NOT re-learn these)

From Week 0 spikes + 4 codex review rounds + 2026-10 on-device debugging, all encoded in code:
- **MCP stdio = newline-delimited JSON + non-blocking POSIX reads** (`FileHandle.read(upToCount:)` times out at 30s). Register with `claude mcp add <name> -s user -- <abs-bin>` (no `--command`, `-s user` is mandatory). Installed release binary lives at `~/Library/Application Support/beamhop/bin/BeamhopMCP` (stable path — NEVER point config at `.build/`); Claude Desktop config: `~/Library/Application Support/Claude/claude_desktop_config.json`, takes effect on app restart. Reinstall after each release build: `swift build -c release && cp "$(swift build -c release --show-bin-path)/BeamhopMCP" ~/Library/Application\ Support/beamhop/bin/`.
- **Native messaging: host→extension ~1MB hard cap**; browser→host→app is allowed up to 4GB, so capture itself needs no chunking. app→extension >1MB chunking is a defensive TODO.
- **Custom `--user-data-dir`: native host manifest must also go into `<profile>/NativeMessagingHosts/`**. Chrome 137+ blocks `--load-extension` → automate via CDP pipe + `Extensions.loadUnpacked`.
- **WAL must be set with `writeOutsideTransaction`** (errors inside a transaction); WAL data lives in `-wal` — corruption simulation must delete `-wal/-shm` too. MCP uses `Database.openReadOnly` (no migration/recovery/creation).
- **AX: query the system-wide focused element** (`AXUIElementCreateSystemWide`); Chromium/Electron apps need `AXManualAccessibility` opt-in first; always `AXUIElementSetMessagingTimeout`.
- **Electron 43 (Kimi 3.2.17, 2026-10): `AXWindows` stays EMPTY even with a visible window — and the app element's subtree exposes only menu bars.** Resolve the window via `AXFocusedWindow`/`AXMainWindow` and BFS from there (`AXComposerFinder.resolveWindow`). Activating the app publishes the window lazily (~200ms) — poll, don't check once (`waitForWindow`).
- **ChatGPT 26.x: composer at AX depth ~30, `AXEditable` no longer exposed** (two-pass candidate logic in `AXComposerFinder`); bundle ids are now `com.openai.chat`/`com.openai.codex` (dual match). Set-value injection still works.
- **Kimi editor: kAXValueAttribute set-value returns success but does NOT take effect** (placeholder pollution) → inject by focusing the composer + clipboard paste (`safePasteOnly`, no Enter). New chat via sidebar button `desc="新建会话"`.
- **Windows/panels: `isReleasedWhenClosed = false`** (the red close destroys the window and the hotkey can never reopen it — S5).
- **Global hotkeys: Carbon `RegisterEventHotKey`** (no Input Monitoring permission; check the OSStatus for conflicts).
- **TCC binds signature identity + path**: ad-hoc-signed rebuilds change the cdhash → the Accessibility grant silently drops. **SOLVED 2026-10-19** with a stable self-signed identity — `scripts/setup-dev-signing.sh` + auto-detect in `packaging/build-app.sh`. Sub-lessons from the debug journey (do NOT retry these dead ends):
  - **`security add-trusted-cert` HANGS headless** (authd prompt blocks forever) — and trust is NOT needed anyway: TCC anchors the grant on the leaf certificate's designated requirement (`identifier "com.beamhop.app" and certificate leaf = H"…"`), which is stable across repacks regardless of keychain trust. Gatekeeper/spctl rejection is expected and irrelevant for local dev.
  - **A private key in the LOGIN keychain blocks `codesign` headless**: securityd requires a user-presence consent that queues behind the lock screen (symptom: codesign frozen in `SecurityServer::ClientSession::generateSignature` → `mach_msg`; `sample` confirms). Fix: dedicated keychain (`security create-keychain -p …`) + `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <pw>` — then codesign is fully dialog-free. `-A` on import alone is NOT sufficient.
  - **Import quirks (LibreSSL 3.3.6 / macOS 26)**: `security import` of a PKCS#12 fails "MAC verification failed" even with `-legacy` and non-empty passwords; import PEM key + cert separately instead. Private key PEM must be PKCS#1 (`BEGIN RSA PRIVATE KEY`) — LibreSSL's `openssl rsa -in pkcs8.pem -out trad.pem` emits that by default (no `-traditional` flag). `security delete-key` is trimmed in macOS 26 — orphaned cert/key cleanup needs Keychain Access GUI. Orphans from the 2026-10-19 first attempt ("Beamhop Dev", login-keychain "Beamhop Sign") are inert but will prompt if something tries to use them.
  - **Screen locked = GUI automation impossible**: every app window reports "no display" (screencapture is black; `caffeinate -u` only wakes to the lock screen). TCC toggles and keychain consent must wait for an unlocked session — see `scripts/tcc-grant-runbook.md`.
- **Clipboard safe paste (§12.3)**: store raw Data per item/per type, refuse if unreadable; only ClaudeCodeDelivery restores; the clipboard fallback handoff does not.
- **Current feature branch never synthesizes terminal Enter.** A prepared trigger requires manual submission until a specific receiving session can be verified. The older conditional auto-Enter behavior was removed on October 20.
- ⚠️ **Incident**: during S6 testing, scripted synthetic keystrokes + undo were sent into the user's real Notes and wiped one note (recovered). **Never send synthetic keys/undo into the user's real apps**; capture is read-only AX.
- **Inbox re-capture noise is fixed on the retrieval side, NOT at capture time** (2026-10-18, Claude's report: same GitHub page captured 13×). The DuplicateGate only covers <500ms; minutes-apart re-captures are byte-identical and stay in the DB (audit trail), but `search_captures` collapses them via `Capture.contentIdentity` (exact equality on app+title+url+selected+body — deliberately not fuzzy; near-dupes are Phase 2 embeddings work). `include_duplicates=true` restores the raw list. Soft-deleted twins are excluded from `duplicate_count`. The Inbox window UI still shows the raw list — collapse there only if dogfood says it matters.
- **SelfTest and the XCTest mirror MUST be updated together** — 2026-10-18 CI failure: plan A changed `claudeCodeTrigger` (added the save_result write-back sentence); SelfTest was updated but `Week3FeatureTests` wasn't, so every push mailed "Run failed: CI" until the mirror caught up. CI runs BOTH (`swift test` gates `swift run BeamhopSelfTest` behind it in the same job — one fails, the other never runs).
- **`plutil -lint` only accepts XML/binary plists, exits 1 on JSON** — validate JSON with `plutil -convert json -o /dev/null <file>`. Swift has no imported constant for `"AXEditable"` — use the raw string.
- **`.build/release` is a symlink to the triplet dir** — `find` doesn't follow a symlinked start point; use `find -H`. CI's `TMPDIR` has a trailing slash → `//` paths; normalize with the same `cd+pwd` on both sides of path assertions.
- **This machine's Claude is the 3p deployment (Cowork/Gateway)** — its MCP config is `~/Library/Application Support/Claude-3p/claude_desktop_config.json`, NOT `~/Library/Application Support/Claude/` (edits there are silently ignored; the app spawns whatever the 3p file says). Tool permissions are per-tool: each of fetch/search/save needed its own "Allow for this task" click even after allowing siblings.
- **Info-level os_log is NOT persisted on this Mac** (only errors show in `log show`; `log stream` yields nothing either) — any Beamhop metric logged at info/signpost level is invisible. Read timings from DB columns (`capture_duration_ms`) or measure on screen; don't burn time on the §3 grep method here.
- **macOS 26 renamed the TCC panes**: Accessibility is 设置 → 隐私与安全性 → **设备控制和数据访问** (no standalone "辅助功能"); Screen Recording is **录屏与系统录音**. Synthetic ⌘⇧Space via CGEventPost works and triggers Carbon hotkeys, but the OS occasionally drops a synthetic press (18/20 landed in the acceptance session) — sample counts should tolerate misses.
- **`pbpaste` in a `LANG=C` shell mangles UTF-8** (looks like an encoding bug, is only terminal display) — use `LANG=en_US.UTF-8 pbpaste` before debugging "corruption".
- **"Hotkey sometimes works" symptom checklist**: check the log for which PID logged the failure (old process vs current), and whether presses landed in a restart gap (`log show --predicate 'processID == <pid>'`).

---

## 7. Next steps (dependency-ordered)

**A. Unblock formal engineering (user action, ~2 min)**
1. ~~`sudo xcodebuild -license accept`~~ — stale: `swift test` already works locally via the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); CI runs both suites on macos-15.
2. Developer ID signing for `dist/Beamhop.app` remains the public-release gate (paid Apple account).
3. **One-time Accessibility grant** (screen must be unlocked; everything else automated): follow `scripts/tcc-grant-runbook.md` — after this, repacks no longer drop the grant.

**B. Perf & acceptance closure (Week 3 leftovers)**
- ✅ 20-press P95 done 2026-10-18 (211ms, results in §8) — method deviation: info-level os_log is not persisted on this Mac; used screen-diff + DB columns instead of the §3 grep.
- Ongoing tracking is automated: run `scripts/dogfood-metrics.sh` weekly during the dogfood window (panel_ms now also durable in `events`).
- ✅ §7-C focus-stealing fix landed 2026-10-19 (restore pre-panel frontmost on Esc/⌘0/clipboard-degrade).
- Re-run AX word-grab spot checks on the 8 S6 apps.
- Visual check of the new Inbox Timeline (detail chain) on a capture with agent write-backs, once the screen is unlocked.

**C. Product candidates (pick after a week of dogfood)**
- ~~Prompt-injection language~~: plan-A write-back trigger landed (Chinese base); unify EN/zh on top of the toggle later if wanted.
- ~~zh-Hans UI~~: **done 2026-10-19 (code)** — menu-bar Language submenu flips the per-app `AppleLanguages` override and relaunches; `build-app.sh` ships `zh-Hans.lproj` into the bundle; interpolated labels use `L10n.f`. On-device visual check pending (restart-apply flow).
- Cowork MCPB end-to-end.

**D. Week 2 close-out**
- ~~AX total 800ms deadline~~: **done 2026-10-19** — `AXDeadline` (BeamhopCore, unit-tested) bounds the whole `AXHelper.read` pass; expiry returns partials (`ax-deadline`).
- ~~MCP one-click registration~~: **done 2026-10-19 (code)** — Diagnostics "Register now" runs the real `claude mcp add` (bundle MCP binary + real DB path, augmented PATH for GUI context) and verifies `~/.claude.json`; copy-command fallback under `swift run`. On-device verify pending.
- ⬜ app→extension >1MB chunking protocol + bidirectional reassembly test.
- ⬜ Multi-browser/profile routing (currently single connection, "latest host wins").

**D. Phase 2 prerequisite (after Week 3 + acceptance + two weeks of dogfood)**
- One-hour evaluation per the evolution-decisions spec §2.3 (personal-model review + dogfood signals) → pick the memory route → kick off.

---

## 8. Week 3 acceptance record (2026-10-18, on-device)

**October 20 feature review:** The hosted macOS run verifies the native panel/shelf interactions listed in the current follow-up. Before promoting the feature PR from draft, separately accept logged-in ChatGPT/Kimi draft protection and current-conversation behavior, real terminal preparation, TCC capture, VoiceOver speech, fullscreen/Stage Manager and multiple displays. The October 18 results below describe the earlier implementation and do not close these items.

User-verified this session:
1. ⌘⇧Space pops the panel (after Accessibility re-grant on the fresh build) ✅
2. Target shortcuts ⌘1–⌘4 + ⌘0 present and selectable ✅
3. Enter delivers, Esc cancels (capture kept in Inbox) ✅
4. Kimi Work: paste lands in a fresh conversation, placeholder untouched ✅
5. ChatGPT Desktop v26: set-value injection into composer ✅
6. Failure fallback → clipboard + notification (Kimi/ChatGPT window closed case) ✅
7. Duplicate <500ms same-window press swallowed silently ✅

Perf P95: ✅ **2026-10-18, 20-press automated session (synthetic ⌘⇧Space via CGEventPost; panel visibility detected by screencapture crop-diff; capture_ms read from the DB `capture_duration_ms` column)**. Method deviation: this Mac does NOT persist info-level os_log messages (`log show` only ever shows errors from Beamhop, and `log stream` captures nothing) — the spec §3 grep method is unusable here, so panel latency was measured as press→panel-visible-on-screen.
- press→panel-visible: 18/20 valid samples (2 synthetic presses were dropped by the OS), min 179 / median 195 / **P95 211 / max 211 ms** — end-to-end is already under the 300ms panel_ms budget, and in-app panel_ms is only a fraction of this number. ✅
- capture_ms (session): P95 = 6ms, but 17/20 presses captured Beamhop itself (0ms AX — see focus-stealing finding below), so this is the optimistic floor. Real-app reference from today's organic captures: Chrome 122–155ms, Kimi 3–55ms. Worst realistic end-to-end ≈ 155 + ~150 ≈ 300ms — right at budget; fine for now, re-measure with Chrome frontmost if it ever feels slow.
- Dogfood finding: after the panel closes (Esc/deliver), frontmost stays Beamhop — the next capture grabs Beamhop itself (useless 0ms rows in the log). ~~Candidate fix: app-activate the pre-capture frontmost app on panel close (or exclude self in CaptureService). Logged in §7-C.~~ **Fixed 2026-10-19** (`restorePrePanelFocus` in AppServices).

Compatibility matrix updated: `spike/compatibility-matrix-v0.json` — chatgpt_desktop versions_tested += 26.1007.71326 (dual bundle id, AXEditable gone, composer depth ~30, set-value OK); kimi_work added (paste-injection mechanism, new-chat button desc).

---

## 9. Dogfood log (weekly gate-table pastes)

> Format: date + window + the `scripts/dogfood-metrics.sh` gate table. Two clean weeks of
> data → evolution-decisions §2.3 evaluation.

- (empty — first paste due the Friday after the dogfood launch)
