# S6 probe protocol

Build and start:

```bash
swiftc -O AXProbe.swift -o axprobe -framework Cocoa -framework ApplicationServices
./axprobe | tee results.jsonl
```

Grant Accessibility and Input Monitoring to the terminal first. In each of Safari, Chrome, Notes, Mail, Slack, VS Code, Cursor, and iTerm: bring a real content window forward, select a unique 1–3 word phrase, and press `⌘⇧P` once.

An app scores one only when `app_name`, `bundle_id`, `window_title`, and `selected_text` are all non-empty and `selected_text` matches the phrase. Pass is at least 6/8. Keep the raw JSONL as evidence; do not hand-edit it.

