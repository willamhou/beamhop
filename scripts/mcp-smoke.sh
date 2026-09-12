#!/usr/bin/env bash
# MCP stdio smoke test against the REAL BeamhopMCP binary (newline-delimited JSON per S1).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${BEAMHOP_MCP_BINARY:-$repo_root/.build/debug/BeamhopMCP}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-mcp-smoke.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

[[ -x "$binary" ]] || { echo "Build BeamhopMCP first (swift build)." >&2; exit 2; }

# --- 1. protocol handshake + tool listing + graceful "db missing" error path ---
responses="$({
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}'
} | "$binary" --db "$test_dir/missing.sqlite")"

grep -Fq '"protocolVersion":"2025-06-18"' <<<"$responses"
grep -Fq '"name":"fetch_capture"' <<<"$responses"
grep -Fq 'Beamhop database unavailable' <<<"$responses"
echo "handshake + missing-db error path OK"

# --- 2. seeded DB: real capture content via tool + resource ---
cd "$repo_root"
swift run -c debug BeamhopSelfTest --seed "$test_dir/inbox.sqlite" >/dev/null

seeded="$({
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"capture://latest"}}'
} | "$binary" --db "$test_dir/inbox.sqlite")"

grep -Fq '"cap_' <<<"$seeded"
grep -Fq '"isError"' <<<"$seeded" && { echo "seeded tool call returned isError" >&2; exit 1; }
grep -Fq '"contents"' <<<"$seeded"
echo "seeded tool + resource read OK"

# --- 3. no --db: falls back to the standard Inbox path under a fake HOME (missing → error, no crash) ---
fake_home="$test_dir/home"
mkdir -p "$fake_home"
fallback="$(HOME="$fake_home" "$binary" <<< '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}')"
grep -Fq '"id":1' <<<"$fallback"
echo "default-db fallback OK (no --db, fake HOME)"
echo "MCP smoke test passed"
