# Memory MCP 形态决策：溯源写回 vs 专用 memory server

> 日期：2026-10-18
> 状态：V1 — 记录方案 A 写回接口的设计决策与依据
> 定位：演进决策 spec（2026-09-14）§2 路线 A 的第一个落地增量；不改 Phase 1 范围

## TL;DR

给 BeamhopMCP 补写半边（`save_result` / `fetch_results` / `search_captures`），让任意 agent 把结论写回 Inbox 并共享同一份带溯源的记忆。**不采用**专用 memory MCP server（官方 `@modelcontextprotocol/server-memory` 及同类）作为记忆层，理由：它存"agent 蒸馏后的事实"，我们存"带证据链的现场"。两者是事件溯源与知识蒸馏两条路线，不互斥，但地基层必须是前者。

## 1. 背景

当前 BeamhopMCP 是只读拉取数据源（1 个 tool `fetch_capture` + `capture://` resource），投递链路有去程无回程：agent 的结论从不回流 Inbox。记忆闭环缺"问题 → 答案"的右半边。

生态现状（2026-10 查证）：

- MCP 官方 reference server `@modelcontextprotocol/server-memory`：知识图谱（entity/relation/observation）存本地 JSONL，9 个 tool（`create_entities` / `add_observations` / `search_nodes` 等）——即"MCP 写回"模式的原型
- Claude Code auto memory：非 MCP，模型读写 `~/.claude/projects/<project>/memory/` 下的 markdown，`MEMORY.md` 索引前 200 行/25KB 注入启动上下文

结论：agent 侧对"调 MCP tool 存记忆"的行为模式已天然兼容，方案 A 不需要教育 agent。

## 2. 决策

### 2.1 在 BeamhopMCP 内实现写回，三个新 tool

| tool | 方向 | 作用 |
|---|---|---|
| `save_result(origin_capture_id, content, agent, session_id?)` | 写 | agent 把结论写回，落 `results` 表，挂到 origin capture |
| `fetch_results(origin_capture_id?)` | 读 | 取某条 Capture 的回程结论（或最近 N 条） |
| `fetch_capture(id?)` | 读 | 已有，不变 |
| `search_captures(query)` | 读 | FTS5 双表现有检索暴露给 agent，支持按主题召回相关 Capture |

`agent` 为自由文本（`claude_code` / `codex` / `kimi` / …），MCP server 本身 agent-agnostic；多 agent 共享 = 各自注册同一个 stdio server，写同一份 `inbox.sqlite`。

### 2.2 数据模型：`results` 独立表，不塞进 captures

```sql
CREATE TABLE results (
    id                TEXT PRIMARY KEY,            -- res_<ulid>
    origin_capture_id TEXT NOT NULL REFERENCES captures(id) ON DELETE CASCADE,
    agent             TEXT NOT NULL,               -- 写回方（自由文本）
    session_id        TEXT,                        -- agent 侧会话标识（可选）
    content           TEXT NOT NULL,               -- 结论文本（原文，不蒸馏）
    created_at        INTEGER NOT NULL
);
```

理由：

1. **captures 保持纯净**：capture = "你从世界里抓到的"，result = "agent 还给世界的"，两个方向的事件不混表
2. **append-only 证据门**：results 只插不改不删（软删也不做——结论本身是不可变事件），与 captures 的软删策略一致，支持时间旅行
3. **一对多天然成立**：一条 Capture 可能投给多个 agent、一个 agent 可能多轮写回，外键 + cascade 由 v2 同款模式保证

### 2.3 不做的事（本次范围外）

- **不做蒸馏事实图谱**：不把 results 二次提炼成 entity/observation 图——那是读取侧的整理（路线 A 图谱），不在写路径做
- **不写回 deliveries 状态**：agent 主动 `save_result` 即隐含"收到了、处理了"，deliveries 表保持投递通道的客观记录，两者不耦合
- **不自动召回注入**：`search_captures` 由 agent 自主决定是否调用，不在 server 侧做任何"自动附带相关记忆"的魔法（那是 Phase 2.2 投递时建议功能）

## 3. 为什么不直接用专用 memory server

| 维度 | 专用 memory MCP | Beamhop 溯源写回 |
|---|---|---|
| 记忆单位 | 模型蒸馏后的一句话事实 | 原始 Capture + agent 结论（原文都留） |
| 出处 | 无 provenance，不可回溯 | 每条 result 指向 origin capture 的完整现场 |
| 谁决定记 | 模型判断（opaque） | 抓取自动（零判断），写回显式调用（有结构） |
| 与投递关系 | 只存不喂 | 双向：喂上下文（fetch）+ 收结论（save） |
| 用户检查 | 翻 JSONL | Inbox UI 浏览，证据链可视化 |
| 跨 agent | 各 agent 各配各的蒸馏 | 统一接口，任何 agent 的结论汇到同一 Inbox |

本质是两条经典路线：**知识蒸馏**（适合稳定事实，快但会错且难察觉）vs **事件溯源**（全档留证，整理放到读取侧）。专用 memory server 在抓取那一刻不在场，拿不到现场，干不了地基层的活；图谱提炼层将来可以建在 results 之上，两者互补不互斥。

## 4. 多 agent 使用方式

```bash
BIN=$(swift build --show-bin-path)/BeamhopMCP
# Claude Code
claude mcp add beamhop -s user -- "$BIN"
# Codex（示例，以 codex 的 mcp 配置命令为准）
codex mcp add beamhop -- "$BIN"
# 任何支持 stdio MCP 的 agent 同理——同一个二进制，同一份 inbox.sqlite
```

agent 侧的行为约定（写进触发 prompt / agent 说明）：处理完 capture 后，把结论文本调 `save_result` 写回，`agent` 参数填自己的标识。

## 5. 验收

- `swift build` 通过
- `BeamhopSelfTest` 新增 results 往返 + 迁移自测，全绿
- 真机端到端（后续）：Claude Code 投递 → 处理 → `save_result` 写回 → Inbox UI 可见回程结论

## 6. 与既有文档的关系

- 演进决策 spec §2 路线 A：本文是其第一个落地增量，不预判 A/B 终局
- roadmap Phase 2.2：本文实现的 results 表是该阶段"上下文图谱"的右半边数据源
