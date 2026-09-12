# Beamhop

> macOS 桌面 app — 在浏览器 / IDE / Notes / PDF / Figma 等任意 app 间抓取上下文，一键投递到任意外部 AI agent（Claude Code、Claude Cowork、ChatGPT Desktop 等）。

**状态**：Phase 1 源码已实现；Week 0 的 macOS 实机 Spike 与真机验收尚未执行。未验证的 ChatGPT/Cowork/浮窗能力默认安全降级，不把 Linux 上的静态结果伪装成 PASS。

## 文档

- [📐 MVP 设计稿 V2](docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — 经 Codex review 修订
- [🗺️ Roadmap](docs/superpowers/roadmap.md) — Phase 1 → Phase 4
- [🧪 Week 0 Spike 实施计划](docs/superpowers/plans/2026-06-03-week-0-spike.md) — 6 个集成假设验证

## 命名约定

- **Beamhop**（首字母大写）：品牌名、UI 文本、文档叙述
- `beamhop`（全小写）：bundle id、CLI、目录、SQL 字段

## 战略

Phase 1 是纯 agent-agnostic 投递工具；Phase 2 上 memory + 跨设备 Inbox；Phase 3+ 引入自家 agent（但保留外部投递）。详见 [roadmap.md](docs/superpowers/roadmap.md)。

## 在 macOS 上开干

Week 0 Spike 必须在 macOS 实机跑（Linux 沙盒/容器做不了 Accessibility API、Cocoa 浮窗、装 Chrome 扩展等）。建议流程：

```bash
# 1. clone 到 mac
git clone git@github.com:willamhou/beamhop.git
cd beamhop

# 2. 装 mac 端依赖（Spike 需要）
xcode-select --install                                # Xcode CLT (Swift toolchain)
brew install --cask claude              # Claude Cowork (mac 桌面版)
brew install --cask chatgpt             # ChatGPT Desktop
# Claude Code CLI: 按 https://docs.claude.com/en/docs/claude-code/install 装
# Chrome: brew install --cask google-chrome
# Accessibility Inspector: 装 Xcode 后自带

# 3. 在仓库根开 Claude Code，让它按 plan 跑 Week 0 Spike
cd /path/to/beamhop
claude
# 然后在 Claude Code 里说：
# "按 docs/superpowers/plans/2026-06-03-week-0-spike.md 的 Task 0 起步"
```

Plan 用 subagent-driven 模式执行（每个 Task 独立 fresh subagent，Task 间 review）。

## Phase 1 源码与验证

仓库现在包含四个 SwiftPM product：

- `Beamhop`：菜单栏 app、AX 抓取、浮窗、Inbox、诊断与投递 UI
- `BeamhopCore`：Capture/Delivery、SQLite、双 FTS5、provenance 与 prompt renderer
- `beamhop-mcp`：Claude Code / MCPB 共用的只读 MCP server
- `beamhop-native-host`：Chrome Native Messaging bridge

Chrome 扩展在 `browser-extension/`，Cowork 的 MCPB 包装在 `cowork-extension/`。macOS 本地构建：

```bash
npm ci --prefix browser-extension
npm run build --prefix browser-extension
npm test --prefix browser-extension
swift build
swift test
./packaging/build-app.sh
```

产物为 `dist/Beamhop.app`。Claude Code 与 Chrome 注册命令见 [`packaging/README.md`](packaging/README.md)。

Week 0 探针和未填造的实机证据位于 `spike/`。只有六项都按计划在 macOS 实机跑完，才能把 `spike/results.md` 的 `NOT RUN` 改为 PASS/FAIL 并回写 spec V2.1。
