# S4 — Chrome Native Messaging

## Status: ✅ PASS — fully automated end-to-end in real Chrome (2026-06-08)
Tested against real Chrome 148, **zero manual clicks** (see automation note below). Evidence:
`results.json`.

### Results
- **Round-trip works**: `ping` → `{pong:true, host_version:"0.0.2"}`; 900KB echo exact match.
- **Latency (900KB, 10 runs, fresh host process PER call incl. spawn overhead):**
  **median 18.7ms, p95 27.5ms** — comfortably under the 100ms pass criterion. ✅
- **Host→extension ~1MB limit CONFIRMED empirically:**
  | payload | result |
  |---|---|
  | 900 KB (921600) | ✅ match |
  | 1.1 MB (1153434) | ❌ `Error when communicating with the native messaging host` |
  | 2 MB (2097152) | ❌ same |
  Chrome's own log: `Native Messaging host tried sending a message that is 1153471 bytes long.`
  → **application-layer chunking is REQUIRED for any capture that could exceed ~1MB.**

### How it was automated (Chrome 137+ removed `--load-extension`)
Command-line `--load-extension` (even with `--test-type`) is ignored by modern Chrome. The
working path: launch Chrome with `--remote-debugging-pipe --enable-unsafe-extension-debugging`,
then over the CDP **pipe** transport (the `Extensions` domain is gated to pipe, not port) call
`Extensions.loadUnpacked` → returns the extension id → write the native-host manifest with that
id → `Target.createTarget`/`Page.navigate` to `auto.html`, whose script auto-runs ping + bench +
boundary probes and reports results through the host (which writes `/tmp/beamhop_s4_result.json`).
Driver: `cdp_pipe.js` (throw-away). Isolated `--user-data-dir`, does not touch the user's Chrome.
Note: with a custom `--user-data-dir`, the manifest had to also be written to
`<profile>/NativeMessagingHosts/`; real users on the default profile use the standard
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` path.

### Not yet covered
- Arc / Brave / Edge (only Chrome tested). Per-browser manifest paths still as documented below.
- The real product must implement the app-layer chunking protocol + test its reassembly.

### ⚠️ Accuracy corrections (codex review 2026-06-08)
- The earlier claim "~1MB payloads chunk OK" is **overstated** — only 900KB **single-frame**
  at the process level was tested; **no chunking was exercised and Chrome was never in the loop**.
- **Real constraint to validate:** Chrome native messaging caps **native-host→extension**
  messages at **~1MB**. This host can emit a >1MB response (echo) with no app-layer chunking,
  so a large capture would be dropped by Chrome. The real Beamhop bridge **must implement an
  application-layer chunking/streaming protocol**, not rely on the OS pipe. The Chrome run
  must test 900KB / 1.1MB / 2MB boundaries explicitly.
- Code-level (do not ship as-is): `UInt32` read via `load(as:)` can trap on misalignment
  (use `loadUnaligned`/byte-decode); `try!` on JSON encode can crash the host (return a framed
  error); extension `background.js` has no request timeout and doesn't clear listeners on host
  disconnect; `install.sh` builds JSON via `sed` without escaping (use a real JSON encoder).

## Manual steps
1. `cd host && swiftc -O main.swift -o beamhop-bridge` (already built).
2. Chrome → `chrome://extensions/` → enable Developer mode → "Load unpacked" →
   select `spike/s4-chrome-native-messaging/extension`. Copy the extension ID.
3. `cd host && ./install.sh <EXTENSION_ID>` — generates the host manifest with the
   absolute binary path + your ext ID and installs it to every Chromium browser found.
4. Reload the extension (refresh icon on its card).
5. Click the toolbar icon → "Ping native host" → expect `{pong:true, host_version:"0.0.2"}`.
6. "10x 900KB round-trip benchmark" → record median + p95 below.
7. Boundary probe (proves Chrome's host→extension ~1MB limit): click "echo 900 KB",
   "echo 1.1 MB", "echo 2 MB" in turn. Expectation: 900KB succeeds; 1.1MB & 2MB FAIL
   (host disconnects / message dropped) → confirms app-layer chunking is required.
8. Repeat in Arc / Brave / Edge if installed (each needs its own extension load + reload).

If "Specified native messaging host not found": check the manifest path, that the ext ID
in `allowed_origins` matches, and that `beamhop-bridge` is executable.

Cleanup after recording: `rm` the `com.beamhop.bridge.json` from each browser's
`NativeMessagingHosts/` dir and remove the unpacked extension.

## Hypothesis
4-byte LE length + JSON framing works; round-trip < 100ms; ~1MB payloads chunk OK.
(Status: framing ✓ at process level; round-trip + chunking NOT yet validated in Chrome —
see corrections above. The ~1MB extension-bound limit means chunking is REQUIRED, not optional.)

## Implementation note (lesson carried from S1)
Host reads with raw POSIX `read()` in an exact-length loop (`readExactly`), NOT
`FileHandle.read(upToCount:)` — the latter blocks until the full count or EOF and would
deadlock when Chrome delivers a large body in multiple chunks. Confirmed correct with the
900KB process-level echo.

## Evidence (fill after Chrome run)
- Ping: <ms>
- 900KB single (via Chrome): <ms>
- 10-run bench median/p95: <ms>/<ms>
- Process-level 900KB echo (no Chrome): 7.6ms, exact byte match ✓
- Browsers tested: Chrome [v.?] [ ], Arc [ ], Brave [ ], Edge [ ]

## Conclusion
[x] **PASS** — native messaging round-trip works in Chrome at median 18.7ms (≪100ms target).
The hypothesis's "1MB chunked OK" is **corrected**: a single host→extension message is capped
at ~1MB by Chrome, so the product MUST chunk at the application layer (not optional). No need
to fall back to a local HTTP port.

## Spec patch needed
- §6.3 "Chrome MV3 native messaging 关键约束": confirm/update chunking bullet; note the
  exact-length read requirement on the host side.
- Add per-browser manifest path table to §6.3:
  - Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
  - Arc:    `~/Library/Application Support/Arc/User Data/NativeMessagingHosts/`
  - Brave:  `~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/`
  - Edge:   `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/`
