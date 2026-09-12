#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${BEAMHOP_MCP_BINARY:-$repo_root/.build/debug/beamhop-mcp}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-mcp-smoke.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

[[ -x "$binary" ]] || { echo "Build beamhop-mcp before running this test." >&2; exit 2; }

responses="$({
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}'
} | "$binary" --database "$test_dir/inbox.sqlite")"

grep -Fq '"protocolVersion":"2025-06-18"' <<<"$responses"
grep -Fq '"name":"fetch_capture"' <<<"$responses"
grep -Fq '"readOnlyHint":true' <<<"$responses"
grep -Fq 'No captures are available' <<<"$responses"

content_request='{"jsonrpc":"2.0","id":4,"method":"ping","params":{}}'
content_response="$(
  printf 'Content-Length: %s\r\n\r\n%s' "${#content_request}" "$content_request" |
    "$binary" --database "$test_dir/content-length.sqlite"
)"
grep -Fq 'Content-Length:' <<<"$content_response"
grep -Fq '"id":4' <<<"$content_response"
echo "MCP smoke test passed"
