# Beamhop MVP 设计稿

> 项目名：**Beamhop**（品牌呈现）/ `beamhop`（技术标识：bundle id、目录、CLI）
> 日期：2026-06-03（V2 修订：2026-06-03）
> 状态：V2 — 经 Codex 独立 review 修订；Week 0 Spike 必须先跑通才能开 Week 1
> 修订说明：V1 假设 MCP 路径/Cowork 集成/AX 粘贴稳定性都过于乐观；V2 引入 Spike-First、范围收窄、provenance 升为一等公民。

## TL;DR

一个 macOS 菜单栏常驻的桌面 app，按 `⌘⇧Space` 抓取当前活跃 app（浏览器/IDE/Notes/PDF/Figma…）的上下文，弹浮窗让用户选择投递目标，通过 MCP / connector / Accessibility 粘贴的组合通道把上下文喂给目标 agent。所有抓取自动入 Inbox（本地 SQLite，**带完整 provenance**），可通过 `⌘⇧I` 浏览/搜索/重新投递。

技术栈：Swift / SwiftUI 原生。**总工期：1 周 Spike + 5 周 MVP**。

**金线（必交付）**：Chrome 抓取 + 通用 AX 选中文本 + 本地 Inbox + Claude Code MCP + 剪贴板兜底 handoff。
**条件交付（视 Week 0 Spike 结果）**：ChatGPT Desktop AX 粘贴、Claude Cowork connector 集成。
**推迟 Phase 1.5**：Safari 扩展、Cowork（如 Spike 失败）、ChatGPT 自动按回车。

## 1. 背景与目标

### 1.1 痛点

主力使用桌面 app 的人在多 agent 工具间频繁切换。典型链路：

- 浏览器看到一篇文章/PR/issue → 想让 Claude Code、Codex、ChatGPT 深入分析 → **只能手动截图或复制粘贴**
- IDE 里的代码 → 想喂给 chatbox → 同上
- 手机上看到的内容 → 想在桌面端 agent 里继续 → 经微信/Notes 中转，体验断裂

现有产品（Sider/Monica/Comet/Atlas/Dia/Claude in Chrome 等）都是"投递到自家 AI"的闭环；Invoko、Highlight AI 做了"跨 app 抓取"，但 Invoko 转向自家 agent runtime，Highlight 的外投只到剪贴板级别。**"任意 app 抓取 → 投递到任意外部 agent"的赛道几乎空白**。

### 1.2 用户画像

主力使用桌面原生 app（不是 web 重度用户）的开发者 / 研究者 / 知识工作者。日常 agent 工具组合包括：
- 本地 CLI：Claude Code、Codex CLI
- 桌面 app：Claude Cowork、ChatGPT Desktop
- 偶尔回退到 web 版 chatbox（Phase 2 覆盖）

### 1.3 MVP 目标

| 目标 | 验证什么 |
|---|---|
| **金线**：Chrome → Claude Code MCP 抓投全链路在 macOS 单机跑通 | 核心工程可行性 + UX 手感 |
| **条件目标**：ChatGPT Desktop / Cowork 集成（视 Week 0 Spike 结果纳入） | MCP / connector / AX 各通道是否站得住 |
| Inbox 本地持久化 + **完整 provenance**（capture_id + 源 app + bundle id + pid + window title + 时间戳 + AX 路径快照） | 出错时用户能看清"为什么"，比"能跑"更重要 |
| 自己（产品发起者）daily 用上 | dogfood 即真实 PMF 信号 |

**Codex review 给出的战略提示（V2 强化）**：防御性 wedge 不是"我们能粘上下文到 AI"——这条很快会被 OpenAI Codex macOS app / ChatGPT "Work with Apps" / Anthropic Cowork+connector 生态吃掉。真正的 wedge 是**本地的、可检查的、跨 app 的 provenance + 用户控制的隐私边界 + 跨 agent 路由**。这意味着 MVP 必须把 provenance、inspectability、permission diagnostics 当一等公民写，不是事后补丁。

### 1.4 MVP 非目标

iOS / 跨设备同步、OCR、Web chatbox 自动注入、长期 memory / 语义搜索、Cursor/Windsurf 投递、自定义 Prompt 模板、收费、自动投递目标建议、Capture 加密。详见 §10。

## 2. 竞品定位

| 产品 | 形态 | 与 Beamhop 的关系 |
|---|---|---|
| Invoko | mac 桌面 app，跨 app 抓取 → 自家 agent | 抓取广，但投递闭环；Beamhop 抓取同样广 + 投递到任意外部 agent |
| Highlight AI | mac 桌面 app，跨 app context-aware | 最接近的对手；Beamhop 在"投递到外部 dev agent"上更专 |
| **OpenAI Codex macOS app**（2026 早） | 多 agent 命令中心，扩展 computer-use 方向 | **平台级威胁**：能从 OpenAI 生态内部抓取 + 投递，长期可能挤压 Beamhop |
| **ChatGPT "Work with Apps"**（macOS） | 系统级集成，读 IDE/终端/Notes 上下文 | 已覆盖部分场景，但仅服务 ChatGPT，不投递到外部 |
| Claude Cowork + Claude in Chrome + connector | Anthropic 自家生态 | 平台主在做相同事，但闭环；Beamhop 必须保持 agent-agnostic |
| Perplexity Comet / Dia / Atlas | AI 浏览器 | 浏览器内闭环 |
| Drawbridge | 网页评论 → Claude Code/Cursor task | 投递方向对，但只覆盖前端反馈这一窄场景 |
| Raycast `{browser-tab}` | Launcher | 抓取浏览器 tab 到 Raycast AI，外发需自写脚本 |
| Playwright MCP / Fetch MCP | MCP server | agent 主动取网页；Beamhop 是用户主动投页面 |

**差异化（V2 强化）**：抓取广（不止浏览器）+ 投递广（agent-agnostic）+ macOS 原生体验 + **本地可检查的 provenance + 用户控制的隐私边界 + 跨 agent 路由**。仅有前三点不足以抵御平台主，第四点（provenance/inspectability/privacy）必须作为产品的视觉与功能存在感被用户感知，不只是后端能力。

## 3. 战略与演化路径

**核心策略：开放为引，封闭为质。** 先做纯 agent-agnostic 投递工具获取用户和数据，飞轮起来后引入自家 agent 层。

| Phase | 时间窗 | 形态 |
|---|---|---|
| **1 (MVP)** | 0–6 月 | 纯投递工具，无内置 agent。本文档覆盖这一阶段。 |
| **2** | 6–12 月 | Inbox 语义搜索 + 长期 memory + 上下文图谱 + iOS 端 + 云同步 + Web chatbox 自动注入 |
| **3** | 12+ 月 | 投递列表里加入"在 Beamhop 内直接处理"选项（不强推），home court advantage 浮现 |
| **4** | 飞轮起来后 | 自然封闭：自家 agent 用得多了，外部 agent 仍保留作为长尾 |

