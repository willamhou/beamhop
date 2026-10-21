"""One static navigation map for every published page; no client-side routing."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ESSAYS = ("handoff", "work-in-hand", "quiet-panel", "product-notes")
LABELS = {
    "zh": ("首页", "交互随笔", "原生界面", "站点导航", "随笔目录", "01 · 让信息过去", "02 · 事情可以分岔", "03 · 先响应，再理解", "产品讨论"),
    "en": ("Home", "Interactive essays", "Native UI", "Site navigation", "Essay series", "01 · Send the information", "02 · When work branches", "03 · Respond, then understand", "Product notes"),
}


def header(page, english=False, nested=False):
    labels = LABELS["en" if english else "zh"]
    prefix = "../" if nested else "./"
    suffix = ".en.html" if english else ".html"
    home = prefix + "index" + suffix
    gallery = prefix + "native-ui/" + ("index.html" if english else "index.zh.html")
    zh = "./index.zh.html" if nested else f"./{page}.html"
    en = "./index.html" if nested else f"./{page}.en.html"
    current = lambda active: ' aria-current="page"' if active else ''
    markup = (
        '<header class="site-header"><a class="site-brand" href="' + home + '">Beamhop</a>'
        f'<nav class="site-primary" aria-label="{labels[3]}">'
        f'<a href="{home}"{current(page == "index" and not nested)}>{labels[0]}</a>'
        f'<a href="{home}#essays"{current(page in ESSAYS)}>{labels[1]}</a>'
        f'<a href="{gallery}"{current(nested)}>{labels[2]}</a></nav>'
        '<nav class="site-language" aria-label="Language">'
        f'<a href="{zh}" lang="zh-CN" hreflang="zh-CN"' + (' aria-current="true"' if not english else '') + '>中文</a>'
        '<span aria-hidden="true">/</span>'
        f'<a href="{en}" lang="en" hreflang="en"' + (' aria-current="true"' if english else '') + '>English</a></nav></header>'
    )
    if page in ESSAYS:
        markup += f'<nav class="site-essays" aria-label="{labels[4]}">'
        for slug, label in zip(ESSAYS, labels[5:]):
            markup += f'<a href="{prefix}{slug}{suffix}"{current(page == slug)}>{label}</a>'
        markup += '</nav>'
    return markup


def apply(page, english=False, nested=False):
    filename = ("native-ui/index.html" if english else "native-ui/index.zh.html") if nested else page + (".en.html" if english else ".html")
    path = ROOT / filename
    source = path.read_text(encoding="utf-8")
    # Replace the whole header, including any older language/series navigation.
    source = re.sub(r'<header\b[^>]*>.*?</header>', lambda _: header(page, english, nested), source, count=1, flags=re.S)
    # A generated header may already be followed by an old series row.
    if page in ESSAYS:
        rows = list(re.finditer(r'<nav class="site-essays".*?</nav>', source, re.S))
        for row in reversed(rows[1:]):
            source = source[:row.start()] + source[row.end():]
    source = re.sub(r'<nav class="site-reading\b.*?</nav>', '', source, flags=re.S)
    href = '../site-nav.css' if nested else './site-nav.css'
    if 'href="' + href + '"' not in source:
        source = source.replace('</head>', f'<link rel="stylesheet" href="{href}">\n</head>', 1)
    path.write_text(source, encoding="utf-8", newline="\n")


def main():
    for page in ("index",) + ESSAYS:
        for english in (False, True):
            apply(page, english)
    for english in (False, True):
        apply("native-ui", english, nested=True)


if __name__ == "__main__":
    main()
