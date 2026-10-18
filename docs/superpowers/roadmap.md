# Beamhop Roadmap

> Maintenance index: the single source of truth for every Phase's status, deliverables, and spec links.
> Last updated: 2026-06-03 (status column refreshed 2026-10-18: Phase 1 Week 3 delivered and user-verified)

## Maintenance conventions

**After any spec finishes implementation, update its entry in this document immediately**:

1. Change the Phase status from `📋 planned` or `🚧 in progress` to `✅ delivered`
2. Add an "actually completed on" date under the entry
3. Add the actual deliverables list (diff against the original plan)
4. Explicitly mark anything deferred into the next Phase
5. In the same commit: update the roadmap + flip the spec file's status to "implemented"

**When drafting a new spec**: add the spec file path placeholder under the corresponding Phase.

---

## Status overview

| Phase | Window | Status | Spec | Completed |
|---|---|---|---|---|
| Phase 1 — MVP | weeks 0–6 | ✅ delivered (Week 0 spike 6/6 → V2.1; Week 1 foundation; Week 2 golden path; integration peripherals; **Week 3 floating panel 2026-10-18, user-verified**) | [2026-06-03-beamhop-mvp-design.md](specs/2026-06-03-beamhop-mvp-design.md) (Chinese original, archived) | 2026-10-18 |
| Phase 1.5 — short-term patches | MVP + 2–4 weeks | 📋 planned | — | — |
| Phase 2.1 — cross-device Inbox | month 3–4 | 📋 planned | — | — |
| Phase 2.2 — memory & semantic search | month 4–6 | 📋 planned | — | — |
| Phase 2.3 — web chatbox & IDE agents | month 6–9 | 📋 planned | — | — |
| Phase 2.4 — OCR, templates, subscription | month 9–12 | 📋 planned | — | — |
| Phase 3 — first-party agent emerges | month 12+ | 📋 planned | — | — |
| Phase 4 — natural enclosure | month 18+ | 📋 planned | — | — |

---

## Phase 1 — MVP (Week 0 spike + 5 weeks, V2)

**Goal**: the capture→deliver golden path works on a single macOS machine; conditional goals fold in per spike results; the author uses it daily.

**Spec**: [2026-06-03-beamhop-mvp-design.md](specs/2026-06-03-beamhop-mvp-design.md) (V2 — revised after Codex review; Chinese original archived under docs/zh/)

**🟢 Golden path (must ship)**:
- macOS menu-bar app (native Swift / SwiftUI)
- Global hotkeys `⌘⇧Space` / `⌘⇧I` / `⌘⇧V`
- Chromium-family browser extension + generic AX capture
- Local SQLite Inbox + FTS5 (dual tables: unicode61 + trigram) + full provenance
- Own MCP server + **Claude Code CLI delivery** (`claude mcp add` onboarding)
- **Clipboard fallback handoff** (shared by all targets, always works)
- Permission diagnostics panel
- Built-in compatibility matrix + report channel
- Clipboard-safe paste protocol
- Failure recovery UI

**🟡 Conditional deliverables (decided by Week 0 spike, 2026-06-08)**:
- ChatGPT Desktop AX paste → **🟢 included (conditional)**: AX injection works (needs opt-in); single version at the time, re-tested on v26 2026-10-18
- Claude Cowork connector integration → **🟢 mechanism confirmed, fast-follow**: local `.mcpb`/config paths exist; e2e registration still pending
- Floating window over fullscreen apps / Stage Manager / multi-display → **✅ included**: fullscreen + Stage Manager pass; dual-display still untested

**✅ Week 0 spike complete (2026-06-08) — 6/6 hypotheses concluded** (see spec §14.4 + `spike/results.md`):
S1 Claude Code MCP **✅ PASS** / S2 Cowork **🟢 mechanism confirmed** / S3 ChatGPT AX **🟢 PARTIAL/PASS** / S4 Chrome native messaging **✅ PASS** / S5 floating window **✅ PASS** / S6 cross-app AX word-grab **🟡 PARTIAL**. Compatibility Matrix v0 → `spike/compatibility-matrix-v0.json`.