风险：
- Phase 1 必须真心 agent-agnostic（否则用户感知到藏私心 → 失去信任）
- Phase 3 引入时机过早会失去信任，过晚会失去时间窗口
- 数据隐私立场从第一天就要刻进产品（本地优先，云同步 E2E）

## 4. MVP 范围（Spike + 5 周）

**分三层：金线必交付 / 条件交付 / 推迟 Phase 1.5**。这是 V2 对 V1 "极简 MVP 4-6 周" 的修订——Codex review 指出原范围对一名工程师 + 4-6 周是"naive"，必须先做 Week 0 Spike 验证关键集成假设，再分层落地。

### 4.1 🟢 金线 — 必交付（无论 Spike 结果如何）

- macOS 菜单栏 app 框架 + 全局快捷键 + 浮窗 + Inbox 窗口
- **Chrome 浏览器扩展**（Manifest V3，含 native messaging host + 1MB 消息分片）
- **通用 AX 抓取**（轻量元数据：app name + bundle id + pid + window title + selected text）
- 按需截图（用户勾选时触发，Apple Screen Recording 权限单独引导）
- Inbox 本地 SQLite + FTS5（**unicode61 + trigram** 双 tokenizer）
- **完整 provenance 记录**（详见 §11.5）
- **Claude Code CLI 投递**（自家 MCP server + `claude mcp add` 引导）
- **剪贴板兜底 handoff**：所有 AX 粘贴失败时降级为"已复制到剪贴板 + 通知"
- 首次启动权限引导 + Permission Diagnostics 面板
- Compatibility Matrix 内置文档（用户可看：哪个目标 app 哪个版本测过）

### 4.2 🟡 条件交付 — 视 Week 0 Spike 结果纳入

| 能力 | 依赖 spike 验证 | 纳入条件 |
|---|---|---|
| ChatGPT Desktop AX 粘贴 | ChatGPT Desktop 当前版本 AX tree 中输入框 identifier 稳定 + 跨 ≥ 2 个最近版本一致 | Spike 通过 → 加入金线；失败 → 仅做剪贴板 handoff |
| Claude Cowork 集成 | Cowork 的 connector/plugin 实际机制摸清 + 注册流程可一键完成 | Spike 通过且工作量 < 1 周 → 纳入；否则推迟 Phase 1.5 |
| 浮窗覆盖全屏 app | `canJoinAllSpaces` + `fullScreenAuxiliary` 在真实全屏 / Stage Manager / 多显示器场景验证 | Spike 通过 → 纳入；失败 → 文档化"在全屏 app 中按热键会退出全屏" |

### 4.3 🔴 明确推迟到 Phase 1.5 或更晚

- **Safari 扩展**（containing app + JS + native extension 三 sandbox 架构，工作量被低估，详见 §6.3）
- ChatGPT Desktop "投递后自动按回车"
- Cowork 集成（如 Spike 失败）
- 全文 OCR
- 多浏览器扩展（Arc/Brave/Edge）

❌ **完全不在 Phase 1 范围**：见 §10 Out of Scope。

## 5. 架构总览

### 5.1 总体结构

```
┌─────────────────────────────────────────────────────────────┐
│  beamhop.app (Swift / SwiftUI, 菜单栏常驻)                    │
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐    │
│  │ 抓取引擎      │  │ Inbox 存储    │  │ 投递引擎          │    │
│  │             │  │ (SQLite)     │  │                 │    │
│  │ • AX API    │→ │ • captures   │←─│ • MCP server    │    │
│  │ • Screencap │  │ • deliveries │  │ • AX 粘贴       │    │
│  │ • Ext bridge│  │              │  │ • Prompt Renderer│    │
│  └─────────────┘  └──────────────┘  └─────────────────┘    │
│         ↑                ↑                  ↓               │
│  ⌘⇧Space 浮窗      ⌘⇧I Inbox 窗口      到各目标 agent       │
└─────────────────────────────────────────────────────────────┘
        ↑                                      ↓
┌──────────────────┐                  ┌─────────────────────┐
│ Safari/Chrome    │                  │ Claude Code CLI     │
│ 浏览器扩展        │                  │ Claude Cowork       │
│ (Native Msg)     │                  │ ChatGPT Desktop     │
└──────────────────┘                  └─────────────────────┘
```

### 5.2 核心数据流（按 `⌘⇧Space` 的 90% 路径）

```
1. 用户在 Safari 看 GitHub PR，⌘⇧Space
2. 抓取引擎并行触发：
   ├─ AX API 读取：app=Safari, window=PR title, URL, 选中文本
   ├─ 浏览器扩展（如装了）：返回该 tab 的 DOM 正文 / 高亮代码
   └─ Screencap：只在用户勾选时执行，否则不截
3. 抓取结果合并为 1 条 Capture 记录，写入 Inbox SQLite
4. 浮窗弹出，光标在备注输入框，默认目标 = 上次成功投递的目标
5. 用户回车 → 投递引擎根据目标选不同通道（见 §7）
6. 浮窗收起 + 系统通知"已投递 Claude Code"
```

### 5.3 关键架构判断

1. **投递引擎不是单一通道**。MCP 只覆盖懂协议的 agent（Claude Code/Cowork），ChatGPT Desktop 和 Web chatbox 必须走 Accessibility 粘贴。
2. **抓取与投递完全解耦**。中间通过 Inbox SQLite 缓冲。每次抓取**总是入 Inbox**，浮窗仅是"立刻处理"的快捷出口。
3. **浏览器扩展是增强不是必需**。没装扩展时，AX 也能拿 URL + 标题 + 选中文本；产品初体验门槛低。
4. **MCP 是"拉"协议，本身不能"投递"**。需要 MCP（数据层）+ AX 粘贴一条引导 prompt（触发层）的组合（详见 §7）。

## 6. 抓取层细节

### 6.1 抓取目标三分类

| 当前活跃 app | 主通道 | 辅助通道 | 兜底 |
|---|---|---|---|
| 浏览器（Safari/Chrome/Arc/Brave） | 浏览器扩展（DOM 正文 + URL + 选中 + meta） | AX API（标题/URL） | 截图 |
| 文本类 app（Notes, Mail, PDF Reader, Cursor/VS Code, iTerm） | AX API（聚焦元素文本 + 选中 + 窗口标题） | — | 截图 |
| 图形类 app（Figma 桌面版、Sketch、Preview、QuickTime） | 截图（带光标位置标记） | AX 拿窗口标题 + app 名 | — |

