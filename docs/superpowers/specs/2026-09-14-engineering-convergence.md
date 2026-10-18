# Beamhop Engineering Convergence Spec (branch model & two-machine collaboration)

> Date: 2026-09-14
> Status: V1 — in effect alongside the `integration` branch (CI green)
> Positioning: the **process-layer** companion to MVP design spec V2.1. Changes no product scope; locks down "where code is written, how it's verified, how it merges".
> Origin: the 2026-06~09 parallel-implementation incident (a Linux clone sat at the June 3 baseline while an agent, working from stale docs, rewrote all of Phase 1 — diverging from 33 on-device-verified commits on the Mac).

## TL;DR

The only long-lived branch is `main`; `main` means "the most recent on-device-verified state". Linux develops, CI is the compile gate (full macos-15 suite), the Mac is the acceptance gate; every machine, every session runs `git fetch` to align with origin before starting.

## 1. Incident mechanism (why this spec exists)

| Fact | Consequence |
|---|---|
| Linux clone stayed at 0a712f9 (June 3 docs-only baseline), never fetched | Locally invisible: the Mac's June 7–8 spike results and Week 1/2 implementations |
| Agent rewrote Phase 1 from the stale spec V2 | An implementation contradicting measured conclusions (MCP Content-Length frames, no AXManualAccessibility) |
| Both versions happened to share `Sources/BeamhopCore/` and `Sources/BeamhopMCP/` paths | git merge auto-resolved → duplicate type definitions → **neither side compiled** |

Conclusion: the root cause was not a git mistake but **no cross-machine sync discipline + no single source of truth**. Tools can't prevent it; process can.

## 2. Branch model

### 2.1 Target state (after acceptance)

```
main ──────────●─────────●─────────→   the only long-lived branch
               │         │
        verified-2026-09 │   (tag after each on-device acceptance pass)
               │
     feature/* ─┴─ CI green → squash merge → delete branch (lifetime ≤ 1 week)
```

- **`main` = the most recent on-device-verified state.** Merge preconditions: CI fully green **and** the affected on-device acceptance items pass (see §4).
- **Feature branches are short-lived** (≤ 1 week): branch from latest `main`, squash-merge after CI green, delete immediately.
- **`verified-<YYYY-MM>` tags**: applied to `main` after each full on-device acceptance. When things break, roll back to the previous tag instead of hotfixing on the spot.

### 2.2 Transitional branch disposition (one-time)

| Branch | Disposition | When |
|---|---|---|
| `integration` | Run the PROGRESS §8 acceptance list on a Mac → merge back to `main` → delete | next time at the Mac |
| `phase1-linux-reimpl` | Tag `archive/phase1-linux-reimpl` → delete branch (unique assets all moved into integration) | right after the integration merge |
| `main` (the June state) | untouched until integration merges | superseded |

## 3. Two-machine split and the two gates

| Machine | Role | Does | Does NOT |
|---|---|---|---|
| Linux (daily) | dev machine | write code, run JS tests, shell lint, push | **make any "it runs/works" claims** |
| GitHub CI (macos-15 + ubuntu) | **compile gate** | swift build/test, SelfTest, MCP smoke, manifest smoke, assemble Beamhop.app, extension esbuild | grant TCC permissions, test the real app |
| Mac | **acceptance gate** | TCC grants, ⌘⇧Space golden path, real ChatGPT/Cowork/Kimi delivery, panel & Inbox feel | long-term development (avoid divergence) |

**Mental model**: CI green = "not wrong"; on-device pass = "usable". Neither substitutes for the other, and neither side may overstate its conclusion.

## 4. On-device acceptance list (merge gate for main)

Items CI cannot cover that must be tested on a Mac (maintained in PROGRESS.md §8; tick every item before merging):

1. ChatGPT Desktop AX injection (S3 path, version at S3-test time + current version)
2. Inbox window (list / dual-FTS search / re-deliver / soft-delete feel)
3. FirstRun + compatibility matrix windows
4. `packaging/build-app.sh` artifact runs (TCC binds to signing identity)
5. MCPB install → `fetch_capture` from a Cowork session (S2 end-to-end)

## 5. Iron rules (incident prevention)

1. **Every machine, every session: `git fetch` and confirm the relationship with origin before starting work.** This is the only directly targeted prevention for that incident.
2. **PROGRESS.md is the single entry point** — every session reads it before touching code; its "last updated" timestamp must move with every substantive push forward.
3. **Specs are the source of truth** — before writing an implementation, confirm you're reading the spike-written-back version (V2.1+), not stale assumptions.
4. **Never re-implement in parallel** — when something "seems missing", run `git log --all --oneline` and fetch first.

## 6. Success criteria

- 6 months from now the repo has only `main` + short-lived feature branches + `verified-*` tags, no parallel long-lived branches
- Any commit on `main` can be built into `Beamhop.app` by CI
- Every `verified-*` tag has a matching acceptance record in PROGRESS (which Mac, which app versions, conclusion)
- No more "two generations of implementation coexisting"

---

**End of document. Actions to take effect: Mac acceptance → merge integration back to main → tag → delete both transitional branches.**
