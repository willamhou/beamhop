# Beamhop — Progress & Resume Guide (PROGRESS)

> Single entry point for current status, verification boundaries and next steps.
> Last updated: 2026-10-26 — this change starts from `main@66dea66` (PR #16), after the Kimi and Pocket HUD follow-ups. Check Git for the actual merged tip. Read [AGENTS.md](AGENTS.md) for collaboration, safety and CI-gated merge rules. Historical specifications and acceptance records below do not certify every current build.

## Ordinary Hop identity and optional conclusions (2026-10-26)

New handoff attempts append a durable identity after literal instructions/edited material. Conclusion return is explicit opt-in in the panel and batch controls, preserved with drafts and exact-snapshot equality. A mixed-consent selection defaults off. Recovery and retries get fresh attempt IDs. The existing manual copy/prepare, attachment fallback and no-auto-send policies remain unchanged.

Additive v10 stores append-only `handoff_results` against frozen `hop_records`, independently of captures and transport receipts. New MCP tools read only an allowlisted edited snapshot and save/fetch conclusions by an exact opted-in handoff ID. Unknown, legacy, non-opted-in and deleted origins are rejected; the helper does not migrate/create the Inbox. Original capture bodies and local attachment paths are not included. Old capture tools and old backup payloads remain compatible. Deleting a backup removes its conclusions, not active input or source captures.

Inbox has a separate handoff-conclusions section; Pocket history shows scoped conclusions, identity and the frozen outgoing payload. Both poll external writes while visible, support long answers/paging, and keep agent-reported answers distinct from task completion. Upgrade the app and helper together and deliberately reload receiving MCP sessions; availability is not inferred from registration. As with v9, old binaries do not roll back the schema. No acceptance bundle, real Inbox, TCC or Claude configuration was changed for this work.

Regression scope approved by the owner: identity/actual output; restart/retry/edits and correct result association; MCP/UI behavior, invalid origins, compatibility and truthful receipts. Mirrored XCTest/SelfTest cover these public contracts. A new actual-stdio smoke test uses only explicit temporary databases, including missing/pre-v10 schema checks. Hosted native fixtures exercise the consent controls and external conclusion refresh. A small equivalent `StateObject` container replaces the baseline Pocket HUD's `@State` usage to support the local CLT SwiftUI build; hover/fade behavior is unchanged.

Local evidence for `1bf95d5`: full `swift build`, SelfTest and the actual MCP round-trip passed, including external refresh at a pagination boundary, late results, consent-only edits, recovery, legacy rejection and missing/pre-v10 no-migration checks. Provenance (9 tests), signing safety (7 cases), localization lint and whitespace checks passed. `swift test` was attempted and cannot resolve XCTest under `/Library/Developer/CommandLineTools`; hosted XCTest is still required. Two-axis review and latest-head hosted CI remain required before merge. Native fixtures have not been run in the user's active desktop session. Logged-in MCP-agent tool discovery and optional write-back, real capture/TCC, focus/fullscreen/multidisplay acceptance remain manual; this is not a verified task-completion protocol. [Contract and test surfaces](docs/superpowers/specs/2026-10-26-hop-result-return.md).

## Earlier merged baseline: Inline Hop, Pocket and trial engineering

[PR #8](https://github.com/willamhou/beamhop/pull/8) was squash-merged on October 22 as `3cb279a`, after both workflows for final head `cd88c8a` passed: [PR CI](https://github.com/willamhou/beamhop/actions/runs/39709892162), [branch CI](https://github.com/willamhou/beamhop/actions/runs/39709887477). Its four earlier review findings were checked against the fixes/tests and resolved. [PR #10](https://github.com/willamhou/beamhop/pull/10) had already merged trial-build engineering as `5c6f829`. Start new branches from current `main`, not either old workstream branch.

Capture uses one native panel for instructions, editable text, original comparison, added text, attachment imports, app/window intent and local project creation. ⌘Return confirms; Return inserts a newline. Pocket provides compact searchable drafts, new/edit/duplicate/delete/undo, separate history, and multi-select handoff. Matching routes carry over; mixed project/app/session routes require an explicit destination. No AI service or ScreenCaptureKit dependency is introduced.

HopLibrary persists active input, independent Pocket batches and route choices in `hop_state` (v8); v9 migrates frozen handoff backups into individually written `hop_records` rows. Typing does not rewrite full history. Restore/recover parks current input atomically; material-only reuse copies identities without replacing the route/instruction. Successful completion consumes only unchanged matching snapshots, including parked ones; failure and later edits survive. Pending imports follow their draft across panel reopening and block premature handoff. Imported attachments stay local; transports do not transfer them, and explicit text fallback lists files to add manually.

Projects are local context, not external session addresses. New-session handoff copies text and opens an installed receiver, including when closed, for manual session creation. Current-window draft filling keeps the nonempty-composer protection. Inline Hop/Pocket copies Claude Code material rather than injecting arbitrary text into an unverified terminal; legacy Inbox re-delivery can still prepare an MCP trigger for manual submission. Copied/prepared is not agent receipt or task completion. Interrupted handoffs retain an unknown-status warning and never retry automatically.

Trial engineering provides version/commit/local-change display, embedded provenance, signed-binary receipts and preview-before-save typed diagnostics. Claude registration detects CLI and both Desktop config homes; explicit Desktop registration preflights existing JSON, preserves unrelated settings and creates missing supported homes. Registration presence does not verify a live MCP session. Diagnostic export excludes raw detail/config/Inbox data and never uploads automatically.

Verification: final PR #8 CI ran build/XCTest/SelfTest, MCP/native-host checks, packaging, native Pocket/inline-editor fixtures, offscreen diagnostic privacy checks and focus/Inbox regressions, plus extension and script checks. Earlier local CLT verification and the `81f23a6` 228-check UI run are historical intermediate evidence, not proof for later revisions. Logged-in agent/TCC, native export Save/Cancel, VoiceOver speech, fullscreen/Stage Manager, multiple displays and fresh real-source latency measurements remain manual acceptance work.

The October 21 acceptance bundle at `dist/Beamhop.app` was not replaced by either merge. User feedback reported no issues in that tested package, without a per-case matrix. New source does not imply a new local `.app` or a completed acceptance pass. Build into a fresh output directory when a new package is requested.

Current process: the owner authorized direct merge after the latest head's required CI passes and conflicts are resolved, without an additional confirmation or indefinite review-bot wait. Known actionable findings still need resolution; never bypass protection or merge pending/failed checks. Synchronize local `main` after merging. This replaces the historical real-device-before-every-merge policy; real-device evidence and release gates remain separate.

> 🗂 Full pre-2026-10 history (Chinese) is archived at [docs/zh/PROGRESS.zh.md](docs/zh/PROGRESS.zh.md).

---


## PR #8 review fixes (2026-10-22)

Pocket parity follow-up: the Hop shelf now has compact selectable rows, search, separate draft/history tabs, new/edit/duplicate/delete/undo actions, and one combined handoff for a selected batch. Matching routes are inherited; mixed project/app/session selections require an explicit destination. Each batch receipt freezes its source drafts; success removes only unchanged selected snapshots, while failure preserves selection and retry. Active input, concurrent edits and unselected drafts survive. Attachment imports and unsupported attachments block batch delivery. History is rendered in pages of 20 and can be inspected, restored or removed. The native fixture now clicks the actual new/edit/select-all/delete/undo/deliver controls, covers batch failure and success, and captures compact, selected, retry, dense and history states. XCTest/SelfTest mirror CRUD, restart/undo, frozen batch completion and route/filter/attachment guards.

Four review findings against `f54e349` are addressed: new-session handoffs open installed receivers when closed; v9 migrates full handoff backups into individually written `hop_records` rows so editor changes do not rewrite history; successful completion consumes only unchanged active/Pocket snapshots while failures and later edits survive; explicit Claude Desktop registration creates both supported config homes and preflights existing JSON before writes. A legacy-only registration no longer hides the repair action. Text copying and application launch remain distinct from creating a session or submitting a message.

Regression coverage: XCTest and SelfTest mirror legacy migration/order/reopen, history-write rejection during edits, transactional rollback, all active/parked × unchanged/edited × prepared/copied/failed combinations, and missing/legacy/current/both/malformed Desktop configs. The native focus fixture exercises closed/running/missing/unlaunchable receiver apps using a disposable bundle only. These changes were developed in a Windows session and verified by the hosted macOS runs linked above; that is not a claim about the local Mac's toolchain. Tests did not modify real Claude configs or the acceptance app. The v9 migration retains all history; older binaries cannot display the separated records and are not a schema rollback mechanism.

## Historical package evidence: trial-build engineering (2026-10-21)

The user is testing the October 21 acceptance app (`2dd92bb` plus the CLT `StateObject` compatibility adjustment). Its app bundle is preserved at `dist/Beamhop.app`; do not replace it while acceptance is in progress. Checklist: [real-device acceptance](docs/regressions/2026-10-21-device-acceptance.md). Local native fixtures passed 156/156 checks plus 20 repeated focus cycles, self-capture rejection and MCP-to-Inbox refresh; these are not real-agent/TCC/fullscreen/multidisplay acceptance.

Trial engineering adds version/commit/local-change display, embedded build provenance, source fingerprints and post-signing binary receipts, plus a typed allowlist diagnostic report with full preview and explicit local save. No raw logs, capture text, notes, URLs, local paths, session IDs, configuration or credentials enter the report. Build outputs use a separate directory; no automatic diagnostic upload is implemented. See [trial builds](docs/trial-builds.md) for the mechanism and its original pre-merge package snapshot; use the current baseline above for integration status and AGENTS for merge policy.

At that package snapshot, Release/Debug build and SelfTest passed; 7 signing-credential tests, ShellCheck, localization lint and four offscreen language/appearance fixtures passed. Provenance coverage reached 9 local tests, including index-hidden source edits and tagged-release receipt assets. The packaged runtime metadata and signed hashes matched the manifest/receipt, and the acceptance executable remained unchanged. Local XCTest was unavailable under CLT. Later final head `a8f6d2d` passed hosted CI/review before PR #10 merged as `5c6f829`; the dirty local preview does not represent that clean commit or the subsequent Inline Hop merge. Preview/cancel/native-save interactions still need manual acceptance. [Exact local package snapshot](docs/regressions/2026-10-21-trial-engineering.md); [PR #10](https://github.com/willamhou/beamhop/pull/10).

User acceptance feedback: the user reported no issues in the current acceptance app during this round. No per-case matrix was supplied; do not infer that every platform/Agent scenario or the separate engineering export Save/Cancel flow has passed.

Signing is conditional: an existing usable development identity can be selected; otherwise local/hosted builds are ad-hoc. The October 21 acceptance app is ad-hoc signed, not notarized. A stable development certificate is not Developer ID distribution, and password rotation remains required on Macs that used the former default. CI/XCTest success on another Mac does not imply this local CLT installation provides XCTest.

## Merged baseline: compact handoff (2026-10-20)

**PR #7 merged:** integrated PR #6 and was squash-merged to `main` as `2dd92bb` on October 20. The compact nonactivating panel, corner shelf, named-work safeguards and signing-password remediation remain intact. The capture gate and self-capture rejection, presentation-scoped focus recovery, deterministic timeline ordering, and Inbox external-write refresh/pagination now share one implementation. Both sets of storage/model regressions are retained. The native focus/Inbox fixture asserts that the source app stays active while the panel owns keyboard input and runs alongside compact-panel UI checks. [Main CI run 39382794001](https://github.com/willamhou/beamhop/actions/runs/39382794001) passed; real-app integration acceptance remains separate.

**Signing credential remediation:** GitGuardian found a fixed default password in the earlier development-keychain setup and packaging scripts. The current scripts require hidden interactive input or an explicitly supplied secret, do not trace/export it to child commands, and stop on explicit unlock failure. Seven isolated command-stub regression cases cover these paths. The owner approved feature-history cleanup: 23 of 25 commits were rewritten, with the final file tree unchanged. [GitGuardian on `97ea92e`](https://github.com/willamhou/beamhop/pull/7/checks?check_run_id=118436760729) scanned all 25 commits and reported **No secrets detected**. The signing regression tests and ShellCheck also passed in hosted CI. The historical Windows remediation session did not rotate Mac credentials; rotation remains required wherever the former default was used unless independently recorded as complete. See [remediation instructions](docs/dev-signing-security.md).

**Mac-side signing state (2026-10-21):** on the development Mac the dedicated `beamhop-sign` keychain became inaccessible — the owner does not know its password, it sat locked, and `codesign` failed headless with `errSecInternalComponent` while repeated password dialogs popped. The locked keychain file was moved aside to `~/beamhop-sign.locked-backup.keychain-db` (useless without its password; delete it once confirmed unneeded). Consequence: `packaging/build-app.sh` auto-detect no longer finds the identity and falls back to **ad-hoc** signing — every repack changes the cdhash and drops the TCC Accessibility grant, so re-grant per repack via `scripts/tcc-grant-runbook.md`. To restore repack-stable signing, rerun `scripts/setup-dev-signing.sh` with a new owner-known password (or supply `BEAMHOP_KEYCHAIN_PASSWORD` from a secret provider) and redo the one-time grant. Reverified on this Mac 2026-10-21 on `main@2dd92bb`: `swift build` clean (deprecation warnings only), SelfTest ALL PASS, XCTest 48/48, `mcp-smoke.sh` PASS, `native-ui-smoke.sh` 156/156 PASS against the ad-hoc-signed `dist/Beamhop.app`.

Historical development branch: `feat/phase15-detail-chain`. The compact-handoff fixes from `codex/refine-capture-workflow` were integrated there before [PR #7](https://github.com/willamhou/beamhop/pull/7) merged. Use current `main` for new branches, not the old feature-branch instructions. The user selected a compact shortcut panel with destinations disclosed on demand; the corner pocket remains optional.

Implemented: nonactivating keyboard-capable panels; content-driven sizing; full destination label with a native menu; explicit handling of unavailable receivers; preserved manual shelf destinations; protection against stale binding confirmations; compact destination menu and optional naming; recent named destinations; selection-based corner panel; a single combined payload per handoff; work-intent preservation (v7 migration); recovery without clearing pending selections; serialized delivery; draft protection; no automatic Kimi new chat or terminal Enter; separate copied/prepared receipts; corrected destination acknowledgment and memory. Details and Mac acceptance: [compact handoff](docs/superpowers/specs/2026-10-20-compact-handoff.md).

Validation: macOS CI passed for `fde3a97` ([run 39360579032](https://github.com/willamhou/beamhop/actions/runs/39360579032)): build, XCTest, SelfTest, MCP/native-host smoke checks, app packaging, extension and shell checks. The production app also ran on macOS 15.7.9: **152/152 native UI assertions passed** (38 each in English/Chinese, light/dark), with 20 PNGs reviewed. Evidence covers actual key focus and editor input, the accessible destination button opening its native menu, menu selection without dismissal, source-app nonactivation, replacement-draft recovery, selection retention and failed/successful handoff state. CI provides the gallery/reports and a downloadable development app; see [native verification](docs/native-ui-verification.md).

Integration acceptance remains pending for logged-in agent apps, TCC capture, VoiceOver speech, fullscreen/Stage Manager and multiple displays. Named works still bind apps, not exact agent sessions; app injection still brings the receiver forward for manual review. Earlier “machine-verified” claims below describe the October 19 implementation, not the current integration paths.

## 0. Historical baseline before the October 20 compact-handoff changes

Week 0–2 plus integration peripherals are done (CI green). **Week 3 is now implemented and machine-verified**: ⌘⇧Space grabs the frontmost app's context and pops a keyboard-first floating panel (⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork→clipboard / ⌘4 Kimi Work / ⌘0 Inbox-only; Enter delivers; Esc cancels and keeps the capture). Delivery coverage: Claude Code (MCP+paste), ChatGPT Desktop 26.x (set-value), Kimi Work 3.2.17 (clipboard-paste into a fresh chat), Cowork (clipboard fallback). Logic is covered by 198 SelfTest checks. **MCP write-back (plan A) + search dedup merged 2026-10-18** (stage table below). **Product essays 01/02 implemented 2026-10-19** (from the pages branch thinking): essay 01 「先留着」 — ⌘5 parks capture+note+intended target in a `pocket_items` stack (`PocketStore`), ⌘⇧P pocket window delivers the stack in hold order (serial, failure keeps the item); essay 02 two-layer destinations — named works (`works` table: work name over a bound receiving session) with `⌘5 先留着` / two-step rebind confirmation: an in-panel receiver change under a confirmed work, or a stored unconfirmed rebind, makes the first Enter acknowledge the new address and only the second deliver. Both machine-verified 2026-10-19. **UI pass 2026-10-19 (dogfood feedback)**: panel slimmed (460pt, single-row instruction+work-name inputs, inline two-layer destination line, no "Deliver to" caption); ⌘3 is Clipboard (the self-deceiving "Cowork → clipboard" is gone — `.cowork` keeps API-level existence for S2 but no panel slot); the panel only offers destinations that are REAL on the machine (`TargetAvailability` + `TargetDetector`: Claude CLI / ChatGPT (either bundle id) / Kimi / clipboard-always), with graceful fallback when a remembered target vanishes; held items now surface as a bottom-right HUD chip (「口袋 · N ⌘⇧P」, hides when empty, click opens the pocket window, which itself anchors bottom-right). SelfTest 206 checks. **Dogfood instrumentation (Phase 1.5)**: an append-only local `events` table + `deliveries.duration_ms` feed `scripts/dogfood-metrics.sh`, which prints the evolution-decisions §3 gate table (press frequency, delivery success, Inbox accumulation/revisits, readable failures, panel P95) — all local, never leaves the machine. The app still ships as a SwiftPM-assembled `dist/Beamhop.app` (ad-hoc signed); `swift test`/XCTest work on machines with the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, CI runs them on macos-15); the original dev Mac still has CLT only.

**Historical signing result, not a guarantee for every Mac:** an optional stable self-signed identity was verified on the original development Mac. Developer ID signing/notarization remain separate work. Ad-hoc builds may require regranting Accessibility after repacks; the current acceptance package is ad-hoc. See `scripts/tcc-grant-runbook.md` and the credential remediation guide.

---

## 1. Historical stage table (see current follow-up for present evidence)

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
| **Stable dev signing ("Beamhop Sign")** | ⚠️ identity retired 2026-10-21 (keychain password lost on dev Mac) | mechanism was verified headless (dedicated keychain + self-signed cert + partition list; DR-stable across repacks) — see the 2026-10-21 note above; `packaging/build-app.sh` now falls back to ad-hoc until `setup-dev-signing.sh` is rerun with a new password |
| §7-C focus-restore fix | ✅ merged into working tree | pre-panel frontmost app re-activated on Esc / ⌘0 / clipboard-degraded paths only (never steals focus from a successful delivery); orphan-safe (never captures Beamhop-on-Beamhop) |
| Xcode project + signed build | ⬜ blocked | same as above |

---

## 2. Key docs (read in order)

> ⚠️ **Iron rule: `git fetch` and align with origin before starting work on any machine** (lesson of the 2026-09 two-machine divergence; see the engineering-convergence spec §5).
>
> **Remote layout (2026-10-18)**: development moved to the main repo — `origin` = `willamhou/beamhop` (push target, main is protected: PR + 3 required checks), `fork` = `AuSmith-hub/beamhop` (legacy, read-only archive). `upstream/main` history was squash-merged (PR #5); local pre-squash commits were rebased away on 2026-10-18 — if you see "ahead/behind" drift vs `fork`, that is expected.

- **Historical MVP foundation (V2.1)**: [docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — Chinese original; later merged behavior and current evidence take precedence over superseded plans
- **Current repository rules**: [AGENTS.md](AGENTS.md) — workflow, architecture, validation, package protection, privacy and CI-gated merges
- **Historical Week 3 floating-window spec + plan**: [docs/superpowers/specs/2026-09-18-week-3-floating-window.md](docs/superpowers/specs/2026-09-18-week-3-floating-window.md) + [docs/superpowers/plans/2026-09-18-week-3-implementation.md](docs/superpowers/plans/2026-09-18-week-3-implementation.md) — not the current Inline Hop UI contract
- **Engineering convergence (2026-09)**: [docs/superpowers/specs/2026-09-14-engineering-convergence.md](docs/superpowers/specs/2026-09-14-engineering-convergence.md) — historical transition and acceptance policy; current merge policy is in AGENTS and the baseline above, not its old integration-branch instructions
- **Evolution decisions (2026-09)**: [docs/superpowers/specs/2026-09-14-evolution-decisions.md](docs/superpowers/specs/2026-09-14-evolution-decisions.md) — Xcode timing / Phase 2 memory / Phase 3 triggers
- **Product positioning (2026-08-24)**: [docs/product-positioning.md](docs/product-positioning.md) — external-agent-native local context router; the "why not X" anchor
- **Roadmap**: [docs/superpowers/roadmap.md](docs/superpowers/roadmap.md)
- **Spike results + compatibility matrix**: [spike/results.md](spike/results.md) + [spike/compatibility-matrix-v0.json](spike/compatibility-matrix-v0.json)

---

## 3. Recover / quick verify (SwiftPM, Command Line Tools)

```bash
# From this repository root; use the installed toolchain (xcode-select -p).
swift build                 # build all targets (incl. GRDB)
swift run BeamhopSelfTest   # expect ALL PASS ✅, including focus + Inbox regressions
BEAMHOP_OUTPUT_DIR="$PWD/dist/preview-$(date +%Y%m%d-%H%M%S)" ./packaging/build-app.sh
# Inspect the reported bundle/receipt; launch only when ready to switch acceptance apps.
```

**Dogfood gate report (evolution-decisions §3) — run this weekly during the dogfood window:**
```bash
scripts/dogfood-metrics.sh                 # default: 14-day window on the real inbox.sqlite
scripts/dogfood-metrics.sh --days 7        # shorter window
```
Backed by migration v3: append-only `events` (capture outcomes, panel ms, Inbox engagement) + `deliveries.duration_ms`. All local; no telemetry.

**Dogfood protocol (started 2026-10-19):**
1. On the acceptance Mac: fetch and fast-forward a clean `main`, build to a new output directory,
   and switch apps deliberately (quit old instances first). Do not replace a bundle under test.
   Check Accessibility for the current signature/path → Diagnostics →
   "Register now" (points MCP at the real `inbox.sqlite`).
2. Use `⌘⇧Space` for real work daily (gate: ≥10/day). No script ever sends synthetic keys
   into real apps (incident rule, §6).
3. Every Friday: run `scripts/dogfood-metrics.sh` and paste the gate table into the dogfood
   log (this file §9). Two clean weeks → run the evolution-decisions §2.3 memory-route
   evaluation (plan A already landed; confirm or correct with data).

**MCP server smoke (real protocol, explicit temporary database, no registration changes):**
```bash
task_mcp_dir="$(mktemp -d)"
swift run BeamhopSelfTest --seed "$task_mcp_dir/inbox.sqlite"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"local-fixture","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}' \
  | "$(swift build --show-bin-path)/BeamhopMCP" --db "$task_mcp_dir/inbox.sqlite"
```

Do not register this temporary database in the user's Claude config. CI also runs `scripts/mcp-smoke.sh`; review its default-path case before running it on a machine with a real Inbox, since overriding `HOME` alone does not establish Foundation path isolation.

**Perf evidence boundary:** `capture_ms` and `panel_ms` are logged separately; `panel_ms` measures panel-show work, not full hotkey-to-interactive latency. Historical P95 values (including 211ms) must not be reused as current end-to-end acceptance. A fresh measurement with real sources is still needed.

---

## 4. Code structure (SwiftPM)

```
Package.swift
Sources/
  BeamhopCore/                 # testable logic (no AppKit; depends on GRDB)
    Models/      Capture, Delivery, CaptureResult, Source/DomainHint/DeliveryTarget,
                 HopMaterial/HopRoute/HopDraft/HopRecord, TimelineEntry+TimelineBuilder
    Storage/     Database (WAL + openReadOnly + corruption recovery), migrations (dual FTS5+triggers),
                 CaptureStore, CaptureReader, ResultStore, HopLibrary (v8 drafts + v9 receipts),
                 legacy PocketStore/WorkStore (import/compatibility)
    Capture/     AppBlacklist, DuplicateGate (W3-4 <500ms same-window re-press guard)
    Delivery/    PromptRenderer (trigger/full markdown) — moved from app for testability
    Panel/       CapturePanelModel, HopPocketModel, PanelShortcut, TargetMemory
    Support/     AppPaths, Version, ULID, BuildInfo, DiagnosticReport, MCPRegistrationConfig
    Inbox/       InboxModel (external result refresh/pagination)
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
    Panel/       HopCoordinator (draft/pocket/transport wiring), CapturePanelController,
                 CapturePanelView (inline editing), DestinationMenu, HandoffPanel
    Pocket/      PocketWindowController (draft/history UI), PocketHUD
    Bridge/      BrowserBridgeServer (unix socket)
    Diagnostics/ DiagnosticsService, DiagnosticsWindow, DiagnosticExport, native fixture runners
    Inbox/       InboxWindow
    Compatibility/ CompatibilityMatrix
  BeamhopMCP/    main.swift    # stdio capture reads + results-only writeback; app owns migrations
  BeamhopSelfTest/             # XCTest-free runner, Pocket regression helper and --seed
Tests/BeamhopCoreTests/        # XCTest mirror (requires full Xcode, not CLT alone)
host/            main.swift     # native messaging host, pure frame relay Chrome<->app socket
extension/       manifest.json, background.js, vendor/readability.js, build/ (esbuild source)
```

---

## 5. Historical verification inventory (not current-build acceptance)

**Verified:**
- ✅ Data layer: dual FTS5 (unicode61+trigram), soft delete, corruption recovery, 10k ULID uniqueness (`BeamhopSelfTest`)
- ✅ MCP server against real Claude Code (`fetch_capture` returns a real capture)
- ✅ 3-hop browser bridge end-to-end; Readability body extraction (CDP-automated)
- ✅ **Week 3 on-device (2026-10-18, user-verified)**: panel appears on ⌘⇧Space; target shortcuts; Enter/Esc semantics; <500ms same-window dedup (silent); Kimi Work paste-into-fresh-chat; ChatGPT v26 set-value injection; Inbox-only (⌘0) keeps capture
- ✅ Logic: 206 SelfTest checks green (incl. DuplicateGate, PanelShortcut, TargetMemory, PromptRenderer, panel model + **essay-02 receiver-change two-step gate**, raw values, **EventStore + DogfoodReport + v5 reconcile + zh-Hans strings + AXDeadline**, MCP dedup + plan-A write-back, **TimelineBuilder detail chain**, **PocketStore + WorkStore v6 migrations**)
- ✅ Historical PR #6 logic: SelfTest green, including focus/self-capture, Inbox external-write/selection/pagination/error and deterministic timeline coverage; XCTest mirror added in `FocusInboxRegressionTests.swift`.
- ✅ Historical PR #6 native fixture: 20 consecutive panel open/cancel cycles; self capture creates no DB row; save/clipboard returns focus; click-away and delivery retain destination focus; late completion does not affect a new panel; Inbox polls two agents' write-backs. Uses temporary fixture apps/database only.
- ✅ Dogfood instrumentation: events table (v3) + delivery durations wired into capture/panel/inbox/delivery paths; `scripts/dogfood-metrics.sh` verified end-to-end against a seeded DB

**Pending:**
- ✅ Superseded pending item: trial engineering and Inline Hop/Pocket passed hosted XCTest/CI before PR #10/#8 merged. See the current baseline for exact revisions; local CLT still does not provide XCTest.
- ⬜ Cowork MCPB end-to-end (S2 mechanism confirmed only)
- ⬜ AX word-grab re-test across 8 apps (per-app policy from S6)
- ⬜ Week 3 perf P95 measurement session (20 presses, method in §3) — ongoing tracking now automated via `scripts/dogfood-metrics.sh`

---

## 6. Pitfalls & decisions (do NOT re-learn these)

From Week 0 spikes + 4 codex review rounds + 2026-10 on-device debugging, all encoded in code:
- **MCP stdio = newline-delimited JSON + non-blocking POSIX reads** (`FileHandle.read(upToCount:)` times out at 30s). Explicit CLI registration uses `claude mcp add <name> -s user -- <abs-bin>` (no `--command`; user scope is required). Diagnostics prefers an executable installed helper at `~/Library/Application Support/beamhop/bin/BeamhopMCP`, then the bundled helper; packaging alone does not update a separately installed copy. Do not register transient `.build/` paths for normal use or replace a helper during an acceptance session without an intentional upgrade. Desktop supports both `Claude/claude_desktop_config.json` and `Claude-3p/claude_desktop_config.json` under Application Support; explicit registration preflights/preserves both and takes effect after Desktop restarts.
- **Native messaging: host→extension ~1MB hard cap**; browser→host→app is allowed up to 4GB, so capture itself needs no chunking. app→extension >1MB chunking is a defensive TODO.
- **Custom `--user-data-dir`: native host manifest must also go into `<profile>/NativeMessagingHosts/`**. Chrome 137+ blocks `--load-extension` → automate via CDP pipe + `Extensions.loadUnpacked`.
- **WAL must be set with `writeOutsideTransaction`** (errors inside a transaction); WAL data lives in `-wal` — corruption simulation must delete `-wal/-shm` too. MCP uses `Database.openReadOnly` (no migration/recovery/creation).
- **AX: query the system-wide focused element** (`AXUIElementCreateSystemWide`); Chromium/Electron apps need `AXManualAccessibility` opt-in first; always `AXUIElementSetMessagingTimeout`.
- **Electron 43 (Kimi 3.2.17, 2026-10): `AXWindows` stays EMPTY even with a visible window — and the app element's subtree exposes only menu bars.** Resolve the window via `AXFocusedWindow`/`AXMainWindow` and BFS from there (`AXComposerFinder.resolveWindow`). Activating the app publishes the window lazily (~200ms) — poll, don't check once (`waitForWindow`).
- **ChatGPT 26.x: composer at AX depth ~30, `AXEditable` no longer exposed** (two-pass candidate logic in `AXComposerFinder`); bundle ids are now `com.openai.chat`/`com.openai.codex` (dual match). Set-value injection still works.
- **Kimi editor: kAXValueAttribute set-value returns success but does NOT take effect** (placeholder pollution) → current-window preparation uses the checked composer + clipboard paste (`safePasteOnly`, no Enter). The historical spike found a new-chat sidebar button, but current delivery must not click it automatically; new-session mode opens the app for manual creation.
- **Windows/panels: `isReleasedWhenClosed = false`** (the red close destroys the window and the hotkey can never reopen it — S5).
- **Global hotkeys: Carbon `RegisterEventHotKey`** (no Input Monitoring permission; check the OSStatus for conflicts).
- **TCC binds signature identity + path**: ad-hoc repacks can require Accessibility re-grant. A stable self-signed identity was verified on October 19, but the reported development keychain was retired on October 21; this is not globally solved. Check the actual current signing mode. `scripts/setup-dev-signing.sh` can establish a new owner-known identity; public Developer ID signing/notarization remain separate. Sub-lessons from the debug journey (do NOT retry these dead ends):
  - **`security add-trusted-cert` HANGS headless** (authd prompt blocks forever) — and trust is NOT needed anyway: TCC anchors the grant on the leaf certificate's designated requirement (`identifier "com.beamhop.app" and certificate leaf = H"…"`), which is stable across repacks regardless of keychain trust. Gatekeeper/spctl rejection is expected and irrelevant for local dev.
  - **A private key in the LOGIN keychain blocks `codesign` headless**: securityd requires a user-presence consent that queues behind the lock screen (symptom: codesign frozen in `SecurityServer::ClientSession::generateSignature` → `mach_msg`; `sample` confirms). Fix: dedicated keychain (`security create-keychain -p …`) + `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <pw>` — then codesign is fully dialog-free. `-A` on import alone is NOT sufficient.
  - **Import quirks (LibreSSL 3.3.6 / macOS 26)**: `security import` of a PKCS#12 fails "MAC verification failed" even with `-legacy` and non-empty passwords; import PEM key + cert separately instead. Private key PEM must be PKCS#1 (`BEGIN RSA PRIVATE KEY`) — LibreSSL's `openssl rsa -in pkcs8.pem -out trad.pem` emits that by default (no `-traditional` flag). `security delete-key` is trimmed in macOS 26 — orphaned cert/key cleanup needs Keychain Access GUI. Orphans from the 2026-10-19 first attempt ("Beamhop Dev", login-keychain "Beamhop Sign") are inert but will prompt if something tries to use them.
  - **Screen locked = GUI automation impossible**: every app window reports "no display" (screencapture is black; `caffeinate -u` only wakes to the lock screen). TCC toggles and keychain consent must wait for an unlocked session — see `scripts/tcc-grant-runbook.md`.
- **Clipboard safe paste (§12.3)**: store raw Data per item/per type, refuse if unreadable; only ClaudeCodeDelivery restores; the clipboard fallback handoff does not.
- **Current main never synthesizes terminal Enter.** Inline Hop/Pocket copies Claude Code material for checked manual paste; legacy Inbox triggers also require manual submission. The older conditional auto-Enter behavior was removed on October 20.
- ⚠️ **Incident**: during S6 testing, scripted synthetic keystrokes + undo were sent into the user's real Notes and wiped one note (recovered). **Never send synthetic keys/undo into the user's real apps**; capture is read-only AX.
- **Inbox re-capture noise is fixed on the retrieval side, NOT at capture time** (2026-10-18, Claude's report: same GitHub page captured 13×). The DuplicateGate only covers <500ms; minutes-apart re-captures are byte-identical and stay in the DB (audit trail), but `search_captures` collapses them via `Capture.contentIdentity` (exact equality on app+title+url+selected+body — deliberately not fuzzy; near-dupes are Phase 2 embeddings work). `include_duplicates=true` restores the raw list. Soft-deleted twins are excluded from `duplicate_count`. The Inbox window UI still shows the raw list — collapse there only if dogfood says it matters.
- **SelfTest and the XCTest mirror MUST be updated together** — 2026-10-18 CI failure: plan A changed `claudeCodeTrigger` (added the save_result write-back sentence); SelfTest was updated but `Week3FeatureTests` wasn't, so every push mailed "Run failed: CI" until the mirror caught up. CI runs BOTH (`swift test` gates `swift run BeamhopSelfTest` behind it in the same job — one fails, the other never runs).
- **`plutil -lint` only accepts XML/binary plists, exits 1 on JSON** — validate JSON with `plutil -convert json -o /dev/null <file>`. Swift has no imported constant for `"AXEditable"` — use the raw string.
- **`.build/release` is a symlink to the triplet dir** — `find` doesn't follow a symlinked start point; use `find -H`. CI's `TMPDIR` has a trailing slash → `//` paths; normalize with the same `cd+pwd` on both sides of path assertions.
- **Historical acceptance Mac: Claude used the 3p deployment (Cowork/Gateway)** — only editing the legacy `Claude/` config did not affect that deployment. Do not generalize one Mac's deployment to every machine: current explicit registration updates both supported homes, and tool permissions still need real-session acceptance.
- **Historical acceptance Mac: info-level os_log was not persisted** (only errors appeared in `log show`; `log stream` was empty). Verify the current machine rather than assuming log persistence; use DB columns (`capture_duration_ms`) or an explicit timing fixture when needed.
- **macOS 26 renamed the TCC panes**: Accessibility is 设置 → 隐私与安全性 → **设备控制和数据访问** (no standalone "辅助功能"); Screen Recording is **录屏与系统录音**. Synthetic ⌘⇧Space via CGEventPost works and triggers Carbon hotkeys, but the OS occasionally drops a synthetic press (18/20 landed in the acceptance session) — sample counts should tolerate misses.
- **`pbpaste` in a `LANG=C` shell mangles UTF-8** (looks like an encoding bug, is only terminal display) — use `LANG=en_US.UTF-8 pbpaste` before debugging "corruption".
- **"Hotkey sometimes works" symptom checklist**: check the log for which PID logged the failure (old process vs current), and whether presses landed in a restart gap (`log show --predicate 'processID == <pid>'`).

---

## 7. Next steps (dependency-ordered)

**A. Fresh-package acceptance (when the user requests a new build)**

1. Build current `main` into a fresh output directory, retaining the existing acceptance bundle and its receipt. Record source commit/build ID, actual signing mode and toolchain; privately back up app data before a deliberate upgrade. Do not run two normal instances against one Inbox or treat an old binary as a v9 rollback.
2. Verify Accessibility for the exact path/signature on an unlocked Mac. Ad-hoc repacks may need re-grant; optional stable development signing is not already established on every machine. See `scripts/tcc-grant-runbook.md`.
3. Test real-source focus restoration/self-capture rejection, inline edits/newlines, pending imports, Pocket CRUD/undo/mixed-route batch retry, Inbox conclusions, and diagnostic preview/Save/Cancel. Test logged-in ChatGPT/Kimi/Claude workflows separately from fixture success; include fullscreen/Stage Manager, multiple displays and VoiceOver speech.
4. Record per-case outcomes against that exact package. Previous general "no issues" feedback and old screenshot galleries do not close this matrix.

**B. Performance and dogfood evidence**

- Re-measure real-source hotkey-to-interactive latency. The historical 211ms session mostly captured Beamhop itself; `panel_ms` measures panel-show work, not the preceding capture. It is not a current end-to-end pass.
- Run `scripts/dogfood-metrics.sh` during a deliberate dogfood session and add weekly gate tables in §9. The script exists; no unattended weekly monitor is implied, and the log is still empty.
- Re-run AX word-grab spot checks on the S6 apps and the language-toggle restart/apply flow. Keep app versions and signing/TCC state with the results.

**C. Engineering/release prerequisites and candidates**

- Full XCTest requires full Xcode on each Mac; CLT SelfTest and hosted macos-15 CI remain distinct. Installing Xcode locally is optional for documentation work, not a missing CI prerequisite.
- Developer ID signing/notarization and distribution acceptance remain public-release work. Do not claim a development identity or ad-hoc CI package meets that gate.
- Cowork MCPB end-to-end, app→extension >1MB chunking/reassembly, and multi-browser/profile routing (currently "latest host wins") remain candidates; do not implement them from historical plans without confirming scope.
- After current acceptance and two clean weeks of dogfood data, evaluate the memory route per the evolution-decisions spec §2.3 before starting Phase 2. Focus/self-capture, Inbox conclusions, Inline Hop/Pocket, MCP registration and trial-build engineering are already implemented, not a new reimplementation backlog.

---

## 8. Week 3 acceptance record (2026-10-18, on-device)

**Historical October 20 review note:** PR #7 and the subsequent PR #8 are now merged under the current CI-gated policy. Logged-in ChatGPT/Kimi draft protection and current-conversation behavior, checked manual terminal handoff, TCC capture, VoiceOver speech, fullscreen/Stage Manager and multiple displays still need package-specific acceptance. The October 18 results below describe the earlier implementation (including its old Enter/new-chat behavior), not the current Inline Hop contract.

User-verified in the October 18 session:
1. ⌘⇧Space pops the panel (after Accessibility re-grant on the fresh build) ✅
2. Target shortcuts ⌘1–⌘4 + ⌘0 present and selectable ✅
3. Enter delivers, Esc cancels (capture kept in Inbox) ✅
4. Kimi Work: paste lands in a fresh conversation, placeholder untouched ✅
5. ChatGPT Desktop v26: set-value injection into composer ✅
6. Failure fallback → clipboard + notification (Kimi/ChatGPT window closed case) ✅
7. Duplicate <500ms same-window press swallowed silently ✅

Perf P95: ✅ **2026-10-18, 20-press automated session (synthetic ⌘⇧Space via CGEventPost; panel visibility detected by screencapture crop-diff; capture_ms read from the DB `capture_duration_ms` column)**. Method deviation: this Mac does NOT persist info-level os_log messages (`log show` only ever shows errors from Beamhop, and `log stream` captures nothing) — the spec §3 grep method is unusable here, so panel latency was measured as press→panel-visible-on-screen.
- press→panel-visible: 18/20 valid samples (2 synthetic presses were dropped by the OS), min 179 / median 195 / **P95 211 / max 211 ms**. This historical observation does not establish current real-source or interactive latency.
- capture_ms (session): P95 = 6ms, but 17/20 presses captured Beamhop itself (0ms AX — see focus-stealing finding below), so this is an optimistic floor. Organic captures from that date measured Chrome 122–155ms and Kimi 3–55ms; adding separate observations is not a measured end-to-end P95. Fresh real-source sampling remains required.
- Dogfood finding: after the panel closes (Esc/deliver), frontmost stays Beamhop — the next capture grabs Beamhop itself (useless 0ms rows in the log). **Fixed in the 2026-10-19 patch**: restore source conditionally, preserve destination/user focus, reject own PID/bundle before reading or inserting. Native fixture regression passed; real-source perf sampling remains pending.

Compatibility matrix updated: `spike/compatibility-matrix-v0.json` — chatgpt_desktop versions_tested += 26.1007.71326 (dual bundle id, AXEditable gone, composer depth ~30, set-value OK); kimi_work added (paste-injection mechanism, new-chat button desc).

---

## 9. Dogfood log (weekly gate-table pastes)

> Format: date + window + the `scripts/dogfood-metrics.sh` gate table. Two clean weeks of
> data → evolution-decisions §2.3 evaluation.

- (empty — first paste due the Friday after the dogfood launch)

---

## 10. Kimi capture/delivery fix (2026-10-24, local branch codex/kimi-ax-capture-delivery)

Dogfood evidence (real Inbox, read-only): 2026-10-24 11:17/11:18 captures with frontmost =
Kimi Work stored `selectedText` = 0 chars via `ax-native`; the 11:18:48 delivery to
`kimi_work` failed with "未找到 Kimi 输入框(AXTextArea)" and fell back to clipboard, while a
settled read-only probe on the same Kimi 3.2.17 resolves the window and finds exactly one
AXTextArea at depth 18 (tree 252 nodes, well inside the 4000/40 bounds).

Root causes:
1. `com.moonshot.kimichat` missing from `AXHelper.needsManualAX` — without the
   AXManualAccessibility opt-in, Kimi's Electron web content exposes no AX selection, so
   mouse-drag-selected text inside Kimi reads empty. One-line whitelist addition.
2. Single-shot `findComposer` right after activation can race Chromium's lazy AX build
   (window published, composer not yet). Added bounded `waitForComposer` (2 s poll, same
   pattern as `waitForWindow`); KimiDelivery and ChatGPTDelivery now use it.

Validation: `git diff --check`, `swift build`, `swift run BeamhopSelfTest` (ALL PASS) on this
branch. Real-device acceptance still required: drag-select text inside Kimi → capture shows
the selection; deliver to Kimi pastes into the composer.

User-verified 2026-10-24 on the ad-hoc preview build (dist/preview-kimi-fix-20261024-180733):
drag-selected text inside Kimi captures with content (was 0 chars) and delivery to Kimi
lands in the composer (was "未找到 Kimi 输入框" → clipboard fallback). Owner accepted the fix.
