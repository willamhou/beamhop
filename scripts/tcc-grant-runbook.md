# Beamhop Accessibility 授权 — 一次性 runbook（机器在席时执行）

> 背景：ad-hoc 签名每次重打包都会改变 cdhash，TCC 授权随之失效（PROGRESS §6）。
> 现在构建已改用稳定的自签名身份 "Beamhop Sign"（`scripts/setup-dev-signing.sh`），
> TCC 授权锚定到证书而非 cdhash——**只需授权一次，以后所有重打包都不再掉授权**。
> 本 runbook 把这次授权做成自动化：解锁屏幕后执行，全程无需手动点击。
>
> ⚠️ 前置：屏幕必须处于解锁状态（锁屏时所有 GUI 窗口对后台自动化不可见，这是
> macOS 的安全设计，无法绕过）。确认方式：终端 `screencapture -x /tmp/s.png` 截出来
> 不是黑屏/锁屏壁纸。

## 步骤

### 0. 确保应用在运行（让 TCC 列表里出现 Beamhop 条目）

```bash
open /Users/leo/Documents/Kimi/Workspaces/beamhop/dist/Beamhop.app
sleep 3
pgrep -fl Beamhop | head -2    # 确认进程在
```

应用首次请求 Accessibility 时会在 TCC 数据库创建条目；首次运行还会弹出系统授权
对话框（"Beamhop 想要控制这台电脑" → 点"打开系统设置"或直接出现在列表中）。

### 1. 用 kimi-cu 打开 TCC 面板

经由 Kimi Work 的 kimi-cu 插件（后台执行，不抢鼠标键盘）：

1. `list_apps` 找到 `com.apple.systempreferences`（系统设置）。
2. `get_app_state`（app: `com.apple.systempreferences`）观察当前窗口。
3. 点击 "隐私与安全性"（Privacy & Security）→ 滚动找到 "设备控制和数据访问"
   （macOS 26 里 Accessibility 合并在这个面板，PROGRESS §6 有记录）。
4. 在应用列表中找到 "Beamhop"：若开关是关的，点一下打开；若列表里没有，
   回到步骤 0 确认应用已启动并发起过权限请求。

### 2. 验证授权生效（无需人眼）

```bash
# 合成按下 ⌘⇧Space，然后对比前后屏幕差异确认面板弹出
screencapture -x /tmp/before.png
osascript -e 'tell application "System Events" to key code 49 using {command down, shift down}'
sleep 1
screencapture -x /tmp/after.png
# 有像素差异 = 面板弹出 = 热键 + 激活链路 OK；再用 DB 验证 capture 落库：
sqlite3 "$HOME/Library/Application Support/beamhop/inbox.sqlite" \
  "SELECT id, app_name, capture_duration_ms FROM captures ORDER BY created_at DESC LIMIT 1;"
# capture_duration_ms > 0 且 app_name 不是 Beamhop = AX 捕获链路真正通
```

### 3. 验证"重打包不再掉授权"（本方案的核心收益）

```bash
cd /Users/leo/Documents/Kimi/Workspaces/beamhop
rm -rf dist/Beamhop.app && ./packaging/build-app.sh >/dev/null
osascript -e 'quit app "Beamhop"' 2>/dev/null; sleep 1
open dist/Beamhop.app
# 重复步骤 2 的合成按键 + DB 检查——若 capture 仍正常落库，授权已锚定到证书
```

## 故障排查

- **列表里没有 Beamhop**：应用启动时会通过 `PermissionService` 主动请求；若仍没有，
  运行 `tccutil reset Accessibility com.beamhop.app` 后重启应用重新请求。
- **点击开关无反应**：macOS 26 偶发 TCC 面板刷新延迟，重新 `get_app_state` 再点一次。
- **想完全从头来**：`tccutil reset All com.beamhop.app`，然后重新走本 runbook。

## 备注

- 开发签名钥匙串的密码必须由使用者私下提供；仓库不提供默认密码。
- 登录钥匙串里遗留了 2026-10-19 第一次尝试的孤儿证书/私钥（"Beamhop Dev"、
  "Beamhop Sign" 各一份，无 partition list，使用时**会**弹授权框）。删除需要图形界面：
  钥匙串访问 → 登录 → 证书/密钥，搜 "Beamhop"，删除即可（不影响专用钥匙串里的正式身份）。