**Exit criteria**:
- Author personally uses `⌘⇧Space` ≥ 10 times/day
- Golden-path delivery success ≥ 95%; conditional targets ≥ 80%
- Panel popup latency P95 ≤ 300ms
- Inbox accumulates ≥ 200 captures
- 100% of failed deliveries show a human-readable "why" (no silent failures)

**Risks**: see spec §15; the highest risk (per Codex review) is the integration weeks (4–5), not the UI weeks — AX / native messaging / MCP registration are all version-sensitive; keep a 20% buffer.

---

## Phase 1.5 — short-term patches (MVP + 2–4 weeks)

**Trigger**: two weeks after MVP ships; high-frequency issues from user feedback + dogfood.

**Confirmed deferrals (from the V2 spec reshuffle)**:
- **Safari extension** (three sandboxes: containing app + JS + native extension; standalone mac app engineering effort)
- **Claude Cowork integration e2e verification + `.mcpb` packaging** (mechanism confirmed in Week 0; only logged-in registration + tool call verification remain)
- **Auto-Enter after delivering to ChatGPT Desktop**
- Multi-browser extension packaging (Arc/Brave/Edge manifest paths)

**Fast-follows rolled over from Week 0 spike (half-verified; close before GA)**:
- S3 ChatGPT AX path cross-version stability re-test (was single version 1.2026.119; re-done for 26.x 2026-10-18 — keep re-testing)
- S5 floating window dual-display behavior (Week 0 test machine had no external monitor)
- S4 native messaging app-level chunking protocol + reassembly test (~1MB cap measured)
- S6 Safari word-grab PoC via `AXSelectedTextMarkerRange`; Slack re-test signed in

**Other expected deliverables**:
- Delivery channel stability hardening (from dogfood-period compatibility matrix feedback)
- Panel UX polish (default-target memory policy, note field sizing)
- Inbox window performance (list rendering beyond 500 captures)
- Error logging & telemetry (local only, no reporting)
- Auto-update mechanism (Sparkle)

**Spec placeholder**: `specs/YYYY-MM-DD-phase-1-5-patches.md` (draft after MVP completes)

---

## Phase 2.1 — cross-device Inbox (month 3–4)

**Goal**: phone can one-tap send screenshots/links/text to the Inbox; desktop can use them immediately.

**Core deliverables**:
- iOS app + Share Extension (receive phone screenshots, Safari shares, selected text)
- Cloud sync channel (candidates: iCloud Drive fallback + self-hosted lightweight sync server)
- Sync policy: last-write-wins + soft-delete markers, no conflict resolution (each capture is independent, never concurrently edited)
- End-to-end encryption starts here — all cloud-synced content encrypted with a locally generated master key
- Inbox window gains an "originating device" filter

**Open decisions**:
- iCloud Drive vs self-hosted (cost, compliance, user trust)
- Linux/Windows sync explicitly out of scope (user base expected to stay mac + iOS)

**Spec placeholder**: `specs/YYYY-MM-DD-phase-2-1-cross-device-inbox.md`

---

## Phase 2.2 — memory & semantic search (month 4–6)

**Goal**: the Inbox is not just a history list — it's the user's "working memory".

**Core deliverables**:
- Local embeddings (candidates: small sentence-transformers model, or Apple Foundation Models on-device embeddings)
- Semantic search: FTS5 + embedding dual recall + reranking
- Context graph: auto-link captures "on the same topic" (embedding distance + time window + URL host)
- "Related captures" sidebar in the Inbox window
- Delivery-time suggestions of related captures (user checks what to attach)
- Memory storage: local SQLite + vector blob column (or sqlite-vss extension)

**Key UX decision**:
- Auto-linking **surfaces only when the user actively opens a capture** — never proactively in the panel (avoid attention theft)

**Spec placeholder**: `specs/YYYY-MM-DD-phase-2-2-memory.md`

---

## Phase 2.3 — web chatbox & IDE agents (month 6–9)

