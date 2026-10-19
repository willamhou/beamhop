# 让信息过去，人留在这里

Beamhop 的可交互产品随笔。讨论如何认出已有的 agent 会话、在来源应用中直接路由摘抄，以及在还没确定去处时临时保存材料。

**页面地址：** https://willamhou.github.io/beamhop/

本分支是独立的 `gh-pages` 静态发布分支，不包含 Beamhop 主应用的代码。主应用位于 [`main`](https://github.com/willamhou/beamhop/tree/main)。

## 本地阅读与维护

直接用浏览器打开 `index.html` 即可。页面不需要安装依赖或构建，也不加载远程脚本、字体或分析服务。手动复制功能需要浏览器允许剪贴板访问；通过本地服务器或 GitHub Pages 阅读可以获得更完整的体验。

正文、样式和交互均在 `index.html` 内。修改并推送到本分支后，GitHub Pages 会重新发布。

所有会话、材料、连接状态和回执均为演示数据。页面不会连接真实 agent，也不会向外部工具发送材料。交互状态仅保留在当前页面内，刷新后重置。

## GitHub Pages 配置

仓库 **Settings → Pages → Build and deployment**：

- Source：**Deploy from a branch**
- Branch：**gh-pages**
- Folder：**/ (root)**

保存后等待 Pages 部署完成，即可通过上方地址访问。`.nojekyll` 让 GitHub 直接发布本分支的静态文件。
