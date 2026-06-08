# Beamhop Week 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭起 Beamhop 的工程地基 —— 菜单栏常驻 app + 全局快捷键 + AX 权限引导 + Capture 数据模型/SQLite/双 FTS5 + Permission Diagnostics 面板框架。Week 1 **不做**实际抓取(AX 读取)和投递(MCP/AX 粘贴),那是 Week 2;但要把这两者依赖的地基(数据层、权限、诊断、热键)全部立住,且把 Week 0 实测结论烧进代码。

**Reference spec:** `docs/superpowers/specs/2026-06-03-beamhop-mvp-design.md`(V2.1)。Week 1 范围见 §15;细节见 §6.5 / §8.1 / §9.3 / §9.4 / §12.1 / §12.2 / §13。
**Week 0 实测结论(必须遵守):** `spike/results.md` + `spike/compatibility-matrix-v0.json`。

**Tech Stack:** Swift 5.10+ / Xcode 16 / macOS 14+(目标)/ SwiftUI + AppKit(菜单栏用 NSStatusItem)/ GRDB.swift(SQLite + FTS5)/ Carbon RegisterEventHotKey(全局热键,**Week 0 S5 验证:无需 Input Monitoring**)。

**命名约定(README):** 品牌 **Beamhop**;`beamhop` 全小写用于 bundle id 段、目录、SQL。本计划用 bundle id `com.beamhop.app`,app support 目录 `~/Library/Application Support/beamhop/`。

**Week 0 → Week 1 必须烧进代码的结论:**
- 全局热键用 Carbon `RegisterEventHotKey`,**检查返回值**以提示冲突(S5 codex)。
- 任何浮窗/面板窗口 `isReleasedWhenClosed = false`(S5 实测:红叉会销毁窗口)。
- AX 读 focused element 用**系统级** `AXUIElementCreateSystemWide()`(S6);Chromium/Electron/ChatGPT 需先设 `AXManualAccessibility`(S3/S6)—— 这些在 Week 2 抓取层用,但 `AXHelper` 地基在 Task 3 立。
- Permission Diagnostics 的 "Claude Code MCP 注册" 行用 `claude mcp add beamhop -s user -- <abs-bin>` 语法判定 + 修复(S1)。
- 数据层 FTS:`unicode61` + `trigram` 双表(spec §8.1,V1 的 bigram 是错的)。

**Output structure:**

```
beamhop/
├── Beamhop.xcodeproj
├── Beamhop/
│   ├── App/            (BeamhopApp, AppDelegate, MenuBarController)
│   ├── Models/         (Capture, Source, DomainHint, Delivery)
│   ├── Storage/        (Database, Migrations, CaptureStore)
│   ├── Hotkeys/        (HotkeyManager, Hotkey)
│   ├── Permissions/    (PermissionService, AXHelper)
│   ├── Diagnostics/    (DiagnosticsService, DiagnosticsWindow)
│   ├── Support/        (AppPaths, Version, ULID, Logger)
│   └── Resources/      (Info.plist, Beamhop.entitlements, Assets)
└── BeamhopTests/       (StorageTests)
```

**Week 1 不做(明确边界,留给后续 week):** 实际 AX 抓取内容、浮窗投递 UI(Week 3)、浏览器扩展/native host(Week 2)、MCP server 实现(Week 2)、Inbox 列表 UI(Week 3)、截图(Week 2+)。Diagnostics 里依赖 Week 2 产物的检查项(native messaging host、MCP server 启动)先做成"框架 + 真状态读取(能读的读,读不了的标 🚧 Week 2)"。

---

## Task 0: Xcode 工程脚手架

**Files:**
- Create: `Beamhop.xcodeproj`(Xcode macOS App, SwiftUI lifecycle)
- Create: `Beamhop/Resources/Info.plist`、`Beamhop/Resources/Beamhop.entitlements`
- Create: `Beamhop/Support/AppPaths.swift`、`Version.swift`、`Logger.swift`

