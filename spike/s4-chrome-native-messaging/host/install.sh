#!/bin/zsh
# Usage: ./install.sh <EXTENSION_ID>
# Generates com.beamhop.bridge.json from the template (filling in the absolute host
# path + your extension ID) and installs it into every Chromium browser found.
set -e
EXT_ID="$1"
if [ -z "$EXT_ID" ]; then echo "usage: ./install.sh <EXTENSION_ID>"; exit 1; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
HOST_PATH="$HERE/beamhop-bridge"
if [ ! -x "$HOST_PATH" ]; then echo "build first: swiftc -O main.swift -o beamhop-bridge"; exit 1; fi

OUT="$HERE/com.beamhop.bridge.json"
sed -e "s#__HOST_PATH__#$HOST_PATH#" -e "s#__EXT_ID__#$EXT_ID#" \
    "$HERE/com.beamhop.bridge.json.template" > "$OUT"
echo "generated $OUT"

install_to() {
  local label="$1" base="$2"
  if [ -d "$base" ]; then
    mkdir -p "$base/NativeMessagingHosts"
    cp "$OUT" "$base/NativeMessagingHosts/"
    echo "installed -> $label"
  fi
}
install_to "Chrome"  "$HOME/Library/Application Support/Google/Chrome"
install_to "Arc"     "$HOME/Library/Application Support/Arc/User Data"
install_to "Brave"   "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
install_to "Edge"    "$HOME/Library/Application Support/Microsoft Edge"
echo "done. Reload the extension at chrome://extensions/ then click 'Ping native host'."
