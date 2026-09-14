# Beamhop — 进度与续作指南（PROGRESS）

> 这份文档是「下次接着干」的唯一入口。记录:做到哪了、什么验证过了、卡在哪、怎么恢复、下一步做什么。
> 最近更新:2026-09-12（integration 分支:Phase 1 外围整合）。

---

## 0. 一句话现状

Week 0 Spike（6 假设）全部实测完 → spec 升 **V2.1**;Week 1 地基**已实现**;Week 2 金线（AX 抓取 → Claude Code 投递）+ 浏览器桥（含 Readability/GitHub）**已实现并自动化验证**。
**当前形态是 SwiftPM（纯 Command Line Tools 可编译跑）**,尚未迁成 Xcode 正式 `.app`。

**唯一阻塞:** 装 Xcode 需要 Apple ID（用户说"账号找不到了"）。免费 Apple ID 即可（`appleid.apple.com` 建/找回 → `xcodes install --latest`)。

---

## 1. 阶段进度表

| 阶段 | 状态 | 验证方式 |
|---|---|---|
| **Week 0** Spike S1–S6 | ✅ 全部完成 | 实机实测 + 2 轮 codex review;结论回写 spec V2.1 |
| **Week 1** 地基 | ✅ 实现 | `BeamhopSelfTest` 28 项全绿 + app 启动建库 |
| **Week 2A** 最短金线 | ✅ 代码完成 | **MCP server 真 Claude Code 实测**;其余编译+自测 |
| **Week 2B** 浏览器桥 + 正文抽取 | ✅ 代码完成 | **三段桥 + Readability + GitHub 全 CDP 自动化实测** |
| **integration** Phase 1 外围 | 🚧 代码完成 | ChatGPT AX 注入、Inbox/首次引导/兼容矩阵 UI、CI、打包、MCPB;**CI(macOS runner) 验证编译+自测,真机验收待做** |
| 真机完整 `⌘⇧Space` 端到端 | ⬜ 待权限 | 需给 app 授 Accessibility |
| Xcode 正式打包 + 签名 | ⬜ 待 Apple ID | — |

---

## 2. 关键文档（按顺序读）

> ⚠️ **铁律：任何机器、任何会话，开工前先 `git fetch` 对齐 origin**（2026-09 双机分叉事故的直接教训，详见工程收敛 spec §5）。

- **设计 spec（真源,V2.1）**: `docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md`
- **Week 0 spike 结果 + 兼容矩阵**: `spike/results.md` + `spike/compatibility-matrix-v0.json`
- **工程收敛 spec（2026-09）**: `docs/superpowers/specs/2026-09-14-engineering-convergence.md` — 分支模型/双机分工/验收门槛
- **演进决策 spec（2026-09）**: `docs/superpowers/specs/2026-09-14-evolution-decisions.md` — Xcode 时机/Phase 2 memory 方向/Phase 3 触发
- **Roadmap**: `docs/superpowers/roadmap.md`
- **实施计划**:
  - Week 1: `docs/superpowers/plans/2026-06-08-week-1-foundation.md`（已实现）
  - Week 2: `docs/superpowers/plans/2026-06-08-week-2-capture-golden-path.md`（已实现,切了 2A/2B）
  - Week 0: `docs/superpowers/plans/2026-06-03-week-0-spike.md`（已完成）

---

## 3. 怎么恢复 / 快速验证（SwiftPM,Command Line Tools 即可）

```bash
cd /Users/willamhou/Codes/beamhop
swift build                       # 编译全部 target（含 GRDB）
swift run BeamhopSelfTest         # 数据层自测,28 项,应 ALL PASS ✅
swift run Beamhop                 # 启动菜单栏 app（✦ 图标 + 热键 + 诊断窗）
swiftc -O host/main.swift -o host/beamhop-bridge   # 编译 native messaging host
```

**MCP server 实测（真 Claude Code）:**
```bash
DB=/tmp/x.sqlite; swift run BeamhopSelfTest --seed "$DB"   # 造一条 capture
BIN=$(swift build --show-bin-path)/BeamhopMCP
claude mcp add beamhop -s user -- "$BIN" --db "$DB"        # ✓ Connected
claude -p "用 beamhop 的 fetch_capture 拉最新 capture" --allowedTools "mcp__beamhop__fetch_capture"
claude mcp remove beamhop -s user                          # 清理
```

