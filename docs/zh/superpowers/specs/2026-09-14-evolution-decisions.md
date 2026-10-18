# Beamhop 演进决策 Spec（Phase 1 收尾 → Phase 2 方向）

> 日期：2026-09-14
> 状态：V1 — 锁三个演进决策点的判断依据与触发条件；具体范围在各自开工时另立实施计划
> 定位：MVP 设计稿 V2.1 的**战略层**补充。不改 Phase 1 范围。
> 关键外部输入：Intuition-Lab/personal-model（2026-09 分析，~1.3k stars）对 Phase 2 赛道的影响。

## TL;DR

三个决策点：① Apple ID/Xcode 在 Phase 1 收尾时解决（Phase 2 前置）；② Phase 2 memory 不做"天真版"，在"provenance-first 任务图谱"与"集成 personal-model"两条路里于 Phase 2 开工前选定；③ Phase 3 自家 agent 的引入时机由 Phase 1 dogfood 指标触发，不由直觉触发。

## 1. 决策点一：Xcode / Apple ID 的解决时机

**现状**：Apple ID 遗失（PROGRESS §0），`swift build` + CLT + CI 已覆盖日常开发验证，Xcode 只在两处成为硬阻塞：

| 场景 | 何时到来 | 阻塞原因 |
|---|---|---|
| 正式签名分发（他人可用） | Phase 1 对外发布 | Developer ID 签名 + 公证；ad-hoc 签名的 TCC 授权在别人机器上不可靠 |
| iOS 端 / 跨设备（roadmap Phase 2） | Phase 2 中后段 | Xcode 工具链 + 真机调试 |

**决策**：在 **Phase 1 收尾（Week 3 浮窗 + 真机验收）与 Phase 2 开工之间**解决。理由：
- 拖进 Phase 2 会与 memory 工程量叠加，双线阻塞；
- 免费 Apple ID 即可解锁 Xcode 安装（`appleid.apple.com` 建/找回 → `xcodes install --latest`），成本一小时以内；
- 付费 Developer Program（$99/年）可再推迟到真要分发/上 iOS 时。

**注意**：Xcode 就位后 `swift test`（XCTest）成为常规步骤；SwiftPM → Xcode app target 迁移按 PROGRESS §7A 执行。

## 2. 决策点二：Phase 2 memory 的方向

### 2.1 赛道现实（2026-09 评估结论）

Intuition-Lab/personal-model 已开源并先发验证了"本地个人记忆 runtime"：
- 持续 AX 捕获 + 本地 OCR + 五分钟归约 + 分层模型（Point→Line→Face→Volume→Root）
- 工程深度在**证据门**：每个推断必须引用会话原文；新实体需两个独立 session 的回执才晋升 Point；同日重放不重复计票；append-only 可审计可时间旅行
- 它的空白恰是我们的主场：**投递/路由层完全没做**（无浮窗、无 AX 粘贴触发、无 agent-agnostic 目标选择）

**推论**：Phase 2 若只做"Inbox + embedding 语义搜索"，是用弱化版撞人家主场，且毫无防御性。**明确不做天真版。**

### 2.2 两条候选路线

| | 路线 A：provenance-first 任务上下文图谱 | 路线 B：集成 personal-model 作为记忆后端 |
|---|---|---|
| 做什么 | Beamhop Capture 本就带完整溯源（app/窗口/通道/时间），把 Inbox 升级为"带证据链的任务记忆"：任务↔Capture↔投递去向的图谱，检索按"我当时在干什么"组织 | Beamhop 专注投递/路由，记忆层对接 personal-model（其支持本地导入引导，架构有口子），Inbox 作为它的捕获源之一 |
| 定位连续性 | 与"投递工具"天然连续（记忆的单位是任务上下文，不是用户画像） | 承认记忆是独立赛道，交换生态位 |
| 工程量 | 大（自建图谱 + 检索 + UI） | 中（适配层 + 联调） |
| 风险 | 与 personal-model 的 Face/Volume 层功能重叠部分需要差异化叙事 | 依赖外部项目节奏；其证据门设计若变动需要跟随 |
| 防御性 | provenance/inspectability 是平台主吃不掉的 wedge（spec §1.3 原判仍成立） | 我们变薄，护城河让渡 |

### 2.3 决策程序（不现在拍板）

Phase 2 开工前一周执行一次**一小时评估**（写回本节）：
1. personal-model 六个月演化（是否做了投递/路由？证据门是否变严/变松？商业化动向？）
2. 我们 Phase 1 dogfood 数据：Inbox 回访率、搜索命中率、"找不回当时的上下文"痛点频率
3. 若 personal-model 未向投递扩张且集成口子稳定 → 倾向 **B 起步**（快、承认现实），图谱能力（A）作为 Phase 3 自家 agent 的地基再做
4. 若 dogfood 中"按任务找回上下文"是最强信号 → 倾向 **A**，且必须达到其证据门水准（引用原文 + 独立双采样 + append-only 三件套是底线，不是加分项）

## 3. 决策点三：Phase 3 自家 agent 的引入时机

**原则**（沿用 spec §3 战略）：开放为引，封闭为质；过早失去信任，过晚失去窗口。

**决策**：时机由 **Phase 1 dogfood 指标**（MVP spec §16）触发，不由日历或直觉触发：

| 指标（MVP 上线后 2 周窗口） | 阈值 | 未达标动作 |
|---|---|---|
| 发起者本人 ⌘⇧Space 频次 | ≥ 10 次/天 | 修 UX，不谈 Phase 3 |
| 金线投递成功率（Claude Code + 剪贴板兜底） | ≥ 95% | 修可靠性 |
| Inbox 累计 / 回访 | ≥ 200 条，≥ 3 次/周 | 修 Inbox 价值（这是 memory 需求的前置信号） |
| 失败投递 100% 有可读原因 | 100% | 修 failure recovery |

全部达标 → 进入 Phase 2（memory 决策按 §2.3 执行）；Phase 2 中若"在 Beamhop 内直接处理"的自然份额出现（用户主动要求、外部投递占比下降），才立项 Phase 3。

## 4. 与既有文档的关系

- MVP 范围/金线：以 spec V2.1 为准，本文不改
- 阶段时间窗：roadmap.md 为准；本文给 §2.3/§3 的触发条件补充判断依据
- 本文档维护节奏：Phase 2 开工评估（§2.3）与 Phase 1 dogfood 数据回填（§3）时更新，更新即升版本号

---

**文档结束。近期动作：完成 Week 3 浮窗 + 真机验收 → 解决 Apple ID → 执行 §2.3 评估 → Phase 2 立项。**
