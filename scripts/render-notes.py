"""Render the discussion notes using the essays' existing visual style.

Uses only Python's standard library. The source deliberately uses a small
Markdown subset: headings, paragraphs, unordered lists, bold text, and links.
The committed HTML is ready to publish; no build is required to read the site.
"""

from html import escape
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "product-notes.md"


def inline(text):
    text = escape(text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)


def render_body(blocks):
    output = []
    for index, block in enumerate(blocks):
        if block.startswith("## "):
            output.append("<h2>" + inline(block[3:]) + "</h2>")
        elif block.startswith("- "):
            items = ["<li>" + inline(line[2:]) + "</li>" for line in block.splitlines()]
            output.append("<ul>" + "".join(items) + "</ul>")
        else:
            cls = ' class="lead"' if index == 0 else ""
            output.append("<p" + cls + ">" + inline(block.replace("\n", " ")) + "</p>")
    return "\n".join(output)


def main():
    blocks = SOURCE.read_text(encoding="utf-8").strip().split("\n\n")
    title = blocks[0].removeprefix("# ")
    subtitle = blocks[1]
    index = (ROOT / "index.html").read_text(encoding="utf-8")
    style = re.search(r"<style>(.*?)</style>", index, re.S).group(1)
    nav = (
        '<nav class="site-series" aria-label="产品随笔导航">'
        '<a href="./index.html">随笔 01</a>'
        '<a href="./work-in-hand.html">随笔 02</a>'
        '<a href="./product-notes.html" aria-current="page">产品讨论</a></nav>'
    )
    html = f'''<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="description" content="Beamhop 本次产品讨论的启发、边界和取舍：原地路由优先，让剪板按需出现，用直觉和真实交接来裁决功能。">
<meta property="og:type" content="article"><meta property="og:locale" content="zh_CN">
<meta property="og:title" content="{escape(title)} · Beamhop 产品讨论">
<meta property="og:description" content="保留判断力度，分清设计假设。让信息抵达正在进行的工作，也让人留在原来的思路里。">
<meta property="og:url" content="https://willamhou.github.io/beamhop/product-notes.html">
<link rel="canonical" href="https://willamhou.github.io/beamhop/product-notes.html">
<link rel="icon" href="./favicon.svg" type="image/svg+xml">
<title>{escape(title)} · Beamhop 产品讨论</title>
<style>{style}
.notes-hero h1 span{{font-size:clamp(24px,4vw,36px);line-height:1.5}}
.notes-prose h2{{margin-top:55px;margin-bottom:20px;font-size:24px;line-height:1.6}}
.notes-prose ul{{padding-left:23px;margin:22px 0}}.notes-prose li{{font-size:15px;line-height:2;margin:12px 0;padding-left:4px}}
.notes-prose .lead{{font-size:19px}}.notes-footer{{margin-top:50px;border-top:1px solid var(--line);padding-top:20px;color:var(--muted);font-size:12px;line-height:1.9}}
@media(max-width:540px){{.notes-prose h2{{font-size:22px}}.notes-prose li{{font-size:14px}}}}
</style></head><body>
<header class="masthead"><div class="brand"><span class="star" aria-hidden="true">✦</span>Beamhop <small>/ 产品讨论与取舍</small></div>{nav}</header>
<main><div class="prose hero notes-hero"><div class="eyebrow">用人的动作，裁决功能</div><h1>{escape(title)}<span>产品讨论与取舍</span></h1><p class="deck">把这次对话留下的启发，变成可以继续检验的判断。</p><div class="byline">{escape(subtitle)}</div></div>
<article class="prose notes-prose">{render_body(blocks[2:])}</article>
<footer class="prose notes-footer">这是本次讨论的整理稿，包含明确的产品边界、设计建议和待验证假设。<br><a href="./product-notes.md">查看 Markdown 原稿</a></footer>
<nav class="site-reading prose" aria-label="继续阅读"><a href="./index.html">01 · 让信息过去</a><a href="./work-in-hand.html">02 · 事情可以分岔</a><a href="./product-notes.html" aria-current="page">讨论 · 先把那一下做对</a></nav>
</main></body></html>
'''
    (ROOT / "product-notes.html").write_text(html, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