**浏览器三段桥端到端（CDP 自动化,免手点 Chrome）:**
```bash
APPBIN=$(swift build --show-bin-path)/Beamhop; HOSTBIN=$(pwd)/host/beamhop-bridge; EXTDIR=$(pwd)/extension
EXTID=$(python3 -c "import hashlib;print(''.join(chr(ord('a')+int(c,16)) for c in hashlib.sha256('$EXTDIR'.encode()).hexdigest()[:32]))")
rm -f "$HOME/Library/Application Support/beamhop/bridge.sock"
"$APPBIN" --bridge-test > /tmp/bt.txt 2>/dev/null & BT=$!; sleep 1
node host/bridge_cdp.js "$HOSTBIN" "$EXTID" "https://en.wikipedia.org/wiki/Accessibility" >/tmp/bcdp.log 2>&1 &
wait $BT; cat /tmp/bt.txt          # 期望: PING -> {pong} / CAPTURE -> url/title/body_len
pkill -f beamhop_bridge_profile; rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.beamhop.bridge.json"
```

**扩展 Readability 重新构建（改了才需要）:**
```bash
cd extension/build && npm install && npm run build   # 输出 ../vendor/readability.js
```

---

## 4. 代码结构（SwiftPM）

```
Package.swift
Sources/
  BeamhopCore/                 # 可测逻辑（无 AppKit 依赖,依赖 GRDB）
    Models/      Capture, Delivery, Source/DomainHint
    Storage/     Database(WAL + openReadOnly + 损坏恢复), Migrations(双 FTS5+触发器),
                 CaptureStore(CRUD+搜索), CaptureReader(只读)
    Capture/     AppBlacklist
    Support/     AppPaths, Version, ULID
  Beamhop/                     # 菜单栏 app（AppKit）
    App/         main.swift(含 --bridge-test 模式), AppDelegate, AppServices(DI), MenuBarController, Notifier
    Hotkeys/     HotkeyManager(Carbon,免 Input Monitoring)
    Permissions/ PermissionService, AXHelper(系统级 focused + AXManualAccessibility + 超时)
    Capture/     CaptureService(组装 Capture + provenance + per-app 策略 + 黑名单)
    Delivery/    ClipboardService(§12.3 安全粘贴), PromptRenderer, TerminalLocator,
                 ClaudeCodeDelivery, DeliveryService(路由+剪贴板兜底)
    Bridge/      BrowserBridgeServer(unix socket)
    Diagnostics/ DiagnosticsService, DiagnosticsWindow
  BeamhopMCP/    main.swift    # 自家 MCP server(stdio,读 inbox.sqlite 只读,--db 传路径)
  BeamhopSelfTest/ main.swift  # XCTest-free 自测 + --seed 助手（CLT 无 XCTest）
Tests/BeamhopCoreTests/        # XCTest 版（等 Xcode 才能 swift test）
host/            main.swift     # native messaging host = 纯帧中继 Chrome<->app socket
                 bridge_cdp.js  # CDP-pipe 加载扩展的测试驱动
extension/       manifest.json, background.js(SW: 常驻端口+ping+capture_active_tab),
                 vendor/readability.js(已 vendored), build/(esbuild 源)
```

---

## 5. 已验证 vs 待验证

**已验证（实机/自动化）:**
- ✅ 数据层:双 FTS5(unicode61+trigram)、软删、损坏恢复、10k ULID 唯一(`BeamhopSelfTest`)
- ✅ MCP server:真 Claude Code `claude mcp add … -s user -- <bin> --db <path>` → ✓ Connected + `fetch_capture` 返回真实 capture
- ✅ 三段桥:`PING`/`capture_active_tab` 端到端,1 个干净 host 进程(CDP 自动化)
- ✅ Readability:Wikipedia 54K 正文;GitHub PR `kind=pr`+正确标题(CDP 自动化)

**待验证（需用户环境）:**
- ⬜ 完整 `⌘⇧Space` 真机金线（需给 Beamhop 二进制授 **Accessibility** + 前台开 Claude Code 终端 + MCP 指向真 `inbox.sqlite`）
- ⬜ 多 type 剪贴板还原真机回归（逻辑写了,§12.3）
- ⬜ AX 取词在 8 app 的真机复测（逻辑基于 S6 实测的 per-app 策略）

---

## 6. 必须记住的坑 / 决策（别重新踩）

