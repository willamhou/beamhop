#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
extension_dir="$repo_root/cowork-extension"
binary="$repo_root/.build/release/BeamhopMCP"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MCPB binary build requires macOS." >&2
  exit 2
fi

cd "$repo_root"
swift build -c release --product BeamhopMCP
mkdir -p "$extension_dir/server" "$extension_dir/dist"
cp "$binary" "$extension_dir/server/BeamhopMCP"
chmod 755 "$extension_dir/server/BeamhopMCP"
# The bundled server runs with no args, so it falls back to the standard Inbox at
# ~/Library/Application Support/beamhop/inbox.sqlite (see BeamhopMCP main.swift).

if ! command -v mcpb >/dev/null 2>&1; then
  echo "Install the official packer first: npm install -g @anthropic-ai/mcpb" >&2
  exit 3
fi

cd "$extension_dir"
mcpb pack . "dist/beamhop.mcpb"
mcpb info "dist/beamhop.mcpb"
