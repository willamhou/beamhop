# Beamhop Native Messaging Host

The Chrome extension starts this executable through `com.beamhop.bridge.json`. Chrome messages use its required 4-byte little-endian length prefix followed by UTF-8 JSON. The host rejects browser frames at 64 KiB and keeps host frames below 1 MiB.

Logical messages have this shape:

```json
{
  "protocolVersion": 1,
  "requestId": "uuid",
  "route": "browser.captureCurrentTab",
  "payload": {},
  "sentAt": "2026-08-23T00:00:00Z"
}
```

Each logical message is UTF-8 encoded, checksummed with FNV-1a, base64 encoded in chunks, and reassembled by `transferId`. Receivers acknowledge chunks and completion. Missing acknowledgements are retried twice; incomplete transfers expire after 15 seconds.

## Desktop app transport

The host connects to `~/Library/Application Support/beamhop/bridge.sock`, or `BEAMHOP_BRIDGE_SOCKET` when set. The desktop side owns the Unix domain socket and exchanges the same logical JSON messages using 4-byte little-endian framing. This makes requests bidirectional: send `browser.captureCurrentTab` through the socket and receive `browser.captureResult` with the same `requestId`.

Browser-to-app delivery always uses `~/Library/Application Support/beamhop/browser-inbox` as its durable source of truth. The host has already reassembled and verified all browser chunks before it atomically publishes a complete logical JSON file. Socket availability is never reported as business-level delivery.

Queue contract:

- Directory mode is `0700`; files are mode `0600`.
- Published names strictly match `<13-digit-epoch-ms>-<lowercase-uuid>.json`.
- Each file is at most 8 MiB. At 100 files or 20 MiB the host rejects the new transfer with `QUEUE_WRITE_FAILED`; it never deletes an older message that was already acknowledged.
- The app scans only matching `.json` names and atomically renames one to `.<original>.processing-<app-uuid>` to claim it.
- After its database transaction commits, the app deletes the claimed file. On a recoverable failure it renames it to the original name. At launch it returns processing files older than five minutes to their original names.
- Queue files contain the logical JSON shown above, not chunk envelopes. `route: browser.captureResult` contains `payload.ok` and either `payload.capture` or `payload.error`.

When connected, the socket receives a small `bridge.queueAvailable` notification with `payload.queueDirectory` and, when applicable, `payload.fileName`; the app should still use the claim protocol instead of treating that notification as payload delivery. On reconnect, a notification without `fileName` means "rescan the directory".

## Install manifests

After building the executable and loading the unpacked extension, copy its 32-character id from `chrome://extensions`:

```bash
Sources/BeamhopNativeHost/install-manifest.sh \
  --host /absolute/path/to/BeamhopNativeHost \
  --extension-id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --browser chrome --browser brave
```

Use `--dry-run` to inspect destinations. With no `--browser`, the script installs only for detected Chrome, Chrome Canary, Chromium, Arc, Brave, and Edge profiles.
