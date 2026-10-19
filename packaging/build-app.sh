#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$repo_root/dist"
app_bundle="$output_dir/Beamhop.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Beamhop.app must be built on macOS." >&2
  exit 2
fi
if [[ -e "$app_bundle" ]]; then
  echo "$app_bundle already exists; move it aside before rebuilding." >&2
  exit 3
fi

cd "$repo_root"
swift build -c release --product Beamhop
swift build -c release --product BeamhopMCP

staging="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
contents="$staging/Beamhop.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$repo_root/packaging/Info.plist" "$contents/Info.plist"

# UI localization: ship the zh-Hans table as a proper lproj — the menu-bar Language
# submenu (AppleLanguages override) resolves against it on relaunch (2026-10-19).
if [[ -d "$repo_root/packaging/lproj/zh-Hans.lproj" ]]; then
  cp -R "$repo_root/packaging/lproj/zh-Hans.lproj" "$contents/Resources/zh-Hans.lproj"
fi
cp "$repo_root/.build/release/Beamhop" "$contents/MacOS/Beamhop"
cp "$repo_root/.build/release/BeamhopMCP" "$contents/MacOS/BeamhopMCP"
chmod 755 "$contents/MacOS/Beamhop" "$contents/MacOS/BeamhopMCP"

# Native messaging host (pure frame relay, no SwiftPM deps — plain swiftc per PROGRESS.md).
swiftc -O "$repo_root/host/main.swift" -o "$contents/MacOS/beamhop-bridge"
chmod 755 "$contents/MacOS/beamhop-bridge"

# SwiftPM resource bundle (compatibility matrix), layout Beamhop_Beamhop.bundle. .build/release
# is a SYMLINK to the triplet dir — find needs -H to follow the starting-point symlink.
resource_bundle="$(find -H "$repo_root/.build" -maxdepth 4 -type d -name '*Beamhop*.bundle' -print -quit)"
if [[ -z "$resource_bundle" ]]; then
  echo "SwiftPM did not produce the Beamhop resource bundle." >&2
  exit 4
fi
cp -R "$resource_bundle" "$contents/Resources/$(basename "$resource_bundle")"

plutil -lint "$contents/Info.plist"

# Stable dev signing (scripts/setup-dev-signing.sh): when the dedicated keychain exists,
# prefer the self-signed "Beamhop Sign" identity over ad-hoc — TCC then anchors the grant
# to the certificate and survives repacks (ad-hoc cdhash changes drop it every time).
dev_keychain="$HOME/Library/Keychains/beamhop-sign.keychain-db"
if [[ -z "${BEAMHOP_CODESIGN_IDENTITY:-}" && -f "$dev_keychain" ]] \
    && security find-certificate -c "Beamhop Sign" "$dev_keychain" >/dev/null 2>&1; then
  BEAMHOP_CODESIGN_IDENTITY="Beamhop Sign"
  BEAMHOP_CODESIGN_KEYCHAIN="$dev_keychain"
  echo "dev signing: using 'Beamhop Sign' from $dev_keychain"
fi

codesign_args=(--force --deep --options runtime)
if [[ -n "${BEAMHOP_CODESIGN_IDENTITY:-}" ]]; then
  if [[ -n "${BEAMHOP_CODESIGN_KEYCHAIN:-}" ]]; then
    # self-signed: no notarization-timestamp service; --timestamp=none keeps signing offline
    security unlock-keychain -p "${BEAMHOP_KEYCHAIN_PASSWORD:?Supply the signing password through a secret provider}" "$BEAMHOP_CODESIGN_KEYCHAIN" 2>/dev/null || true
    codesign_args+=(--keychain "$BEAMHOP_CODESIGN_KEYCHAIN" --timestamp=none)
  fi
  codesign "${codesign_args[@]}" --sign "$BEAMHOP_CODESIGN_IDENTITY" "$staging/Beamhop.app"
else
  codesign "${codesign_args[@]}" --sign - "$staging/Beamhop.app"
fi

mkdir -p "$output_dir"
mv "$staging/Beamhop.app" "$app_bundle"
echo "Built $app_bundle"
echo "MCP helper:  $app_bundle/Contents/MacOS/BeamhopMCP"
echo "NM host:     $app_bundle/Contents/MacOS/beamhop-bridge"
