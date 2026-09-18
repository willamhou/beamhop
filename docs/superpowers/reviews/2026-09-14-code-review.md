# Beamhop 代码 Review（2026-09-14）

> 范围：`main` @ aa95aa6 全量 Swift/JS/shell 源码（含 integration 移植件）
> 方法：逐文件人工通读 + 对照 spec V2.1 / PROGRESS 坑清单
> 结论先行：**无致命 bug**;1 个 P1 主线程阻塞问题、2 个 P2 数据/正确性隐患、若干 P3 重构项。金线路径（AX 抓取 → Claude Code 投递 → 剪贴板兜底）的代码质量好——这批是经过 spike + codex review 洗过的。
>
> **修复状态（2026-09-18）**:P1-1、P2-1、P2-2、P2-3、P3-1 已修（含 FK v2 迁移 + cascade 自测）;P3-2~P3-7 保持待办,随 Week 3 处理。P2-2 的真机验证项仍在 PROGRESS §8。

## P1 — 应尽快修

### P1-1 投递/抓取全程跑在主线程，会卡 UI（最坏 ~2s+）

- `AppServices.swift:101` `doCapture()` 在热键回调里**同步**执行 `captureFrontmost()`（多次 AX 读，各 0.8s 超时）+ `delivery.deliver()`
- `ClaudeCodeDelivery.swift:24-30` 前台激活循环 `usleep(80_000)×15`（最坏 1.2s）；`ChatGPTDelivery.swift:20-31` 同款 + `usleep(150_000)`
- `TerminalLocator.swift` 的 `pgrep` `waitUntilExit` 也在主线程
- 菜单栏 app 虽然没有重 UI,但热键到浮窗弹出(spec 要求 P95 ≤ 300ms)会被这条链路直接拖死
- **修法**:热键回调里 `DispatchQueue.global(qos:.userInitiated).async` 包住 doCapture 全链;Inbox 的 `onDeliver` 已经是这么做的(`AppServices.swift:57`),照抄即可。注意 AX 调用在后台线程是允许的;`NSWorkspace`/`NSRunningApplication.activate` 亦然

## P2 — 真实隐患，排进近期

### P2-1 物理清除会留下孤儿投递记录（FK 从未启用）

- `Migrations.swift:47` `capture_id TEXT NOT NULL REFERENCES captures(id)` 声明了外键,但全库**没有任何 `PRAGMA foreign_keys=ON`**——SQLite 默认关闭 FK
- 后果:`CaptureStore.purgeExpired()` 30 天物理删除 captures 时,关联 deliveries 行静默残留,Inbox 的投递历史查询会引用不存在的 capture
- **修法**（二选一）:GRDB `Configuration().foreignKeysEnabled = true` + 迁移补 `ON DELETE CASCADE`;或 purge 时先删 deliveries（显式两步删）。前者更对,但需确认现有库升级路径(存量孤儿数据清理一次)

### P2-2 ChatGPTDelivery 的 BFS 去重用 `ObjectIdentifier` 可能失效

- `ChatGPTDelivery.swift` `findComposer` 用 `ObjectIdentifier(child)` 做 visited 集合,但 AX API 每次查询可能返回**新的 AXUIElement 实例**（CF 引用不等价于同一底层元素）,树会被重复访问,800 次访问上限可能在深树(Electron 嵌套 20-60 层)提前耗尽而找不到输入框
- **修法**:AX 树按结构是树不是 DAG——去掉 visited 集合、只留 `maxDepth`+`maxVisits` 双上限即可（更简单也更对）;或改为按 (depth, index) 计数。**这条必须进 Mac 验收清单**:S3 当时验证的是探针脚本,本实现未实测

### P2-3 extension→app 的分片重组是"死代码"，与注释声明不符

- `BrowserBridgeServer.request`（约 :95-125）实现了 chunk 重组,但 `extension/background.js` 的 `reply()` 只发单帧——JS 侧从未分片(`MAX_RESP` 常量定义后无使用)
- 现实无害（extension→host 方向 Chrome 允许 4GB,大正文确实不需要分片）,但注释暗示"我们会 chunk"而实现缺失,未来谁加上 `app→extension` 大消息（PROGRESS §7C 防御性分片）时会被误导
- **修法**:短期改注释说明"重组是防御性预留,extension 侧未实现分片";长期按 §7C 实现双向分片时一起补测试

