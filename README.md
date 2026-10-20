# Beamhop

> macOS menu-bar app — grab context from any app (browser / IDE / Notes / PDF / Figma) and deliver it in one keystroke to any external AI agent (Claude Code, Claude Cowork, ChatGPT Desktop, Kimi Work, …).

**Status**: Phase 1 MVP — Week 0 Spike ✅ (spec V2.1) → Week 1 foundation ✅ → Week 2 golden path + browser bridge ✅ → integration peripherals ✅ → **Week 3 floating capture panel + Kimi Work delivery ✅ (verified on-device 2026-10-18)**.

> 📌 **Resume here → [PROGRESS.md](PROGRESS.md)** — progress, verified/pending, recovery commands, pitfalls, next steps. Single entry point.

## Build & run (SwiftPM, Command Line Tools is enough)

```bash
swift build                 # build (incl. GRDB)
swift test                  # BeamhopCore XCTest (requires full Xcode)
swift run BeamhopSelfTest   # logic self-test (no Xcode/XCTest needed)
swift run Beamhop           # menu-bar app (✦ icon + ⌘⇧Space/⌘⇧I/⌘⇧V + Inbox/diagnostics/compatibility windows)
scripts/mcp-smoke.sh        # MCP stdio smoke (S1 frame format + seed data)
./packaging/build-app.sh    # assemble dist/Beamhop.app (auto-signs with the "Beamhop Sign" dev identity if set up — run scripts/setup-dev-signing.sh once; otherwise ad-hoc)
```

Pushing any branch runs Swift tests, packaging and native panel checks on GitHub Actions (`macos-15`), plus extension and shell checks on Ubuntu. Native UI evidence includes English/Chinese light/dark PNGs and interaction reports. Feature-branch pushes also produce a downloadable development app. See [native UI verification](docs/native-ui-verification.md) for commands, artifacts and coverage.

Active development is on `feat/phase15-detail-chain`: a compact handoff panel with an optional corner shelf. Named works remember the receiving app; they do not yet address a specific agent conversation.

## Delivery target matrix

| Target | Channel | Evidence |
|---|---|---|
| Claude Code CLI | MCP server (data) + AX safe-paste (trigger), manual submission | MCP protocol covered in CI; current terminal handoff needs integration acceptance |
| ChatGPT Desktop | Locate a readable empty composer and prepare a draft; otherwise copy for review, never auto-send | Injection mechanism verified on v26; current draft-protection path needs integration acceptance |
| Kimi Work | Prepare a draft in the current conversation only when its composer is known empty; otherwise copy for review | Paste mechanism probed 2026-10-18; current conversation/draft protection needs integration acceptance |
| Claude Cowork | `cowork-extension/` MCPB wrapper (mechanism S2 confirmed, E2E pending); clipboard fallback for now | S2 |
| All targets | Clipboard fallback with a copied receipt; copy failure is reported and material is kept | Core recovery checks in CI; copying does not imply agent receipt |

## Docs

Language policy: **English is the default**; the Chinese originals are archived under [docs/zh/](docs/zh/) (historical deep-specs there are marked translation-pending).

- [📐 MVP design spec V2.1](docs/zh/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — Chinese original (913 lines, translation pending): Codex-reviewed + Week 0 spike writeback
- [🪟 Week 3 floating-window spec](docs/superpowers/specs/2026-09-18-week-3-floating-window.md) + [implementation plan](docs/superpowers/plans/2026-09-18-week-3-implementation.md)
- [🧪 Spike results](spike/results.md) — Week 0 decision matrix + [Compatibility Matrix v0](spike/compatibility-matrix-v0.json)
- [🛠️ Engineering convergence spec](docs/superpowers/specs/2026-09-14-engineering-convergence.md) — branch model, two-machine split, acceptance gates (2026-09)
- [🧭 Evolution decisions spec](docs/superpowers/specs/2026-09-14-evolution-decisions.md) — Xcode timing, Phase 2 memory direction, Phase 3 triggers (2026-09)
- [🗺️ Roadmap](docs/superpowers/roadmap.md) — Phase 1 → Phase 4
- [🧪 Week 0 spike plan](docs/zh/superpowers/plans/2026-06-03-week-0-spike.md) — 6 integration hypotheses (Chinese original, completed)

## Naming

- **Beamhop** (capitalized): brand, UI text, prose
- `beamhop` (lowercase): bundle id, CLI, directories, SQL columns

## Strategy

Phase 1 is a pure agent-agnostic delivery tool; Phase 2 adds memory + cross-device Inbox; Phase 3+ introduces a first-party agent (external delivery stays). See [roadmap.md](docs/superpowers/roadmap.md).

## Getting started on macOS

Week 0 spike must run on real macOS hardware (Accessibility API, Cocoa panels, Chrome extensions don't work in Linux containers). Suggested flow:

```bash
# 1. clone on a mac
git clone git@github.com:willamhou/beamhop.git
cd beamhop

# 2. install mac-side deps (spike needs)
xcode-select --install                     # Xcode CLT (Swift toolchain)
brew install --cask chatgpt                # ChatGPT Desktop
brew install --cask kimi                   # Kimi Work desktop (optional target)
# Accessibility Inspector ships with Xcode

# 3. build and run
swift build && ./packaging/build-app.sh && open dist/Beamhop.app
# grant Accessibility when prompted (System Settings → Privacy & Security)
```

Plans were executed subagent-driven (fresh subagent per task, review between tasks).