### 6.2 Accessibility API 能拿到什么（mac 现实清单）

| 数据 | 可取得性 | 备注 |
|---|---|---|
| 活跃 app bundle id + 名字 | ✅ 100% | `NSWorkspace.shared.frontmostApplication` |
| 当前窗口标题 | ✅ 99% | `AXTitle` |
| 浏览器 URL | ✅ Safari/Chrome/Arc/Brave 都有 | AX 有 `AXDocument` 或 `AXURL`，需逐家适配 |
| 选中文本 | ✅ 80%+ | `AXSelectedText`，Electron app 部分支持差 |
| 焦点输入框内文本 | ✅ 80%+ | 同上 |
| 滚动可视区域全文 | ⚠️ 50% | 文档类给，IDE/聊天 app 给不全 |
| 整个文档全文 | ❌ 极少 | 几乎拿不到，靠扩展或截图 OCR |

**设计决定**：AX 只拿"轻量元数据"（app 名、窗口标题、URL、选中文本），不试图通过 AX 拿全文。全文走浏览器扩展或截图 OCR（OCR Phase 2）。

### 6.3 浏览器扩展（V2 修订：只做 Chrome；Safari 推迟）

**MVP 覆盖（V2）**：仅 **Chrome 系**（Chrome、Arc、Brave、Edge 共用 Chrome MV3 包 + 同一份 native messaging host）。

**Safari 为何推迟到 Phase 1.5**：Safari Web Extension 不是 Chrome MV3 的小包装：
- containing app（必须打包成完整的 macOS app）
- JS（extension content script）
- native app extension（独立的 macOS extension target）
- 三者跑在三个 sandboxed 环境
- content script **不能直接** `chrome.runtime.connectNative` 到 beamhop.app，必须通过 app extension 中转
- 工作量等同于做一个独立的小 mac app，被 V1 严重低估

Codex review 指出这是 V1 没意识到的硬约束。MVP 砍掉，Phase 1.5 单独处理。

**职责（明确边界）：**

✅ 接收桌面 app 通过 native messaging 发来的"抓取当前 tab"指令
✅ 返回：URL、page title、meta 描述、选中文本、当前 tab 的 Readability 正文（`@mozilla/readability`）
✅ GitHub 模板结构化抽取（PR diff、issue 元信息、code 块）—— MVP 只内置 GitHub 一家

❌ 不做 AI、不做改写、不做扩展内 UI（除一个 popup 显示"已连接 Beamhop"）
❌ 不直接和 agent 通信，所有数据通过桌面 app 中转

**通信通道：Native Messaging（V2 细化）**

```
beamhop.app (Swift) ←─ stdio JSON ─→ com.beamhop.bridge (native messaging host)
                                         ↑
                                         │ chrome.runtime.connectNative
                                         │
                                  浏览器扩展 (TS)
```

**Chrome MV3 native messaging 关键约束（V2 新增，依据 Codex review）**：
- Host manifest 路径：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json`（每个 Chromium 系浏览器路径不同，Arc/Brave/Edge 各有自己的路径，安装时需逐一写入）
- Manifest 必须包含 `allowed_origins`（扩展 id），`path`（host 二进制绝对路径），`type: "stdio"`
- stdout 帧格式：4 字节 little-endian length + JSON payload
- 单条消息上限 **1 MB**（host→browser 方向；browser→host 是 64KB），大正文必须分片
- 不用 WebSocket 的原因仍然成立：无需开本地端口，无防火墙弹窗

### 6.4 截图策略

- **抓取时不自动截屏**。macOS Sonoma 之后 `CGWindowListCreateImage` 每次触发系统通知，会吵。
- **只在用户在浮窗里勾选"附带截图"时才截**。屏幕录制权限单独申请、单独提示。
- 截图存独立 PNG 文件：`~/Library/Application Support/beamhop/screenshots/{yyyy-mm}/{id}.png`，路径写入 SQLite。
- **图形类 app 例外**：Figma/Preview 等抓取时直接截屏，浮窗显式提示"图形 app，已附截图"。

### 6.5 Capture 数据结构

```swift
struct Capture {
    let id: String                  // "cap_<6位 ulid>"，对应 SQLite 的 TEXT 主键
    let createdAt: Date
    let source: Source              // .browser / .ax / .screenshot
    let appBundleID: String         // e.g. "com.apple.Safari"
    let appName: String
    let windowTitle: String?
    let url: URL?                   // 仅浏览器
    let selectedText: String?
    let extractedBody: String?      // 浏览器扩展给的正文 markdown
    let screenshotPath: String?     // PNG 相对路径，可选
    let userNote: String?           // 浮窗里用户输入的备注
    let domainHint: DomainHint?     // .github(.pr/.issue/.repo/.code) | .stackoverflow | .generic
}
```

**关键决定**：抓取产物是 Capture（数据），不是 Prompt（文本）。Prompt 拼装放投递层，因为不同目标 agent 最佳格式不同。

### 6.6 边界与降级

| 场景 | 处理 |
|---|---|
| AX 权限未授予 | 浮窗提示并跳转系统设置；只保留"纯截图"模式作为兜底 |
| 浏览器扩展未装 | 当前 app 是浏览器时，仅用 AX 拿 URL + 标题 + 选中，正文留空，浮窗 toast 提示"装扩展可抓全文" |
| 当前 app 是受保护进程（密码管理器、银行 app） | bundle id 黑名单，拒绝抓取并提示 |
| AX 调用 > 800ms 没返回 | 直接走截图兜底，不让浮窗卡顿 |
| AX 抓到敏感字段（`AXSecureTextField`） | 跳过该字段 |

## 7. 投递层细节

### 7.1 投递目标的通道决策（V2 修订）

| 目标 | 状态 | 主通道 | 触发方式 | 关键约束 |
|---|---|---|---|---|
| Claude Code CLI | 🟢 金线 | 自家 MCP server（数据）+ AX 粘贴（触发） | 在活跃 Terminal/iTerm/Warp 窗口粘 prompt | Claude Code 必须在前台终端运行 |
| ChatGPT Desktop | 🟡 条件 | AX 粘贴 或 剪贴板兜底 | 在输入框粘整段 markdown | App 已打开；AX 路径需 Spike 验证 |
| Claude Cowork | 🟡 条件 | Cowork connector/plugin（待 Spike 验证）+ AX 粘贴 | 见 §7.4 | Cowork 实际机制可能与 Claude Desktop legacy 不同 |
| 所有目标 | 🟢 金线 | 剪贴板 + 系统通知（"内容已复制，请粘贴"） | — | 无任何外部依赖，永远可用 |

**剪贴板 handoff 升为金线**：任何 AX/MCP 投递失败时自动降级到剪贴板，给用户明确的失败原因 + 已复制的事实。Codex review 指出 silent failure 是这类工具用户体验杀手。

### 7.2 关键认知：MCP 是"拉"协议

MCP 协议下，agent 必须主动调 tool / 读 resource，server 没法主动推 prompt 进 agent 的会话。

所以"投递到 Claude Code"实际是两步：
1. **数据层**：Beamhop 把 Capture 暴露成 MCP resource，agent 一调就能拿
2. **触发层**：Beamhop 同时用 AX 粘一条**带占位 token 的引导 prompt** 到 agent 输入框，让 agent 立刻去拉

这个"MCP + AX"组合是 MVP 投递的核心架构判断。

### 7.3 Claude Code CLI 投递

```
① Inbox 写入 Capture → 生成 id（e.g. "cap_7f3a"）
② Beamhop MCP server 暴露：
     resource: capture://latest
     resource: capture://{id}
     tool:     fetch_capture(id?) -> Capture JSON
