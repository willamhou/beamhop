# Beamhop Week 2 — Capture + Golden-Path Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 打通 MVP 金线 —— `⌘⇧Space` 抓取当前 app(AX + Chrome 扩展)→ 写入 Inbox(Week 1 已就绪)→ 投递到 Claude Code(自家 MCP server + AX 粘贴触发)→ 失败自动降级剪贴板兜底。本周是**集成周**,把 Week 0 实测的 4 个原型(S1 MCP / S4 native messaging / S6 AX 取词)固化成产品代码。

**前置:** Week 1 地基已完成(`BeamhopCore` 数据层 + 菜单栏 app + Carbon 热键 + 权限/AXHelper + 诊断框架)。Week 2 在其上接真逻辑。

**Reference spec:** `docs/.../2026-06-03-beamhop-mvp-design.md`(V2.1)§5.2(数据流)/§6.2-6.3(抓取)/§7.2-7.3(投递)/§7.6(Prompt Renderer)/§12.3(Clipboard-Safe Paste)。
**Week 0 实测原型(直接复用/移植):** `spike/s1-claude-code-mcp/`(MCP server)、`spike/s4-chrome-native-messaging/`(host + 扩展)、`spike/s6-ax-selected-text/AXProbe.swift`(AX 取词)。

**Tech Stack:** 续 Week 1(Swift + GRDB + Carbon)。新增:独立可执行 `BeamhopMCP`(stdio JSON-RPC)、`beamhop-bridge`(native messaging host)、Chrome MV3 扩展(TypeScript + Vite + `@mozilla/readability`)。

**Week 2 范围(spec §15):** AX 抓取 + Chrome 扩展/native messaging + 自家 MCP server + Claude Code 注册引导 + 剪贴板兜底(全目标共用)。

**⚠️ 里程碑切分(codex review:整周偏大,切两段交付):**
- **Week 2A — 最短金线(不含 Chrome 扩展)**:Task 0(DB/WAL/只读)→ Task 2(MCP)→ Task 1(AX 元数据/选区)→ Task 4 + 5(Claude Code 投递 + 剪贴板兜底)→ smoke。**这段独立可用**:非浏览器 app(Notes/编辑器/任意)+ 浏览器的 AX 选区都能抓投。
- **Week 2B — 浏览器增强支路**:Task 3(bridge contract → 最小 ping → active tab url/title/selection → Readability → GitHub 抽取 → 双向分片测试)。给浏览器抓取补上"全文正文"。
- 诊断项**随对应 Task 做最小诊断**(MCP 注册随 Task 2、bridge/manifest/扩展连通性随 Task 3),不要堆到最后(codex review)。
**Week 2 不做:** 浮窗投递 UI(Week 3 —— 本周 `⌘⇧Space` 直接投默认目标 Claude Code + 通知,先不弹选择浮窗)、Inbox 列表 UI(Week 3)、ChatGPT/Cowork 投递(Week 4-5)、截图(Week 5)。

**必须遵守的 Week 0 实测结论:**
- MCP stdio = **换行分隔 JSON + 非阻塞 POSIX 读**(S1;`FileHandle.read(upToCount:)` 会 30s 超时)。注册 `claude mcp add beamhop -s user -- <abs-bin>`(无 `--command`,必须 `-s user`)。
- native messaging:4 字节 LE 长度 + JSON;host→extension **~1MB 硬上限 → 应用层分片(强制)**;host 用精确长度循环读 + `loadUnaligned`(S4)。
- AX 取词:**系统级** focused element;Chromium/Electron/ChatGPT 先设 `AXManualAccessibility`;Safari 网页选区走 `AXSelectedTextMarkerRange`,Electron 编辑器退剪贴板(S6)。设 `AXUIElementSetMessagingTimeout`。
- 浮窗/窗口 `isReleasedWhenClosed=false`(S5)。

