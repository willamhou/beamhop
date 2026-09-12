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
swift build -c release --product beamhop-mcp
swift build -c release --product beamhop-native-host

staging="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
contents="$staging/Beamhop.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$repo_root/packaging/Info.plist" "$contents/Info.plist"
cp "$repo_root/.build/release/Beamhop" "$contents/MacOS/Beamhop"
cp "$repo_root/.build/release/beamhop-mcp" "$contents/MacOS/beamhop-mcp"
cp "$repo_root/.build/release/beamhop-native-host" "$contents/MacOS/beamhop-native-host"
chmod 755 "$contents/MacOS/Beamhop" "$contents/MacOS/beamhop-mcp" "$contents/MacOS/beamhop-native-host"

resource_bundle="$(find "$repo_root/.build/release" -maxdepth 1 -type d -name '*BeamhopApp*.bundle' -print -quit)"
if [[ -z "$resource_bundle" ]]; then
  echo "SwiftPM did not produce the BeamhopApp resource bundle." >&2
  exit 4
fi
cp -R "$resource_bundle" "$staging/Beamhop.app/$(basename "$resource_bundle")"

plutil -lint "$contents/Info.plist"
if [[ -n "${BEAMHOP_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$BEAMHOP_CODESIGN_IDENTITY" "$staging/Beamhop.app"
else
  codesign --force --deep --sign - "$staging/Beamhop.app"
fi

mkdir -p "$output_dir"
mv "$staging/Beamhop.app" "$app_bundle"
echo "Built $app_bundle"
echo "MCP helper: $app_bundle/Contents/MacOS/beamhop-mcp"
echo "Native host: $app_bundle/Contents/MacOS/beamhop-native-host"