③ Beamhop 找前台 Terminal（NSWorkspace + AX 判 bundle id ∈
   {com.apple.Terminal, com.googlecode.iterm2, dev.warp.Warp,
    com.mitchellh.ghostty, ...}）
④ 检测窗口里是否有 Claude Code 进程在跑（pgrep claude 或扫描标题）
   ├─ 是 → 步骤⑤
   └─ 否 → 浮窗提示"Claude Code 未运行，是否启动新会话？"
            若是：osascript 开新 iTerm 窗口跑
                  `claude "请用 beamhop_fetch_capture 处理 cap_7f3a：{userNote}"`
⑤ 通过 AX 模拟键盘事件，向当前会话粘入：
   "使用 Beamhop MCP 的 fetch_capture('cap_7f3a') 拿到我最新抓取的上下文，{userNote}"
   末尾自动按回车
⑥ Claude Code 触发 MCP tool call → 拿到 Capture 完整数据 → 开始处理
```

**前置条件（V2 修正）**：Claude Code 的 MCP 配置不是 `~/.config/claude-code/mcp.json`（V1 写错了）。实际机制是：
- 用户级 / 本地：写入 `~/.claude.json`
- 或调用 `claude mcp add beamhop --transport stdio --command <beamhop-mcp-binary>` CLI 命令
- 项目级（不适用本场景）：项目根的 `.mcp.json`

Beamhop 首次启动时优先尝试调用 `claude mcp add`（最稳）；若 `claude` 二进制不在 PATH 中则降级为提示用户手动复制命令并打开终端。**这一项必须在 Week 0 Spike 中实测确认**。

**为何不直接粘 markdown 正文进终端**：终端粘大段文本会引发 bracketed paste 异常、换行污染、token 浪费，且无法附图。MCP resource 让 agent 按需取，省 token 省事。

### 7.4 Claude Cowork 投递（V2 大幅修订）

**V1 假设错误**：以为 Cowork 用与 Claude Desktop legacy 相同的 stdio MCP server（配置文件路径 `~/Library/Application Support/Claude/claude_desktop_config.json`）。

**Codex review 指出**：Cowork 实际上**不直接读 `claude_desktop_config.json`**，它有独立的 connector/plugin 模型（Anthropic 官方文档明确说 legacy local MCP 配置"not available in Cowork or claude.ai"）。

**V2 处理**：

| 状态 | 决策 |
|---|---|
| Week 0 Spike 前 | 假设不成立，**不写实现代码** |
| Spike 验证 connector 流程可一键自动化 | 实现 Cowork 投递（仍是 connector + AX 触发组合） |
| Spike 验证连接需要 Anthropic 后台账号 / OAuth / 用户手动操作 | 推迟到 Phase 1.5，MVP 仅做剪贴板兜底（点 "Cowork" → 复制 + 通知"请在 Cowork 中粘贴"） |
| Spike 验证完全无可行通道 | 从 MVP 投递目标列表移除，Phase 2 重新评估 |

**AX 部分的辅助仍然成立**（找输入框 + 粘贴 + 回车），但触发数据通道必须先 Spike。Cowork 的 bundle id 假设为 `com.anthropic.claudefordesktop`，**待 Spike 用 Accessibility Inspector 确认**。

### 7.5 ChatGPT Desktop 投递（V2：条件交付）

**V2 状态**：纳入 MVP 的条件是 Week 0 Spike 验证 ChatGPT Desktop 输入框 AX 路径在 ≥ 2 个最近版本中保持稳定。失败则降级为剪贴板 handoff。

ChatGPT Desktop 不支持 MCP，所以必须把 Capture 渲染成完整 prompt 后整段粘进去。

```
① Inbox 写入 Capture
② Beamhop 调 Prompt Renderer 生成纯 markdown：

   Source: Safari · github.com/foo/bar/pull/123
   Title: Fix race condition in queue

   <selected>
   if (q.size > 0) { ... }
   </selected>

   <body>
   [Readability 抽出的正文 markdown]
   </body>

   {userNote}

③ AX 找 ChatGPT Desktop 输入框（com.openai.chat, AXTextArea）
④ NSPasteboard 写入文本 + AX 执行 ⌘V（不逐字符 typing，长文本太慢）
   - 粘前先备份用户原剪贴板，粘后立刻还原（避免污染）
⑤ 若 Capture 含截图且勾选"附带截图"：
   - 在 markdown 后追加 "[已附截图]"
   - 再次写剪贴板为图片，AX 执行 ⌘V
   - 还原剪贴板
⑥ AX 模拟回车提交（默认不按，等用户人工确认；浮窗有"投递后自动回车"开关）
```

**为何不用文件上传**：ChatGPT Desktop 上传按钮 AX 路径稳定性差，版本更新易坏。文本/图片粘贴是 OS 级协议，几乎不坏。

### 7.6 Prompt Renderer

每个目标用不同模板，渲染规则集中：

```swift
protocol PromptRenderer {
    func render(_ capture: Capture, userNote: String?) -> String
}

