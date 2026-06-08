# Beamhop Week 2 — Capture + Golden-Path Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 打通 MVP 金线 —— `⌘⇧Space` 抓取当前 app(AX + Chrome 扩展)→ 写入 Inbox(Week 1 已就绪)→ 投递到 Claude Code(自家 MCP server + AX 粘贴触发)→ 失败自动降级剪贴板兜底。本周是**集成周**,把 Week 0 实测的 4 个原型(S1 MCP / S4 native messaging / S6 AX 取词)固化成产品代码。

**前置:** Week 1 地基已完成(`BeamhopCore` 数据层 + 菜单栏 app + Carbon 热键 + 权限/AXHelper + 诊断框架)。Week 2 在其上接真逻辑。

**Reference spec:** `docs/.../2026-06-03-beamhop-mvp-design.md`(V2.1)§5.2(数据流)/§6.2-6.3(抓取)/§7.2-7.3(投递)/§7.6(Prompt Renderer)/§12.3(Clipboard-Safe Paste)。
**Week 0 实测原型(直接复用/移植):** `spike/s1-claude-code-mcp/`(MCP server)、`spike/s4-chrome-native-messaging/`(host + 扩展)、`spike/s6-ax-selected-text/AXProbe.swift`(AX 取词)。

**Tech Stack:** 续 Week 1(Swift + GRDB + Carbon)。新增:独立可执行 `BeamhopMCP`(stdio JSON-RPC)、`beamhop-bridge`(native messaging host)、Chrome MV3 扩展(TypeScript + Vite + `@mozilla/readability`)。

**Week 2 范围(spec §15):** AX 抓取 + Chrome 扩展/native messaging + 自家 MCP server + Claude Code 注册引导 + 剪贴板兜底(全目标共用)。
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

- [ ] **Step 0.2: 共享 inbox.sqlite 的并发读(关键)**
  - Beamhop app 写库;`BeamhopMCP` 进程**只读**同一个 `inbox.sqlite`。
  - GRDB 开 **WAL 模式**(`DatabaseQueue`/`DatabasePool`),保证跨进程读不阻塞写。`BeamhopMCP` 用只读连接(`Configuration.readonly = true`)。
  - 在 `Database` 里确认 `PRAGMA journal_mode=WAL`(GRDB 默认 WAL,验证一下)。

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
  - 极长正文 > 100k 截断 + `truncated=1`,Inbox 存完整(§11)。
  - `domain_hint` 粗判(github.com/pr|issue 等;细的留扩展 Task 3)。
  - 产物 `insert` 进 `CaptureStore`,返回 `Capture`。

- [ ] **Step 1.4: 接 `⌘⇧Space`**
  - `AppServices.placeholderCapture()` → 真 `CaptureService.captureFrontmost()`;成功后(Week 2 暂)直接进 Task 4 的默认投递。
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
  - 数据源:**只读**打开 `AppPaths.databaseURL`(Task 0 的 WAL 只读连接)。注意 MCP server 由 Claude Code 拉起,工作目录/环境未知 → 用绝对路径定位 DB。

- [ ] **Step 2.3: 注册引导(§9.4 / S1)**
  - app 内"注册 Claude Code"动作:校验 `claude` 在 PATH → `claude mcp add beamhop -s user -- <BeamhopMCP 绝对路径>`;不在 PATH 则给可复制命令。
  - 二进制路径要**稳定**(装到 app bundle 内或固定 support 目录;SwiftPM 阶段先用 `.build` 绝对路径,Xcode 后改 bundle)。

- [ ] **Step 2.4: 验证(复用 S1 手法)**
  - `claude mcp add` 后 `claude mcp list` = ✓ Connected;`claude -p "用 fetch_capture 拉最新 capture 并贴出 window_title"` → 返回最近一条抓取的真实数据。
  - 排障日志路径见 S1 notes(`~/Library/Caches/claude-cli-nodejs/.../mcp-logs-beamhop/`)。

---