- [ ] **Step 0.1: 新建 Xcode 工程**
  - Xcode → New Project → macOS → App。Product Name `Beamhop`,Bundle id `com.beamhop.app`,Interface SwiftUI,Language Swift,**不勾** Core Data/Tests(测试 target 后面单加)。
  - 删掉默认 `ContentView`,改菜单栏架构(Task 1)。
  - 注意:CLT-only 环境跑不了 `.xcodeproj` 构建,需安装完整 Xcode 16。

- [ ] **Step 0.2: Info.plist 关键键**
  - `LSUIElement = YES`(纯菜单栏 app,不在 Dock,不出主窗口)。
  - `LSMinimumSystemVersion = 14.0`。
  - `NSScreenCaptureUsageDescription`(截图功能用,Week 2 真用)。
  - (Accessibility 无 usage string,靠 `AXIsProcessTrusted`;权限提示在 Task 3。)

- [ ] **Step 0.3: 入口与 entitlements**
  - App Sandbox 对 Accessibility/全局热键不友好 → **关闭 App Sandbox**(MVP 直分发,不上 MAS;spec §13)。Hardened Runtime 开,签名用 Developer ID(后续公证)。
  - `Beamhop.entitlements`:暂不需要特殊 entitlement(无 sandbox)。记录此决定的理由到注释。

- [ ] **Step 0.4: 加 SPM 依赖 GRDB.swift**
  - File → Add Packages → `https://github.com/groue/GRDB.swift`,加到 Beamhop target。

- [ ] **Step 0.5: 基础 Support 工具**

  `Beamhop/Support/AppPaths.swift`:
  ```swift
  import Foundation
  enum AppPaths {
      // ~/Library/Application Support/beamhop/
      static let supportDir: URL = {
          let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          let dir = base.appendingPathComponent("beamhop", isDirectory: true)
          try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          return dir
      }()
      static var databaseURL: URL { supportDir.appendingPathComponent("inbox.sqlite") }
      static var screenshotsDir: URL { supportDir.appendingPathComponent("screenshots", isDirectory: true) }
  }
  ```

  `Beamhop/Support/Version.swift`:
  ```swift
  import Foundation
  enum Version {
      static var beamhop: String {
          (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
      }
      static var os: String {
          let v = ProcessInfo.processInfo.operatingSystemVersion
          return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
      }
  }
  ```

  `Logger.swift`: 轻封装 `os.Logger`(subsystem `com.beamhop.app`)。

- [ ] **Step 0.6: 编译通过 + commit**
  - 工程能 build & run(出现菜单栏占位即可,Task 1 完善)。
  - `git add . && git commit -m "feat: xcode app scaffold (menu-bar, GRDB dep, app paths)"`

---

## Task 1: 菜单栏 app 骨架 + 生命周期

**Files:**
- Create: `Beamhop/App/BeamhopApp.swift`、`AppDelegate.swift`、`MenuBarController.swift`

- [ ] **Step 1.1: App 入口走 AppDelegate**

  `BeamhopApp.swift`:
  ```swift
  import SwiftUI
  @main
  struct BeamhopApp: App {
      @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
      var body: some Scene { Settings { EmptyView() } } // 无主窗口
  }
  ```

- [ ] **Step 1.2: AppDelegate 装配核心单例**

  `AppDelegate.swift`(`applicationDidFinishLaunching`):
  ```swift
  NSApp.setActivationPolicy(.accessory)        // 不在 Dock
  AppServices.shared.bootstrap()               // DB、热键、权限、诊断
  ```
  - `AppServices`:持有 `Database`、`HotkeyManager`、`PermissionService`、`DiagnosticsService`、`MenuBarController` 的容器(简单手写 DI,别引框架)。

