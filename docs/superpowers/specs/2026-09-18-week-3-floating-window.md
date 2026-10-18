# Beamhop Week 3 — Floating-Window Delivery UI Spec

> Date: 2026-09-18
> Status: V1 — implemented & user-verified 2026-10-18 (implemented as specified; BrowserCatalog / diagnostics rows / MCP one-click registration from W3-5..W3-8 still open); implementation plan at `docs/superpowers/plans/2026-09-18-week-3-implementation.md`
> Positioning: the landing of MVP spec V2.1 §9.1 (floating window) + a wrap-up iteration pack. With this done, Phase 1's user-visible shape is complete.

## TL;DR

After `⌘⇧Space` captures, instead of delivering immediately, a **keyboard-first floating panel** pops up: the cursor lands in the note field, ⌘1/2/3/0 pick the target, Enter delivers, Esc cancels (the capture is already in the Inbox, nothing is lost). The panel uses the S5-measured configuration and can float above fullscreen apps. The same iteration packs four wrap-up items: capture dedup, BrowserCatalog convergence, extra diagnostics rows, and one-click MCP registration.

## 1. Goals and non-goals

### 1.1 Goals (delivered this iteration)

| # | Capability | Basis |
|---|---|---|
| W3-1 | Floating delivery UI (note + target selection + keyboard flow) | MVP spec §9.1 |
| W3-2 | Panel window behavior (visible over fullscreen / Stage Manager / all Spaces; focus loss = cancel) | S5 measurements + spec §11 |
| W3-3 | Default target memory (within session = last successful target) | spec §9.1 |
| W3-4 | Duplicate hotkey dedup (<500ms same window does not enter the Inbox twice) | spec §11 |
| W3-5 | BrowserCatalog convergence (single source for browser/terminal lists) | review P3-2 |
| W3-6 | Extra diagnostics rows (ChatGPT AX path, MCP default DB) | review P3-5 |
| W3-7 | One-click Claude Code MCP registration (diagnostics button) | PROGRESS §7C |
| W3-8 | `recordDelivery` write failures become visible logs | review P3-4 |

### 1.2 Non-goals (explicitly out)

- **Screenshot checkbox**: no ScreenshotService in the Mac build yet; handled in Week 5/Phase 1.5 per plan. The panel does not show a screenshot checkbox (a permanently grayed option is worse than none)
- **ChatGPT auto-Enter toggle**: spec defers to Phase 1.5
- **Delivery target auto-suggestion**: "guessing" intelligence goes to Phase 2
- **Editing capture content inside the panel**: a capture is data, not a document
- **Multi-display position memory**: dual-display untested in S5, no promises yet

## 2. UX design

### 2.1 Layout (spec §9.1 prototype, adjusted)

```
┌──────────────────────────────────────────────────────────┐
│ 📋 Captured  Safari · Fix race condition in queue · 1.2k │
│ [first 200 chars of body preview + URL in gray]           │
│ ──────────────────────────────────────────────────────── │
│ Note (optional): [cursor waits here____________________]  │
│ ──────────────────────────────────────────────────────── │
│ Deliver to:  ⌘1 ● Claude Code  ⌘2 ○ ChatGPT  ⌘3 ○ Cowork*│
│              ⌘4 ○ Kimi Work                               │
│              ⌘0 ○ Inbox only                              │
│           (*Cowork unverified, actually clipboard —       │
│             labeled as such inside the panel)             │
│              Esc cancel      ⏎ Deliver (Claude Code)      │
└──────────────────────────────────────────────────────────┘
```

### 2.2 Keyboard flow (core invariants — acceptance checks one by one)

1. When the panel pops up, the cursor is **already in the note field**
2. ⌘1/2/3/4/0 switch the target; the dot updates instantly, and the Enter button label follows
3. **Enter delivers the currently selected target directly** — the whole flow is mouse-free
4. **Esc cancels the trigger** — the capture is already in the Inbox, nothing is lost (say so in the notification)
5. **Panel losing focus (clicking elsewhere) = Esc-equivalent**
6. Delivery runs on a **background thread** (reuses the P1-1 dispatch pattern); the panel dismisses immediately + a system notification fires on completion
7. Pressing ⌘⇧Space again while a capture is in flight: <500ms and same window → ignore as duplicate (W3-4); otherwise treat as a new capture and replace the panel content

### 2.3 Default target rule (spec §9.1 — no intelligence)

- First time in a session: Claude Code
- After that: the last **successful** delivery target **in this session** (in-memory; a restart returns to Claude Code — no persistence; "predictable" beats "clever")

## 3. Technical design

### 3.1 Window (S5-measured conclusions — copy verbatim)