## Task 3: Chrome 扩展 + Native Messaging 桥(浏览器抓取)

**Files:** `host/`(移植 `spike/s4`)、`extension/`、`Sources/Beamhop/Bridge/BrowserBridgeServer.swift`

- [ ] **Step 3.1: 架构 —— app ↔ host ↔ 扩展(关键设计)**
  - Beamhop app 起一个 **unix domain socket** server(`~/Library/Application Support/beamhop/bridge.sock`)。
  - `beamhop-bridge`(Chrome 用 `connectNative` 拉起)在启动时连上 app 的 socket,**双向中继**:Chrome stdio 帧 ↔ socket。
  - 扩展 background service worker **常驻一个 `connectNative` 端口**(保持 host 进程活着 + 连着 app)。
  - 取数据是 **app 发起**:app → socket → host → 扩展 →(content script 抓取)→ 原路返回。

- [ ] **Step 3.2: native host(移植 S4 + 加分片)**
  - 复用 S4 的精确长度读 + `loadUnaligned` + 4 字节 LE 帧。
  - **应用层分片(S4 实测必须)**:host→extension 单条 > ~1MB 要拆成多帧(`{id, seq, total, chunk}`),扩展端重组。Readability 正文很容易超 1MB。
  - host 不再"自己造数据",改成**纯中继** Chrome ↔ app socket。

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
  - 大正文(> 1MB)分片重组正确(对照 S4 的 1MB 边界结论)。

---

## Task 4: Clipboard-Safe Paste + Claude Code 投递(金线)

**Files:** `Sources/Beamhop/Delivery/{ClipboardService,TerminalLocator,ClaudeCodeDelivery,PromptRenderer}.swift`

- [ ] **Step 4.1: ClipboardService —— §12.3 安全协议**
  - 步骤严格按 §12.3:① 读当前 `NSPasteboard` **所有 type** 缓存 → ② 写待粘贴 → ③ AX 触发 ⌘V → ④ 等 ~50ms → ⑤ 还原全部 type → ⑥ **第①步读失败(无法序列化的特殊 type)→ 直接拒绝粘贴**并提示用户手动。
  - 提供可取消 + 失败回滚;绝不污染用户剪贴板(Codex 在 spec 里强调过)。

- [ ] **Step 4.2: PromptRenderer(§7.6)**
  - `protocol PromptRenderer { func render(_ capture: Capture, userNote: String?) -> String }`。
  - Claude Code 的触发文案(§7.3 ⑤):`"用 Beamhop MCP 的 fetch_capture('cap_xxx') 拿我刚抓的上下文,{userNote}"` —— **不粘正文,让 agent 按需取**(§7.3 关键决定:省 token)。

- [ ] **Step 4.3: TerminalLocator(§7.3 ③④)**
  - 找前台终端(bundle ∈ {com.apple.Terminal, com.googlecode.iterm2, dev.warp.Warp, com.mitchellh.ghostty})。
  - 判断里面是否有 `claude` 在跑(`pgrep claude` / 扫窗口标题);否 → 提示"Claude Code 未运行,开新会话?"(`osascript` 开新 iTerm 跑 `claude "..."`)。

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

- [ ] **Step 6.2: 诊断面板补真(Week 1 的 🚧 项现在能做了)**
  - Chrome native messaging host:真检测 manifest + host 二进制 + 扩展连通性 → ✅/❌ + "一键写入 manifest"。
  - Claude Code MCP:从"复制命令"升级为**真·一键 `claude mcp add … -s user`**(host 二进制现在有了)。

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

**建议执行顺序:** Task 0 → Task 2(MCP,低耦合,可独立验)→ Task 1(AX 抓取)→ Task 4+5(投递+兜底,先用 AX 抓取的 capture 跑通金线)→ Task 3(浏览器扩展,最重,放后面)→ Task 6 串联。即**先把"AX 抓取 → Claude Code"这条最短金线打通,再加浏览器扩展这条增强支路**。
