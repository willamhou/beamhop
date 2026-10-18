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
grep -Fq '"name":"search_captures"' <<<"$responses"
grep -Fq '"name":"save_result"' <<<"$responses"
grep -Fq '"name":"fetch_results"' <<<"$responses"
grep -Fq 'Beamhop database unavailable' <<<"$responses"
echo "handshake + missing-db error path OK"

# --- 2. seeded DB: real capture content via tool + resource ---
cd "$repo_root"
seed_out="$(swift run -c debug BeamhopSelfTest --seed "$test_dir/inbox.sqlite")"
cap_id="$(awk '/^seeded /{print $2}' <<<"$seed_out")"
[[ -n "$cap_id" ]] || { echo "seed failed: $seed_out" >&2; exit 1; }

seeded="$({
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"capture://latest"}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_captures","arguments":{"query":"race condition"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"save_result","arguments":{"origin_capture_id":"'"$cap_id"'","content":"smoke: 结论是竞态","agent":"codex","session_id":"smoke-1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"fetch_results","arguments":{"origin_capture_id":"'"$cap_id"'"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"save_result","arguments":{"origin_capture_id":"cap_doesnotexist","content":"orphan","agent":"codex"}}}'
} | "$binary" --db "$test_dir/inbox.sqlite")"

grep -Fq '"cap_' <<<"$seeded"
grep -Fq '"contents"' <<<"$seeded"
grep -Fq 'smoke: 结论是竞态' <<<"$seeded"          # save_result echo + fetch_results read-back
grep -Fq '"isError":true' <<<"$seeded"            # FK rejection for unknown origin
# 既有路径(id 2/3)与新 tool(id 4/5/6)必须无 isError,只有 id 7(坏 origin)该报错
for rid in 2 3 4 5 6; do
  line="$(grep -F "\"id\":$rid," <<<"$seeded" || true)"
  grep -Fq '"isError"' <<<"$line" && { echo "request $rid returned isError: $line" >&2; exit 1; }
done
echo "seeded tool + resource + 方案A save/fetch/search round-trip OK"

# --- 3. no --db: falls back to the standard Inbox path under a fake HOME (missing → error, no crash) ---
fake_home="$test_dir/home"
mkdir -p "$fake_home"
fallback="$(HOME="$fake_home" "$binary" <<< '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fetch_capture","arguments":{}}}')"
grep -Fq '"id":1' <<<"$fallback"
echo "default-db fallback OK (no --db, fake HOME)"
echo "MCP smoke test passed"