```swift
let panel = NSPanel(contentRect:…, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], …)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.isReleasedWhenClosed = false          // S5: hide, not destroy
panel.hidesOnDeactivate = false             // focus-loss handling is ours (=Esc), not the system's
panel.isMovableByWindowBackground = true
```

- `.nonactivatingPanel`: popping up does **not** activate Beamhop or steal focus from the source app, but the panel itself can `makeKey` to receive keyboard input
- Focus-loss detection: observe `NSWindow.didResignKey` → take the same path as Esc (dismiss + capture stays in the Inbox)
- Cowork-unverified labeling: small "→clipboard" next to the target button — don't hide the truth

### 3.2 Data-flow rewiring (changes to existing code)

```
old: doCapture(background) → capture → delivery.deliver(.claudeCode) → notify
new: doCapture(background) → capture → showPanel(capture) on the MAIN thread
    → user presses Enter → delivery.deliver(selected) (background) → dismiss + notify + remember default target
    → Esc/focus loss → dismiss (capture already in the Inbox)
```

- `AppServices` owns `CapturePanelController` (same lazy pattern as Inbox/Diagnostics)
- The delivery completion callback refreshes the Inbox model (if an Inbox window is open)
- **Timing instrumentation from capture to panel-visible** (os_signpost): this is the acceptance data source for spec §16 P95 ≤ 300ms — instrument from day one

### 3.3 BrowserCatalog (W3-5)

New `BeamhopCore/Support/BrowserCatalog.swift` (lives in Core for unit testability):

```swift
public enum BrowserCatalog {
    public struct Entry { public let bundleID: String; public let chromium: Bool }
    /// Mainstream browsers: the chromium flag drives AXManualAccessibility opt-in + native manifest path
    public static let browsers: [Entry] = [.safari, .chrome, .arc, .brave, .edge]
    public static func isBrowser(_ bundleID: String) -> Bool
    public static func needsManualAX(_ bundleID: String) -> Bool   // chromium || known Electron
    public static let terminalBundleIDs: Set<String>               // migrated from TerminalLocator
}
```

`CaptureService.isBrowser`, `AXHelper.needsManualAX`, and `TerminalLocator.terminalBundleIDs` all delegate to it; the compatibility-matrix JSON remains "measured evidence" — do not merge responsibilities.

### 3.4 One-click MCP registration (W3-7)

Upgrade the diagnostics-panel "Claude Code MCP" row's fix action:

1. Locate the `claude` binary (`/usr/local/bin`, `/opt/homebrew/bin`, PATH)
2. Locate BeamhopMCP: prefer the `.build` product → embedded in `Bundle.main` (when packaged)
3. `Process` runs `claude mcp add beamhop -s user -- <abs-bin>` (the exact form verified in S1)
4. On failure → show the **full copyable command** + an open-Terminal button (the existing degradation does not regress)

### 3.5 Dedup (W3-4)

`CaptureService` records `(bundleID, windowTitle?, last time)`; same key within 500ms → return `.duplicate` — and this outcome **shows no error notification** (it is expected behavior); silently ignore + log only.

## 4. Acceptance criteria

**CI-verifiable** (macos-15):
- Everything compiles + SelfTest (new tests for BrowserCatalog and default-target logic)
- Existing smokes don't regress

**Mac on-device acceptance** (appended to PROGRESS §8):
1. With fullscreen Safari/VS Code, ⌘⇧Space → panel visible and keyboard-receivable (S5 scenario)
2. Pure keyboard flow: capture → type note → ⌘2 → Enter → ChatGPT injection succeeds
3. After Esc, the capture is in the Inbox with no delivery record
4. Clicking elsewhere (focus loss) behaves like Esc
5. Pressing ⌘⇧Space twice (<500ms) produces only one capture
6. Capture→panel timing logged: P95 ≤ 300ms (20 consecutive samples)
7. Diagnostics-panel one-click MCP registration works on device (`claude mcp list` shows beamhop)

## 5. Risks

| Risk | Mitigation |
|---|---|
| Edge-case combinations of `.nonactivatingPanel` and keyboard focus (first press after screen lock, Stage Manager) | S5-tested configuration as the floor; acceptance list covers all scenarios; degrade to "panel activates the app" if it fails, then re-evaluate |
| `makeKey` failing over a fullscreen app | S5 concluded it works; covered by on-device acceptance; if it fails, document "exit fullscreen first" |
| Slow capture (AX 800ms timeouts ×N) squeezing the 300ms budget | Instrumentation separates capture time from panel-show time; if over budget, parallelize AX reads first |

---

**End of document. Next step: implement per `plans/2026-09-18-week-3-implementation.md`; Linux development + CI gate + Mac acceptance.**
