# Repository guidance

## Start here

- Read this file, `PROGRESS.md` and `README.md` before changing the repository. Use current code and revision-specific evidence to resolve conflicts with dated specifications; do not restart an already implemented feature from an old plan.
- Fetch `origin`, inspect local changes and compare with `origin/main` before working. Preserve unrelated changes and untracked files, including `.mimosa/`; never include them in a commit by default.
- Start new work from current `main` on a short-lived `codex/<topic>` branch. Do not reuse historical integration or feature branches as the baseline.
- Keep repository documentation in English. Follow the user's language in conversation. Record changing status/evidence in `PROGRESS.md`, not duplicated milestone lists in this file.

## Architecture and behavior

- `Sources/BeamhopCore/`: testable models, GRDB storage/migrations, capture/focus policy, panel/Pocket models and typed diagnostic/provenance data; no AppKit UI.
- `Sources/Beamhop/`: AppKit/SwiftUI app, `HopCoordinator`, capture/delivery services, Pocket, Inbox and Diagnostics.
- `Sources/BeamhopMCP/`: newline-delimited stdio JSON-RPC; capture reads and results-only write-back. The app owns schema migrations; the MCP helper must not migrate or create the Inbox.
- `Sources/BeamhopSelfTest/` and `Tests/BeamhopCoreTests/`: CLT-compatible regression runner and XCTest mirror. Update both when changing shared logic.
- `host/` and `extension/`: browser native-message relay and extension. `packaging/` and `scripts/`: packaging, provenance and verification tools.
- Inline Hop/Pocket is the current workflow. Preserve immutable source captures, literal edited material, pending-import ownership, durable draft recovery, exact-snapshot completion and separate handoff history.
- Return inserts a newline; Command-Return confirms. Projects are local context, not verified conversation addresses. New-session handoffs copy text and open the receiver for manual creation; never silently create a conversation or auto-send/press terminal Enter.
- Inline Hop's Claude Code path copies text for manual paste. Legacy Inbox re-delivery can still prepare an MCP trigger; do not confuse that path with the default Hop workflow. Copied/prepared receipts never establish agent receipt or task completion.
- Current transports do not transfer attachments. Preserve the import/delivery guards and explicit manual-add fallback. A failed handoff must not consume input; late success must not remove newer edits or unrelated drafts.

## Validation

Run from the repository root, selecting checks proportionate to the change:

```sh
git diff --check
swift build
swift run BeamhopSelfTest
swift test                                  # requires full Xcode, not CLT alone
python3 scripts/build-provenance-smoke.py
python3 scripts/dev-signing-smoke.py
```

- Check the installed toolchain with `xcode-select -p`. Report a missing local XCTest framework honestly; SelfTest does not replace hosted XCTest. Do not run concurrent SwiftPM commands against the same build directory.
- For script/extension changes, follow `.github/workflows/ci.yml`: ShellCheck, signing/provenance regressions and the Node build in `extension/build`.
- Native fixtures (`scripts/native-ui-smoke.sh`, `--ui-regression`, `--trial-ui-smoke`) belong in an isolated test session or hosted CI. They are not real-agent/TCC/fullscreen/multidisplay acceptance. Avoid stealing focus while the user is testing a real app.
- Use temporary fixture databases/configs/apps. Do not change real Claude registration, TCC grants, keychains or Inbox data merely to validate a change. A fake `HOME` is not proof that Foundation resolves its support directory there; inspect default-path tests before running locally.
- Documentation-only changes need whitespace/link/consistency checks; hosted CI must still pass before merging. Do not claim code or native tests ran locally unless they did.

## Packaging, data and privacy

- Do not replace, delete or relaunch an acceptance app without the user's request. Build into a fresh `BEAMHOP_OUTPUT_DIR`, for example `dist/preview-<unique-id>`; packaging refuses to overwrite an existing app. Preserve its matching build receipt.
- Do not run two normal app instances against the same Inbox. Before a requested upgrade, arrange a private data backup and deliberate app switch. Old binaries do not roll back migrations, including the v9 separated history schema.
- Do not automate synthetic keys/undo into the user's real Notes, terminals or agent apps. Capture is read-only; delivery must retain the existing composer/focus safeguards. Reject Beamhop itself before reading/inserting captures.
- Diagnostic export is a typed allowlist with preview and explicit local save. Never add raw logs, capture text, source URLs/titles, local paths, session/project names, configuration or credentials to it; do not add automatic upload.
- Explicit MCP registration must preserve unrelated settings, reject malformed existing JSON and cover both supported Desktop config homes. Presence is not a live-session test.
- Never introduce a default signing password, log/export secrets or downgrade an explicit signing/unlock failure to ad-hoc. A usable stable development identity is optional; ad-hoc repacks may require renewed TCC permission. Developer ID signing/notarization are separate release work.

## PR and merge workflow

- For an authorized commit/push/merge task, open a PR against `main` and attach its URL to the chat. Avoid direct pushes to protected `main` and force-pushing shared history.
- The owner's current rule is to merge directly after the latest PR head's required CI checks pass and conflicts are resolved; do not wait indefinitely for an unresponsive review bot or ask for redundant confirmation. This is not permission to merge unrelated repositories, bypass branch protection, ignore known actionable findings, or merge failed/pending CI.
- Resolve conflicts by preserving both intended feature sets. Push fixes and wait for fresh CI on the changed head. Verify review findings against code/tests before resolving their threads; an outdated diff alone is not proof of a fix.
- Prefer squash merge with the expected head SHA so a concurrent push cannot be merged accidentally. Check the PR's current base/head and CI immediately before merging; do not rely on an older green revision.
- After merge, fetch, switch local `main` and fast-forward it to `origin/main` without discarding user work. Confirm synchronization and report the PR/merge commit, validation and anything left pending. If unrelated changes prevent a safe switch, stop and explain instead of resetting or stashing them without consent.
- CI-green `main` is an integration baseline, not a claim of real-device acceptance or notarized release. Keep historical evidence dated and revision-specific. User feedback without a case matrix does not close every manual acceptance item.