- [ ] **Step 1.3: 菜单栏 item + 菜单**

  `MenuBarController.swift`:`NSStatusItem`(✦ 或 SF Symbol `sparkles`),菜单项:
  - "抓取当前(⌘⇧Space)" → 占位 action(Week 2 接抓取)
  - "Inbox(⌘⇧I)" → 占位(Week 3)
  - "诊断…" → 打开 Permission Diagnostics(Task 5)
  - 分隔符 / "退出"
  - 菜单项 keyEquivalent 仅作展示;真正全局热键在 Task 2。

- [ ] **Step 1.4: 验收 + commit**
  - 启动后菜单栏出现图标,菜单可点,"退出"有效,Dock 无图标。
  - commit: `feat: menu-bar controller + app lifecycle`

---

## Task 2: 全局快捷键 + 冲突检测(Carbon,S5 结论)

**Files:**
- Create: `Beamhop/Hotkeys/HotkeyManager.swift`、`Hotkey.swift`

- [ ] **Step 2.1: Carbon 热键封装**(无需 Input Monitoring —— Week 0 S5 已验证)
  - `Hotkey`:`{ id, keyCode, modifiers, handler }`。
  - `HotkeyManager.register(_:)` 用 `RegisterEventHotKey` + 一个 `InstallEventHandler` 分发;**检查 `RegisterEventHotKey` 的 `OSStatus` 返回值**,非 `noErr` 记为冲突(S5 codex 提醒)。
  - 参考 `spike/s5-floating-window/FloatingDemo/Sources/FloatingDemo/main.swift` 的热键注册写法。

- [ ] **Step 2.2: 注册 MVP 三个全局键(spec §9.3)**
  - `⌘⇧Space`(keyCode 49)→ 抓取占位
  - `⌘⇧I`(keyCode 34)→ Inbox 占位
  - `⌘⇧V`(keyCode 9)→ 应急投递占位
  - 每个先接到 `Logger` 打日志 + `NSSound.beep()`,证明全局生效(Week 2/3 接真逻辑)。

- [ ] **Step 2.3: ⌘⇧Space 冲突检测 + 引导改键(spec §9.3/§9.4)**
  - 若 `⌘⇧Space` 注册失败(多半被 Spotlight/输入法占),记录冲突状态,首启时引导改键(Task 5 诊断面板里也展示)。
  - 热键绑定持久化到 `UserDefaults`(MVP 够用),预留"设置里重绑"。

- [ ] **Step 2.4: 验收 + commit**
  - 在任意前台 app 按三个键都能在 Console 看到对应日志/beep。
  - 故意占用 ⌘⇧Space(开 Spotlight 自定义)验证冲突被检测到。
  - commit: `feat: global hotkeys via Carbon + conflict detection`

---

## Task 3: AX / 截图权限引导 + AXHelper 地基

**Files:**
- Create: `Beamhop/Permissions/PermissionService.swift`、`AXHelper.swift`

- [ ] **Step 3.1: 权限状态读取**

  `PermissionService`:
  ```swift
  import ApplicationServices
  import CoreGraphics
  enum PermState { case granted, denied, notDetermined }
  struct PermissionService {
      func accessibility() -> PermState { AXIsProcessTrusted() ? .granted : .denied }
      func screenRecording() -> PermState { CGPreflightScreenCaptureAccess() ? .granted : .denied }
      func promptAccessibility() {  // 弹系统提示
          let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
          _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
      }
      func openAccessibilitySettings() {
          NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
      }
      func openScreenRecordingSettings() {
          NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
      }
  }
  ```
  - settings 跳转 URL 在 Week 0 S6 里已实测可用。

- [ ] **Step 3.2: AXHelper 地基(供 Week 2 抓取层复用,Week 1 只立 API + 单元自测)**
  - 把 Week 0 `spike/s6-ax-selected-text/AXProbe.swift` 的可复用部分固化为正式 `AXHelper`:
    - `systemFocusedElement()` 用 `AXUIElementCreateSystemWide()`(S6 结论:别用 app 级)
    - `enableManualAX(forPID:)` 设 `AXManualAccessibility` + `AXEnhancedUserInterface`(仅对 Chromium/Electron/ChatGPT 目标调用,记录失败)
    - `frontmostApp()`、`selectedText(...)`、`windowTitle(...)`、`url(...)` 的签名(Week 2 填实现)
    - **必须**:`AXUIElementSetMessagingTimeout` + 遍历节点上限(S6 codex)
  - Week 1 只需 `frontmostApp()` + `accessibility()` 能跑通(读到前台 app 名/bundle),其余留 TODO。

