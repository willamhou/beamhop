#!/usr/bin/env bash
# Install the Chrome Native Messaging host manifest (spec §6.3) for one Chromium browser.
# The extension id is the 32-char a-p string from chrome://extensions (unpacked installs
# derive it from the load path, so it is stable per machine).
set -euo pipefail

host_bin=""
extension_id=""
browser="chrome"

usage() {
  cat >&2 <<EOF
usage: $0 --host <beamhop-bridge-binary> --extension-id <32-char-id> [--browser chrome|arc|brave|edge]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host_bin="${2:?}"; shift 2 ;;
    --extension-id) extension_id="${2:?}"; shift 2 ;;
    --browser) browser="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$host_bin" && -n "$extension_id" ]] || usage
[[ -x "$host_bin" ]] || { echo "host binary not executable: $host_bin" >&2; exit 2; }
[[ "$extension_id" =~ ^[a-p]{32}$ ]] || { echo "extension id must be 32 chars a-p" >&2; exit 2; }

case "$browser" in
  chrome) rel="Google/Chrome/NativeMessagingHosts" ;;
  arc)    rel="Arc/User Data/NativeMessagingHosts" ;;
  brave)  rel="BraveSoftware/Brave-Browser/NativeMessagingHosts" ;;
  edge)   rel="Microsoft Edge/NativeMessagingHosts" ;;
  *) echo "unknown browser: $browser" >&2; exit 2 ;;
esac

dir="$HOME/Library/Application Support/$rel"
mkdir -p "$dir"
manifest="$dir/com.beamhop.bridge.json"
host_abs="$(cd "$(dirname "$host_bin")" && pwd)/$(basename "$host_bin")"

cat > "$manifest" <<EOF
{
  "name": "com.beamhop.bridge",
  "description": "Beamhop bridge between the browser extension and the Beamhop desktop app",
  "path": "$host_abs",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$extension_id/"]
}
EOF

if command -v plutil >/dev/null 2>&1; then
  # -lint only accepts XML/binary plists; a same-format convert round-trip validates JSON.
  plutil -convert json -o /dev/null "$manifest"
fi
echo "installed $manifest"
echo "restart $browser, then reload the extension."
