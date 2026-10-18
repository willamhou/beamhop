# Beamhop Week 3 — Floating-Window Delivery UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land the delivery floating panel from MVP spec §9.1 — after `⌘⇧Space` captures, pop a panel (note + ⌘1/2/3/0 target selection + Enter direct delivery + Esc keeps it in the Inbox), replacing the current Week 2 simplified flow that delivered straight to Claude Code. The same iteration ships four wrap-up items: capture dedup, BrowserCatalog convergence, extra diagnostics rows, and one-click MCP registration.

**Prerequisites (done):** main @ d6d8f35 — capture/delivery/Inbox/diagnostics ready; P1-1 moved the capture+delivery path off the main thread (the panel inherits no main-thread blocking); `AppActivator` extracted; review P2 fixes merged.

**Reference spec:** `docs/superpowers/specs/2026-09-18-week-3-floating-window.md` (this iteration's spec, incl. acceptance criteria) + MVP spec V2.1 §9.1/§9.3/§11.
**S5-measured constraints (copy verbatim, do not change):** `.floating` + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` + `isReleasedWhenClosed=false`.
**Dev mode:** Linux writes → CI (macos-15) gates → Mac accepts (engineering-convergence spec §3). **Any UI behavior claim can only say "pending acceptance" until Mac acceptance passes.**

**Output structure:**
```
Sources/Beamhop/
  Panel/          CapturePanelController.swift, CapturePanelView.swift, CapturePanelModel.swift
  Diagnostics/    + one-click MCP registration, ChatGPT/default-DB diagnostics rows
Sources/BeamhopCore/
  Support/        BrowserCatalog.swift
```

**Milestone split:**
- **3A — the panel itself (Tasks 0–3):** instrumentation → panel + keyboard flow → wiring + dedup. Completing this restores the core "pick a target in the panel" experience.
- **3B — wrap-up pack (Task 4):** BrowserCatalog + diagnostics rows + MCP registration + logging. Independent of each other; can be split into separate PRs.

---

## Task 0: timing instrumentation (before any UI)

- [x] **Step 0.1: os_signpost — two intervals**
  - `AppServices.doCapture`: capture start → captureFrontmost returns; then returns → panel `orderFront` completes.
  - Logger prints `capture_ms` and `panel_ms` with FIXED field names — Mac acceptance P95 data is grepped straight from these lines.
  - Verified: CI compiles; both lines visible in the log on the Mac.

## Task 1: CapturePanelController + View (the panel itself)

- [x] **Step 1.1: NSPanel configuration (per S5, verbatim)**
  - `styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable]`; `level = .floating`; the three collection behaviors; `isReleasedWhenClosed = false`; `hidesOnDeactivate = false`; `isMovableByWindowBackground = true`; `becomesKeyOnlyIfNeeded`.
  - `show(capture:)` → `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps: true)` (a nonactivating panel needs explicit activation to reliably receive keyboard; covered by on-device acceptance in Task 3, tune if it fails).
- [x] **Step 1.2: CapturePanelView (SwiftUI, layout per spec §2.1)**
  - Top: captured summary (app · title · char count) + 200-char body preview + URL in gray.
  - Note field: `TextField`, focused on appear (`@FocusState`).
  - Target row: ⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork (badge "→clipboard") / ⌘4 Kimi Work / ⌘0 Inbox only; the dot updates instantly.
  - Bottom: Esc cancel / ⏎ Deliver (current target name).
  - `.background(KeyboardShortcut…)` wait — implemented via `.keyboardShortcut` on buttons: ⌘1/2/3/4/0, Esc (`.cancelAction`), Enter (`.defaultAction`).
- [x] **Step 1.3: CapturePanelModel**
  - `selectedTarget: DeliveryTarget?` (initial value injected by the caller — `TargetMemory`)
  - `note: String`; `confirm()` / `cancel()` callback interface (injected by AppServices; the model holds no services).
  - Cowork button labeled "→clipboard" (unverified truth visible, spec §2.1).

## Task 2: AppServices wiring (data-flow switch)

- [x] **Step 2.1: doCapture rerouted**
  - Background capture success → **main thread** `panel.show(capture:)`; rejected still goes to Notifier.
  - Panel confirm → background `delivery.deliver(capture, selected, userNote: note)` → on success `targetMemory.markSucceeded(selected)` + notification; failure paths use DeliveryService's built-in clipboard fallback.
  - Cancel → panel dismisses, Notifier.info("Saved to Inbox", capture.id) — make explicit that nothing was lost.
- [x] **Step 2.2: focus loss = Esc**
  - Observe `NSWindow.didResignKey` (the panel observes its own notification; trigger the cancel path when resigned and not delivering).
  - Race with confirm: confirm calls `panel.orderOut` before delivering; the resign handler checks an `isDelivering` flag and skips.
- [x] **Step 2.3: default target memory (W3-3, in-memory)**
  - `AppServices` holds `TargetMemory()` (default `.claudeCode`); updated on delivery success; read at panel show.
  - **No UserDefaults** — restarting back to Claude Code is the spec's decision.
- [x] **Step 2.4: duplicate hotkey dedup (W3-4)**
  - `CaptureService` records `(bundleID, windowTitle)` + time; same key within 500ms → new case `.duplicate` → AppServices **silently ignores** (no notification, log only).
  - `CaptureOutcome` gains a `.duplicate` case; all existing switch call sites updated.

## Task 3: on-device acceptance support

- [x] **Step 3.1: acceptance list written back**
  - The 7 Mac acceptance items from spec §4 appended to PROGRESS §8 (including the P95 data-collection method: `log show --predicate 'subsystem == "com.beamhop.app"' | grep panel_ms` over 20 consecutive presses).
  - README "Build & run" gets a one-line panel description.

## Task 4: wrap-up pack (3B, can be a separate PR)

- [ ] **Step 4.1: BrowserCatalog (W3-5)**
  - `BeamhopCore/Support/BrowserCatalog.swift`: browsers (with chromium flag), `isBrowser`, `needsManualAX` (chromium + known Electron prefixes), terminalBundleIDs.
  - `CaptureService` / `AXHelper` / `TerminalLocator` delegate to it; **behavior unchanged** (copy current lists verbatim; don't sneak in additions).
  - SelfTest/XCTest gain catalog assertions (≥3 examples each for isBrowser/needsManualAX).
- [ ] **Step 4.2: extra diagnostics rows (W3-6)**
  - DiagnosticsService gains two rows: ① ChatGPT Desktop — installed? version within the compatibility matrix's versions_tested (read CompatibilityMatrixLoader's snapshot); ② MCP default DB — does `AppPaths.databaseURL` exist + row count.
- [ ] **Step 4.3: one-click MCP registration (W3-7, spec §3.4 four steps)**
  - Find claude → find BeamhopMCP → `claude mcp add beamhop -s user -- <abs>` → on failure show the copyable command.
  - Diagnostics row refreshes on success; the `claude mcp list` smoke script gains a register-verify-cleanup echo case (runs in CI without a real account — only verifies the binary exists and argument assembly; real registration is Mac acceptance).
- [ ] **Step 4.4: recordDelivery visibility (W3-8)**
  - `DeliveryService.record`'s `try?` → do/catch + Logger.error; delivery is not interrupted.

## Definition of Done (this iteration)

1. CI fully green (including new assertions)
2. All 7 Mac acceptance items from spec §4 executed and recorded (PASS/FAIL + versions)
3. PROGRESS §8 written back; P95 data pasted into PROGRESS
4. Review report P3-2/P3-4/P3-5 marked fixed
5. All pass → `verified-<YYYY-MM>` tag candidate (decide together with the remaining historical §8 items)
