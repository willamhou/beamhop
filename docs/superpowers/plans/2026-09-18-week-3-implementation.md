# Beamhop Week 3 — 浮窗投递 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 落地 MVP spec §9.1 的投递浮窗——`⌘⇧Space` 抓取后弹浮窗（备注 + ⌘1/2/3/0 目标选择 + Enter 直投 + Esc 留 Inbox），替代当前"直接投 Claude Code"的 Week 2 简化流。同一迭代交付四个收尾件：抓取去重、BrowserCatalog 收敛、诊断补行、MCP 一键注册。

**前置（已完成）:** main @ d6d8f35——抓取/投递/Inbox/诊断已就绪;P1-1 已把抓投链路后台化（浮窗不继承主线程阻塞）;`AppActivator` 已提取;review P2 已修。

**Reference spec:** `docs/superpowers/specs/2026-09-18-week-3-floating-window.md`（本迭代 spec,含验收标准）+ MVP spec V2.1 §9.1/§9.3/§11。
**S5 实测约束(逐条照抄,不许改):** `.floating` + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` + `isReleasedWhenClosed=false`。
**开发模式:** Linux 写码 → CI(macos-15) 把关 → Mac 验收（工程收敛 spec §3）。**任何 UI 行为声明在 Mac 验收前只能写"待验收"。**

**Output structure:**
```
Sources/Beamhop/
  Panel/          CapturePanelController.swift, CapturePanelView.swift, CapturePanelModel.swift
  Diagnostics/    + MCP 一键注册、ChatGPT/缺省库诊断行
Sources/BeamhopCore/
  Support/        BrowserCatalog.swift