- [ ] **Step 3.3: 验收 + commit**
  - 首次运行触发系统 Accessibility 提示;授权后 `accessibility()` 返回 granted;"打开设置"按钮跳对面板。
  - commit: `feat: permission service + AX helper foundation`

---

## Task 4: Capture 数据模型 + SQLite(GRDB)+ 双 FTS5 + 损坏恢复

**Files:**
- Create: `Beamhop/Models/{Capture,Source,DomainHint,Delivery}.swift`
- Create: `Beamhop/Storage/{Database,Migrations,CaptureStore}.swift`
- Create: `Beamhop/Support/ULID.swift`
- Create: `BeamhopTests/StorageTests.swift`

- [ ] **Step 4.1: 模型(spec §6.5 + §12.1 provenance)**
  - `Source`(`.browser/.ax/.screenshot`)、`DomainHint`(`.github(.pr/.issue/.repo/.code)/.stackoverflow/.generic`)枚举(`String, Codable`)。
  - `Capture: Codable, FetchableRecord, PersistableRecord`,字段对齐 §6.5 + §12.1 的 provenance 列(`pid, appVersion, osVersion, beamhopVersion, axTreeSnapshot, captureMethod, extensionVersion, isPrivate, truncated, captureDurationMs`)。
  - `Delivery`(capture_id, target, delivered_at, status, error_message)。

- [ ] **Step 4.2: ULID 生成 `cap_<6位>`**
  - `ULID.short()` 返回 6 位 Crockford base32(时间高位 + 随机),id = `"cap_" + short()`。(spec 写 "6 位 ulid";严格 ULID 是 26 位,这里取短前缀够用且可读,注明非标准 ULID。)

- [ ] **Step 4.3: Database + GRDB DatabaseQueue + 迁移**

  `Database.swift`:打开 `AppPaths.databaseURL` 的 `DatabaseQueue`,跑 `Migrations`。
  `Migrations.swift`(用 GRDB `DatabaseMigrator`),v1 迁移建表(直接 §8.1 + §12.1 合并后的最终 schema,**provenance 列一开始就 NOT NULL/默认值齐**,不要真用 ALTER):
  ```sql
  CREATE TABLE captures (
    id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, source TEXT NOT NULL,
    app_bundle_id TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT, url TEXT,
    selected_text TEXT, extracted_body TEXT, domain_hint TEXT, user_note TEXT,
    screenshot_path TEXT, deleted_at INTEGER,
    -- provenance (§12.1)
    pid INTEGER NOT NULL, app_version TEXT, os_version TEXT NOT NULL,
    beamhop_version TEXT NOT NULL, ax_tree_snapshot TEXT, capture_method TEXT NOT NULL,
    extension_version TEXT, is_private INTEGER NOT NULL DEFAULT 0,
    truncated INTEGER NOT NULL DEFAULT 0, capture_duration_ms INTEGER
  );
  CREATE TABLE deliveries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, capture_id TEXT NOT NULL REFERENCES captures(id),
    target TEXT NOT NULL, delivered_at INTEGER NOT NULL, status TEXT NOT NULL, error_message TEXT
  );
  CREATE INDEX idx_captures_created ON captures(created_at DESC);
  CREATE INDEX idx_deliveries_capture ON deliveries(capture_id);
  ```

