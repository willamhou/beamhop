# Beamhop Week 3 — 浮窗投递 UI Spec

> 日期：2026-09-18
> 状态：V1 — 待实施；实施计划见 `docs/superpowers/plans/2026-09-18-week-3-implementation.md`
> 定位：MVP spec V2.1 §9.1（浮窗）的落地 + 一个收尾迭代包。完成它，Phase 1 的用户可见形态就齐了。

## TL;DR

`⌘⇧Space` 抓取后不再直接投递，而是弹出**键盘优先的浮窗**：光标落在备注框，⌘1/2/3/0 选目标，Enter 投递，Esc 取消触发（Capture 已入 Inbox 不丢）。浮窗按 S5 实测配置，可浮在全屏 app 之上。同一迭代打包四个收尾件：抓取去重、BrowserCatalog 收敛、诊断面板补行、MCP 一键注册。

## 1. 目标与非目标

### 1.1 目标（本迭代交付）

| # | 能力 | 依据 |
|---|---|---|
| W3-1 | 浮窗投递 UI（备注 + 目标选择 + 键盘流） | MVP spec §9.1 |
| W3-2 | 浮窗窗口行为（全屏/Stage Manager/多 Space 可见，失焦=取消） | S5 实测 + spec §11 |
| W3-3 | 默认目标记忆（本 session 内 = 上次成功目标） | spec §9.1 |
| W3-4 | 重复热键去重（<500ms 同窗口不重复入 Inbox） | spec §11 |
| W3-5 | BrowserCatalog 收敛（浏览器/终端名单单一来源） | review P3-2 |
| W3-6 | 诊断面板补行（ChatGPT AX 路径、MCP 缺省库） | review P3-5 |
| W3-7 | Claude Code MCP 一键注册（诊断面板按钮） | PROGRESS §7C |
| W3-8 | `recordDelivery` 写失败改为可见日志 | review P3-4 |

### 1.2 非目标（明确不做）

- **截图勾选**：Mac 版尚无 ScreenshotService，按原计划 Week 5/Phase 1.5 处理；浮窗不放截图 checkbox（放一个永远灰的选项比不放更糟）
- **ChatGPT 自动回车开关**：spec 定为 Phase 1.5
- **投递目标自动建议**："猜测式"智能放 Phase 2
- **浮窗内编辑 Capture 内容**：Capture 是数据不是文档
- **多显示器拖拽记忆**：S5 未测双屏，先不承诺

## 2. UX 设计

### 2.1 布局（spec §9.1 原型，微调后）

```
┌──────────────────────────────────────────────────────────┐
│ 📋 已抓取  Safari · Fix race condition in queue · 1.2k 字 │
│ [正文预览前 200 字 + URL 灰字]                             │
│ ──────────────────────────────────────────────────────── │
│ 备注(可选): [光标在此等待输入_________________]            │
│ ──────────────────────────────────────────────────────── │
│ 投递到:  ⌘1 ● Claude Code  ⌘2 ○ ChatGPT  ⌘3 ○ Cowork*    │
│          ⌘0 ○ 仅入 Inbox                                  │
│           (*Cowork 未验收,实际走剪贴板——浮窗内标注)        │
│              Esc 取消        ⏎ 投递(Claude Code)          │
└──────────────────────────────────────────────────────────┘
```

### 2.2 键盘流（核心不变量，验收逐条对照）

1. 浮窗弹出时光标**自动在备注框**
2. ⌘1/2/3/0 切换目标，圆点即时更新，Enter 按钮文案跟随
3. **Enter 直接投递当前选中目标**，全程无鼠标
4. **Esc 取消触发**——Capture 已入 Inbox，不丢（通知里说清楚）
5. **浮窗失焦（点别处）= Esc 等效**
6. 投递在**后台线程**执行（复用 P1-1 的派发模式），浮窗立即收起 + 完成后系统通知
7. 抓取进行中再按 ⌘⇧Space：<500ms 且同一窗口 → 忽略重复（W3-4），否则视为新抓取替换浮窗内容

### 2.3 默认目标规则（spec §9.1，不做智能）

- Session 首次：Claude Code
- 之后：本 session 上一次投递**成功**的目标（存内存，重启回 Claude Code——不做持久化，"用户能预测"优先于"聪明"）

## 3. 技术设计

### 3.1 窗口（S5 实测结论，逐条照抄）

```swift
let panel = NSPanel(contentRect:…, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], …)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.isReleasedWhenClosed = false          // S5: hide, not destroy
panel.hidesOnDeactivate = false             // 失焦处理自己做(=Esc),不交给系统
panel.isMovableByWindowBackground = true
```

