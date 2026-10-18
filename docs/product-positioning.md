# Beamhop 产品定位

> 决策日期：2026-08-24

## 一句话

Beamhop 是面向多-agent用户的 macOS 本地上下文路由器：把当前 app 的内容连同可检查的来源信息，在 5 秒内交给已经在工作的外部 AI agent。

## 首要用户

同时使用浏览器和 coding agent 的开发者。首要场景是把 GitHub PR/Issue、技术文档、代码片段或报错交给当前项目中的 Claude Code 等外部 agent。

## 产品边界

Beamhop 负责：

- 从当前 app、浏览器页面或选区抓取上下文。
- 在本机保存 Capture、provenance 与投递记录。
- 让用户预览、备注、检查来源并选择投递目标。
- 通过 MCP、Accessibility 或剪贴板把上下文交给外部 agent。
- 对失败给出可读原因和恢复动作。

Beamhop 不负责：

- 托管或选择大模型。
- 在自己的聊天框里回答问题。
- 成为通用写作、摘要或语音助手。
- 未经确认写入、发送、创建或点击。
- 在 Phase 1 建立云端账号、Web Agent 或自家 agent runtime。

## 与 Clico 的边界

Clico（原 Invoko）从屏幕上下文出发，在自己的多模型 agent/runtime 中回答并执行工作。Beamhop 与它共享"减少复制粘贴和上下文切换"的上游痛点，但不争夺同一个执行层。

Beamhop 的差异必须在产品中直接可见：

1. **External-agent-native**：交给用户真实的外部 agent、会话和项目环境。
2. **Developer workflow**：优先 PR、Issue、文档、代码和终端错误。
3. **Inspectability**：展示 app、窗口、URL、版本、抓取方法、截断与失败原因。
4. **Local-first**：Inbox 和索引留在本机，Beamhop 本身不成为模型供应商。

## MVP 成功标准

- 从按快捷键到外部 agent 获得 Capture 不超过 5 秒。
- Claude Code + 剪贴板兜底投递成功率不低于 95%。
- 浮窗 P95 出现时间不超过 300ms。
- 所有失败均有可读原因，无 silent failure。
- 连续完成至少 50 次真实 dogfood 后再决定第二个原生投递目标。

## 决策护栏

在上述使用数据形成前，冻结内置模型、自家 agent、语音、Web Agent、跨 app 自动执行、云同步、语义 Memory、OCR 和收费系统。任何新增能力必须回答：它是否让外部 agent 更快、更可靠地获得可检查的上下文？
