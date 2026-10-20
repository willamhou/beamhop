# Inbox Detail Chain — capture → deliveries → results 时间线

> 日期：2026-10-19
> 状态：V1 — Phase 1.5 第一个知识层增量（roadmap Phase 1.5 "Panel UX polish / Inbox value" 项下）
> 定位：memory-mcp-decision（2026-10-18）的读取侧第一步。数据地基（三张 append-only 表 + 外键链）已就绪，本文把"流程记录"变成用户可感知的时间线。

## 1. 背景与目标

方案 A 落地后，一条 Capture 的完整链路是：**抓取（现场）→ 投递（deliveries 表）→ agent 结论写回（results 表）**。三张表都在，但 Inbox 详情页只展示 deliveries——agent 给回的结论看不见，"这条上下文后来怎么样了"答不了。

目标（小步、纯增量、不动写路径）：

1. Inbox 详情页新增 **Timeline** 区：把该 capture 的 deliveries 与 results 按时间合并成一条时间线，↩ 标记写回事件。
2. 列表行显示写回计数徽标（"↩ 2"），不展开任何内容——避免注意力窃取（roadmap Phase 2.2 的 UX 决策同样适用）。
3. 合并逻辑放 `BeamhopCore`（纯函数，可测），UI 只消费——遵循 PromptRenderer 先例。

非目标（明确不做）：

- 跨 capture 的主题轨迹/图谱（Phase 2.2 语义层的事）
- results 的编辑/删除（append-only 证据门基线，读取侧也不破坏）
- 自动召回注入（memory-mcp-decision §2.3 明确留给投递时建议功能）

## 2. 设计

### 2.1 Core：`TimelineEntry`（Sources/BeamhopCore/Models/TimelineEntry.swift）

```swift
public enum TimelineEntry: Equatable, Sendable {
    case delivery(Delivery)
    case result(CaptureResult)
    public var timestamp: Int64   // delivered_at / created_at, 升序排列用
}

public enum TimelineBuilder {
    public static func entries(deliveries: [Delivery], results: [CaptureResult]) -> [TimelineEntry]
    // deliveries + results 按 timestamp 升序合并；同刻 delivery 在前（先投递后有结论）
}
```

放 Core 的理由：合并与排序是纯逻辑，SelfTest/XCTest 双镜像覆盖（CI 教训：两边必须同步改）。

### 2.2 InboxModel

- `@Published var results: [String: [CaptureResult]]` — 与 deliveries 同一批加载（`captures.prefix(50)`，选中条目的时间线需要）。
- `selectedID` 变化时无需额外加载（同批已覆盖）。

### 2.3 UI（InboxWindow.swift）

- **CaptureRow**：有写回时行尾加 `↩ N` caption 徽标（secondary 色）。
- **CaptureDetail**：原 "Delivery history" 区替换为 **"Timeline"** 区：
  - 投递事件：沿用现有图标/文案（success/fail、target、duration_ms、相对时间）。
  - 写回事件：↩ 图标 + agent 名 + session（如有）+ 相对时间；content 以 callout 展示，限 2000 字符（与 Body 一致），`textSelection(.enabled)`。
- 保持键盘流与现有布局不变，仅 detail 列内容增加。

### 2.4 事件埋点

复用现有 `captureViewed`（detail 打开即记）。不新增事件名——写回区没有独立的打开动作，独立埋点属于过度设计；若 dogfood 后需要"结论被阅读"信号，再加 `resultViewed`。

## 3. 验收

- `swift build` 通过；`swift run BeamhopSelfTest` 与 `swift test` 同步新增 TimelineBuilder 检查并全绿。
- 手测：Inbox 选中一条已被 agent 写回的 capture，Timeline 区同时出现投递与写回事件，按时间升序；无写回的 capture 界面与现在一致。

## 4. 与既有文档的关系

- memory-mcp-decision（2026-10-18）：本文是其"读取侧整理"的第一个 UI 增量。
- roadmap Phase 2.2：语义轨迹（embeddings、跨 capture 关联）仍是下一阶段；本文不预判其设计。
- PROGRESS.md：完成后更新 §1 阶段表与 §7-C。
