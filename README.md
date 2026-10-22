# Beamhop

The inline Hop panel now edits selected text, accepts additional text and local file/image copies, and keeps the original source for comparison. Instructions come first; ⌘Return prepares the handoff. Pocket uses a compact searchable list with new/edit/duplicate/delete/undo actions and multi-select handoff. Matching destinations carry over; cross-project combinations require an explicit destination. Drafts and handoff history have separate tabs. Restoring a draft preserves current input; failed batches keep their selection, while success removes only unchanged selected drafts. Handoff backups distinguish prepared drafts, copied text and incomplete operations.

Projects are local context, with multiple remembered app/window choices. “New session” copies text and opens the receiving app for manual creation; it does not invent a conversation address. Current integrations do not transfer attachments: imported files stay local and must be added manually in the receiving app. Inline Hop hands Claude Code text through the clipboard; arbitrary multiline material is never pasted into an unverified terminal. There is no model, API-key requirement or UI projection in this workflow.

**Capture context. Choose a destination. Keep your train of thought.**

A native macOS menu-bar app for handing material from the app you are using to an external AI tool. Bring along the source and a short note; hold material in a corner shelf when you want to return to it later.

**[Releases](https://github.com/willamhou/beamhop/releases) · [Website & product essays](https://willamhou.github.io/beamhop/index.en.html) · [Native screenshots](https://willamhou.github.io/beamhop/native-ui/) · [Builds & checks](https://github.com/willamhou/beamhop/actions/workflows/ci.yml)**

[![CI](https://github.com/willamhou/beamhop/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/willamhou/beamhop/actions/workflows/ci.yml)

[![Beamhop’s compact native capture panel](https://willamhou.github.io/beamhop/native-ui/assets/capture-en-light.png)](https://willamhou.github.io/beamhop/native-ui/)

*Native AppKit / SwiftUI interface. The [published gallery](https://willamhou.github.io/beamhop/native-ui/) records the earlier compact-panel baseline in English/Chinese and light/dark; use revision-specific CI artifacts for the latest Inline Hop/Pocket UI.*

## One handoff, from the app you are using

1. **Capture.** Select text and press **⌘⇧Space**. A compact panel shows the material and its source.
2. **Compose and choose.** Edit material inline, add instructions or text, and choose a receiving app/window intent with optional local project context. **Return** inserts a newline.
3. **Hand off or hold.** Press **⌘Return** to prepare/copy for manual review, or **⌘5** to hold for later. Open Pocket with **⌘⇧P**, select what belongs together, and hand it off as one ordered payload. Mixed project/app/session routes require an explicit destination.

Your Inbox keeps the originals, notes, delivery history and agent results written back through MCP. Selected conclusions refresh while the Inbox is active; long answers can be expanded and earlier results loaded. A failed shelf handoff preserves the material and selection for retry.

Beamhop handles context and handoff; reasoning and execution stay with your external tools. A project remembers local route choices, not a verified conversation address. Preparing a draft brings the receiver forward for review; an unavailable receiver requires an explicit choice or manual fallback. **Copied** and **prepared** receipts do not mean an agent has received or completed the task.

## Get Beamhop

**Development preview · macOS 14 or later.** There is no tagged release yet. [Releases](https://github.com/willamhou/beamhop/releases) is the home for future versions; the merged baseline is `main`, with builds available through [GitHub Actions](https://github.com/willamhou/beamhop/actions/workflows/ci.yml?query=branch%3Amain).

To try a development build, open a successful `main` push run and download its **Beamhop-app** artifact. Extract the outer artifact and the inner `Beamhop-macOS.zip`, then move `Beamhop.app` into Applications. Hosted builds are ad-hoc signed and not notarized. Grant Accessibility access when requested. Before an upgrade, quit the app and privately back up its Application Support directory; an old app alone cannot roll back database migrations. See [packaging and MCP setup](packaging/README.md).

## Receiving tools

| Destination | Current behavior |
|---|---|
| Claude Code | Inline Hop/Pocket copies text and opens the terminal for checked, manual paste/submission. MCP remains available for capture reads and result write-back; legacy Inbox re-delivery can prepare a trigger for manual submission. |
| ChatGPT Desktop | Prepare a draft in a readable empty composer; otherwise copy for review. Never auto-send. |
| Kimi Work | Prepare a draft in the current conversation when its composer is known empty; otherwise copy. No automatic new conversation. |
| Clipboard | Copy once with sources and notes, then paste where you need it. |
| Claude Cowork | An MCPB wrapper is available in `cowork-extension/`; end-to-end acceptance is pending, with clipboard fallback. |

Only detected applications appear as direct destinations. An unavailable remembered receiver requires an explicit choice. Pocket does not silently combine different projects/app/window intents onto a guessed route. “New session” copies text and opens the app; the user creates the session and adds any attachments.

## Build and verify

On macOS 14+ with Swift 5.10 or newer:

```bash
git clone git@github.com:willamhou/beamhop.git
cd beamhop
git switch main
swift build
swift test                          # requires full Xcode
swift run BeamhopSelfTest            # works with Command Line Tools
BEAMHOP_OUTPUT_DIR="$PWD/dist/preview-$(date +%Y%m%d-%H%M%S)" ./packaging/build-app.sh
# Inspect the reported bundle/receipt; launch only when ready to switch apps.
```

The app includes the menu-bar UI and MCP helper. The [packaging guide](packaging/README.md) covers MCP registration, the browser bridge and separate output directories. Trial engineering adds version/commit display, embedded provenance, signed-binary build receipts and preview-before-save, allowlisted diagnostics; see [trial builds and privacy](docs/trial-builds.md). For a stable local signing identity, see [development signing](scripts/setup-dev-signing.sh). The setup uses a hidden password prompt or an explicitly supplied secret, with no default password. Existing users of the earlier signing script should follow the [credential remediation guide](docs/dev-signing-security.md).

CI runs Swift tests, protocol smoke checks, packaging and native UI interactions on **macOS**, plus extension and shell checks on Ubuntu. The [PR #8 integration run](https://github.com/willamhou/beamhop/actions/runs/39709892162) passed for `cd88c8a`, covering Inline Hop/Pocket interactions, history/migration regressions, receiver launch, diagnostic privacy and focus/Inbox checks across English/Chinese and light/dark. This is automated fixture evidence, not logged-in agent delivery, VoiceOver speech, fullscreen or multiple-display acceptance. [Verification scope and artifacts →](docs/native-ui-verification.md)

## Read more

- [Product essays on Pages](https://willamhou.github.io/beamhop/index.en.html) — interactive explorations of destinations, context and the corner shelf; [Chinese edition](https://willamhou.github.io/beamhop/).
- [Native macOS gallery](https://willamhou.github.io/beamhop/native-ui/) — production views with fixture data and downloadable check reports.
- [Repository guidance](AGENTS.md) — synchronization, architecture, validation, privacy and CI-gated merge rules for coding agents.
- [Progress and next steps](PROGRESS.md) — PR #8/#10 merged baseline, pending acceptance and evidence boundaries. New work branches from current `main`.
- [Compact handoff specification](docs/superpowers/specs/2026-10-20-compact-handoff.md) — historical compact-panel baseline; Inline Hop/Pocket changes and current evidence are recorded in PROGRESS.
- [Product positioning](docs/product-positioning.md) · [Roadmap](docs/superpowers/roadmap.md) · [Compatibility evidence](spike/compatibility-matrix-v0.json).
- [MVP design](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) · [Historical engineering convergence](docs/superpowers/specs/2026-09-14-engineering-convergence.md). Current merge policy is in AGENTS; CI-green `main` does not certify real-device acceptance.

English is the default documentation language. Historical Chinese documents live in [docs/zh/](docs/zh/); the product essays provide both languages.