**新增 Output structure:**
```
Sources/
  BeamhopCore/Capture/      (CaptureService, AppBlacklist, ProvenanceBuilder)  ← 复用 Week 1 store
  Beamhop/Capture/          (AXCapture — AppKit/AX 实现)
  Beamhop/Delivery/         (ClipboardService, TerminalLocator, ClaudeCodeDelivery, ClipboardHandoff, PromptRenderer)
  Beamhop/Bridge/           (BrowserBridgeServer — unix socket to native host)
  BeamhopMCP/               (独立可执行:Beamhop 的 MCP server,读 inbox.sqlite)
host/                       (beamhop-bridge native host,移植自 spike/s4)
extension/                  (Chrome MV3,移植自 spike/s4 + Readability/GitHub 抽取)
```

---

## Task 0: Week 2 工程结构 + 共享 DB 读

- [ ] **Step 0.1: 新增可执行 target**
  - `BeamhopMCP`(executableTarget,依赖 BeamhopCore)—— 自家 MCP server。
  - `beamhop-bridge`(可先用独立 `swiftc` 编译,或加 executableTarget)—— native messaging host。
  - Package.swift 注册;`swift build` 通过。

- [ ] **Step 0.2: 共享 inbox.sqlite 的并发读(关键 — codex review:需拆只读接口)**
  - ⚠️ 当前 Week 1 的 `Database` 固定走 `DatabaseQueue(path:)` + integrity check + **损坏恢复(会备份/删库)** + migration。**这套绝不能用在 MCP 只读进程**(否则 MCP 可能误删/恢复用户库)。必须拆:
    - app 写库初始化时**显式执行并断言 `PRAGMA journal_mode=WAL`**(跨进程读不阻塞写;GRDB 默认 WAL,但要显式确认)。
    - 新增 `Database.openReadOnly(path:)`(`Configuration.readonly = true`):**只读、不 migration、不损坏恢复、不创建目录、不碰 wal/shm**。
    - `BeamhopMCP` 启动时若 DB 不存在/无权限 → 返回**结构化 MCP error**,绝不创建空库或触发恢复。
  - 跨进程 smoke:app 持续写入时,MCP 只读 `capture://latest` 不阻塞、读到最新。

---

## Task 1: AX 抓取实现(CaptureService)

**Files:** `Sources/Beamhop/Capture/AXCapture.swift`、`Sources/BeamhopCore/Capture/{CaptureService,AppBlacklist}.swift`

- [ ] **Step 1.1: 把 Week 1 的 AXHelper 补全为真取词(S6 策略)**
  - `windowTitle(pid:)`、`url(focused:)`(`AXURL`)、`selectedText(...)` 按 §6.2 的 per-app 策略:
    - 原生 AppKit / 终端 → `kAXSelectedText`
    - Chromium/Electron(Chrome/Slack)→ 先 `enableManualAX` 再读 `AXWebArea` 的 `kAXSelectedText` + `AXURL`
    - Safari → app/window/url 可拿;选中文本走 `AXSelectedTextMarkerRange`(取不到则置空 + 标 method)
    - Electron 编辑器(VS Code/Cursor)→ `kAXSelectedText` 拿不到 → 标记走剪贴板(Week 2 先标 method=limited,真剪贴板取词可选)
  - 全程 `AXUIElementSetMessagingTimeout(0.8)` + 遍历节点上限(S6 codex)。

- [ ] **Step 1.2: AppBlacklist + 敏感字段跳过(§6.6 / §11)**
  - bundle id 黑名单(1Password 等密码管理器、银行 app)→ 拒绝抓取并提示。
  - focused element 是 `AXSecureTextField` → 跳过 selectedText,标 `is_private`。
  - 私密浏览(若可判定)→ `is_private=1`。

- [ ] **Step 1.3: CaptureService —— 组装 Capture + provenance(§12.1)**
  - 输入:`AXHelper.frontmostApp()` + 取词结果(+ 可选浏览器扩展正文,Task 3 接)。
  - 填 provenance:`pid / app_version(从目标 app bundle 读)/ os_version / beamhop_version / capture_method / capture_duration_ms / ax_tree_snapshot(可选 JSON)`。
  - **800ms 超时**(§6.6):AX 整体超时 → 退化为"仅元数据"或截图兜底(截图 Week 5,先仅元数据)。
  - 极长正文(codex review:消除矛盾)—— **DB 存完整原文**;`truncated=1` 仅标记"投递/预览会截断到 100k",不删 DB 数据。投递层和预览层各自截断,渲染时用标记提示,不误导(§11)。
  - `domain_hint` 粗判(github.com/pr|issue 等;细的留扩展 Task 3)。
  - 产物 `insert` 进 `CaptureStore`,返回 `Capture`。

