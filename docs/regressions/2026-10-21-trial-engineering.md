# Trial engineering — local verification

Date: 2026-10-21 (Asia/Shanghai). Package snapshot captured before commit on `codex/trial-build-engineering`, based on main `2dd92bb`, with then-uncommitted source changes (including the earlier CLT state compatibility fix). This historical local-package record does not establish later commit, CI or merge status; inspect the repository/PR separately.

## Package identity

- Separate app: `dist/engineering-preview/Beamhop.app` (Release, arm64, ad-hoc, not notarized).
- Build ID: `953c86fe-8dce-403d-93d2-dafcba0328c0`.
- Source fingerprint: `9c56756ab7d081d6ba84af24c3d9e29e77c4172cad57f2727728fa89425785d4`.
- Runtime `--build-info`, sealed `Contents/Resources/build-info.json`, and `dist/engineering-preview/build-records/953c86fe-8dce-403d-93d2-dafcba0328c0.json` agree. All three signed-binary SHA-256 values were independently recalculated and matched the receipt.
- Existing user acceptance app remains at `dist/Beamhop.app`; its executable SHA-256 is unchanged: `0bd09971565eb887f3dd13af15f38b7856adfe24b2f1289d28a8ccec36db5e95`.

## Completed checks

| Check | Result |
| --- | --- |
| Release packaging + strict code-signature verification | Passed |
| Debug build / CLT SelfTest, including provenance and privacy sentinels | Passed |
| `python3 scripts/build-provenance-smoke.py` | 7 tests passed |
| `python3 scripts/dev-signing-smoke.py` | 7 cases passed; temporary command stubs, no keychain access |
| `shellcheck packaging/build-app.sh` / `bash -n` | Passed |
| zh-Hans strings plist lint / whitespace check | Passed |
| Production Diagnostics and export-preview views, offscreen | English/Chinese × light/dark passed; 8 PNGs reviewed for readable layout |
| Private fake diagnostic-row details | Path, URL and note sentinels absent from generated report |
| Runtime manifest, embedded manifest, receipt, signed binary hashes | Matched |
| Current acceptance app executable | Unchanged |
| `swift test` | Attempted; blocked by CLT's missing XCTest module, not reported as passed |

Offscreen fixtures use synthetic diagnostic rows, never the real collector, app bootstrap or Inbox. The child process has prohibited activation policy; before/after foreground PID was unchanged. No capture-panel focus cycling or synthetic input into user apps was run during this engineering turn, to avoid disrupting the user's acceptance session.

Screenshots and fixture JSON: `dist/engineering-preview/verification/`. The diagnostic-window screenshots intentionally show **fake** private text in local row details; export screenshots/JSON prove these details are not part of the allowlisted report. Do not confuse local diagnostic UI contents with exported contents.

## Pending

- Full-Xcode XCTest and hosted CI for the actual committed engineering revision.
- Manual production-window checks: preview selection/scroll, Cancel, native Save dialog cancellation, save failure/retry and saved bytes. Automated serialization/rendering is not proof of those interactions.
- Real-source/Agent/TCC/fullscreen/multidisplay acceptance remains tracked separately in the [user checklist](2026-10-21-device-acceptance.md).

Do not replace the user acceptance app mid-test. When ready to inspect this engineering package, quit the other instance first, back up the data directory privately and check Accessibility for the new app path/signature. See [trial build documentation](../trial-builds.md).
