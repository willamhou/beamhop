#!/usr/bin/env bash
# host/install-manifest.sh contract test: manifest shape, path resolution, id validation.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
installer="$repo_root/host/install-manifest.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-nmh-smoke.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
[[ -x "$installer" ]] || { echo "installer missing" >&2; exit 2; }

fake_bin="$test_dir/beamhop-bridge"
printf '#!/bin/sh\nexit 0\n' > "$fake_bin"; chmod 755 "$fake_bin"

# reject a malformed extension id
if "$installer" --host "$fake_bin" --extension-id "not-a-valid-id!!" 2>/dev/null; then
  echo "installer accepted an invalid extension id" >&2; exit 1
fi

HOME="$test_dir" "$installer" --host "$fake_bin" \
  --extension-id abcdefghijklmnopabcdefghijklmnop

manifest="$test_dir/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json"
[[ -f "$manifest" ]] || { echo "manifest not written: $manifest" >&2; exit 1; }
# -lint rejects JSON (XML/binary plists only); a same-format convert round-trip validates it.
plutil -convert json -o /dev/null "$manifest"

grep -Fq '"name": "com.beamhop.bridge"' "$manifest"
grep -Fq '"type": "stdio"' "$manifest"
grep -Fq '"allowed_origins": ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"]' "$manifest"
# the manifest must pin the RESOLVED absolute host path; canonicalize BOTH sides the same way
# because $TMPDIR may end in "/" (runner) producing "//" that logical pwd may collapse.
recorded_path="$(sed -n 's/.*"path": "\(.*\)",$/\1/p' "$manifest")"
resolved_recorded="$(cd "$(dirname "$recorded_path")" && pwd)/$(basename "$recorded_path")"
resolved_expected="$(cd "$(dirname "$fake_bin")" && pwd)/$(basename "$fake_bin")"
[[ "$resolved_recorded" == "$resolved_expected" ]] || {
  echo "manifest path mismatch: recorded=$recorded_path expected=$fake_bin" >&2; exit 1; }
echo "native manifest smoke test passed"
