## Changes

Capturing a passage now opens a compact native handoff panel with the remembered destination, receiving app and actual action. The panel takes keyboard input without activating Beamhop as a document app. Other destinations and optional work naming are revealed on demand.

- Add an optional corner shelf: hold material with its source, note and intended work; select a subset and prepare one ordered payload. Failure retains the selection and material. Different works cannot silently share a handoff just because they use the same app.
- Preserve notes and work intent through v6/v7 migrations. Add an Inbox timeline combining delivery history and agent write-backs, while keeping original captures recoverable.
- Serialize delivery, protect existing or unreadable drafts, stop automatically opening a Kimi conversation, and require manual terminal submission. Distinguish copied, prepared and failed receipts. An unavailable receiver requires an explicit choice; delayed receipts cannot confirm a newer binding.
- Add hosted macOS UI verification, native screenshots and downloadable feature builds. Include stable local development signing support.
- Rewrite the default README in English with Releases, Pages, native screenshot and build links. Publish the gallery separately on `gh-pages`: https://willamhou.github.io/beamhop/native-ui/ .

Named works currently bind an **application**, not a verified agent conversation. Draft preparation still brings the receiver forward for review. This PR remains a draft while the integration acceptance items below are open.

## Validation

- [x] macOS build, XCTest, SelfTest, MCP/native-host checks and packaging; Ubuntu extension build and shell checks passed on `fde3a97` and documentation revision `1d4e6fc`; current branch checks are attached below.
- [x] Production AppKit/SwiftUI views ran on macOS 15.7.9: **152/152 UI assertions**, English/Chinese × light/dark. Twenty generated PNGs were visually reviewed. Checks exercise native keyboard focus and text input, destination-menu selection, dismissal, draft recovery, sizing, selection and retry. [Verified run](https://github.com/willamhou/beamhop/actions/runs/39360579032).
- [x] Static gallery: 24 browser combinations passed, covering both page languages, both screenshot languages, both appearances and three viewport widths. Local links resolve; existing essay interaction scripts are unchanged.
- [ ] Remaining Mac integration acceptance: logged-in ChatGPT/Kimi draft protection and conversation behavior, real terminal preparation, TCC capture, VoiceOver speech, fullscreen/Stage Manager and multiple displays. Recorded in `PROGRESS.md` and `docs/native-ui-verification.md`. Hosted UI fixtures do not establish real agent receipt or execution.

## Documentation

- [x] Current behavior and acceptance scope recorded in the compact-handoff spec, verification guide, roadmap and README.
- [x] `PROGRESS.md` distinguishes current feature verification from historical on-device results.

## Discipline

- [x] Fetched and aligned with `origin` before changes; work remains on `feat/phase15-detail-chain`.
- [x] No claims that hosted UI tests verify logged-in external-agent delivery or task completion.
