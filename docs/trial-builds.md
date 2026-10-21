# Trial builds, provenance and privacy-filtered diagnostics

Implementation baseline: `main` / `2dd92bb` (PR #7); engineering workstream: `codex/trial-build-engineering`. Use repository/PR status for integration state. The locally verified engineering package is a pre-commit dirty-source snapshot, recorded separately; it does not replace or certify the package undergoing user acceptance.

## Identify the exact package

The menu-bar header and Diagnostics show the app version, bundle build number, short source commit and build-input state. Diagnostics also shows the unique build ID and UTC build time. A package built with local source/resource/packaging changes says **Local changes**; it must not be identified as a clean build of the base commit. A plain SwiftPM launch or old package without metadata says **unknown** rather than inventing provenance.

App version and build number come from `packaging/Info.plist`. The build ID is a fresh UUID on each packaging run, so builds sharing version `0.1.0 (1)` remain distinguishable. This work does not introduce automatic release-version management.

Each new package contains `Contents/Resources/build-info.json`, sealed by its code signature:

- schema version, app version/build number, unique build ID;
- full base commit, dirty/unknown build-input state and SHA-256 input fingerprint;
- UTC build time, release configuration, actual Mach-O architecture and numeric Swift version;
- requested signing mode (`adhoc` / `identity`), not a certificate name or an assertion of notarization.

Input state covers `Sources`, Swift package manifests, the bridge source, packaged localization/plist, the packaging script and provenance generator. Staged, untracked and even git-ignored files in those locations count, since SwiftPM may compile ignored source files. Documentation and `.mimosa/` do not affect the source fingerprint. Symlinked build inputs are rejected. Input changes during packaging abort receipt creation; avoid concurrent source edits. The fingerprint is traceability, not a claim of fully reproducible dependency/toolchain output or remote attestation.

After signing, packaging performs strict code-signature verification and writes an external JSON receipt in `<output>/build-records/<build-id>.json`. It contains the same provenance plus SHA-256 of the signed app executable, MCP helper and native bridge. The receipt is external to avoid a circular dependency between an embedded hash and the code signature. Changing a packaged binary invalidates its recorded digest. Keep the app and its matching receipt together; do not modify the app after signing.

Inputs marked `assume-unchanged` or `skip-worktree` are conservatively labeled dirty even without a visible porcelain diff, because those index flags can hide edited worktree content. Tagged releases publish the matching JSON receipt beside the app ZIP and fail if either asset glob has no matches; CI also retains receipts as a separate artifact.

Headless inspection (does not bootstrap the app, open Inbox or request permissions):

```sh
dist/engineering-preview/Beamhop.app/Contents/MacOS/Beamhop --build-info
```

## Build without replacing an acceptance app

```sh
# From the repo root, after fetching and checking local changes.
BEAMHOP_OUTPUT_DIR="$PWD/dist/engineering-preview" ./packaging/build-app.sh
```

The default remains `dist/Beamhop.app`. Packaging refuses to overwrite an existing app; choose a fresh output directory or preserve the old app first. This engineering work leaves the October 21 acceptance app at `dist/Beamhop.app` intact. Do not run two normal instances against the same Inbox. Before trying a new app, quit the current one, privately back up its Application Support directory and verify Accessibility for the current app path/signature. Old binaries alone cannot roll back schema migrations.

Signing uses the requested identity, an existing detected development identity, or ad-hoc fallback only when no identity was selected. Explicit signing/unlock failure does not downgrade to ad-hoc. A stable self-signed development identity is optional and is not Developer ID distribution or notarization. Existing Macs that used the former default keychain password still need [private password rotation](dev-signing-security.md); this workflow does not rotate credentials.

## Export diagnostics: preview, then explicitly save

Open **Diagnostics → Preview diagnostic export…**. Status checks refresh when the preview is requested. The window displays the entire JSON; it is selectable but not editable. Cancel closes it without writing a report. **Save report…** opens the native save dialog and writes exactly the previewed bytes, atomically, only after confirmation. Canceling the save dialog leaves the preview open and writes nothing. A failed save keeps the preview available for retry and shows a generic error without a local path.

This is privacy filtering by construction, not regex redaction of an unrestricted log archive. The report takes typed, allowlisted data only:

| Included | Excluded by the report model |
| --- | --- |
| Validated build provenance | Branch names, repository paths/remotes, builder usernames, machine names |
| Numeric macOS version and runtime architecture | Serial numbers, device IDs, environment variables, certificate names, keychain data |
| Stable check IDs + `ok` / `warn` / `fail` / `todo` | Human-readable diagnostic details, raw logs, free-form errors, fix commands |
| Privacy policy and schema version | Inbox/database rows, captures, source URLs/titles, text, notes, results, sessions, work names, MCP configuration, tokens |

The normal diagnostic service performs existing permission/integration presence checks; it may read registration state as before. The exporter does not collect those config contents or read the Inbox. A registration check reports presence, not a live MCP session or actual agent receipt. The Chrome host check remains unverified until a live bridge check exists; packaging a host binary is not a healthy-browser assertion. Even decoded provenance fields are validated and unknown keys discarded before export.

No automatic upload, email, issue creation, clipboard copy or telemetry is part of export. The user decides whether and where to share a saved report. A build ID/source fingerprint can correlate reports from the same build; do not call this anonymous telemetry.

## Verification and manual checks

Automated coverage: malformed/unknown manifests, safe fallback, injected private sentinels, deterministic report schema, known status IDs, clean/dirty/untracked build inputs, source mutation during packaging, receipt hashes, no-clobber records, and signing-password regression cases. XCTest mirrors the core cases for full-Xcode CI; CLT runs SelfTest. Packaging/receipt tests use temporary repositories and command stubs, not real keychains.

Manual checks for the engineering preview (after the current acceptance session):

1. Compare menu/Diagnostics version, commit and build ID to the embedded manifest and receipt; a dirty build must be labeled.
2. Open diagnostic preview. Search visually for any local username/path, URL, note or token; none should occur. Confirm only stable check IDs/statuses are present.
3. Cancel preview and cancel a Save dialog: no report file should appear. Save to a chosen location; confirm its bytes match the preview. Retry a rejected/read-only destination without losing the preview.
4. Open/close Diagnostics and the preview repeatedly; verify controls remain usable in English/Chinese and light/dark. Do not infer native save-dialog behavior from serialization tests.
5. Confirm no application activation, Inbox capture or network upload happens merely from `--build-info`. Runtime permission and save-panel acceptance still require a real Mac session.

CI retains new receipts as `Beamhop-build-records-<commit>` once these workflow changes are pushed. Existing historical builds do not gain metadata retroactively. Local verification and a local engineering app do not imply the branch was pushed, CI passed or a release was notarized.
