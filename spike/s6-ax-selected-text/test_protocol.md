# Probe protocol (S6)

## One-time setup (manual — required before first run)
1. System Settings → Privacy & Security → **Accessibility** → enable your terminal app
   (Terminal / iTerm — whichever you run `./axprobe` from).
2. System Settings → Privacy & Security → **Input Monitoring** → enable the same terminal.
3. Fully quit & reopen the terminal so the permissions take effect.

## Run
```bash
cd spike/s6-ax-selected-text
./axprobe | tee results.jsonl
```
You should see `[probe] ready …` on stderr. Leave it running.

## For each app
1. Open the app and bring its window forward.
2. Select a 1–3 word phrase.
3. Press **Cmd+Shift+P**.
4. Confirm a JSON line appears in the probe terminal.

Apps to test (8):
- Safari: open https://github.com, select the repo name
- Chrome: open https://news.ycombinator.com, select a title
- Notes: type "hello" + select
- Mail: open any email, select the sender name
- Slack: open any channel, select a word in a message
- VS Code: open any file, select a line
- Cursor: same as VS Code
- iTerm: type "ls" + select

After all 8: Ctrl+C the probe, then run Step 3.6 (jsonl → json) from the plan.
