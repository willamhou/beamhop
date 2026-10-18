#!/usr/bin/env bash
# Dogfood metrics report (evolution-decisions §3 gate) from the local inbox.sqlite.
# Usage: scripts/dogfood-metrics.sh [--days N] [--db PATH]
# Env overrides: BEAMHOP_DB, BEAMHOP_SELFTEST_BINARY. All data stays local.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
days=14
db="${BEAMHOP_DB:-$HOME/Library/Application Support/beamhop/inbox.sqlite}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) days="${2:?--days needs a value}"; shift 2 ;;
    --db) db="${2:?--db needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1 (usage: $0 [--days N] [--db PATH])" >&2; exit 2 ;;
  esac
done

binary="${BEAMHOP_SELFTEST_BINARY:-$repo_root/.build/debug/BeamhopSelfTest}"
[[ -x "$binary" ]] || { echo "Build first: swift build" >&2; exit 2; }
[[ -f "$db" ]] || { echo "No inbox database at: $db" >&2
                     echo "Capture something first (or pass --db / set BEAMHOP_DB)." >&2; exit 2; }

exec "$binary" --dogfood "$db" --days "$days"