来自 Week 0 实测 + 4 轮 codex review,已落进代码:
- **MCP stdio = 换行分隔 JSON + 非阻塞 POSIX 读**（`FileHandle.read(upToCount:)` 会 30s 超时）。注册 `claude mcp add <name> -s user -- <abs-bin>`（**无 `--command`**,**必须 `-s user`** 否则跨项目失效;path 要稳定,别用 `.build`）。
- **native messaging:host→extension ~1MB 硬上限**;但浏览器大正文走 `extension→host→app`（Chrome 允许 4GB）→ **实际抓取不需要分片**。app→extension >1MB 分片是防御性 TODO。
- **自定义 `--user-data-dir` 时,native host manifest 要同时写进 `<profile>/NativeMessagingHosts/`**（不止默认位置）。Chrome 137+ 命令行 `--load-extension` 已封 → 自动化用 **CDP pipe + `Extensions.loadUnpacked`**（`--remote-debugging-pipe --enable-unsafe-extension-debugging`）。
- **WAL 必须 `writeWithoutTransaction` 设**（事务内设会报错）;WAL 下数据在 `-wal` 文件,损坏模拟要连 `-wal/-shm` 一起删。MCP 用 `Database.openReadOnly`（不 migration/不恢复/不建库）。
- **AX:查系统级 focused element**(`AXUIElementCreateSystemWide`);Chromium/Electron/ChatGPT 要先设 `AXManualAccessibility`;**Safari 网页选区走 `AXSelectedTextMarkerRange`**(目前只标 method,未实现);设 `AXUIElementSetMessagingTimeout`。
- **浮窗/窗口 `isReleasedWhenClosed=false`**（红叉会销毁窗口,热键再也调不出 — S5 踩过)。
- **全局热键用 Carbon `RegisterEventHotKey`**（免 Input Monitoring,检查返回值报冲突）。
- **TCC 绑签名身份+路径**:SwiftPM 裸二进制重编 → AX 授权会掉 → 真机金线最好等 Xcode 签名 app。
- **剪贴板安全粘贴**(§12.3):逐 item/逐 type 存 raw Data,拿不到就拒绝;只有 ClaudeCodeDelivery 还原,ClipboardHandoff(兜底)不还原。
- **auto-Enter 仅当"定位的终端是前台 + claude 在跑"**,否则让用户确认（别回车发错窗口）。
- ⚠️ **事故教训**:测 S6 时用脚本往用户 Notes 发模拟按键+撤销,清空过一条笔记(已恢复)。**绝不往用户真实 app 发模拟键/撤销**;抓取走只读 AX。
- **`plutil -lint` 只认 XML/binary plist,JSON 直接 exit 1**——校验 JSON 用 `plutil -convert json -o /dev/null <file>`（CI 实测踩坑）。Swift 里 `"AXEditable"` 属性没有导入常量名,用原始字符串。
- **`.build/release` 是指向三元组目录的符号链接**,`find` 默认不跟随起点符号链接——找 SwiftPM 产物要 `find -H`。CI 的 `TMPDIR` 带尾斜杠会产生 `//` 路径,路径断言两边要用同一种 `cd+pwd` 规范化。

---

## 7. 下一步（按依赖排）

