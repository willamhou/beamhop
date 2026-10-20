#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="${1:-$repo_root/dist/Beamhop.app}"
output_dir="${2:-$repo_root/dist/ui-smoke}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Native UI smoke tests require macOS." >&2
  exit 2
fi
mkdir -p "$output_dir"

# Run only our fixture harness. No global synthetic input, capture permissions, real
# agent apps, or user database. Finder is the source app for activation checks.
python3 - "$app_bundle/Contents/MacOS/Beamhop" "$output_dir" <<'PY'
import html
import json
import pathlib
import subprocess
import sys

binary, output = sys.argv[1], pathlib.Path(sys.argv[2])
failed = False
for language in ("en", "zh-Hans"):
    for appearance in ("light", "dark"):
        subprocess.run(["open", "-a", "Finder"], check=True)
        args = [binary, "--ui-smoke", str(output), "-AppleLanguages", f"({language})"]
        if language == "zh-Hans":
            args.append("--zh")
        if appearance == "dark":
            args.append("--dark")
        try:
            result = subprocess.run(args, timeout=120, capture_output=True, text=True)
            log = result.stdout + result.stderr
            print(log, flush=True)
            (output / f"log-{language}-{appearance}.txt").write_text(log)
            failed |= result.returncode != 0
        except subprocess.TimeoutExpired:
            print(f"Native UI timed out: {language} {appearance}", flush=True)
            failed = True

reports = [json.loads(p.read_text()) for p in sorted(output.glob("report-*.json"))]
failed |= len(reports) != 4
parts = ["<!doctype html><meta charset='utf-8'><title>Beamhop native UI</title>",
         "<style>body{font:15px system-ui;background:#f5f5f7;padding:32px}section{margin:40px 0}"
         "figure{display:inline-block;vertical-align:top;margin:12px}img{max-width:420px;border-radius:12px}"
         "figcaption{margin:12px 0;color:#666}.fail{color:#b22}</style>",
         "<h1>Beamhop · native macOS UI</h1>",
         "<p>Production AppKit/SwiftUI views, fixture data. These checks do not validate external agent integrations.</p>"]
for report in reports:
    checks = report["checks"]
    failures = [c for c in checks if not c["passed"]]
    failed |= bool(failures)
    parts.append(f"<section><h2>{report['language']} · {report['appearance']}</h2>"
                 f"<p>{len(checks)-len(failures)}/{len(checks)} checks passed</p>")
    for check in failures:
        parts.append("<p class='fail'>" + html.escape(check["name"] + ": " + check["detail"]) + "</p>")
    for snapshot in report["snapshots"]:
        file = html.escape(snapshot["file"])
        parts.append(f"<figure><img src='{file}'><figcaption>{file}</figcaption></figure>")
    parts.append("</section>")
(output / "index.html").write_text("\n".join(parts))
sys.exit(1 if failed else 0)
PY
