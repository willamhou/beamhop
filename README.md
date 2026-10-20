# Beamhop 产品随笔与讨论

[中文](./README.md) · [English](./README.en.md)

两篇可以动手读的文章，以及本次产品讨论的整理。讨论如何把当前应用里的材料顺手交给已有的 agent 工作，同时保住阅读位置和思路。

- [随笔 01 · 让信息过去，人留在这里](./index.html)：第一次找去处、原地发送，以及需要时才出现的剪板。
- [随笔 02 · 事情可以分岔，思路不必散掉](./work-in-hand.html)：在文章里点选材料，选区旁直接发送，右下角按需暂存；收起后保留选择和交代。
- [产品讨论 · 先把那一下做对](./product-notes.html)：启发、产品边界、设计建议和待验证的假设。也可以直接阅读 [Markdown 原稿](./product-notes.md)。

本分支是独立的 `gh-pages` 静态发布分支，不包含 Beamhop 主应用代码。主应用位于 [`main`](https://github.com/willamhou/beamhop/tree/main)。

## 阅读与维护

用浏览器打开 HTML 文件即可阅读，无需安装依赖或构建。页面不加载远程脚本、字体或分析服务。通过本地静态服务器阅读，可以获得更完整的浏览器剪贴板体验。

每篇页面的页眉都可以切换中文和英文，文章导航会保持所选语言。切换语言会打开对应版本，并重置本页模拟交互；不会发送任何材料。

中文随笔的正文、样式和交互分别在 `index.html` 和 `work-in-hand.html` 内。英文译稿在 `translations/*.en.json`，运行 `python scripts/build-english.py` 生成对应英文页面；不要直接修改生成的英文 HTML。

讨论稿的中英文源文件分别是 `product-notes.md` 和 `product-notes.en.md`。修改后先运行 `python scripts/render-notes.py`，更新两种语言的讨论页面，再运行 `python scripts/build-english.py` 更新英文随笔。讨论页面沿用第一篇随笔的样式。两个脚本都只使用 Python 标准库；生成的 HTML 已提交，阅读时不需要运行脚本。

文字编辑、翻译和检查的方法见 [AGENTS.md](./AGENTS.md)。

所有会话、材料、模型建议、连接状态和回执均为演示数据。页面不会连接真实 agent，也不会向外部工具发送材料。交互状态只保留在当前页面，刷新后重置。

## 发布状态

本次仅将静态文件提交至 `gh-pages`。GitHub Pages 的启用由仓库管理者另行安排，未验证公开站点已经上线。未来如使用 GitHub Pages，可将发布来源设为本分支的根目录；`.nojekyll` 用于直接发布静态文件。
