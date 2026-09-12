# Beamhop Week 0 Spike

这里的代码都是可抛弃的集成探针，用于验证 MVP 设计稿 §14 的六个假设。探针必须在 macOS 15+ 实机运行；Linux 只能检查文件和纯协议逻辑，不能产生 Accessibility、Cocoa 浮窗或桌面 app 兼容性证据。

运行顺序与验收标准以 [`docs/superpowers/plans/2026-06-03-week-0-spike.md`](../docs/superpowers/plans/2026-06-03-week-0-spike.md) 为准：

- S1：Claude Code MCP 注册与工具调用
- S2：Claude Cowork connector 机制
- S3：ChatGPT Desktop AX 粘贴稳定性
- S4：Chrome native messaging 全链路
- S5：全屏、Stage Manager、多显示器浮窗
- S6：八个目标 app 的 AX 选中文本

证据必须写进各目录的 `notes.md`，没有真机输出时保持 `NOT RUN`，不得用推断填写 PASS。全部完成后再生成 `results.md`、回写 spec V2.1。

