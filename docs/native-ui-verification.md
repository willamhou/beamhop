# Native UI verification from a Windows development machine

Beamhop's feature branch runs its production AppKit/SwiftUI views on GitHub's `macos-15` runner. Windows is used to edit, inspect reports and review the generated PNGs. The Windows browser is not used as a substitute for the macOS application.

## Run and inspect

Push to `feat/phase15-detail-chain`. The CI workflow builds and tests Swift, assembles the app, and runs `scripts/native-ui-smoke.sh` against the packaged binary. The same script can run on a Mac:

```sh
bash scripts/native-ui-smoke.sh dist/Beamhop.app dist/ui-smoke
```

CI retains three artifacts:

- `Beamhop-native-ui-<commit>`: PNGs, per-scenario JSON assertions, logs and an `index.html` gallery. Download and extract it; open the gallery to review native rendering.
- `Beamhop-build-log-<commit>`: Swift compiler diagnostics, including failed builds.
- `Beamhop-app-<commit>`: an inner `Beamhop-macOS.zip`, created with `ditto` to preserve executable permissions. Extract both archives before opening the app on a Mac. This is an ad-hoc signed development build, not a notarized release.

Reports use synthetic text and an isolated temporary database. The harness bypasses normal bootstrap, does not register global hotkeys, does not request capture permissions, and does not interact with installed AI applications. Keyboard events are dispatched only to our own panel; the destination menu is opened through the native button's accessibility press action and its receiver item is then selected during native menu tracking.

## What is checked

Each case runs in English and Simplified Chinese, in light and dark appearance:

- The capture panel stays nonactivating, receives keyboard focus and initially focuses the note editor. Text entered into that native editor updates the model.
- Destination shortcuts work before opening the menu. Unavailable shortcuts are ignored. Opening and choosing a native menu item preserves the panel.
- Escape closes once. Confirming and holding do not also cancel. Replacing a capture saves the previous note. Losing key-window status takes the cancellation path.
- Long notes and confirmation/error text fit the actual panel. Exact shelf positioning across multiple displays is still part of integration acceptance.
- A subset of held materials survives closing/reopening and failure. A successful handoff removes only those selected rows. Source text and notes remain recoverable.
- Production views are rendered to PNGs from their `NSHostingView`, at actual size. Review these visually in addition to checking assertions: a valid layout can still hide information.

Core tests separately cover unavailable receivers, explicit destination choices, work isolation, delayed confirmation receipts, migrations and ordered payloads. These tests run before the UI harness.

## Verified run

Commit `fde3a97`, [CI run 39360579032](https://github.com/willamhou/beamhop/actions/runs/39360579032), passed on macOS 15.7.9 (24G830). Each of four locale/appearance combinations passed 38 assertions, for 152/152 total. The artifact contains 20 native PNGs, reviewed for destination detail, confirmation text, long notes and shelf failure state. Swift tests, SelfTest, protocol checks, packaging, extension build and shell checks passed in the same run.

The accessible destination control is a real `NSButton`; SwiftUI draws its multiline label without intercepting clicks or duplicating the accessible name. Testing the button's press action and menu selection does not constitute full VoiceOver acceptance.

## Evidence boundaries

Finder is the independent source application for activation checks on the hosted Mac. Passing those checks verifies the nonactivation behavior in that environment. It does not establish behavior in every fullscreen/Stage Manager/multiple-display arrangement or under every macOS release.

The harness uses a simulated completion for external delivery. It does not verify a logged-in ChatGPT/Kimi conversation, live terminal paste, Accessibility permissions, agent receipt or execution. The UI continues to distinguish prepared drafts and copies from agent completion; exact session addressing remains separate work.

Do not merge to `main` solely because screenshots exist. Read failed assertions, inspect the images, check the intended receiving behavior, and record which integration scenarios have evidence.