**A. 解锁正式工程（需用户做）**
1. `appleid.apple.com` 建/找回免费 Apple ID → `xcodes install --latest` 装 Xcode 16。
2. 装好后:`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
3. 告诉 Claude → 把 SwiftPM 包迁成 Xcode app target（Info.plist `LSUIElement`、Developer ID 签名、Hardened Runtime、关 App Sandbox）→ 跑 `swift test`（XCTest）。

**B. 真机金线端到端（需 A 或手动授权）**
- 给 Beamhop 授 Accessibility → 注册 MCP 指真库 → 前台开 Claude Code → 在 Safari/Chrome 选文字按 `⌘⇧Space` → 确认投到 Claude Code。

**C. Week 2 收尾（可继续写）**
- MCP 真·一键注册（目前诊断面板是命令预览）。
- AX 整体 800ms deadline（目前各 AX 调用 0.8s,但无总超时）。
- 防御性 app→extension >1MB 分片 + 双向分片测试。
- 多浏览器/profile 路由（目前单连接"最新 host wins"）。

**D. Week 3 计划（可起草）**
- 浮窗投递 UI（§9.1,带目标选择 ⌘1/2/3/0 + 备注框）——integration 已交付 Inbox/FirstRun/兼容矩阵窗口,浮窗是剩余大头;
- Failure Recovery UI 深化（Inbox 列表已显示失败原因 + 投递历史,§12.4 骨架已就位）;
- 完整 onboarding 向导（FirstRun 窗口已就位,浏览器扩展/agent 注册步骤待接入）。

---

## 8. integration 分支（2026-09-12）— Phase 1 外围整合

`integration` 以 main（Mac 版,真机证据 lineage）为骨架,把 `phase1-linux-reimpl` 分支的工程外围择优搬入,并按 S1/S3 实测修正:

**新增:**
- `Sources/Beamhop/Delivery/ChatGPTDelivery.swift` — S3 实测路径:`AXManualAccessibility` opt-in → 焦点窗口 BFS 找 `AXTextArea`(可编辑) → `kAXValueAttribute` set-value 注入全文,**不自动发送**;任何失败→剪贴板兜底。
- `Sources/Beamhop/Inbox/InboxWindow.swift` — ⌘⇧I Inbox 窗口:列表+双 FTS5 搜索+详情(provenance 全字段)+投递历史+重投+软删。
- `Sources/Beamhop/App/FirstRunWindow.swift` — 首启引导(Accessibility 必需/其余可选,全部可跳过)。
- `Sources/Beamhop/Compatibility/CompatibilityMatrix.swift` + `Sources/Beamhop/Resources/` — spike 实测矩阵作为 SwiftPM 资源内置,菜单"兼容性矩阵…"窗口展示(真源仍是 `spike/compatibility-matrix-v0.json`)。
- `⌘⇧V` 应急通道 — 最新 Capture 一键渲染到剪贴板(spec §9.3)。
- `cowork-extension/` — MCPB 打包(入口 `BeamhopMCP`,无参运行回退默认 Inbox;S2 机制已确认,端到端待验收)。
- `packaging/build-app.sh` + `packaging/Info.plist` — 组装 `dist/Beamhop.app`(Beamhop+BeamhopMCP+swiftc 编译的 beamhop-bridge+资源 bundle,ad-hoc 或 `BEAMHOP_CODESIGN_IDENTITY`)。
- `host/install-manifest.sh` — 四浏览器 native messaging manifest 安装器(id 校验+plutil lint)。
- `scripts/mcp-smoke.sh`(S1 帧格式握手+种子数据 tool/resource 读取+无 --db 回退)、`scripts/native-manifest-smoke.sh`。
- `.github/workflows/ci.yml` — macos-15:swift build/test + SelfTest + 两个冒烟 + host 编译 + 整 app;ubuntu:extension esbuild。

**修改:**
- `BeamhopMCP/main.swift` — 无 `--db` 时回退 `AppPaths.databaseURL`(供 MCPB 无参启动;显式 `--db` 不变)。
- `DeliveryService` — `.chatgptDesktop` 走 S3 注入路径(原直接降级剪贴板);`.cowork` 维持剪贴板待 S2 端到端。
- `CaptureStore.deliveries(captureID:)` — Inbox 投递历史查询。
- `AppServices`/`MenuBarController` — 接入三个新窗口 + ⌘⇧V。

**integration 待真机验收清单:**
- ✅ CI 全绿(macos-15:swift build/test + SelfTest 28 项 + MCP 冒烟 + manifest 冒烟 + **完整组装出 Beamhop.app**;ubuntu:extension esbuild)
- ⬜ ChatGPT Desktop 注入(AX opt-in 后 set-value;S3 只测过单版本,且当时是探针脚本不是本实现)
- ⬜ Inbox 窗口真机(列表/搜索/重投/软删手感)
- ⬜ FirstRun + 兼容矩阵窗口真机
- ⬜ `./packaging/build-app.sh` 产物可运行(TCC 授权按签名身份绑定)
- ⬜ MCPB `cowork-extension` 安装→Cowork 会话调 `fetch_capture`

---

## 8. 全部 commit（参考）

从 `ad13e4a`（spike 脚手架）到 `88949c2`（week2b Readability）共 30+ commit;tag `week-0-spike-complete`。
`git log --oneline 0a712f9..HEAD` 看全量。所有 `spike/` 代码是 throw-away;正式代码在 `Sources/ host/ extension/`。
