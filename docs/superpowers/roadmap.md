# Beamhop Roadmap

> 维护索引：所有 Phase 的状态、交付物、对应 spec 链接的唯一真源。
> 最近更新：2026-06-03

## 维护约定

**每次某条 spec 完成实现后，必须立刻更新本文档对应条目**：

1. 把该 Phase 状态从 `📋 规划中` 或 `🚧 进行中` 改为 `✅ 已交付`
2. 在条目下补上"实际完成日期"
3. 在条目下补上"实际交付物"清单（与原计划对比，记录差异）
4. 如有未完成的内容下沉到下一个 Phase，明确标记
5. 同一 commit 里：更新 roadmap + 标记 spec 文件状态行为"已实现"

**新 spec 起草时**：在本文档对应 Phase 下添加 spec 文件路径占位。

---

## 当前状态总览

| Phase | 时间窗 | 状态 | Spec | 完成日期 |
|---|---|---|---|---|
| Phase 1 — MVP | 0–6 周 | 🚧 进行中（spec 已对齐 2026-06-03） | [2026-06-03-beamhop-mvp-design.md](specs/2026-06-03-beamhop-mvp-design.md) | — |
| Phase 1.5 — 短期补丁 | MVP + 2–4 周 | 📋 规划中 | — | — |
| Phase 2.1 — 跨设备 Inbox | Month 3–4 | 📋 规划中 | — | — |
| Phase 2.2 — Memory 与语义搜索 | Month 4–6 | 📋 规划中 | — | — |
| Phase 2.3 — Web chatbox 与 IDE agent | Month 6–9 | 📋 规划中 | — | — |
| Phase 2.4 — OCR、模板、订阅 | Month 9–12 | 📋 规划中 | — | — |
| Phase 3 — 自家 agent 浮现 | Month 12+ | 📋 规划中 | — | — |
| Phase 4 — 自然封闭 | Month 18+ | 📋 规划中 | — | — |

---

## Phase 1 — MVP（Week 0 Spike + 5 周，V2）

**目标**：抓取→投递金线在 macOS 单机跑通；条件目标视 Spike 结果纳入；自己 daily 用上。

**Spec**：[2026-06-03-beamhop-mvp-design.md](specs/2026-06-03-beamhop-mvp-design.md)（V2 — Codex review 后修订）

**🟢 金线（必交付）**：
- macOS 菜单栏 app（Swift / SwiftUI 原生）
- 全局快捷键 `⌘⇧Space` / `⌘⇧I` / `⌘⇧V`
- Chrome 系浏览器扩展 + 通用 AX 抓取
- Inbox 本地 SQLite + FTS5（unicode61 + trigram 双表）+ 完整 provenance
- 自家 MCP server + **Claude Code CLI 投递**（`claude mcp add` 引导）
- **剪贴板兜底 handoff**（全目标共用，永远可用）
- Permission Diagnostics 面板
- Compatibility Matrix 内置 + 上报通道
- Clipboard-Safe Paste 协议
- Failure Recovery UI

**🟡 条件交付（视 Week 0 Spike 结果）**：
- ChatGPT Desktop AX 粘贴
- Claude Cowork connector 集成
- 浮窗在全屏 app / Stage Manager / 多显示器上的覆盖

**Week 0 Spike 必须先跑通 6 个假设**（详见 spec §14）：S1 Claude Code MCP / S2 Cowork connector / S3 ChatGPT AX 稳定性 / S4 Chrome native messaging / S5 浮窗 collection behaviors / S6 跨 app AX 选中文本

**退出条件**：
- 自己 daily `⌘⇧Space` 次数 ≥ 10 次/天
- 金线投递成功率 ≥ 95%；条件目标 ≥ 80%
- 浮窗弹出延迟 P95 ≤ 300ms
- Inbox 累计 ≥ 200 条 Captures
- 失败的投递 100% 有可读的"为什么"信息（无 silent failure）

**风险**：详见 spec §15；最高风险点（Codex review 提示）是集成周（Week 4-5）而不是 UI 周，AX / native messaging / MCP 注册都是版本敏感，预留 20% buffer。

