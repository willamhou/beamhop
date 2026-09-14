# Beamhop

> macOS 桌面 app — 在浏览器 / IDE / Notes / PDF / Figma 等任意 app 间抓取上下文，一键投递到任意外部 AI agent（Claude Code、Claude Cowork、ChatGPT Desktop 等）。

**状态**：Phase 1 MVP — Week 0 Spike ✅ → spec V2.1；Week 1 地基 ✅；Week 2 金线 + 浏览器桥 ✅；`integration` 分支补齐 Phase 1 外围（ChatGPT AX 注入、Inbox/首次引导/兼容矩阵 UI、CI、打包、MCPB）——外围部分待 macOS 真机验收，CI（macos-15）覆盖编译与存储/协议自测。

> 📌 **续作从这里开始 → [PROGRESS.md](PROGRESS.md)**（进度、已验证/待验证、恢复命令、坑、下一步,唯一入口）

## 构建运行（SwiftPM,Command Line Tools 即可）

```bash
swift build                 # 编译(含 GRDB)
swift test                  # BeamhopCore XCTest(需完整 Xcode)
swift run BeamhopSelfTest    # 数据层自测(28 项,无需 Xcode/XCTest)
swift run Beamhop            # 启动菜单栏 app(✦ 图标 + ⌘⇧Space/⌘⇧I/⌘⇧V + Inbox/诊断/兼容性窗口)
scripts/mcp-smoke.sh         # MCP stdio 冒烟(S1 帧格式 + 种子数据)
./packaging/build-app.sh     # 组装 dist/Beamhop.app(ad-hoc 签名)
```

推送任意分支会在 GitHub Actions（macos-15 + ubuntu）上跑全部检查——没有本地 Mac 也能验证编译。

## 投递目标矩阵

| 目标 | 通道 | 依据 |
|---|---|---|
| Claude Code CLI | MCP server（数据）+ AX 安全粘贴（触发） | S1 实测 PASS,真 Claude Code 验证过 |
| ChatGPT Desktop | `AXManualAccessibility` opt-in + `kAXValueAttribute` set-value 注入,不自动发送 | S3 实测可行(单版本);失败→剪贴板 |
| Claude Cowork | `cowork-extension/` MCPB 包装（机制 S2 已确认,端到端待验收）;应用内暂走剪贴板 | S2 |
| 所有目标 | 剪贴板 + 通知（金线兜底,永可用） | spec §7.1 |

## 文档

- [📐 MVP 设计稿 V2.1](docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — 经 Codex review + Week 0 Spike 回写
- [🧪 Spike 结果](spike/results.md) — Week 0 决策矩阵 + [Compatibility Matrix v0](spike/compatibility-matrix-v0.json)
- [🛠️ 工程收敛 Spec](docs/superpowers/specs/2026-09-14-engineering-convergence.md) — 分支模型、双机分工、验收门槛（2026-09）
- [🧭 演进决策 Spec](docs/superpowers/specs/2026-09-14-evolution-decisions.md) — Xcode 时机、Phase 2 memory 方向、Phase 3 触发条件（2026-09）
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

