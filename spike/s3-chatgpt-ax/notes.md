# S3 — ChatGPT Desktop AX

## Status: 🚧 BLOCKED — ChatGPT Desktop not installed
`/Applications/ChatGPT.app` is absent on this machine. Both probes compile clean
(`probe_chatgpt`, `paste_test`, Mach-O arm64) and are ready to run once installed.

### To unblock
```bash
brew install --cask chatgpt
# then, with ChatGPT Desktop open + clicked into its input box:
cd spike/s3-chatgpt-ax
./probe_chatgpt > ax_tree_current.txt        # dump AX tree, find the AXTextArea path
echo "before-test" | pbcopy                   # baseline clipboard
( sleep 3; ./paste_test )                      # click into ChatGPT input within 3s
pbpaste                                         # should print "before-test" (restored)
```
Grant the terminal Accessibility permission first (System Settings → Privacy & Security →
Accessibility). Also record the version:
`defaults read /Applications/ChatGPT.app/Contents/Info.plist CFBundleShortVersionString`.

## Hypothesis
ChatGPT Desktop's input AX path is stable enough that "find input → paste → submit" is
reliable across the current + previous stable versions.

## Pass criterion
Input element locatable deterministically in current version; same path confirmed in the
previous build (or Accessibility Inspector snapshot if no archived installer).

## Versions tested
- Current: <fill>
- Previous: <fill or "not available">

## Input element path
- Current: <fill>
- Previous: <fill or n/a>

## Paste experiment
- Text appeared in input: ?
- Clipboard restored: ?

## Conclusion
[ ] PASS  [ ] FAIL  [ ] PARTIAL — clipboard-only

## Spec patch
- §7.5: state AX outcome; if FAIL/PARTIAL, downgrade ChatGPT delivery to clipboard handoff.
- §12.5 Compatibility Matrix: ax_path snippet.

## Fail handling (per plan)
If AX paste proves unstable, ChatGPT Desktop becomes clipboard-only handoff (no auto-paste).
