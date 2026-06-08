#!/bin/zsh
# Automated S6 sweep (race-proof, READ-ONLY-SAFE).
# Each app: axprobe_once self-activates it, waits until it's truly frontmost, sends ONE ⌘A
# (select-all — apps intercept this as a menu action; it does NOT reach a shell's PTY), then
# reads kAXSelectedText. NO typing, NO undo, NO other keystrokes → content is never modified.
# Notes is intentionally SKIPPED (already a confirmed PASS) to avoid re-touching a user note.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE="$HERE/axprobe_once"
OUT="$HERE/results.jsonl"
: > "$OUT"

if ! "$PROBE" --trust >/dev/null 2>&1; then
  echo "ABORT: Accessibility not granted (axprobe_once --trust = false)."; exit 1
fi

# browsers + slack need content loaded first
open -b com.apple.Safari  "https://example.com"           2>/dev/null || true
open -b com.google.Chrome "https://news.ycombinator.com"  2>/dev/null || true
open -b com.tinyspeck.slackmacgap                          2>/dev/null || true
open -b com.googlecode.iterm2                              2>/dev/null || true
open -b com.todesktop.230313mzl4w4u92                      2>/dev/null || true
sleep 4

probe() {
  echo "--- $2 ($1) ---"
  "$PROBE" --app "$1" --selectall 2>&1 | tee -a "$OUT" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    st=d.get('selected_text','') or ''
    print('  front_locked=%s role=%s | window_title=%r | selected_len=%d | url=%s' % (
        d.get('front_locked'), d.get('focused_role',''), (d.get('window_title','') or '')[:40],
        len(st), d.get('url','—')))
    print('  selected_head=%r' % st[:80])
except Exception as e:
    print('  parse-fail', e)
"
}

probe com.apple.Safari                "Safari"
probe com.google.Chrome               "Chrome"
probe com.tinyspeck.slackmacgap       "Slack"
probe com.microsoft.VSCode            "VS Code"
probe com.todesktop.230313mzl4w4u92   "Cursor"
probe com.googlecode.iterm2           "iTerm"
probe com.apple.mail                  "Mail"
echo "=== done. (Notes skipped — prior PASS.) full json in $OUT ==="