**实施进度（2026-08-23）**：Phase 1 源码、协议测试、macOS 打包脚本和六项 Spike 探针已落盘；状态仍为 🚧，因为当前 Linux 环境不能完成 macOS Swift/AppKit 编译与 Week 0 真机证据。ChatGPT/Cowork/浮窗/逐 app AX 支持在证据完成前保持 unverified/剪贴板降级，不计为已交付。

**剩余交付门**：macOS `swift build && swift test`、S1–S6 真机矩阵、V2.1 结果回写、签名/公证，以及 Roadmap 退出指标的 dogfood 数据。

---

## Phase 1.5 — 短期补丁（MVP + 2–4 周）

**触发条件**：MVP 上线后两周，用户反馈 + dogfood 中发现的高频问题。

**已确认推迟的项（来自 V2 Spec 重排）**：
- **Safari 扩展**（containing app + JS + native extension 三 sandbox，独立 mac app 工程量）
- **Claude Cowork 集成**（如 Week 0 Spike 失败 → 这里补上）
- **ChatGPT Desktop 投递后自动按回车**
- 多浏览器扩展打包（Arc/Brave/Edge 独立 manifest 路径）

**其他预期交付物**：
- 投递通道稳定性补强（基于 dogfood 期 Compatibility Matrix 反馈）
- 浮窗 UX 微调（默认目标记忆策略、备注输入框尺寸）
- Inbox 窗口性能（>500 条 Capture 时的列表渲染）
- 错误日志与 telemetry（仅本地，不上报）
- 自动更新机制（Sparkle）

**Spec 占位**：`specs/YYYY-MM-DD-phase-1-5-patches.md`（待 MVP 完成后起草）

---

## Phase 2.1 — 跨设备 Inbox（Month 3–4）

**目标**：手机端能把截图/链接/文本一键发到 Inbox，桌面端立刻能用。

**核心交付物**：
- iOS app + Share Extension（接收手机截图、Safari 分享、文本选中）
- 云同步通道（候选：iCloud Drive 兜底版 + 自建轻量 sync server）
- 同步策略：last-write-wins + 软删除标记，无冲突解决（每条 Capture 独立，不会并发改）
- 端到端加密（E2E）从这里开始上——所有云同步内容用本地生成的 master key 加密
- Inbox 窗口增加"来源设备"过滤

**核心决策待定**：
- iCloud Drive vs 自建（成本、合规、用户信任的权衡）
- Linux/Windows 同步暂不做（用户群预期仍是 mac + iOS）

**Spec 占位**：`specs/YYYY-MM-DD-phase-2-1-cross-device-inbox.md`

---

## Phase 2.2 — Memory 与语义搜索（Month 4–6）

**目标**：Inbox 不只是历史列表，是用户的"工作记忆"。

**核心交付物**：
- 本地 embedding（候选：sentence-transformers 小模型，或 Apple Foundation Models 本地嵌入）
- 语义搜索：FTS5 + embedding 双路召回 + 重排
- 上下文图谱：自动关联"同主题"Captures（基于 embedding 距离 + 时间窗口 + URL host）
- Inbox 窗口的"相关 Captures"侧栏
- 投递时自动建议附带的相关 Captures（用户可勾选）
- Memory 数据存哪里：本地 SQLite + vector blob 字段（或 sqlite-vss 扩展）

**关键 UX 决策**：
- 自动关联**只在用户主动打开某条 Capture 时展示**，不在浮窗里主动 surface（避免分散注意力）

**Spec 占位**：`specs/YYYY-MM-DD-phase-2-2-memory.md`

---

## Phase 2.3 — Web chatbox 与 IDE agent（Month 6–9）

**目标**：覆盖剩余的高频投递目标，让用户的"agent 矩阵"100% 接入。

**核心交付物**：
- Web chatbox 自动注入（浏览器扩展为每家做 DOM 适配）：
  - Claude.ai
  - ChatGPT.com
  - Perplexity
  - Gemini
  - DeepSeek
