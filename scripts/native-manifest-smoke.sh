#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-native-manifest.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
host="$test_dir/beamhop-native-host"
base="$test_dir/Application Support"
extension_id="abcdefghijklmnopabcdefghijklmnop"

touch "$host"
chmod 755 "$host"
mkdir -p "$base/Google/Chrome"
"$repo_root/Sources/BeamhopNativeHost/install-manifest.sh" \
  --host "$host" --extension-id "$extension_id" --browser chrome --base-dir "$base"

manifest="$base/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json"
jq -e --arg host "$host" --arg origin "chrome-extension://$extension_id/" \
  '.name == "com.beamhop.bridge" and .path == $host and .allowed_origins == [$origin]' \
  "$manifest" >/dev/null

if mode="$(stat -f '%Lp' "$manifest" 2>/dev/null)"; then
  :
else
  mode="$(stat -c '%a' "$manifest")"
fi
[[ "$mode" == "600" ]] || { echo "Expected manifest mode 600, got $mode" >&2; exit 3; }
echo "Native manifest smoke test passed"
