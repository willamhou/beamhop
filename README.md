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

Each new ordinary Hop includes its own handoff ID after the literal instructions and edited material. Enable **Request a conclusion back via MCP** in the panel or Pocket batch controls to invite an optional return; it is off by default. Mixed-consent batches do not opt in automatically. An agent with the updated Beamhop MCP helper can use `fetch_handoff(handoff_id)`, `save_handoff_result(handoff_id, content, agent, session_id?)` and `fetch_handoff_results(handoff_id, limit?)`. These tools require that exact opted-in handoff, not the latest capture, and expose only its edited outgoing snapshot. Existing capture tools remain compatible.

Returned conclusions appear under **Inbox → Handoff conclusions** and the matching Pocket history entry, separate from copied/prepared receipts. They are agent-reported answers, not verified completion. Retries have new identities; late returns do not change newer drafts. Deleting a handoff backup also deletes its conclusions. Old backups retain their original payload without retroactive identity metadata. The app owns the additive v10 migration; the helper never creates or upgrades an Inbox. Upgrade the app and helper together, then deliberately restart the receiving MCP session to load its new tool list; no registration or live-session capability is assumed. Back up before upgrading: an older binary is not a migration rollback.

Beamhop handles context and handoff; reasoning and execution stay with your external tools. A project remembers local route choices, not a verified conversation address. Preparing a draft brings the receiver forward for review; an unavailable receiver requires an explicit choice or manual fallback. **Copied** and **prepared** receipts do not mean an agent has received or completed the task.

## Task context relay

Open **Task and relay context** in Hop to explicitly create/select a local task and
edit the context that should travel. Task IDs link multiple handoff attempts; they
are not project names or external conversation addresses. Preview the outgoing
content before confirming. Instructions and edited materials remain literal and
first; task and fresh handoff IDs are appended at confirmation. Relay text labels
agent claims unverified. No agent histories are read and no model/API key is needed.

Pocket filters drafts/history by task and shows the task ID beside each frozen
handoff. Different tasks (including assigned plus unassigned drafts) cannot be
combined: edit their association or hand them off separately. Same-task batches
retain each draft's relay text. Old records remain unassigned and keep their old
payload; restore one and explicitly select a task to start tracking future attempts.

In an expanded task-linked history entry, **Continue task with this copy** restores
an editable new draft. Alternatively select one specific returned conclusion to
add as unverified relay text, retaining earlier relay constraints. Current input
is parked, not overwritten. Each continuation defaults MCP return off; backup
recovery retains its saved consent. Inbox conclusions show the linked task too.
Result write-back remains optional and scoped to a single handoff, never proof of
task completion. Deleting a backup deletes its conclusions; separately selected
editable relay copies in other drafts/history remain until those copies are deleted.

This first Router slice has no separate task lifecycle, session discovery,
automatic routing, sending or completion detection. Tasks are listed from retained
drafts/history, not inferred from historical activity. See the
[task relay contract](docs/superpowers/specs/2026-10-29-task-context-relay.md).

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

## Small field trial

Recruit 3–5 consenting target users and aim for about 50 real tasks in total. These are a proposed trial size, not completed work or a release gate already passed. Use one concrete flow first: GitHub Issue/PR, add code or an error, hand off manually to an existing agent, then find the conclusion in Inbox/Pocket when the receiver supports MCP. Run the ordinary manual-copy workflow for comparison where practical; label estimated step counts instead of presenting them as observed timings.

Copy the empty [field-trial CSV template](docs/field-trial-template.csv) into a private location outside this repository. Use random participant/task codes, a build commit, fixed scenario categories (`issue`, `pr`, `code`, `error`, `docs`, `other`) and a receiver category. Never put source text, repository/customer names, URLs, actual session/handoff IDs, credentials or private diagnostic details in the shared sheet. Completed records are not committed or automatically uploaded. Obtain consent separately before sharing any feedback or redacted evidence.

Record each real task once. `handoff_receipt` is `copied`, `prepared`, `failed` or `blocked`, never agent receipt or completion. Record `result_found` separately as `yes`, `no` or `unsupported`; record task outcome as the participant's `done`, `partial`, `not_done` or `unknown` self-report. For recovery, Pocket reuse and willingness to use again, use `yes`, `no` or `not_applicable`. Classify blockers (`permission`, `missing_material`, `receiver`, `mcp_setup`, `result_discovery`, `recovery`, `other`) without private prose. Synthetic fixtures, duplicate retries and automatic counters do not establish 50 real tasks or unique participants.

Review after the first five tasks to remove blocking onboarding/recovery issues; then review the whole sample for observed steps saved, repeat-use reasons, recovery, Pocket reuse and whether users can find a returned result. Preserve negative/blocked cases in the denominator. Choose the next product work from those findings rather than extrapolating a global task-success rate from transport receipts.

Local reporting is available through `scripts/dogfood-metrics.sh --db PATH --days 14` (1–180 days). Reporting opens the Inbox read-only and never upgrades, repairs or creates it. Ordinary Hop starts are deduplicated by handoff ID and shown separately from copied/prepared/failed/pending/interrupted receipts. Retries are new attempts, not proven new tasks. Legacy delivery rows may overlap Hop transport and must not be added to Hop counts. Old backups without telemetry are explicitly untracked; no historical activity is fabricated. Local usage events retain 180 days and contain only typed actions/opaque IDs, not material, project/session names, paths or error text. Deleting a backup does not delete its usage events; returned-conclusion counts describe only retained results written within the reporting window, not completion or response rates.

Pocket reporting counts distinct drafts explicitly saved and drafts reopened/material-reused or successfully copied/prepared from a batch. A failed batch is only an attempt, not a successful reuse. Legacy imports do not count as new saves. These action counts are not participant/task counts or a reuse percentage. The menu-bar **Getting Started…** guide checks current Accessibility permission, records actual saved captures and local handoff preparation, preserves progress across restart, and offers Pocket recovery. A copied/prepared receipt still requires manual submission. MCP setup remains optional and registration does not prove live tools are available; no onboarding action creates a conversation or auto-sends.

## Read more

- [Product essays on Pages](https://willamhou.github.io/beamhop/index.en.html) — interactive explorations of destinations, context and the corner shelf; [Chinese edition](https://willamhou.github.io/beamhop/).
- [Native macOS gallery](https://willamhou.github.io/beamhop/native-ui/) — production views with fixture data and downloadable check reports.
- [Repository guidance](AGENTS.md) — synchronization, architecture, validation, privacy and CI-gated merge rules for coding agents.
- [Progress and next steps](PROGRESS.md) — current implementation, pending acceptance and revision-specific evidence. New work branches from current `main`.
- [Hop identity and optional return contract](docs/superpowers/specs/2026-10-26-hop-result-return.md) — consent, edited-payload boundaries, independent results and regression scope.
- [Compact handoff specification](docs/superpowers/specs/2026-10-20-compact-handoff.md) — historical compact-panel baseline; Inline Hop/Pocket changes and current evidence are recorded in PROGRESS.
- [Product positioning](docs/product-positioning.md) · [Roadmap](docs/superpowers/roadmap.md) · [Compatibility evidence](spike/compatibility-matrix-v0.json).
- [MVP design](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) · [Historical engineering convergence](docs/superpowers/specs/2026-09-14-engineering-convergence.md). Current merge policy is in AGENTS; CI-green `main` does not certify real-device acceptance.

English is the default documentation language. Historical Chinese documents live in [docs/zh/](docs/zh/); the product essays provide both languages.