- IDE agent 投递：
  - Cursor（MCP）
  - Windsurf（MCP）
  - VS Code Copilot Chat（如可行）
- 投递目标的"自定义快捷键"绑定（`⌘1-9`）

**核心决策**：
- Web 注入用 content script + DOM observer，还是反向 selenium-style 自动化？建议 content script。
- 每家 chatbox 的 selector 失效如何快速恢复（远程下发规则？）

**Spec 占位**：`specs/YYYY-MM-DD-phase-2-3-web-and-ide.md`

---

## Phase 2.4 — OCR、模板、订阅（Month 9–12）

**目标**：完善长尾功能 + 启动商业化。

**核心交付物**：
- 屏幕截图 OCR（Apple Vision framework 本地 OCR，零成本）
- 自定义 Prompt 模板（用户可编辑 + 模板市场雏形）
- 投递时的 prompt 预编辑面板（高级用户）
- 自动建议投递目标（基于历史投递分布 + Capture domain hint）
- **Pro 订阅启动**：
  - Free：mac 单机 + 3 个投递目标 + 本地 Inbox（无云同步）
  - Pro：跨设备同步 + memory + Web chatbox 注入 + IDE agent 投递
  - 定价候选：$5–8/月
- 收据/账号系统（候选：Paddle Lemon Squeezy）

**Spec 占位**：`specs/YYYY-MM-DD-phase-2-4-pro-launch.md`

---

## Phase 3 — 自家 agent 浮现（Month 12+）

**目标**：在不破坏 agent-agnostic 立场的前提下，引入自家 agent 选项。

**核心交付物**：
- 投递目标列表新增 `⌘0`：在 Beamhop 内直接处理
- 自家 agent runtime：调 OpenAI/Anthropic API（不自训模型），但**带完整 memory + 图谱上下文**
- 卖点不是"模型更强"，是"我们已经有你完整画像，不用再喂"
- 仍保留所有外部投递路径为一等公民
- 自家 agent 的输出可"返投"到外部 agent（继续在 Claude Code 里讨论）

**关键策略**：
- 引入时机判断：Phase 2 飞轮指标达成后才推（避免过早失去信任）
- 自家 agent 不抢用户的现有习惯，只在用户"懒得切窗口"时承接

**Spec 占位**：`specs/YYYY-MM-DD-phase-3-native-agent.md`

---

## Phase 4 — 自然封闭（Month 18+）

**目标**：自家 agent 体验自然超越外部投递，用户主动选择留在 Beamhop 内。

**核心交付物**（高度推测，等 Phase 3 数据再定）：
- 自家 agent 的高级能力（后台 long-running task、跨 Capture 自动 reasoning）
- 团队/共享 Inbox（B2B 入口）
- Marketplace（用户分享 Prompt 模板、抓取模板、agent workflow）
- 但**所有外部投递保留可用**——避免用户感觉被绑架

---

## 持续轨道（贯穿所有 Phase）

| 轨道 | Phase 1 | Phase 2 | Phase 3+ |
|---|---|---|---|
| 隐私 | 本地优先，无 telemetry | E2E 云同步 | 自家 agent 输入数据策略 |
| 性能 | 浮窗 < 300ms | Memory 召回 < 200ms | 自家 agent 首 token < 1s |
| 多语言 | 中英 UI | + 日语 | + 韩语 / 欧语 |
| 包体积 | < 50MB | < 80MB | < 120MB |
| 内存 | 菜单栏 < 80MB | < 150MB | < 250MB |
| 可访问性 | 基础键盘流 | VoiceOver 适配 | 完整 WCAG 2.1 AA |

---

## 已废弃 / 推迟的想法

（用于记录评估过但暂不做的方向，避免重复讨论）

- **桌面 launcher 形态**（Raycast-style）：评估后选了菜单栏 + 浮窗，更轻
- **AI 浏览器形态**（Comet/Dia 路线）：评估后选了 agent-agnostic 投递，更广
- **Electron / Tauri 技术栈**：评估后选了 Swift 原生（详见 spec §12）