- [ ] **Step 1.4: 接 `⌘⇧Space`**
  - `AppServices.placeholderCapture()` → 真 `CaptureService.captureFrontmost()`;成功后(Week 2 暂)直接进 Task 4 的默认投递。
  - ⚠️ **失败不能只 beep(codex review)**:AX 权限缺失 / 命中黑名单 / 仅拿到元数据 / 投递降级,都要发**系统通知说明具体原因**(§7.7 无 silent failure)。
  - **手动 smoke**:在 Safari/Chrome/Notes/VS Code 选中文本按 ⌘⇧Space → `inbox.sqlite` 里多一条,字段符合 S6 实测预期(Chrome 有 selected_text+url;Safari 有 url 无 selected_text;等)。

---

## Task 2: 自家 MCP server(BeamhopMCP)

**Files:** `Sources/BeamhopMCP/main.swift`(移植 `spike/s1-claude-code-mcp/Sources/HelloServer/main.swift`)

- [ ] **Step 2.1: stdio JSON-RPC 框架(直接用 S1 已验证写法)**
  - 换行分隔 JSON + **POSIX `read(0,…)` 非阻塞读**(S1 踩坑:别用 `FileHandle.read(upToCount:)`)。
  - 实现 `initialize` / `notifications/initialized` / `tools/list` / `tools/call` / `resources/list` / `resources/read`。

- [ ] **Step 2.2: 暴露 Beamhop 数据(§7.3)**
  - resource `capture://latest`、`capture://{id}` → 返回 Capture JSON。
  - tool `fetch_capture(id?)` → id 缺省取最新;返回完整 Capture(含 provenance)渲染成给 agent 的结构化文本/JSON。
  - 数据源:**只读**打开 DB(Task 0 的 `openReadOnly`)。⚠️ **codex review:MCP 不自己猜 DB 路径**。MCP server 由 Claude Code 拉起,工作目录/环境未知,且未来若 sandbox 化 app 与 MCP 看到的 Application Support 路径可能不同 → **注册命令里把 DB 路径作为参数显式传入**:`claude mcp add beamhop -s user -- <BeamhopMCP> --db <inbox.sqlite 绝对路径>`。"非 sandbox + Application Support 路径"是产品约束,写进注释。

- [ ] **Step 2.3: 注册引导(§9.4 / S1)**
  - app 内"注册 Claude Code"动作:校验 `claude` 在 PATH → `claude mcp add beamhop -s user -- <BeamhopMCP 绝对路径> --db <inbox.sqlite 绝对路径>`;不在 PATH 则给可复制命令。
  - ⚠️ 二进制必须装到**稳定位置**(Xcode 后:app bundle 内;SwiftPM 阶段:复制到固定 `~/Library/Application Support/beamhop/bin/`)。**`.build/` 绝对路径不能作为可交付验收标准**(重编路径会变 → MCP 失效,S1 已记此坑)。

- [ ] **Step 2.4: 验证(复用 S1 手法)**
  - `claude mcp add` 后 `claude mcp list` = ✓ Connected;`claude -p "用 fetch_capture 拉最新 capture 并贴出 window_title"` → 返回最近一条抓取的真实数据。
  - 排障日志路径见 S1 notes(`~/Library/Caches/claude-cli-nodejs/.../mcp-logs-beamhop/`)。

---

## Task 3: Chrome 扩展 + Native Messaging 桥(浏览器抓取)

**Files:** `host/`(移植 `spike/s4`)、`extension/`、`Sources/Beamhop/Bridge/BrowserBridgeServer.swift`