// renderers/
//   ClaudeCodeRenderer.swift    → "使用 Beamhop fetch_capture(...) ..."（短，引用式）
//   ClaudeCoworkRenderer.swift  → 同上
//   ChatGPTDesktopRenderer.swift → 完整 markdown dump（自包含）
```

MVP 默认模板内置，不开放用户编辑（Phase 2 加）。

### 7.7 反馈与错误处理

| 情况 | 处理 |
|---|---|
| 目标 app 未打开 | 浮窗提示并给"为我打开"按钮（`NSWorkspace.launchApplication`） |
| AX 找不到输入框 | 自动降级为"内容已复制到剪贴板，请手动粘贴" + 通知 |
| MCP 注册未完成 | 投递时同步检查 mcp.json，缺失则跳引导向导 |
| 粘贴超时（>2s） | 还原剪贴板、撤销动作，浮窗显示错误并保留 Capture 在 Inbox |
| 用户在浮窗里取消 | Capture 已入 Inbox（不丢），仅取消触发 |
| 同时投递两条到 Claude Code | 队列化，逐条触发 AX 粘贴，2 秒间隔 |

## 8. Inbox 与存储

### 8.1 SQLite Schema

位置：`~/Library/Application Support/beamhop/inbox.sqlite`

```sql
CREATE TABLE captures (
    id              TEXT PRIMARY KEY,           -- "cap_<6位 ulid>"
    created_at      INTEGER NOT NULL,           -- unix ms
    source          TEXT NOT NULL,              -- 'browser' | 'ax' | 'screenshot'
    app_bundle_id   TEXT NOT NULL,
    app_name        TEXT NOT NULL,
    window_title    TEXT,
    url             TEXT,
    selected_text   TEXT,
    extracted_body  TEXT,
    domain_hint     TEXT,                       -- 'github.pr' | 'generic' ...
    user_note       TEXT,
    screenshot_path TEXT,
    deleted_at      INTEGER                     -- 软删，30 天后物理删
);

CREATE TABLE deliveries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    capture_id      TEXT NOT NULL REFERENCES captures(id),
    target          TEXT NOT NULL,              -- 'claude_code' | 'cowork' | 'chatgpt_desktop'
    delivered_at    INTEGER NOT NULL,
    status          TEXT NOT NULL,              -- 'success' | 'failed' | 'cancelled'
    error_message   TEXT
);

CREATE INDEX idx_captures_created ON captures(created_at DESC);
CREATE INDEX idx_deliveries_capture ON deliveries(capture_id);

-- 双 FTS 表：unicode61 处理英文/欧语词分词，trigram 处理中日韩 substring 搜索
CREATE VIRTUAL TABLE captures_fts USING fts5(
    window_title, url, selected_text, extracted_body, user_note,
    content='captures', content_rowid='rowid',
    tokenize = 'unicode61 remove_diacritics 2'
);

CREATE VIRTUAL TABLE captures_fts_cjk USING fts5(
    window_title, selected_text, extracted_body, user_note,
    content='captures', content_rowid='rowid',
    tokenize = 'trigram'
);
```

**关键决定（V2 修正）**：

- 截图存独立 PNG 文件，不入 BLOB（BLOB 在多 MB 截图下数据库膨胀、备份/同步变慢）
- 软删 30 天后物理删；期间可恢复
- **全文搜索（V2 修正）**：FTS5 没有 bigram tokenizer，V1 写错了。实际可用的是 `unicode61` + `trigram`。MVP 采用双 FTS 表方案：
  - `unicode61` 处理英文/欧语/含空格内容的词分词
  - `trigram` 处理中日韩等连续文本的 substring 搜索
  - 查询时双路召回 → UNION → 按 BM25 + 时间衰减重排
- **预期质量声明（V2 新增，对外可见）**：中文搜索是 substring 级（trigram），不是语义/分词级。Phase 2 加 embedding 提升质量。文档化这个限制是 inspectability 的一部分。

### 8.2 数据库损坏恢复

启动时校验 schema 完整性；损坏则自动重建并备份旧文件到 `inbox.sqlite.broken.{timestamp}`，截图 PNG 保留不丢历史。

## 9. UX 细节

### 9.1 浮窗（抓取后弹出）

**目标**：95% 的"抓→投"流程在 1 秒内完成，键盘可达。

```
┌────────────────────────────────────────────────────────────┐
│ 📋 已抓取  Safari · Fix race condition in queue  · 1.2k 字  │
│                                                            │
│ [Source preview: 前 200 字预览 + URL 灰字]                  │
│ ───────────────────────────────────────────────────────── │
│ 备注 (可选):                                                │
│ │ Cursor 在这等待用户输入                                  │
│ │                                                          │
│ ───────────────────────────────────────────────────────── │
│ 投递到:                                                     │
│   ⌘1 ● Claude Code   ⌘2 ○ Cowork   ⌘3 ○ ChatGPT          │
│   ⌘0 ○ 仅入 Inbox                                          │
│                                                            │
│ ☐ 附带截图   ☐ 投递后自动按回车                            │
│                                                            │
│              Esc 取消         ⏎ 投递（Claude Code）         │
└────────────────────────────────────────────────────────────┘
```

**键盘流（核心 UX 不变量）：**

- 浮窗弹出时光标自动在"备注"输入框
- ⌘1/2/3/0 切换目标，圆点立刻更新
- Enter 直接投递到当前选中目标（不需要点鼠标）
- Esc 取消触发（Capture 已入 Inbox，不丢）
- Tab 跳到"附带截图"和"自动按回车"
- 浮窗失去焦点（点击别处）= Esc 等效

**浮窗 window-level 配置（V2 修订）**：

Codex review 指出仅设 `NSFloatingWindowLevel` 不足以覆盖全屏 app。正确组合：

```swift
window.level = .floating  // 高于普通窗口
window.collectionBehavior = [
    .canJoinAllSpaces,        // 跟随用户切 Space
    .fullScreenAuxiliary,     // 允许浮在全屏 app 之上
    .stationary               // Mission Control 不动它
]
window.isMovableByWindowBackground = true
NSApp.setActivationPolicy(.accessory)  // 菜单栏 app，不在 Dock 占位
```

**Week 0 Spike 必须验证**：在以下场景实测浮窗能否正常弹出且接收键盘输入：
- 全屏 Safari / VS Code / Final Cut
- Stage Manager 开启状态
- 多显示器（不同 Space）
- 锁屏后唤醒第一次按热键

**默认目标的选择规则：**

- 第一次：Claude Code
- 之后：上一次投递成功的目标（per-session 记忆，重启后回 Claude Code）
- **不基于"猜测"自动切换**——用户能预测的快捷键比"智能"更重要

### 9.2 Inbox 窗口（⌘⇧I 调出）

```
┌──────────────────────────────────────────────────────────────┐
│ [搜索框]                                       [⌘N 新建快照]  │
│ ──────────────────────────────────────────────────────────── │
│ 全部 (87)  Safari (42)  Cursor (12)  Notes (8)  Figma (5)... │
│ ──────────────────────────────────────────────────────────── │
│ ◉ 2 分钟前  Safari · Fix race condition in queue             │
│   github.com/foo/bar/pull/123 · 已投 Claude Code             │
│ ──────────────────────────────────────────────────────────── │
│ ○ 15 分钟前  Cursor · onUserAction handler                    │
│   /Users/me/proj/src/handlers.ts · 未投递                    │
│ ──────────────────────────────────────────────────────────── │
│ ○ 1 小时前  Figma · Login flow v3                            │
│   [截图] · 未投递                                             │
│ ──────────────────────────────────────────────────────────── │
│ 选中条目右侧栏：详情预览 + [投递到 Claude Code / Cowork / GPT] │
└──────────────────────────────────────────────────────────────┘
```

**关键交互：**

- ↑/↓ 选项目，Space 预览，Enter 投递（弹出目标选择）
- ⌘1/2/3 直接对选中项投递
- ⌘⌫ 软删除（30 天后物理删）
- 默认按时间倒序，无折叠，最近 100 条直接列

**MVP 故意不做**：文件夹、标签、共享、批量、自定义视图。Phase 2 加。

### 9.3 全局快捷键总表（MVP）

| 快捷键 | 行为 |
|---|---|
| ⌘⇧Space | 抓取当前 app + 弹浮窗 |
| ⌘⇧I | 打开 Inbox 窗口 |
| ⌘⇧V | 在任意输入框里把最近一次 Capture 投到当前光标位置（应急通道） |
| Esc（浮窗内） | 取消触发，Capture 已留 Inbox |
| ⌘1/2/3/0（浮窗内） | 切换投递目标 |

全部可在设置里重绑。`⌘⇧Space` 撞 Spotlight 概率高，首次启动检测冲突并引导改键。

### 9.4 首次启动流程（V2 修正）

```
1. 欢迎页（一屏）：说明产品要做什么 + 三张 GIF
2. 权限引导：
   ① Accessibility（必需）→ 引导跳系统设置 + "我已开启"按钮
   ② Screen Recording（可选）→ "可选，截图功能用，可跳过"
