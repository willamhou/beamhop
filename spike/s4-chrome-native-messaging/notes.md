# S4 — Chrome Native Messaging

## Status: ⏳ BUILT + PROCESS-LEVEL VERIFIED, AWAITING CHROME RUN
Host (`beamhop-bridge`) and the MV3 extension are complete and compile. The native
framing was verified at the process level (Python harness, no Chrome): ping ok, and a
900KB echo round-tripped with an exact byte match in ~7.6ms. The remaining manual part
is loading the extension in Chrome and clicking the buttons.

## Manual steps
1. `cd host && swiftc -O main.swift -o beamhop-bridge` (already built).
2. Chrome → `chrome://extensions/` → enable Developer mode → "Load unpacked" →
   select `spike/s4-chrome-native-messaging/extension`. Copy the extension ID.
3. `cd host && ./install.sh <EXTENSION_ID>` — generates the host manifest with the
   absolute binary path + your ext ID and installs it to every Chromium browser found.
4. Reload the extension (refresh icon on its card).
5. Click the toolbar icon → "Ping native host" → expect `{pong:true, host_version:"0.0.1"}`.
6. "Send 900KB payload" → record round-trip ms.
7. "Run 10 round-trip benchmark" → record median + p95 below.
8. Repeat in Arc / Brave / Edge if installed (each needs its own extension load + reload).

If "Specified native messaging host not found": check the manifest path, that the ext ID
in `allowed_origins` matches, and that `beamhop-bridge` is executable.

Cleanup after recording: `rm` the `com.beamhop.bridge.json` from each browser's
`NativeMessagingHosts/` dir and remove the unpacked extension.

## Hypothesis
4-byte LE length + JSON framing works; round-trip < 100ms; ~1MB payloads chunk OK.

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
[ ] PASS  [ ] FAIL  [ ] PARTIAL

## Spec patch needed
- §6.3 "Chrome MV3 native messaging 关键约束": confirm/update chunking bullet; note the
  exact-length read requirement on the host side.
- Add per-browser manifest path table to §6.3:
  - Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
  - Arc:    `~/Library/Application Support/Arc/User Data/NativeMessagingHosts/`
  - Brave:  `~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/`
  - Edge:   `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/`