- [ ] **Step 3.0: Bridge Contract(先定协议再写代码 — codex review)**
  - **Socket 帧 + 消息**:`{ reqID, type, seq?, total?, payload }`;type ∈ {hello, capture_active_tab, result, error, ping}。统一 reqID + timeout + 错误码。
  - **生命周期/重连**:host 启动即连 `bridge.sock`;**app 未运行/连不上 → 指数退避后退出**,让扩展的 `connectNative` 在下次需要时重新拉起 host(扩展端做重连)。MV3 service worker 被挂起 → 在途 request 超时失败 + 可重发。
  - **路由**:app 维护 `connectionID → {browser, profile}`;每次 capture **选前台浏览器对应的连接**;多浏览器/多 profile 并存要能区分。
  - **并发**:同一浏览器的 capture **串行化**;全局并发上限 1 或显式队列。
  - **安全**:socket 目录 `0700`、socket 文件权限/owner 校验、stale socket 清理。

- [ ] **Step 3.1: 架构落地 —— app ↔ host ↔ 扩展**
  - Beamhop app 起 **unix domain socket** server(`~/Library/Application Support/beamhop/bridge.sock`),按 3.0 契约。
  - `beamhop-bridge`(Chrome `connectNative` 拉起)连 app socket,**纯双向中继**:Chrome stdio 帧 ↔ socket。
  - 扩展 background SW **常驻 `connectNative` 端口** + 重连。
  - 取数据 **app 发起**:app → socket → host → 扩展 →(content script 抓取)→ 原路返回。

- [ ] **Step 3.2: native host + 双向分片(移植 S4)— ⚠️ 方向已修正(codex review)**
  - 复用 S4 的精确长度读 + `loadUnaligned` + 4 字节 LE 帧;host 改为**纯中继**,不自己造数据。
  - **分片是双向的,且大正文走 `extension→host→app` 方向**(Week 2 的浏览器抓取流是扩展把 Readability 正文返回给 app,**不是** host 发给扩展 —— 原计划方向写反了)。S4 只证明了 `native-host→extension` 的 ~1MB 上限。
  - 定义 **双向 request/chunk/reassemble** 协议(`{reqID, seq, total, chunk}`),host 和扩展两端都能拆/合。

- [ ] **Step 3.3: Chrome MV3 扩展(移植 S4 + 抓取能力,§6.3)**
  - background SW:常驻 `connectNative` 端口 + 重连;响应 app 的 `capture_active_tab` 请求。
  - content script:抓 URL / title / meta description / **选中文本** / `@mozilla/readability` 正文 markdown。
  - **GitHub 模板结构化抽取**(MVP 只内置 GitHub):PR diff / issue 元信息 / code 块 → `domain_hint`。
  - 仅一个 popup 显示"已连接 Beamhop"(§6.3 边界:扩展不做 AI/不直连 agent)。
  - 装 manifest 到各浏览器 `NativeMessagingHosts/`(S4 的 `install.sh` 逻辑搬进 app 的首启/诊断"一键写入")。

- [ ] **Step 3.4: app 侧 BrowserBridgeServer + 融合进 CaptureService**
  - 抓取时若前台是浏览器:CaptureService 先 AX 拿 url/title/selection,**再**通过 bridge 问扩展要 Readability 正文 + 结构化抽取,合并进 `extracted_body` / `domain_hint` / `extension_version`。
  - 扩展未装/未响应 → 仅 AX 元数据 + toast "装扩展可抓全文"(§6.6)。

- [ ] **Step 3.5: 端到端验证(可借 Week 0 的 CDP 自动化思路)**
  - 在 Chrome 选中网页文本按 ⌘⇧Space → Inbox 里该条有 url + selected_text + Readability 正文 + (GitHub 页)结构化字段。
  - **两条分片路径分别测(codex review)**:
    - `app/host → extension` 1.1MB 请求 → 必须分片成功(对应 S4 实测的 native-host→extension ~1MB 上限);
    - `extension → host → app` 2MB Readability 正文 → 必须真实返回成功(这才是大正文的实际方向)。

---

## Task 4: Clipboard-Safe Paste + Claude Code 投递(金线)

**Files:** `Sources/Beamhop/Delivery/{ClipboardService,TerminalLocator,ClaudeCodeDelivery,PromptRenderer}.swift`

