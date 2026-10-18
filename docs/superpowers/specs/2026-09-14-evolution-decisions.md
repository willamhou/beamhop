# Beamhop Evolution Decisions Spec (end of Phase 1 → Phase 2 direction)

> Date: 2026-09-14
> Status: V1 — locks the rationale and triggers for three evolution decision points; concrete scope gets its own implementation plan when each starts
> Positioning: the **strategy-layer** companion to MVP design spec V2.1. Does not change Phase 1 scope.
> Key external input: Intuition-Lab/personal-model (2026-09 analysis, ~1.3k stars) and its impact on the Phase 2 track.

## TL;DR

Three decision points: ① Apple ID/Xcode gets resolved at the end of Phase 1 (prerequisite for Phase 2); ② Phase 2 memory must NOT be a "naive version" — choose between "provenance-first task graph" and "integrate personal-model" before Phase 2 starts; ③ the trigger for introducing the Phase 3 first-party agent is Phase 1 dogfood metrics, not intuition.

## 1. Decision point one: when to resolve Xcode / Apple ID

**Current state**: Apple ID lost (PROGRESS §0); `swift build` + CLT + CI covers daily dev verification; Xcode blocks exactly two things:

| Scenario | When it arrives | Blocker |
|---|---|---|
| Formal signed distribution (usable by others) | Phase 1 public release | Developer ID signing + notarization; ad-hoc TCC grants are unreliable on other people's machines |
| iOS / cross-device (roadmap Phase 2) | mid-to-late Phase 2 | Xcode toolchain + on-device debugging |

**Decision**: resolve it **between the end of Phase 1 (Week 3 panel + on-device acceptance) and the start of Phase 2**. Rationale:
- Dragging it into Phase 2 stacks it on top of memory engineering — two blockers at once;
- A free Apple ID unlocks Xcode installation (`appleid.apple.com` create/recover → `xcodes install --latest`), cost under an hour;
- Paid Developer Program ($99/year) can wait until actual distribution/iOS.

**Note**: once Xcode is in place, `swift test` (XCTest) becomes routine; migrate SwiftPM → Xcode app target per PROGRESS §7A.

## 2. Decision point two: the direction of Phase 2 memory

### 2.1 Track reality (2026-09 assessment)

Intuition-Lab/personal-model is open source and has first-mover-validated the "local personal memory runtime":
- Continuous AX capture + local OCR + five-minute reduction + layered model (Point→Line→Face→Volume→Root)
- Engineering depth is in the **evidence gate**: every inference must quote the original session text; new entities need receipts from two independent sessions to promote to Point; same-day replays don't double-vote; append-only, auditable, time-travelable
- Its gap is exactly our home turf: **no delivery/routing layer at all** (no panel, no AX paste trigger, no agent-agnostic target selection)

**Implication**: if Phase 2 ships just "Inbox + embedding semantic search", it rams a weakened version into their home turf with no defensibility. **Explicitly not doing the naive version.**

### 2.2 Two candidate routes

| | Route A: provenance-first task context graph | Route B: integrate personal-model as the memory backend |
|---|---|---|
| What | Beamhop captures already carry full provenance (app/window/channel/time) — upgrade the Inbox into "task memory with an evidence chain": a graph of task↔capture↔delivery-destination, retrieval organized by "what was I doing at the time" | Beamhop focuses on delivery/routing; the memory layer integrates personal-model (it supports local import bootstrapping and the architecture has seams); the Inbox becomes one of its capture sources |
| Positioning continuity | Naturally continuous with the "delivery tool" identity (the unit of memory is task context, not user profiling) | Admits memory is a separate track; swaps niches |
| Engineering cost | Large (self-built graph + retrieval + UI) | Medium (adapter layer + integration) |
| Risk | Functional overlap with personal-model's Face/Volume layers needs a differentiated narrative | Depends on an external project's cadence; its evidence-gate design changes would drag us along |
| Defensibility | Provenance/inspectability is a wedge platform players can't eat (spec §1.3 judgment still stands) | We go thin; the moat is ceded |

### 2.3 Decision procedure (deliberately NOT decided now)

One week before Phase 2 starts, run a **one-hour evaluation** (written back into this section):
1. personal-model's six-month evolution (did it move into delivery/routing? did the evidence gate tighten/loosen? commercialization signals?)
2. Our Phase 1 dogfood data: Inbox revisit rate, search hit rate, frequency of the "can't find that context again" pain
3. If personal-model hasn't expanded into delivery and its integration seams are stable → lean **B to start** (fast, accepts reality); graph capability (A) becomes the foundation of the Phase 3 first-party agent
4. If "recover context by task" is the strongest dogfood signal → lean **A**, and it must meet the evidence-gate bar (quote-the-original + independent double-sampling + append-only is the baseline, not a bonus)

## 3. Decision point three: when to introduce the Phase 3 first-party agent

**Principle** (carried from spec §3 strategy): openness as the hook, enclosure as the quality; too early loses trust, too late loses the window.

**Decision**: timing is triggered by **Phase 1 dogfood metrics** (MVP spec §16), not by calendar or intuition:

| Metric (2-week window after MVP ships) | Threshold | Action if unmet |
|---|---|---|
| Author's own ⌘⇧Space frequency | ≥ 10/day | fix UX; no Phase 3 talk |
| Golden-path delivery success (Claude Code + clipboard fallback) | ≥ 95% | fix reliability |
| Inbox total / revisits | ≥ 200 captures, ≥ 3 visits/week | fix Inbox value (the leading signal for memory demand) |
| Failed deliveries 100% have a readable reason | 100% | fix failure recovery |

All met → enter Phase 2 (memory decision per §2.3); if a natural "handle it directly inside Beamhop" share emerges mid-Phase-2 (users asking for it, external delivery share dropping), only then charter Phase 3.

## 4. Relationship to existing documents

- MVP scope / golden path: spec V2.1 is authoritative; this document changes nothing
- Phase windows: roadmap.md is authoritative; this document adds decision rationale to §2.3/§3 triggers
- Maintenance cadence: update on the Phase 2 kickoff evaluation (§2.3) and Phase 1 dogfood data backfill (§3); every update bumps the version

---

**End of document. Near-term actions: finish Week 3 panel + on-device acceptance → resolve Apple ID → run the §2.3 evaluation → charter Phase 2.**
