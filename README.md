# Beamhop 网站与交互随笔

[中文](./README.md) · [English](./README.en.md)

随笔 03 现采用同一浮层内编辑：选中文字可修改并对照原文，补充文本直接输入，支持文件/图片选择、拖放与图片粘贴。接收菜单包含新建项目和会话；Pocket 可恢复完整批次，也可只复制材料。草稿、复制与接收确认分别呈现，查看历史不移动当前输入。

演示文本保存在当前浏览器标签页的会话存储中，文件留在内存，刷新后需重新选择。所有应用能力和创建操作均为模拟。[Swift 实现分支](https://github.com/willamhou/beamhop/tree/codex/inline-hop-workflow) 使用已有文字交接通道，附件与新会话仍需在接收应用中手动添加和创建。

运行 `python scripts/build-site.py` 生成英文页面与脚本。动态英文文案在 `translations/quiet-flow.en.json`，不要直接编辑生成的 `quiet-panel.en.js`。`node scripts/test-quiet-flow.cjs` 验证两种语言的编辑、创建、恢复、失败、附件与窄屏路径，需要 Playwright；可用 `PLAYWRIGHT_MODULE` 和 `CHROMIUM_EXECUTABLE` 指定本机依赖。

本分支是 Beamhop 的 `gh-pages` 静态网站。原生应用代码位于 [`main`](https://github.com/willamhou/beamhop/tree/main)。

- [首页](./index.html)：当前应用、原生界面与设计探索的统一入口。
- [随笔 03 · 先响应，再理解](./quiet-panel.html)：轻量浮层、混合材料、明确指令、多应用接收位置，以及不依赖模型的本地推荐方向。
- [随笔 02 · 事情可以分岔](./work-in-hand.html)：选区旁交接与按需展开的角落暂存架。
- [随笔 01 · 让信息过去](./handoff.html)：识别去处与减少重复寻找。
- [产品讨论](./product-notes.html)：取舍、依据与待验证假设。
- [原生界面](./native-ui/index.zh.html)：真实 AppKit / SwiftUI 截图，使用示例数据。

网站导航统一回到同语言首页，语言切换打开对应文章。原 `index.html#finding`、`#sending`、`#delivery-log`、`#pocket` 的链接会转到原文章的新地址。首页 `#essays` 保持在目录。

## 维护

页面不加载远程脚本、字体或分析服务，打开 HTML 即可阅读。预置资料、建议、会话、接收能力和回执均为模拟，不向外部工具发送内容。随笔 03 可添加独立文本、编辑选区副本并保留原文出处，也可在本页选择、拖入文件或粘贴图片，文件不上传；手动复制路径只会在用户点击后尝试写入剪切板。随笔 03 的等待用于演示后台索引更新，不是模型调用或性能实测；其推荐记录是固定样例。页面刷新会重置本页模拟状态，包括本机材料、暂存批次和交接记录。后台交接、草稿、复制和不支持附件的连接分别演示，不代表对应应用已有这些接口。

中文源是 `index.html`、`handoff.html`、`work-in-hand.html` 和 `quiet-panel.html`。英文译文在 `translations/*.en.json`；不要直接修改生成的英文页面。讨论源是 `product-notes.md` 与 `product-notes.en.md`。随笔 03 的交互和样式在 `quiet-panel.js`、`quiet-panel.css`，动态文案在该脚本的双语词典中。

修改后运行 `python scripts/build-site.py`，依次重建讨论页面、英文页面与统一导航。导航的唯一来源是 `scripts/site_nav.py`，公用样式为 `site-nav.css`。生成结果已提交，访问网站不需要构建步骤。

发布前核对中英文互链、旧书签、静态资源、模拟交接与失败恢复，并检查窄屏和浅深色外观。只有网站实际返回新内容，才能报告已上线。详细约束见 [AGENTS.md](./AGENTS.md)。

公开地址：[willamhou.github.io/beamhop](https://willamhou.github.io/beamhop/)。新设计探索不表示原生应用已经实现了这些能力。