- [ ] **Step 4.1: ClipboardService —— §12.3 安全协议(codex review:细化还原语义)**
  - 备份按 **`pasteboardItems` 逐 item、逐 type 保存 raw `Data`**(不是只存 string);**任一 type 读不到 data → 拒绝安全粘贴**并提示用户手动(owner/lazy pasteboard、文件 promise、多 item 这些拿不到 data 的情况都走拒绝)。
  - 步骤(§12.3):① 逐 item/type 缓存 raw Data → ② 写待粘贴 → ③ AX ⌘V → ④ 等 ~50ms → ⑤ **clearContents 后逐 item 重建**全部 type → ⑥ 第①步失败即拒绝(不污染)。
  - **测试矩阵**:plain text、HTML+RTF 多 type、多文件 URL、PNG 图片、空剪贴板 —— 还原后逐项比对一致。
  - ⚠️ 注意:**只有 ClaudeCodeDelivery 的安全粘贴需要还原**;Task 5 的 ClipboardHandoff 是"主动把内容留在剪贴板给用户粘",**不承诺也不应该还原**。

- [ ] **Step 4.2: PromptRenderer(§7.6)**
  - `protocol PromptRenderer { func render(_ capture: Capture, userNote: String?) -> String }`。
  - Claude Code 的触发文案(§7.3 ⑤):`"用 Beamhop MCP 的 fetch_capture('cap_xxx') 拿我刚抓的上下文,{userNote}"` —— **不粘正文,让 agent 按需取**(§7.3 关键决定:省 token)。

- [ ] **Step 4.3: TerminalLocator(§7.3 ③④)**
  - 找前台终端(bundle ∈ {com.apple.Terminal, com.googlecode.iterm2, dev.warp.Warp, com.mitchellh.ghostty})。
  - ⚠️ **判断 claude 会话(codex review:`pgrep claude` 太粗会误判别项目/后台进程)**:优先按**前台终端窗口的 tty / 进程树**判定该窗口里是否在跑 claude;判不准 → **提示用户确认,不直接自动回车**。否 → "Claude Code 未运行,开新会话?"(`osascript` 开新 iTerm 跑 `claude "..."`)。

- [ ] **Step 4.4: ClaudeCodeDelivery(组装金线,§7.3)**
  - 前置:capture 已入库(Task 1)+ MCP 已注册(Task 2,诊断里可见)。
  - 找终端 → focus → ClipboardService 安全粘贴触发文案 → **末尾自动回车**(§7.3 ⑤:Claude Code 金线允许自动回车;ChatGPT 才不允许)。
  - Claude Code 触发 `fetch_capture` → MCP server 读库返回 → 完成。
  - 记录 `Delivery` 行(success/failed/cancelled + error)。
  - 任意步骤失败 → 转 Task 5 剪贴板兜底,**绝不静默失败**(§7.7 / §12.4)。

- [ ] **Step 4.5: 验证(金线端到端)**
  - 前台开着 Claude Code 的 iTerm,Safari 选中文本 → ⌘⇧Space → 终端里出现触发 prompt + 回车 → Claude Code 调 `fetch_capture` 拿到刚抓的内容。全链路 < spec 目标延迟。

---

## Task 5: 剪贴板兜底 handoff(全目标共用,金线)

**Files:** `Sources/Beamhop/Delivery/ClipboardHandoff.swift`

- [ ] **Step 5.1: ClipboardHandoff**
  - 把 Capture 用对应 PromptRenderer 渲成完整 markdown(这里**要带正文**,因为没有 MCP 通道)→ 写剪贴板 → 系统通知"内容已复制,请在目标里粘贴"+ 失败原因。
  - 这是**金线**(spec §4.1 / §7.1:剪贴板兜底升为金线,任何 AX/MCP 失败自动降级)。

- [ ] **Step 5.2: 接成统一降级**
  - DeliveryService 总入口:`deliver(capture, target)` → 按 target 走专用通道 → 失败 catch → ClipboardHandoff。
  - 失败信息进 `Delivery.error_message`,供 Week 3 的 Failure Recovery UI(§12.4)展示。

---

## Task 6: 金线串联 + 端到端 smoke + 诊断补全

