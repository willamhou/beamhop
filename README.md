# Beamhop

> macOS 桌面 app — 在浏览器 / IDE / Notes / PDF / Figma 等任意 app 间抓取上下文，一键投递到任意外部 AI agent（Claude Code、Claude Cowork、ChatGPT Desktop 等）。

**状态**：Phase 1 MVP — Week 0 Spike ✅ → spec V2.1；Week 1 地基 ✅；Week 2 金线 + 浏览器桥 ✅（SwiftPM 实现 + 自动化验证,待 Xcode 打包）。

> 📌 **续作从这里开始 → [PROGRESS.md](PROGRESS.md)**（进度、已验证/待验证、恢复命令、坑、下一步,唯一入口）

## 构建运行（SwiftPM,Command Line Tools 即可）

```bash
swift build                 # 编译(含 GRDB)
swift run BeamhopSelfTest    # 数据层自测(28 项,无需 Xcode/XCTest)
swift run Beamhop            # 启动菜单栏 app(✦ 图标 + ⌘⇧Space/⌘⇧I 热键 + 诊断窗)
```
装完 Xcode 16 后:`Tests/BeamhopCoreTests/`(XCTest)可跑;再把 SwiftPM 包迁成 Xcode app target(Info.plist `LSUIElement` + Developer ID 签名)。

## 文档

- [📐 MVP 设计稿 V2.1](docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md) — 经 Codex review + Week 0 Spike 回写
- [🧪 Spike 结果](spike/results.md) — Week 0 决策矩阵 + [Compatibility Matrix v0](spike/compatibility-matrix-v0.json)
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

