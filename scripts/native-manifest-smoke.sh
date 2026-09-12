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

HOME="$test_dir" bash -x "$installer" --host "$fake_bin" \
  --extension-id abcdefghijklmnopabcdefghijklmnop

manifest="$test_dir/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json"
[[ -f "$manifest" ]] || { echo "manifest not written: $manifest" >&2; exit 1; }
plutil -lint "$manifest" >/dev/null

grep -Fq '"name": "com.beamhop.bridge"' "$manifest"
grep -Fq '"type": "stdio"' "$manifest"
grep -Fq '"allowed_origins": ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"]' "$manifest"
# the manifest must pin the RESOLVED absolute host path, not a relative one
grep -Fq "\"path\": \"$fake_bin\"" "$manifest"
echo "native manifest smoke test passed"
