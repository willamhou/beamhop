# Task context relay — first Router slice

Approved scope: explicit task identity, related handoff attempts, an editable relay
package, history presentation, compatibility and mirrored regressions. No session
reader, routing model, autonomous execution, external configuration or acceptance
app changes belong in this PR.

## Public contract

- A user explicitly creates or selects a local task. Task IDs are independent of
  draft and handoff IDs. Titles are labels, never identity or session addresses.
  Tasks are discoverable from retained drafts/history; this slice has no separate
  task lifecycle or automatic completion state.
- Old drafts/records decode without a task or relay. Do not infer historical
  tasks, rewrite frozen payloads, or advertise new metadata on old receipts.
- Instructions and edited materials remain literal and first. Optional editable
  relay text follows them, labels agent claims unverified, and carries selected
  source handoff/result references. A handoff freezes all outgoing text, task
  identity and consent. Later edits or task selection cannot mutate it.
- Persist/restore/recover/duplicate retain task and relay. A retry has a fresh
  handoff ID. Late outcomes consume only unchanged exact snapshots. Unrelated
  active input is parked, not overwritten.
- A new continuation is explicit and defaults MCP return off. A selected result
  must belong to the selected retained handoff. It is copied as editable,
  agent-reported context, not a confirmed fact or a verified external session.
  Do not import all results or read other agent histories.
- Same-task Pocket batches preserve that identity and each source's relay text.
  Different task IDs (including task-bound plus unassigned) block combined
  handoff and ask the user to edit/reassign or hand off separately.
- Pocket can filter history by task and shows task identity alongside the frozen
  handoff and scoped conclusions. Inbox conclusions show the linked task. Existing
  copied/prepared/failed receipts never establish receipt or completion.
- Task/relay edits persist through the existing draft-change interface and take
  part in snapshot equality. UI previews the outgoing package before manual
  confirmation. Existing attachment/import/focus safeguards remain unchanged.
- Existing result tools stay handoff-scoped and opt-in; MCP never creates or
  migrates an Inbox. No task-wide history tool is introduced. Deleting a backup
  still deletes its conclusions; it does not delete external history or other
  task attempts. Local relay copies are separately retained edited material.

## Approved regression seams

1. HopDraft/HopRecord: task linkage, literal editable relay, frozen outgoing copy,
   legacy decoding and independent consent.
2. HopLibrary: reopen/recovery/retry, exact-snapshot protection, scoped result
   reuse, old data and mixed-task batch rejection.
3. CapturePanelModel/HopPocketModel and native fixtures: editing/preview,
   task/history filtering and conclusion display, truthful manual receipts.

Use temporary fixture databases and mirrored SelfTest/XCTest. Hosted native tests
are not logged-in agent, TCC, fullscreen, multidisplay or real-device acceptance.
