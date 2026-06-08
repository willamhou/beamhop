#!/bin/zsh
# Fully automated S4 test — no clicks. Installs the native host manifest with the computed
# unpacked-extension ID, launches an ISOLATED Chrome instance (separate --user-data-dir, does
# NOT touch your real Chrome) that loads the extension + opens its auto-test page, then waits
# for the host to write /tmp/beamhop_s4_result.json.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
EXTDIR="$HERE/extension"
HOST="$HERE/host/beamhop-bridge"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
RESULT="/tmp/beamhop_s4_result.json"
PROFILE="/tmp/beamhop_s4_profile"

[ -x "$HOST" ] || { echo "build host first"; exit 1; }

# 1) compute the unpacked extension id from the absolute extension dir path
EXT_ID=$(python3 - "$EXTDIR" <<'PY'
import sys, hashlib
h = hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest()[:32]
print(''.join(chr(ord('a')+int(c,16)) for c in h))
PY
)
echo "ext_id = $EXT_ID"

# 2) install the native messaging host manifest (standard user location)
TARGET="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$TARGET"
cat > "$TARGET/com.beamhop.bridge.json" <<JSON
{
  "name": "com.beamhop.bridge",
  "description": "Beamhop spike S4 native host",
  "path": "$HOST",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
JSON
echo "installed manifest -> $TARGET/com.beamhop.bridge.json"

# 3) fresh result + profile, launch isolated Chrome; the service worker auto-runs on install
rm -f "$RESULT" /tmp/beamhop_s4_host_alive.txt
rm -rf "$PROFILE"
"$CHROME" \
  --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check \
  --disable-extensions-except="$EXTDIR" \
  --load-extension="$EXTDIR" \
  "chrome-extension://$EXT_ID/auto.html" about:blank \
  >/tmp/beamhop_s4_chrome.log 2>&1 &
CHROME_PID=$!
echo "launched isolated Chrome pid=$CHROME_PID, waiting for result…"

# 4) poll for the result file (up to ~40s)
for i in $(seq 1 40); do
  [ -f "$RESULT" ] && break
  sleep 1
done

echo "=== host alive marker (did connectNative spawn the host?) ==="
cat /tmp/beamhop_s4_host_alive.txt 2>/dev/null || echo "(host NEVER spawned — manifest/origin/ID mismatch)"
if [ -f "$RESULT" ]; then
  echo "=== RESULT ==="
  cat "$RESULT"
else
  echo "=== NO RESULT after 40s — see /tmp/beamhop_s4_chrome.log ==="
fi

# 5) cleanup: kill the isolated Chrome, remove profile + manifest (throw-away)
kill "$CHROME_PID" 2>/dev/null || true
pkill -f "$PROFILE" 2>/dev/null || true
rm -rf "$PROFILE"
rm -f "$TARGET/com.beamhop.bridge.json"
echo "cleaned up isolated profile + manifest."