- `.nonactivatingPanel`：弹出**不激活 Beamhop**、不抢源 app 焦点，但 panel 自身 `makeKey` 接收键盘
- 失焦检测：监听 `NSWindow.didResignKey` 通知 → 走 Esc 同一路径（收起 + Capture 留 Inbox）
- Cowork 未验收的标注：目标按钮旁小字"→剪贴板"，不隐藏真相

### 3.2 数据流改造（现有代码的接线变化）

```
旧: doCapture(后台) → capture → delivery.deliver(.claudeCode) → 通知
新: doCapture(后台) → capture → 主线程 showPanel(capture)
    → 用户 Enter → delivery.deliver(selected) (后台) → 收起 + 通知 + 记默认目标
    → Esc/失焦 → 收起(Capture 已在 Inbox)
```

- `AppServices` 持有 `CapturePanelController`（同 Inbox/Diagnostics 的 lazy 模式）
- 投递完成回调刷新 Inbox model（若有打开的 Inbox 窗口）
- **抓取→浮窗可见的耗时打点**（os_signpost）：这是 spec §16 P95 ≤ 300ms 的验收数据来源，从第一天就记

### 3.3 BrowserCatalog（W3-5）

新建 `BeamhopCore/Support/BrowserCatalog.swift`（放 Core 是为了可单测）：

```swift
public enum BrowserCatalog {
    public struct Entry { public let bundleID: String; public let chromium: Bool }
    /// 主流浏览器:chromium 标记决定 AXManualAccessibility opt-in + native manifest 路径
    public static let browsers: [Entry] = [.safari, .chrome, .arc, .brave, .edge]
    public static func isBrowser(_ bundleID: String) -> Bool
    public static func needsManualAX(_ bundleID: String) -> Bool   // chromium || 已知 Electron
    public static let terminalBundleIDs: Set<String>               // TerminalLocator 迁移过来
}
```

`CaptureService.isBrowser`、`AXHelper.needsManualAX`、`TerminalLocator.terminalBundleIDs` 全部改为引用它；兼容矩阵 JSON 仍是"实测证据"，不与代码名单合并职责。

### 3.4 MCP 一键注册（W3-7）

诊断面板 "Claude Code MCP" 行的修复动作升级：

1. 找 `claude` 二进制（`/usr/local/bin`、`/opt/homebrew/bin`、PATH）
2. 找 BeamhopMCP：优先 `.build` 产物 → `Bundle.main` 内嵌（打包后）
3. `Process` 执行 `claude mcp add beamhop -s user -- <abs-bin>`（S1 验证过的准确形式）
4. 失败 → 显示**可复制的完整命令** + 打开终端按钮（现有降级不回退）

### 3.5 去重（W3-4）

`CaptureService` 记 `(bundleID, windowTitle?, 上次时间)`；500ms 内同键 → 返回 `.rejected(reason: "重复抓取")`——但这条 rejection **不弹错误通知**（是预期行为），只静默忽略 + 日志。

## 4. 验收标准

**CI 可验证**（macos-15）：
- 全部编译 + SelfTest（新增 BrowserCatalog 与默认目标逻辑的测试）
- 现有冒烟不回归

**Mac 真机验收**（追加进 PROGRESS §8）：
1. 全屏 Safari/VS Code 下 ⌘⇧Space → 浮窗可见且可键盘输入（S5 场景）
2. 纯键盘流：抓取 → 输备注 → ⌘2 → Enter → ChatGPT 注入成功
3. Esc 后 Inbox 里有这条 Capture、无投递记录
4. 点别处（失焦）行为同 Esc
5. 连按两次 ⌘⇧Space（<500ms）只有一条 Capture
6. 抓取→浮窗耗时日志：P95 ≤ 300ms（连续 20 次取值）
7. 诊断面板 MCP 一键注册真机生效（claude mcp list 出现 beamhop）

## 5. 风险

| 风险 | 缓解 |
|---|---|
| `.nonactivatingPanel` 与键盘焦点的边角组合（锁屏后首次、Stage Manager） | S5 已测配置兜底；验收清单含全部场景；失败退化为"panel 激活 app"再评估 |
| 全屏 app 上 makeKey 失败 | S5 结论是可行的；真机验收覆盖；失败则文档化"先退出全屏" |
| 抓取慢（AX 800ms 超时 ×N）挤压 300ms 预算 | 打点区分 capture 耗时 vs panel 显示耗时；超预算先优化 AX 并行读 |

---

**文档结束。下一步：按 `plans/2026-09-18-week-3-implementation.md` 实施；Linux 开发 + CI 把关 + Mac 验收。**