```

**里程碑切分:**
- **3A — 浮窗本体（Task 0-3）:** 打点 → panel + 键盘流 → 接线 + 去重。完成即恢复"浮窗选目标"的核心体验。
- **3B — 收尾包（Task 4）:** BrowserCatalog + 诊断行 + MCP 注册 + 日志。相互独立,可拆 PR。

---

## Task 0: 耗时打点（先于一切 UI）

- [ ] **Step 0.1: os_signpost 打两个区间**
  - `AppServices.doCapture`:capture 开始→captureFrontmost 返回;返回→panel `orderFront` 完成。
  - Logger 输出 `capture_ms` 与 `panel_ms`,字段名固定——Mac 验收的 P95 数据直接从这里取。
  - 验证:CI 编译过;Mac 上日志可见两条打点。

## Task 1: CapturePanelController + View（浮窗本体）

- [ ] **Step 1.1: NSPanel 配置（S5 逐条）**
  - `styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable]`;`level = .floating`;collectionBehavior 三件套;`isReleasedWhenClosed = false`;`hidesOnDeactivate = false`;`isMovableByWindowBackground = true`;`becomesKeyOnlyIfNeeded`。
  - `show(capture:)` → `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps: true)`（nonactivating panel 需要显式激活才能稳收键盘;真机验收 Task 3 覆盖,失败再调）。
- [ ] **Step 1.2: CapturePanelView（SwiftUI,布局照 spec §2.1）**
  - 顶部:已抓取摘要(app · 标题 · 字数)+ 正文预览 200 字 + URL 灰字。
  - 备注框:`TextField`,出现即 focus(`@FocusState`)。
  - 目标行:⌘1 Claude Code / ⌘2 ChatGPT / ⌘3 Cowork(角标"→剪贴板") / ⌘0 仅入 Inbox;圆点即时更新。
  - 底部:Esc 取消 / ⏎ 投递(当前目标名)。
  - `.background(KeyboardShortcut…)`:⌘1/2/3/0、Esc(`.cancelAction`)、Enter(`.defaultAction`)。
- [ ] **Step 1.3: CapturePanelModel**
  - `selectedTarget: DeliveryTarget`（初值由注入的 defaultTargetProvider 给）
  - `note: String`;`confirm()` / `cancel()` 回调接口（由 AppServices 注入,Model 不持有服务）。
  - Cowork 按钮标注"→剪贴板"（未验收的真相可见,spec §2.1）。

## Task 2: AppServices 接线（数据流切换）

- [ ] **Step 2.1: doCapture 改道**
  - 后台 capture 成功 → **主线程** `panel.show(capture:)`;rejected 照旧 Notifier。
  - panel 的 confirm → 后台 `delivery.deliver(capture, selected, userNote: note)` → 成功后 `defaultTarget.update(selected)` + 通知;失败路径沿用 DeliveryService 内建的剪贴板兜底。
  - cancel → panel 收起,Notifier.info("已存入 Inbox", capture.id)——明确告知没丢。
- [ ] **Step 2.2: 失焦=Esc**
  - `NSWindow.didResignKey` 观察(panel 自己监听自己的通知,resign 且非投递中触发)→ 走 cancel 同一路径。
  - 注意与 confirm 竞态:confirm 先 `panel.orderOut` 再投递,resign 触发时检查 `isDelivering` 标志跳过。
- [ ] **Step 2.3: 默认目标记忆（W3-3,内存级）**
  - `AppServices` 持 `var lastSuccessfulTarget: DeliveryTarget = .claudeCode`;投递成功回调更新;panel show 时读取。
  - **不写 UserDefaults**——重启回 Claude Code 是 spec 的决定。
- [ ] **Step 2.4: 重复热键去重（W3-4）**
  - `CaptureService` 记 `(bundleID, windowTitle)` 与时间;500ms 内同键 → 返回新 case `.duplicate` → AppServices **静默忽略**（无通知,只日志）。
  - `CaptureOutcome` 加 `.duplicate` case;现有调用方switch 更新。

## Task 3: 真机验收支持

- [ ] **Step 3.1: 验收清单回写**
  - spec §4 的 7 条 Mac 验收项追加进 PROGRESS §8（含 P95 打点取数方法:`log show --predicate 'subsystem == "com.beamhop.app"' | grep panel_ms` 连续 20 次）。
  - README「构建运行」补浮窗一句话说明。

## Task 4: 收尾包（3B,可独立 PR）

- [ ] **Step 4.1: BrowserCatalog（W3-5）**
  - `BeamhopCore/Support/BrowserCatalog.swift`:browsers(含 chromium 标记)、`isBrowser`、`needsManualAX`（chromium + 已知 Electron 前缀）、terminalBundleIDs。
  - `CaptureService` / `AXHelper` / `TerminalLocator` 改为引用;**行为不变**（名单内容照抄现状,不趁机扩名单）。
  - SelfTest/XCTest 加 catalog 断言（isBrowser/needsManualAX 各 ≥3 例）。
- [ ] **Step 4.2: 诊断面板补行（W3-6）**
  - DiagnosticsService 加两行:①ChatGPT Desktop——装了没/版本在不在兼容矩阵 versions_tested（读 CompatibilityMatrixLoader 的 snapshot）;②MCP 缺省库——`AppPaths.databaseURL` 是否存在 + 行数。
- [ ] **Step 4.3: MCP 一键注册（W3-7,spec §3.4 四步）**
  - 找 claude → 找 BeamhopMCP → `claude mcp add beamhop -s user -- <abs>` → 失败展示可复制命令。
  - 成功后诊断行刷新;`claude mcp list` 冒烟脚本加一个注册-验证-清理的 echo 用例（CI 跑,不依赖真账号——只验证二进制存在与参数拼装,真注册留给 Mac 验收）。
- [ ] **Step 4.4: recordDelivery 可见化（W3-8）**
  - `DeliveryService.record` 的 `try?` → do/catch + Logger.error;投递不中断。

## 完成定义（本迭代 Definition of Done）

1. CI 全绿（含新增断言）
2. spec §4 的 7 条 Mac 验收项全部执行并记录（PASS/FAIL + 版本）
3. PROGRESS §8 回写;P95 数据贴进 PROGRESS
4. review 报告 P3-2/P3-4/P3-5 标记已修
5. 全过 → `verified-<年月>` tag 候选（连同 §8 其余历史项一起决策）
