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
cp "$repo_root/.build/release/Beamhop" "$contents/MacOS/Beamhop"
cp "$repo_root/.build/release/BeamhopMCP" "$contents/MacOS/BeamhopMCP"
chmod 755 "$contents/MacOS/Beamhop" "$contents/MacOS/BeamhopMCP"

# Native messaging host (pure frame relay, no SwiftPM deps — plain swiftc per PROGRESS.md).
swiftc -O "$repo_root/host/main.swift" -o "$contents/MacOS/beamhop-bridge"
chmod 755 "$contents/MacOS/beamhop-bridge"

# SwiftPM resource bundle (compatibility matrix). Layout is Beamhop_Beamhop.bundle; match loosely.
resource_bundle="$(find "$repo_root/.build/release" -maxdepth 1 -type d -name '*Beamhop*.bundle' -print -quit)"
if [[ -z "$resource_bundle" ]]; then
  echo "SwiftPM did not produce the Beamhop resource bundle." >&2
  exit 4
fi
cp -R "$resource_bundle" "$contents/Resources/$(basename "$resource_bundle")"

plutil -lint "$contents/Info.plist"
if [[ -n "${BEAMHOP_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$BEAMHOP_CODESIGN_IDENTITY" "$staging/Beamhop.app"
else
  codesign --force --deep --sign - "$staging/Beamhop.app"
fi

mkdir -p "$output_dir"
mv "$staging/Beamhop.app" "$app_bundle"
echo "Built $app_bundle"
echo "MCP helper:  $app_bundle/Contents/MacOS/BeamhopMCP"
echo "NM host:     $app_bundle/Contents/MacOS/beamhop-bridge"