- [ ] **Step 4.4: 双 FTS5 + 同步触发器(spec §8.1)**
  - `captures_fts`(`unicode61 remove_diacritics 2`,列:window_title/url/selected_text/extracted_body/user_note)
  - `captures_fts_cjk`(`trigram`,列:window_title/selected_text/extracted_body/user_note)
  - 两张都用 external content(`content='captures', content_rowid='rowid'`)→ **必须建 insert/update/delete 触发器**把 captures 的写入同步进两张 FTS(GRDB 不自动做)。把触发器写进同一迁移。
  - ⚠️ external-content FTS 的 delete 触发器要用 `'delete'` 命令行(`INSERT INTO fts(fts, rowid, ...) VALUES('delete', old.rowid, ...)`)。

- [ ] **Step 4.5: CaptureStore CRUD + 搜索**
  - `insert(_:)`、`recent(limit:)`、`softDelete(id:)`、`purgeExpired()`(deleted_at 超 30 天物理删)。
  - `search(_ query:)`:对两张 FTS 各查一次 → UNION by id → 按 `bm25()` + 时间衰减(`created_at`)重排(spec §8.1)。返回去重结果。
  - 预期质量声明落到代码注释:中文是 trigram substring 级,非语义。

- [ ] **Step 4.6: 损坏恢复(spec §8.2)**
  - 打开时 `PRAGMA integrity_check`;失败 → 把旧库重命名 `inbox.sqlite.broken.{ts}` → 重建空库跑迁移 → 截图 PNG 不动。
  - 记日志 + 在 Diagnostics 里可见(Task 5)。

- [ ] **Step 4.7: 单元测试 `StorageTests`**
  - 临时目录起库:insert 一条 → recent 拿到;`search` 英文词命中(unicode61);`search` 中文 substring 命中(trigram);softDelete 后 recent 不返回;purgeExpired 行为;损坏恢复(写坏文件 → 重开 → 自动重建)。

- [ ] **Step 4.8: commit**
  - commit: `feat: capture model + GRDB storage + dual FTS5 + corruption recovery + tests`

---

## Task 5: Permission Diagnostics 面板框架(spec §12.2)

**Files:**
- Create: `Beamhop/Diagnostics/{DiagnosticsService,DiagnosticsWindow}.swift`

- [ ] **Step 5.1: DiagnosticsService 计算各项状态**
  - 行(spec §12.2 表):
    | 项 | Week 1 能真读吗 | 实现 |
    |---|---|---|
    | Accessibility | ✅ | `AXIsProcessTrusted()` |
    | Screen Recording | ✅ | `CGPreflightScreenCaptureAccess()` |
    | Chrome native messaging host | ⚠️ 部分 | 检查 manifest 文件是否存在于各浏览器 `NativeMessagingHosts/`(host 二进制 Week 2 才有)→ 标 🚧 |
    | Claude Code MCP 注册 | ✅ | 解析 `~/.claude.json` 顶层 `mcpServers["beamhop"]` 是否在(S1:`-s user` 落顶层);可选跑 `claude mcp list` |
    | Claude Cowork | 🚧 | 固定显示 "Phase 1.5"(S2:机制确认但 e2e 未做)|
    | ChatGPT Desktop AX | ⚠️ | 检测 `/Applications/ChatGPT.app` 是否在 + 版本是否在内置 Compatibility Matrix(`com.openai.chat` 1.2026.119)|
  - 每项返回 `{ name, state(✅/❌/⚠️/🚧), fixAction? }`。

- [ ] **Step 5.2: 修复动作(能做的真做,做不了的占位)**
  - Accessibility/Screen Recording → 调 `PermissionService` 跳设置(Task 3)。
  - Claude Code MCP → "重新注册":`claude mcp add beamhop -s user -- <Beamhop host 绝对路径>`(host 二进制 Week 2 出;Week 1 先把命令拼好 + 校验 `claude` 在 PATH,缺则提示手动复制 —— S1 结论)。
  - Chrome host → "重新写入 manifest":Week 2 实现,Week 1 按钮置灰 + 标 🚧。
  - 热键冲突项(来自 Task 2)也作为一行展示 + "改键"动作。