## P3 — 重构与打磨（不阻塞验收）

### P3-1 "激活并等前台"逻辑三处重复 → 提取 AppActivator

- `ClaudeCodeDelivery.swift:24-30` 与 `ChatGPTDelivery.swift:20-26` 几乎逐行相同(activate + usleep 循环);`TerminalLocator` 里也有变体
- 提取 `enum AppActivator { static func focus(bundleID: String, timeout: TimeInterval) -> Bool }`,顺便把 usleep 轮询换成带 deadline 的统一实现(P1-1 的一部分)

### P3-2 浏览器/终端名单三处硬编码 → 单一 BrowserCatalog

- `CaptureService.isBrowser`(5 个 bundle id)、`AXHelper.needsManualAX`(10 个前缀)、`TerminalLocator.terminalBundleIDs`(4 个)、兼容矩阵 JSON 里还有一份
- 名单是随兼容性演进的数据,应收敛为一个 `BrowserCatalog`(Swift 常量起步,后续从矩阵 JSON 加载)

### P3-3 Inbox 投递历史 N+1 查询

- `InboxWindow.swift` `loadDeliveries()` 对前 50 条 capture 各发一次 `store.deliveries(captureID:)`——每 50 条列表 = 50 个 SQL
- 加 `CaptureStore.deliveries(captureIDs: [String]) -> [String: [Delivery]]` 批量版(IN 查询),一次取回

### P3-4 静默吞错 `try?` 集中在关键写路径

- `DeliveryService.swift:53` `try? store.recordDelivery(d)`——投递记录写失败等于丢 failure-recovery 证据(§12.4 的根基)
- 至少改为 log;记录失败不应中断投递,但要可见

### P3-5 DiagnosticsService 落后于已实现的能力

- spec §12.2 的表里有 "ChatGPT Desktop AX 路径" 与 MCP 注册行;现在 ChatGPT 已有 S3 实现路径、MCP 有缺省库回退,诊断面板应加对应行(状态从兼容矩阵读),否则"为什么不工作"会漏这两项

### P3-6 ChatGPT set-value 会覆盖用户未发送的草稿

- `ChatGPTDelivery.swift` 注释已声明权衡(composer 通常是空的)。若 dogfood 中踩到,改进方案:先读 `kAXValueAttribute` 拼接而非替换

### P3-7 杂项

- `AppServices.emergencyClipboardPaste` 的错误分支 `Notifier.error` 在剪贴板兜底链路上 OK,但 `store.recent` 失败与"Inbox 为空"共用提示语,可区分
- `InboxModel.deliver` 用固定 2.5s 延迟刷新——骨架期可接受,正式版应在投递完成回调里刷新
- `Host` 的 `host/main.swift` 纯帧中继质量好(POSIX 精确长度读+写满检查),无发现
- `Migrations` 的双 FTS 触发器(INSERT/DELETE/UPDATE)与 `CaptureStore.search` 的双路召回+BM25+时间衰减实现与 spec 一致,无发现;`Database` 损坏恢复(备份+清 wal/shm)符合 §8.2
- `ClipboardService` 逐 item/type 备份、不可序列化即拒绝,符合 §12.3,无发现

## 做得好的（保持）

- **金线路径代码是洗过的**:AXHelper 的系统级 focused element + ManualAX opt-in + 0.8s 超时、MCP 的 newline 帧 + 原始 read、剪贴板安全粘贴协议,全部对应 spike 实测教训并在注释里注明出处——这是这个库最值得保持的风格
- **失败不静默**:DeliveryService 全路径降级剪贴板 + 记录原因,与 spec §12.4 一致
- **诚实降级**:Cowork 未验收就不装懂,走剪贴板并注明原因

## 建议的处理顺序

1. P1-1(主线程) + P3-1(AppActivator) 合并一个 PR——同一片代码
2. P2-2(BFS) 一并修(改动 5 行),进 Mac 验收
3. P2-1(FK) 单独 PR(涉及存量数据清理,要谨慎)
4. P3-2/3-5 随 Week 3 浮窗一起做
5. 其余 P3 按顺手原则