3. 浏览器扩展安装（可选）：
   ① 检测已装的浏览器（Chrome/Arc/Brave/Edge — Safari 在 Phase 1.5）
   ② 一键安装（跳 Chrome Web Store）
   ③ 写入 native messaging host manifest 到对应浏览器目录
   ④ "跳过，仅用 AX 抓取" 是头等选项
4. Agent 注册（按需）：
   ① Claude Code：检测 `claude` 是否在 PATH，若是则调 `claude mcp add beamhop ...`；
      否则提示手动复制命令到终端（V2 修正：V1 写的 `~/.config/claude-code/mcp.json` 路径是错的）
   ② Claude Cowork：仅在 Week 0 Spike 通过后开放；流程视 Spike 结论
   ③ ChatGPT Desktop：检测安装即可，无需注册
5. Permission Diagnostics 面板：
   ① 显示每个权限/集成的"已就绪 / 待操作 / 失败"状态
   ② 失败项给出可执行的修复步骤（不是文档链接）
   ③ 任何时候在菜单栏可重新打开
6. 演示一次抓取（强烈推荐别跳）：
   ① 引导按 ⌘⇧Space
   ② 模拟一次抓取→浮窗→投递（用预置 demo Capture）
   ③ 完成
```

**关键决定**：每一步都可跳过。Inbox 仅本地 + AX 抓取 + 一个投递目标（Claude Code）就是最小可用集。Permission Diagnostics 是首次后任何时候用户调试的入口（"为什么不工作"）。

## 10. MVP 明确不做（Out of Scope，V2 扩展）

| 不做 | 理由 |
|---|---|
| **Safari 扩展** | App Extension 三 sandbox 架构是独立 mac app 工程，V1 严重低估 → Phase 1.5 |
| **Claude Cowork 集成**（如 Week 0 Spike 失败） | Cowork 用独立 connector/plugin 模型，不读 legacy MCP 配置 → 待 Spike 决定 |
| **ChatGPT 自动按回车** | Codex review 建议默认让用户人工确认 → Phase 1.5 |
| iOS app / 跨设备同步 | Phase 1 后期或 Phase 2 |
| OCR | 工程量大，Phase 2 |
| Web chatbox 自动注入（Claude.ai / chatgpt.com / Perplexity） | 浏览器扩展需为每家做 DOM 适配，Phase 2 |
| 长期 memory / 语义搜索 | Phase 2 的核心差异化抓手，MVP 先验证基础链路 |
| Cursor / Windsurf 投递 | 已有 MCP，但适配工作量大，Phase 2 |
| 自定义 Prompt 模板（用户可编辑） | Phase 2，MVP 内置三套足够 |
| 收费 / 账号系统 | Phase 1 全免费，养习惯优先 |
| 自动建议投递目标 | "猜测式"AI 放 Phase 2，先让用户建立直觉 |
| Capture 加密 | Phase 2 加 E2E（云同步时同步上线） |

## 11. 边界情况清单（V2 扩展）

| 场景 | 处理 |
|---|---|
| 用户在密码管理器（1Password 等）按热键 | bundle id 黑名单，拒绝抓取并提示 |
| 浮窗弹出时用户切到别的 app | 浮窗 `canJoinAllSpaces + fullScreenAuxiliary`，跟随用户切空间不被遮挡 |
| 全屏 app 中按热键 | 浮窗作为 `fullScreenAuxiliary` 覆盖在全屏之上；如 Spike 验证失败则降级为"先退出全屏" |
| 同时按多次 ⌘⇧Space | 抓取去重（< 500ms 内同一窗口不重复入 Inbox） |
| 浏览器扩展崩了 | AX 兜底，Toast 提示"扩展未响应，仅抓元数据" |
| Native messaging host 未注册 | 浮窗 toast 提示 + Permission Diagnostics 标红 + 一键重新写入 manifest |
| AX 抓到敏感字段（password input） | 检测 `AXSecureTextField` 跳过 |
| 私密浏览模式抓取 | 标记 `is_private` 字段，UI 显式提示且禁用云同步（Phase 2 生效） |
| 极长正文（> 100k 字符）抓取 | 截断到 100k + 标记 `truncated` + Inbox 保留完整原文 |
| Inbox 数据库损坏 | 自动重建 schema + 备份旧文件，不丢历史 PNG |
| Mac 重启后 Beamhop 没自启动 | 默认 Login Item，可关 |
| 同时投递两条到 Claude Code | 队列化，逐条触发 AX 粘贴，2 秒间隔 |
| Claude Code 会话内已经在等用户输入 | 直接粘 prompt + 回车（这是正常路径） |
| Claude Code 会话内正在执行（不在等待） | AX 检测光标位置可能不可用 → 提示"Claude Code 忙，是否新开会话？" |
| 用户原剪贴板内容是密码 / 大图 | 投递时备份 → 还原；备份失败则拒绝粘贴（不污染） |
| 目标 app 被 macOS 杀掉（OOM、崩溃） | AX 操作失败 → 检测进程不存在 → 自动降级剪贴板 + 提示 |
| 目标 app 升级后 AX 路径变了 | 投递失败 → 自动降级剪贴板 + Toast "目标 app 版本兼容性可能下降，请去 Compatibility 面板上报" |

## 12. MVP 必须能力（V2 新增）

Codex review 指出：原 V1 把若干"基础设施级"能力推到了 Phase 2，但这些恰恰是用户感受"这个工具靠谱不靠谱"的核心。V2 把它们升为 MVP 一等公民。

### 12.1 Capture Provenance（完整溯源）

每条 Capture 必须记录完整的"它从哪来"，存入 `captures` 表的扩展字段：

```sql
ALTER TABLE captures ADD COLUMN pid INTEGER NOT NULL;             -- 抓取时源 app 的 PID
ALTER TABLE captures ADD COLUMN app_version TEXT;                 -- 源 app 版本
ALTER TABLE captures ADD COLUMN os_version TEXT NOT NULL;         -- macOS 版本
ALTER TABLE captures ADD COLUMN beamhop_version TEXT NOT NULL;     -- Beamhop 自身版本
ALTER TABLE captures ADD COLUMN ax_tree_snapshot TEXT;            -- AX 路径快照（JSON）
ALTER TABLE captures ADD COLUMN capture_method TEXT NOT NULL;     -- 实际生效的通道
ALTER TABLE captures ADD COLUMN extension_version TEXT;           -- 浏览器扩展版本
ALTER TABLE captures ADD COLUMN is_private INTEGER DEFAULT 0;     -- 私密浏览 / 受保护字段标记
ALTER TABLE captures ADD COLUMN truncated INTEGER DEFAULT 0;      -- 是否截断
ALTER TABLE captures ADD COLUMN capture_duration_ms INTEGER;      -- 抓取耗时
```

**Why MVP**：用户在投递失败 / 内容不对时，能在 Inbox 详情里看到"这条是从 Safari v17.5 用 AX 通道抓的，扩展 1.2.0 没响应"，比"东西没了"强 100 倍。这正是 Codex 提到的 inspectability/防御性 wedge 的核心。

### 12.2 Permission Diagnostics 面板

菜单栏 → "诊断" → 打开独立窗口，展示：

| 项 | 状态 | 修复动作 |
|---|---|---|
| Accessibility 权限 | ✅ / ❌ | "打开系统设置" 直接跳到对应面板 |
| Screen Recording 权限 | ✅ / ❌ / ⚠️（已授但失效） | 同上 |
| Chrome native messaging host | ✅ / ❌ | "重新写入 manifest" 一键 |
| Claude Code MCP 注册 | ✅ / ❌ / ⚠️（已注册但 server 启动失败） | "查看错误日志" / "重新注册" |
| Claude Cowork 集成 | ✅ / 🚧（Phase 1.5）/ ❌ | 说明当前状态 |
| ChatGPT Desktop AX 路径 | ✅ / ⚠️（版本不在 Compatibility Matrix 内） | "上报当前版本" / "降级到剪贴板" |

**Why MVP**：80% 的"它不工作"问题都是上面这些项之一失效。不让用户写邮件给我，让他自己一键修。

### 12.3 Clipboard-Safe Paste 协议

每次 AX 粘贴动作必须遵守：

```
1. 读取当前 NSPasteboard 全部 type 的数据 → 缓存
2. 写入待粘贴内容
3. AX 触发 ⌘V
4. 等待 50ms（确保 paste 完成）
5. 把缓存的原始 NSPasteboard 数据写回去
6. 如果第 1 步读取失败（如剪贴板包含特殊 type 无法序列化）→ 直接拒绝粘贴，提示用户"无法保护当前剪贴板，请手动操作"
```

**Why MVP**：剪贴板是用户的"工作记忆区"，被工具污染是不可接受的体验事故。Codex 指出 V1 仅一句"还原剪贴板"远远不够。

### 12.4 Failure Recovery & Provenance UI

任何投递失败时：

- Inbox 列表里该条 Capture 的 delivery 状态显示为"❌ Claude Code · 2 分钟前 · 点击查看原因"
- 点开后看到：失败时间、目标 app 版本、AX 路径快照、错误码、剪贴板降级是否生效、"重试"按钮、"切到其他目标"按钮
- 所有失败默认进入"剪贴板兜底"路径，不会让用户陷入"按了热键 → 什么也没发生"

**Why MVP**：Silent failure 是这类工具的体验杀手。明确告诉用户"发生了什么 + 怎么补救"是 Beamhop 必须做对的事。

### 12.5 Compatibility Matrix（内置 + 可上报）

随 app 发布的 JSON 数据 + 用户可上报机制：

```json
{
  "chatgpt_desktop": {
    "tested": ["1.2026.058", "1.2026.064"],
    "known_broken": [],
    "ax_path": ["AXWindow", "AXSplitGroup", "AXGroup", "AXTextArea[role=textbox]"]
  },
  "claude_code": { ... },
  "claude_cowork": { ... }
}
```

- Permission Diagnostics 面板里显示"你的 ChatGPT Desktop 是 1.2026.072 — 未测试过，可能正常也可能失效"
- 用户实际成功投递后可一键"上报本版本工作正常"（仅版本号，不发任何抓取内容；E2E 上报 channel，Phase 2 才开）

**Why MVP**：AX 路径会随 app 更新失效，与其每次都靠 Beamhop 更新追平，不如把 Compatibility Matrix 公开化，让用户成为信号来源。

---

## 13. 技术栈

**Swift / SwiftUI 原生**。理由：

1. Accessibility API 直接调 AXUIElement，0 桥接（Tauri/Electron 都要写 native plugin）
2. 浮窗启动 < 100ms，菜单栏常驻 30–80MB（Electron 重一个数量级）
3. macOS 单机产品没必要为跨平台付出代价
4. Phase 3 演化到 iOS Share Extension 时几乎零迁移成本

依赖（初估）：

- SwiftUI（UI）
- GRDB.swift（SQLite + FTS5 封装）
- HotKey（全局快捷键）
- 自家 MCP server：可用 Swift 写独立可执行（轻量，stdio JSON-RPC）
- 浏览器扩展：TypeScript + Vite + Mozilla Readability

## 14. Week 0 Spike（V2 新增 — 必须先跑通）

**目的**：在写任何长期实现代码前，用 1 周时间实际验证 6 个高风险集成假设。每个假设有明确的"通过 / 失败 / 改方案"判定标准。Spike 输出是**一份回写到本 spec 的结论 + 一个 throw-away 原型仓库**。

### 14.1 Spike 任务清单（按优先级排）

| # | 假设 | 验证方法 | 通过标准 | 失败处理 |
|---|---|---|---|---|
| S1 | Claude Code MCP 注册可一键自动化 | 实际跑 `claude mcp add beamhop ...`，写一个 hello-world MCP server 返回固定 capture | server 注册成功 + Claude Code 一次会话里能调到 tool 拿到数据 | 改为提示用户手动复制命令；不影响 MVP 推进 |
| S2 | Claude Cowork connector/plugin 机制 | 阅读 Anthropic Cowork 当前公开文档；如有 SDK 实测注册一个最小 connector | connector 注册可一键完成 + 流程稳定 | Cowork 推迟 Phase 1.5；MVP 仅做剪贴板 handoff |
| S3 | ChatGPT Desktop AX 粘贴稳定性 | 用 Accessibility Inspector 抓取当前版 + 上一个稳定版的输入框路径快照对比 | 路径在两个版本中完全一致或可用稳定 fallback 规则 | 仅做剪贴板 handoff；不在 MVP 自动按回车 |
| S4 | Chrome native messaging 全链路 | 写最小扩展 + native host，验证 1MB 消息分片 + 错误恢复 | 端到端往返 < 100ms + 大正文分片正确 | 改为本地 HTTP 端口（弹防火墙）；可接受 |
| S5 | 浮窗在全屏 app / Stage Manager / 多显示器上的可见性 | 实测 4 种场景：全屏 Safari、全屏 VS Code、Stage Manager、双 4K 显示器 | 全 4 场景浮窗可见 + 键盘 focus 正确 | 退化为"全屏 app 中按热键先退出全屏" |
| S6 | AX API 跨 app 选中文本抓取 | 实测在 Safari/Chrome/Notes/Mail/Slack/VS Code/Cursor/iTerm 8 个 app 中选中文本 + 按 ⌘⇧Space | ≥ 6/8 通过 | 失败的 app 标记到 Compatibility Matrix；不影响其他 |

### 14.2 Spike 退出条件

- 每条假设有明确"通过 / 失败"结论 + 证据（截屏 / log / repo commit）
- 把每条结论回写到本 spec 对应章节（带 "V2.1 Spike 验证后修订" 标记）
- 失败的假设把对应能力降到剪贴板兜底或推迟 Phase 1.5，**不允许把失败假设带进 Week 1 的实现**
- 输出"Compatibility Matrix v0"作为产品的第一份内置数据

### 14.3 Spike 不做的事

- 不打磨 UI / 不写测试 / 不写 Permission Diagnostics / 不接 SQLite
- 所有原型代码**预设抛弃**；不要因"代码可以复用"而妥协验证质量
- 不验证截图、Readability、Prompt Renderer 这些非集成层的能力（这些风险低，Week 1+ 实现）

---

## 15. 工程评估（Spike + 5 周里程碑，V2 重排）

**Week 0：Spike（见 §14）**
- 6 个假设全部验证 + 结论回写 spec
- 输出 Compatibility Matrix v0

**Week 1：地基**
- 项目脚手架、菜单栏 app、全局快捷键、AX 权限引导
- Capture 数据模型（含 V2 provenance 字段）+ SQLite + 双 FTS5
- Permission Diagnostics 面板框架

**Week 2：抓取 + 金线投递**
- AX 抓取实现（app/window/url/selection + provenance）
- 浏览器扩展（Chrome MV3）+ Native Messaging Bridge
- 自家 MCP server（stdio JSON-RPC）+ Claude Code 注册引导
- **剪贴板兜底 handoff 通道**（全目标共用）

**Week 3：浮窗 + Inbox UX**
- 浮窗 SwiftUI 实现 + 键盘流 + collection behaviors
- Inbox 窗口 + 列表/搜索/预览/provenance 详情视图
- Failure recovery UI（投递失败原因展示）

**Week 4：金线打通 + ChatGPT Desktop（视 Spike）**
- Claude Code 投递端到端跑通
- ChatGPT Desktop 投递（如 Spike 通过）；否则仅剪贴板 + 通知
- Clipboard-safe paste 协议落地

**Week 5：条件目标 + 打磨**
- Cowork 投递（如 Spike 通过）；否则文档化推迟
- 截图模块（按需）
- 首次启动引导完整流程
- Compatibility Matrix 自动加载 + 上报通道（无后端，仅本地标记）
- 自用 dogfood + bug 修复

**前置假设**：1 名熟悉 Swift/macOS 开发的工程师 + AI 协助。无团队协作开销。0 Swift 经验工期至少翻倍。

**Codex 提醒的滑期风险**：Week 4-5 集成周风险最高（不是 SwiftUI 周），所有 AX/native messaging/MCP 注册都是版本敏感，Spike 不能消除所有未知，预留 20% buffer。

## 16. 成功标准

MVP 上线后两周内：

- 自己（产品发起者）daily ⌘⇧Space 次数 ≥ 10 次/天
- **金线**投递成功率 ≥ 95%（Claude Code + 剪贴板兜底）
- **条件目标**投递成功率 ≥ 80%（仅纳入 MVP 的目标）
- 浮窗弹出延迟 P95 ≤ 300ms
- Inbox 累计 ≥ 200 条 Captures，自然回访 Inbox 窗口 ≥ 3 次/周
- 失败的投递 100% 有可读的"为什么"信息可看（不存在 silent failure）
- Permission Diagnostics 面板覆盖 100% 的"为什么不工作"情况

如以上达标，进入 Phase 2 规划（memory、iOS 端、Web chatbox）。

---

## 附：V2 修订摘要（相对 V1）

V2 是 Codex 独立 review 后的修订版。关键变化：

1. **MCP 路径全部修正**：`~/.claude.json` / `claude mcp add` / Cowork connector（非 legacy MCP）
2. **MVP 范围分层**：金线（必交付）vs 条件交付（视 Spike）vs 推迟 Phase 1.5
3. **新增 Week 0 Spike 周**：6 个高风险假设必须先验证
4. **新增 §12 MVP 必须能力**：provenance、permission diagnostics、clipboard safety、failure recovery、compatibility matrix
5. **FTS5 修正**：`unicode61 + trigram` 双表（无 bigram tokenizer）
6. **浮窗 collection behaviors**：`canJoinAllSpaces` + `fullScreenAuxiliary` + `stationary`
7. **Safari 推迟 Phase 1.5**：三 sandbox 架构工作量被低估
8. **Cowork 视 Spike 决定**：connector/plugin 机制需先摸清
9. **防御性 wedge 写入战略**：provenance/inspectability/privacy 是平台主吃不掉的差异化
10. **Compatibility Matrix 内置 + 可上报**：AX 路径会失效，用户成信号来源

---

**文档结束。下一步：Week 0 Spike → V2.1 回写 → writing-plans skill 生成实施计划。**