**Goal**: cover the remaining high-frequency delivery targets; the user's "agent matrix" is 100% connected.

**Core deliverables**:
- Web chatbox auto-injection (browser extension with per-site DOM adapters):
  - Claude.ai
  - ChatGPT.com
  - Perplexity
  - Gemini
  - DeepSeek
- IDE agent delivery:
  - Cursor (MCP)
  - Windsurf (MCP)
  - VS Code Copilot Chat (if feasible)
- Per-target custom hotkey bindings (`⌘1-9`)

**Key decisions**:
- Web injection: content script + DOM observer (recommended) vs reverse selenium-style automation
- How to recover fast when a chatbox's selectors break (remotely pushed rules?)

**Spec placeholder**: `specs/YYYY-MM-DD-phase-2-3-web-and-ide.md`

---

## Phase 2.4 — OCR, templates, subscription (month 9–12)

**Goal**: round out long-tail features + start monetization.

**Core deliverables**:
- Screenshot OCR (Apple Vision framework, on-device, zero cost)
- Custom prompt templates (user-editable + template marketplace prototype)
- Pre-delivery prompt editing panel (power users)
- Auto-suggested delivery targets (from delivery history distribution + capture domain hints)
- **Pro subscription launch**:
  - Free: single mac + 3 delivery targets + local Inbox (no cloud sync)
  - Pro: cross-device sync + memory + web chatbox injection + IDE agent delivery
  - Pricing candidates: $5–8/month
- Receipts/account system (candidates: Paddle, Lemon Squeezy)

**Spec placeholder**: `specs/YYYY-MM-DD-phase-2-4-pro-launch.md`

---

## Phase 3 — first-party agent emerges (month 12+)

**Goal**: introduce a first-party agent option without breaking the agent-agnostic stance.

**Core deliverables**:
- New `⌘0` delivery target: handle it directly inside Beamhop
- First-party agent runtime: calls OpenAI/Anthropic APIs (no self-trained models), but **with full memory + graph context**
- The selling point is not "a stronger model" — it's "we already have your complete picture; nothing to re-feed"
- All external delivery paths remain first-class citizens
- First-party agent output can be "re-delivered" to external agents (continue the discussion in Claude Code)

**Key strategy**:
- Timing judgment: push only after Phase 2 flywheel metrics land (avoid losing trust too early)
- The first-party agent must not fight the user's existing habits — it catches the "too lazy to switch windows" moments

**Spec placeholder**: `specs/YYYY-MM-DD-phase-3-native-agent.md`

---

## Phase 4 — natural enclosure (month 18+)

**Goal**: the first-party agent experience naturally surpasses external delivery; users choose to stay in Beamhop on their own.

**Core deliverables** (highly speculative — decide from Phase 3 data):
- Advanced first-party agent capabilities (background long-running tasks, cross-capture automatic reasoning)
- Team/shared Inbox (B2B entry)
- Marketplace (users share prompt templates, capture templates, agent workflows)
- **All external delivery stays available** — never let users feel locked in

---

## Continuous tracks (across all phases)

| Track | Phase 1 | Phase 2 | Phase 3+ |
|---|---|---|---|
| Privacy | local-first, no telemetry | E2E cloud sync | first-party agent input data policy |
| Performance | panel < 300ms | memory recall < 200ms | first-party agent first token < 1s |
| Languages | EN + ZH UI | + Japanese | + Korean / European languages |
| Bundle size | < 50MB | < 80MB | < 120MB |
| Memory | menu bar < 80MB | < 150MB | < 250MB |
| Accessibility | basic keyboard flow | VoiceOver support | full WCAG 2.1 AA |

---

## Deprecated / deferred ideas

(Record directions evaluated and shelved, to avoid re-discussing)

- **Desktop launcher form factor** (Raycast-style): evaluated; chose menu bar + panel, lighter
- **AI browser form factor** (Comet/Dia route): evaluated; chose agent-agnostic delivery, wider
- **Electron / Tauri stack**: evaluated; chose native Swift (see spec §12)