- [ ] **Step 6.1: `⌘⇧Space` 全链路(无浮窗版,浮窗 Week 3)**
  - `⌘⇧Space` → CaptureService 抓取(AX + 浏览器扩展)→ 入库 → `DeliveryService.deliver(capture, .claudeCode)` → 失败降级剪贴板 → 系统通知结果。
  - 默认目标 = Claude Code(§9.1 默认规则;浮窗选择器 Week 3 再加)。

- [ ] **Step 6.2: 诊断面板补真(codex review:这些应随对应 Task 增量做,本步只做最终汇总验收)**
  - Claude Code MCP(随 Task 2):从"复制命令"升级为**真·一键 `claude mcp add … -s user -- <bin> --db <path>`**。
  - Chrome native messaging host(随 Task 3):真检测 manifest + host 二进制 + 扩展连通性 → ✅/❌ + "一键写入 manifest"。
  - 本步只确认各行最终状态一致、无回归。

- [ ] **Step 6.3: 端到端 smoke 矩阵(手动 + 半自动)**
  - Chrome 网页 → Claude Code:✓ 抓取(url+正文)+ MCP 投递成功。
  - Safari 选中 → Claude Code:✓(url 有,selected_text 走 marker 或空,method 标注正确)。
  - 非浏览器(Notes/VS Code)→ Claude Code:✓ AX 元数据 + 投递。
  - Claude Code 未运行 / MCP 未注册 / 扩展未装 → 各自降级路径正确,通知有明确原因。
  - 剪贴板:投递前后用户剪贴板内容不变(§12.3)。

- [ ] **Step 6.4: 文档 + commit + tag**
  - 更新 roadmap/README;`spike/` 里 S1/S4 标注"已移植到产品 Task 2/3"。
  - `git tag -a week-2-golden-path-complete`。

---

## Self-Review(对照 spec §15 Week 2)

| spec §15 Week 2 项 | 计划任务 | 覆盖? |
|---|---|---|
| AX 抓取实现(app/window/url/selection + provenance) | Task 1 | ✅ per-app 策略 + 黑名单 + 敏感字段 + 超时 + provenance |
| 浏览器扩展(Chrome MV3)+ Native Messaging Bridge | Task 3 | ✅ host 中继 + 分片 + 扩展抓取 + Readability/GitHub + app socket |
| 自家 MCP server + Claude Code 注册引导 | Task 2 | ✅ 移植 S1 + 资源/工具 + 只读共享库 + `-s user` 注册 |
| 剪贴板兜底 handoff(全目标共用) | Task 5(+§12.3 在 Task 4) | ✅ 安全协议 + 统一降级 |

**Week 0 结论已用上:** S1(MCP 框架/注册)、S4(native messaging 分片/帧)、S6(AX per-app 策略/系统级 focused/opt-in)、§12.3 剪贴板安全。

**本周最高风险(集成周):**
1. **app↔host↔扩展 三段桥**(Task 3.1)—— 全新架构,unix socket + 常驻端口 + 重连,最易出问题,建议最先做通最小往返再加抓取。
2. **native messaging 分片重组**(Task 3.2)—— S4 已证 >1MB 必丢,重组逻辑要测边界。
3. **跨进程共享 inbox.sqlite**(Task 0.2)—— WAL + 只读连接,注意 MCP server 由 Claude 拉起时的绝对路径与权限。
4. **Clipboard-Safe 还原**(Task 4.1)—— 多 type/图片/文件的完整备份还原,失败必须拒绝而非污染。

**建议执行顺序(= 里程碑切分,codex review):**
- **Week 2A**:Task 0 → Task 2(MCP)→ Task 1(AX 抓取)→ Task 4 + 5(投递 + 兜底)→ Task 6.1/6.3 的 2A 部分 smoke。**先把"AX 抓取 → Claude Code"最短金线打通并可交付。**
- **Week 2B**:Task 3(bridge contract → 最小 ping → active tab → Readability → GitHub → 双向分片测试)→ Task 6 余下串联 + tag。**再加浏览器扩展增强支路。**

> 集成周最高风险集中在 Week 2B 的三段桥 + 双向分片;2A 先交付能让金线尽早可用、降低整周风险。