- [ ] **Step 5.3: DiagnosticsWindow(SwiftUI)**
  - 一个独立 `NSWindow`(承载 `NSHostingView`),列表展示各行 + 状态点 + 修复按钮。
  - **`window.isReleasedWhenClosed = false`**(S5 实测结论:否则关掉后再打开崩/调不出)。
  - 菜单栏"诊断…"打开;可重复打开(spec §9.4 step 5)。

- [ ] **Step 5.4: 验收 + commit**
  - 打开诊断窗:Accessibility/Screen Recording 显示真实状态并能跳设置;MCP 行能正确反映 `~/.claude.json`(可临时 `claude mcp add beamhop -s user -- /bin/echo` 造数据验证,完后移除);关窗再开不崩。
  - commit: `feat: permission diagnostics panel framework`

---

## Task 6: 首启串联 + 冒烟 + 收尾

- [ ] **Step 6.1: 最小首启流程(spec §9.4 的骨架,GIF/演示留后)**
  - 首次运行:若 Accessibility 未授 → 自动打开诊断窗并高亮该行(替代完整 onboarding 向导,向导留 Week 3 打磨)。
  - 记录"已完成首启"标志到 UserDefaults。

- [ ] **Step 6.2: 端到端冒烟(手动)**
  - 启动 → 菜单栏图标在 → 三个全局热键有日志/beep → Accessibility 提示 + 授权后状态变 ✅ → DB 文件在 `~/Library/Application Support/beamhop/inbox.sqlite` 且 `sqlite3 ... '.schema'` 看到 captures + 两张 FTS + 触发器 → 诊断窗各行状态合理。
  - `StorageTests` 全绿。

- [ ] **Step 6.3: 更新文档 + commit + tag**
  - README 状态行 → "Week 1 地基完成";roadmap Phase 1 加一行 "Week 1 地基完成(日期)"(遵循 roadmap 维护约定)。
  - commit: `feat: week-1 foundation complete (menu-bar + hotkeys + permissions + storage + diagnostics)`
  - `git tag -a week-1-foundation-complete -m "Week 1 foundation; ready for Week 2 capture + golden-path delivery"`

---

## Self-Review(对照 spec §15 Week 1 范围)

| spec §15 Week 1 项 | 计划任务 | 覆盖? |
|---|---|---|
| 项目脚手架 | Task 0 | ✅ Xcode 工程 + 目录 + GRDB + AppPaths |
| 菜单栏 app | Task 1 | ✅ NSStatusItem + .accessory + 菜单 |
| 全局快捷键 | Task 2 | ✅ Carbon(S5)+ 冲突检测 + 三键 |
| AX 权限引导 | Task 3 | ✅ PermissionService + 跳设置 + AXHelper 地基 |
| Capture 数据模型 + SQLite + 双 FTS5 | Task 4 | ✅ §6.5+§12.1 模型 + §8.1 schema + 双 FTS + 触发器 + 损坏恢复 + 测试 |
| Permission Diagnostics 面板框架 | Task 5 | ✅ §12.2 各行 + 真状态(能读的)+ 修复动作框架 |

**Week 0 结论已烧进:** Carbon 热键 + 检查返回值(S5)、`isReleasedWhenClosed=false`(S5)、AX 系统级 focused + AXManualAccessibility 地基(S3/S6)、MCP `-s user` 判定/修复(S1)、双 FTS5 unicode61+trigram(spec §8.1)。

**显式不做(留 Week 2+):** 真抓取内容、MCP server 实现、native host、浏览器扩展、投递 UI、Inbox 列表、截图、完整 onboarding 向导。Diagnostics 里依赖这些的项标 🚧 Week 2。

**风险提示(spec §15):** 集成周(Week 4-5)风险最高,Week 1 是低风险地基周;但 GRDB external-content FTS 的触发器(Task 4.4)和 Carbon 热键冲突(Task 2.3)是本周两个易踩点,已在对应 step 标注。
