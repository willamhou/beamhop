# Hop identity and optional conclusion return

Date: 2026-10-26. Implementation baseline: `66dea66`. Authorized scope: ordinary
Hop identity, optional conclusion return, mirrored regression coverage and CI-gated PR.

## Contract

1. Each new handoff attempt has its own durable identity. The identity belongs to the
   frozen handoff record, not the mutable draft, source capture or external session.
   Retrying or recovering a draft creates a new attempt. A late result belongs to the
   old attempt and must not consume input, change newer edits or mark transport complete.
2. Instructions and edited materials remain literal and first in the outgoing payload.
   Append the handoff identity; never silently reintroduce original capture text, other
   page content or attachment paths. Existing manual attachment fallback stays intact.
3. Conclusion return is explicit opt-in, off by default. Preserve this choice across
   draft save/restore/restart and include it in exact-snapshot equality. The panel and
   Pocket batch controls explain that the receiving agent must support Beamhop MCP.
   Mixed batches require an explicit batch choice; a partial opt-in is not blanket consent.
4. An opted-in payload may ask an agent to return a conclusion using the exact handoff
   identity. Tool availability and invocation are not guaranteed. No auto-send, terminal
   Enter, session creation, credential setup or registration changes are introduced.
5. Add distinct handoff result tools; keep `fetch_capture`, `search_captures`,
   `save_result` and `fetch_results` compatible. A handoff read returns only the edited
   outgoing snapshot and allowlisted identity/status data, never the full stored record
   containing original captures and local file paths. Unknown, legacy and non-opted-in
   handoffs are rejected by the new MCP read/write interfaces.
6. The app owns the additive result-table migration. The MCP helper must not migrate,
   recover, create an Inbox, mutate drafts/records or change copied/prepared receipts.
   Validate origin, nonblank content and agent within the result insertion transaction.
   Results are append-only and tied to a real handoff; deleting its backup removes its
   associated conclusions and causes later writes to fail, without affecting captures.
7. Show returned conclusions separately from transport status in Pocket history and an
   Inbox handoff-results section, including identity, writer, time and the frozen edited
   payload. Support added-text-only and multi-source handoffs without attaching their
   conclusions to an arbitrary capture. Refresh external writes while the view is active,
   preserve selection, paginate long histories and show errors rather than stale success.
8. Old drafts decode with return disabled. Old records retain their original outgoing
   content; do not retroactively claim identity metadata was sent. Existing capture
   conclusions, source provenance and failed-draft recovery remain unchanged.

## Approved test surfaces

- Public draft/record output: identity, literal edited content, optional return and
  legacy decoding. No private originals or file paths in the outgoing/MCP snapshot.
- Public library/result storage: durable origin across restart, retry, batch and late
  completion; explicit opt-in, unknown/deleted-origin rejection, transaction failure,
  separate receipts, cascade deletion and old-schema no-migration behavior.
- Actual stdio tools and presentation models: save/fetch round-trip, legacy tools,
  unavailable schema, invalid arguments, external refresh, paging and selection.

XCTest and the CLT SelfTest runner mirror shared behavior. Protocol checks use explicit
temporary databases. Native interaction fixtures run in hosted CI, not the user's
active apps. CI success is not real-agent acceptance. No acceptance bundle is rebuilt.
