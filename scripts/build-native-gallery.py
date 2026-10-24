"""Publish verified native fixture images with bilingual descriptions."""
from pathlib import Path
import argparse
import html
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]


def build(evidence, sha, run):
    reports = {}
    assets = ROOT / "native-ui/assets"
    assets.mkdir(exist_ok=True)
    scenarios = ("capture", "capture-create-project", "pocket-drafts", "pocket-recovery")
    for locale in ("en", "zh-Hans"):
        for theme in ("light", "dark"):
            key = f"{locale}-{theme}"
            report_path = evidence / f"report-{key}.json"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            assert report["checks"] and all(check["passed"] for check in report["checks"]), key
            reports[key] = report
            shutil.copyfile(report_path, assets / report_path.name)
            for snapshot in report["snapshots"]:
                shutil.copyfile(evidence / snapshot["file"], assets / snapshot["file"])
            for scenario in scenarios:
                name = f"{scenario}-{key}.png"
                assert any(s["file"] == name for s in report["snapshots"]), name
                shutil.copyfile(evidence / name, assets / name)
    total = sum(len(r["checks"]) for r in reports.values())
    attrs = " ".join(f'data-checks-{key}="{len(r["checks"])}"' for key, r in reports.items())
    for chinese in (False, True):
        locale = "zh-Hans" if chinese else "en"
        language = "zh-CN" if chinese else "en"
        title = "原生 macOS 界面 · Beamhop" if chinese else "Native macOS interface · Beamhop"
        headline = "在一个浮层里，把事情交代清楚。" if chinese else "Make the handoff in one panel."
        intro = ("修改材料、补充文字，写下给 Agent 的指令。项目帮助归类，应用与当前窗口说明实际去处。"
                 if chinese else "Edit materials, add text and write instructions for the agent. Projects organize context; the app and current window identify the actual destination.")
        cards = [
            ("指令与材料，都能直接改。", "原始选区留作对照；修改后的文字才用于交接。Return 换行，⌘Return 继续。"),
            ("新建时，留住手上的内容。", "项目在本地创建；新会话需在接收应用中创建，当前输入不会被清空。"),
            ("Pocket 保存整份草稿。", "材料、指令和接收方一起保留。恢复前先暂存当前输入，也可仅添加材料。"),
            ("交接备份可以恢复。", "草稿已准备不代表已发送。恢复的是交接时的副本，原应用里的后续编辑不会同步。"),
        ] if chinese else [
            ("Edit instructions and material directly.", "Keep the source for comparison; hand off the edited text. Return inserts a line break; Command-Return continues."),
            ("Create without losing your input.", "Projects are created locally. New sessions are created in the receiving app while the current draft is retained."),
            ("Pocket keeps the complete draft.", "Materials, instructions and destination stay together. Restore after saving current input, or add materials only."),
            ("Restore a handoff backup.", "A prepared draft is not a sent message. Recovery restores the handoff copy; later edits in the receiving app are not synchronized."),
        ]
        markup = ""
        for i, (scenario, (heading, body)) in enumerate(zip(scenarios, cards)):
            image = f"./assets/{scenario}-{locale}-light.png"
            width = 480 if scenario.startswith("capture") else 390
            markup += f'<section class="card"><span class="step">0{i+1} / BEAMHOP</span><h2>{heading}</h2><p>{body}</p><a class="image-link" data-scenario="{scenario}" href="{image}"><img class="screenshot" src="{image}" alt="{heading}" width="{width}" loading="lazy"></a></section>'
        validation = (f"四种语言／外观组合共 {total} 项原生界面断言通过。这 16 张截图来自 SwiftUI / AppKit 实际运行的界面与测试材料。"
                      if chinese else f"All {total} native UI assertions passed across four language/appearance combinations. These 16 screenshots come from the running SwiftUI / AppKit interface with fixture data.")
        limitation = ("当前通道支持文字草稿或剪贴板交接。文件和图片可保存在 Pocket，但需手动添加到接收应用。没有已验证的外部会话地址或后台接收回执。真实登录后的应用、VoiceOver、多屏及全屏场景仍需设备验证。"
                      if chinese else "Current connections prepare text drafts or clipboard content. Files and images can be kept in Pocket but must be added manually in the receiving app. External session addresses and background receipt confirmation are not verified. Signed-in applications, VoiceOver, multiple displays and fullscreen still need device validation.")
        count = len(reports[f"{locale}-light"]["checks"])
        page = f'''<!doctype html>
<html lang="{language}" data-appearance="light" {attrs}><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><meta name="description" content="{html.escape(intro, quote=True)}">
<link rel="icon" href="../favicon.svg"><link rel="stylesheet" href="./gallery.css">
<script src="./gallery.js" defer></script><link rel="stylesheet" href="../site-nav.css">
</head><body><div class="wrap"><header></header><main>
<div class="intro"><div class="eyebrow">BEAMHOP · NATIVE macOS</div><h1>{headline}</h1><p>{intro}</p><div class="eyebrow">2026-10-21 · {html.escape(reports[f"{locale}-light"]["os"])}</div></div>
<div class="controls"><div class="segmented" role="group" aria-label="{"截图语言" if chinese else "Screenshot language"}"><button data-locale="en" aria-pressed="{str(not chinese).lower()}">English</button><button data-locale="zh-Hans" aria-pressed="{str(chinese).lower()}">中文</button></div><div class="segmented" role="group" aria-label="{"外观" if chinese else "Appearance"}"><button data-theme="light" aria-pressed="true">{"浅色" if chinese else "Light"}</button><button data-theme="dark" aria-pressed="false">{"深色" if chinese else "Dark"}</button></div><p id="view-status" class="status" aria-live="polite">{count} / {count}</p></div>
<div class="grid">{markup}</div>
<section class="evidence"><div><h2>{"实际运行的验证" if chinese else "Verification from the running app"}</h2><p>{validation}</p><p><a id="report" href="./assets/report-{locale}-light.json">{"检查报告" if chinese else "Check report"}</a> · <a href="https://github.com/willamhou/beamhop/actions/runs/{run}">{"构建与全部检查" if chinese else "Build and all checks"}</a></p></div><div><h2>{"当前接入范围" if chinese else "Current integration scope"}</h2><p>{limitation}</p></div></section>
<p class="foot"><a href="https://github.com/willamhou/beamhop/tree/{sha}">Swift · {sha[:7]}</a><a href="../quiet-panel{"" if chinese else ".en"}.html">{"交互演示" if chinese else "Interactive demo"}</a></p></main></div></body></html>
'''
        (ROOT / ("native-ui/index.zh.html" if chinese else "native-ui/index.html")).write_text(page, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run", required=True)
    args = parser.parse_args()
    build(args.evidence, args.sha, args.run)
