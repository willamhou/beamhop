# Beamhop

> macOS 桌面 app — 在浏览器 / IDE / Notes / PDF / Figma 等任意 app 间抓取上下文，一键投递到任意外部 AI agent（Claude Code、Claude Cowork、ChatGPT Desktop 等）。

**状态**：Phase 1 MVP 规划完成，待 Week 0 Spike 验证。

## 文档

- [📐 MVP 设计稿 V2](docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — 经 Codex review 修订
- [🗺️ Roadmap](docs/superpowers/roadmap.md) — Phase 1 → Phase 4
- [🧪 Week 0 Spike 实施计划](docs/superpowers/plans/2026-06-03-week-0-spike.md) — 6 个集成假设验证

## 命名约定

- **Beamhop**（首字母大写）：品牌名、UI 文本、文档叙述
- `beamhop`（全小写）：bundle id、CLI、目录、SQL 字段

## 战略

Phase 1 是纯 agent-agnostic 投递工具；Phase 2 上 memory + 跨设备 Inbox；Phase 3+ 引入自家 agent（但保留外部投递）。详见 [roadmap.md](docs/superpowers/roadmap.md)。
