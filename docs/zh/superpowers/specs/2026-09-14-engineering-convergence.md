# Beamhop 工程收敛 Spec（分支模型与双机协作）

> 日期：2026-09-14
> 状态：V1 — 与 `integration` 分支（CI 全绿）配套生效
> 定位：MVP 设计稿 V2.1 的**流程层**补充。不改产品范围，只锁"代码在哪儿写、怎么验证、怎么合并"。
> 缘起：2026-06~09 发生的双机平行实现事故（Linux 克隆停在 6 月 3 日基线，agent 基于过期文档重写整个 Phase 1，与 Mac 上已真机验证的 33 个 commit 分叉）。

## TL;DR

长期分支只有 `main`；`main` 的语义固定为"最近一次真机验证通过的状态"。Linux 开发、CI 当编译关口（macos-15 全套）、Mac 当验收关口；任何机器任何会话开工前必须 `git fetch` 对齐 origin。

## 1. 事故机制（为什么需要这份 spec）

| 事实 | 后果 |
|---|---|
| Linux 克隆停留在 0a712f9（6 月 3 日 docs-only 基线），从未 fetch | 本地看不见 Mac 上 6 月 7-8 日的 Spike 实测与 Week 1/2 实现 |
| agent 基于过期 spec V2 重写 Phase 1 | 产生与实测结论相反的实现（MCP Content-Length 帧、无 AXManualAccessibility） |
| 两版恰好共用 `Sources/BeamhopCore/`、`Sources/BeamhopMCP/` 路径 | git merge 无冲突合入 → 重复类型定义 → **双方都编译不过** |

结论：事故根因不是 git 操作失误，是**跨机器无同步纪律 + 单一事实源缺位**。工具无法防住，流程可以。

## 2. 分支模型

### 2.1 目标状态（验收后）

```
main ──────────●─────────●─────────→   唯一长期分支
               │         │
        verified-2026-09 │   （每次真机验收通过打 tag）
               │
     feature/* ─┴─ CI 绿 → squash merge → 删分支（生命周期 ≤ 1 周）
```

- **`main` = 最近一次真机验证通过的状态。** 合入 `main` 的前置条件：CI 全绿 **且** 受影响的真机验收项通过（见 §4）。
- **feature 分支短命**（≤ 1 周），从最新 `main` 拉，CI 绿后 squash merge，立即删除。
- **`verified-<年月>` tag**：每次完整真机验收后打在 `main` 上。出问题优先回退到上一个 tag，而不是现场修。

### 2.2 过渡分支处置（一次性）

| 分支 | 处置 | 时机 |
|---|---|---|
| `integration` | Mac 真机跑完 PROGRESS §8 验收清单 → 合回 `main` → 删除 | 下一次坐在 Mac 前 |
| `phase1-linux-reimpl` | 打 `archive/phase1-linux-reimpl` tag → 删除分支（独特资产已全部进 integration） | integration 合并后立即 |
| `main`（当前 6 月态） | 保持不动，直到 integration 验收合入 | 被取代 |

## 3. 双机分工与两个关口

| 机器 | 角色 | 做什么 | 不做什么 |
|---|---|---|---|
| Linux（日常） | 开发机 | 写代码、跑 JS 测试、shell 语法检查、push | **不做任何"能跑/能用"的声明** |
| GitHub CI（macos-15 + ubuntu） | **编译关口** | swift build/test、SelfTest 28 项、MCP 冒烟、manifest 冒烟、组装 Beamhop.app、extension esbuild | 授不了 TCC 权限，测不了真 app |
| Mac | **验收关口** | TCC 授权、⌘⇧Space 金线、ChatGPT/Cowork 真机投递、浮窗手感、Inbox 手感 | 不做长期开发（避免再次分叉） |

**心智模型**：CI 绿 = "没写错"；真机过 = "能用"。两者不可互相替代，任何一环的结论不得越权表述。

## 4. 真机验收清单（main 合入门槛）

CI 无法覆盖、必须 Mac 实测的项（维护在 PROGRESS.md §8，合入前逐项打勾）：

1. ChatGPT Desktop AX 注入（S3 路径，S3 实测时的版本 + 当前版本）
2. Inbox 窗口（列表/双 FTS 搜索/重投/软删手感）
3. FirstRun + 兼容矩阵窗口
4. `packaging/build-app.sh` 产物可运行（TCC 按签名身份绑定）
5. MCPB 安装 → Cowork 会话调 `fetch_capture`（S2 端到端）

## 5. 铁律（防复发）

1. **任何机器、任何会话，开工前 `git fetch` 并确认与 origin 的关系。** 这一条是本次事故唯一直接对症的预防措施。
2. **PROGRESS.md 是唯一入口**——任何会话先读它，再动代码；它的"最近更新"时间戳必须随每次实质推进更新。
3. **spec 是事实源**——写实现前确认自己读的是 spike 回写后的版本（V2.1+），而非旧假设。
4. **不并行重写已有实现**——发现某能力"好像没做"时，先 `git log --all --oneline` 和 fetch 确认，再动手。

## 6. 成功标准

- 6 个月后仓库只有 `main` + 短命 feature 分支 + `verified-*` tags，无平行长期分支
- `main` 上任何一个 commit 都能由 CI 构建出 `Beamhop.app`
- 每个 `verified-*` tag 都有对应的 PROGRESS 验收记录（哪台 Mac、哪些 app 版本、结论）
- 不再出现"两代实现并存"的状态

---

**文档结束。生效动作：Mac 验收 → integration 合回 main → 打 tag → 删两条过渡分支。**
