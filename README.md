# Beamhop

> macOS menu-bar app — grab context from any app (browser / IDE / Notes / PDF / Figma) and deliver it in one keystroke to any external AI agent (Claude Code, Claude Cowork, ChatGPT Desktop, Kimi Work, …).

**Status**: Phase 1 MVP — Week 0 Spike ✅ (spec V2.1) → Week 1 foundation ✅ → Week 2 golden path + browser bridge ✅ → integration peripherals ✅ → **Week 3 floating capture panel + Kimi Work delivery ✅ (verified on-device 2026-10-18)**.

> 📌 **Resume here → [PROGRESS.md](PROGRESS.md)** — progress, verified/pending, recovery commands, pitfalls, next steps. Single entry point.

## Build & run (SwiftPM, Command Line Tools is enough)

```bash
swift build                 # build (incl. GRDB)
swift test                  # BeamhopCore XCTest (requires full Xcode)
swift run BeamhopSelfTest   # logic self-test (86 checks, no Xcode/XCTest needed)
swift run Beamhop           # menu-bar app (✦ icon + ⌘⇧Space/⌘⇧I/⌘⇧V + Inbox/diagnostics/compatibility windows)
scripts/mcp-smoke.sh        # MCP stdio smoke (S1 frame format + seed data)
./packaging/build-app.sh    # assemble dist/Beamhop.app (ad-hoc signed)
```

Pushing any branch runs all checks on GitHub Actions (macos-15 + ubuntu) — compile can be verified without a local Mac.

## Delivery target matrix

| Target | Channel | Evidence |
|---|---|---|
| Claude Code CLI | MCP server (data) + AX safe-paste (trigger) | S1 PASS, verified against real Claude Code |
| ChatGPT Desktop | `AXManualAccessibility` opt-in + composer locate + set-value injection, never auto-send | S3 + v26 re-verified (26.1007.71326) |
| Kimi Work | AX composer locate + clipboard-paste injection (set-value ineffective on Kimi editor), auto new-chat | probed 2026-10-18 (Kimi 3.2.17, Electron 43) |
| Claude Cowork | `cowork-extension/` MCPB wrapper (mechanism S2 confirmed, E2E pending); clipboard fallback for now | S2 |
| All targets | clipboard + notification (golden-path fallback, always works) | spec §7.1 |

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
