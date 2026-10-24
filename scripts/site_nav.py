"""One static navigation map for every published page; no client-side routing."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ESSAYS = ("handoff", "work-in-hand", "quiet-panel", "product-notes")
REPO = "https://github.com/willamhou/beamhop"
RELEASES = REPO + "/releases"
CI = REPO + "/actions/workflows/ci.yml"
LABELS = {
    "zh": {
        "nav_label": "站点导航",
        "home": "首页",
        "essays": "交互随笔",
        "gallery": "原生界面",
        "notes": "产品讨论",
        "series_label": "随笔目录",
        "series": ("01 · 让信息过去", "02 · 事情可以分岔", "03 · 先响应，再理解", "产品讨论"),
        "github": "GitHub",
        "releases": "版本发布",
        "ci": "构建与检查",
        "lang_label": "Language",
        "footer_tagline": "原生 macOS 菜单栏工具：捕获材料，保留来源与交代，交给外部 AI 工具。",
        "footer_site": "站点",
        "footer_project": "项目",
        "footer_language": "语言",
    },
    "en": {
        "nav_label": "Site navigation",
        "home": "Home",
        "essays": "Essays",
        "gallery": "Native UI",
        "notes": "Product notes",
        "series_label": "Essay series",
        "series": ("01 · Send the information", "02 · When work branches", "03 · Respond, then understand", "Product notes"),
        "github": "GitHub",
        "releases": "Releases",
        "ci": "Builds & checks",
        "lang_label": "Language",
        "footer_tagline": "A native macOS menu-bar utility that captures material with its source and instruction, then hands it to an external AI tool.",
        "footer_site": "Site",
        "footer_project": "Project",
        "footer_language": "Language",
    },
}


def _targets(page, english, nested):
    prefix = "../" if nested else "./"
    suffix = ".en.html" if english else ".html"
    gallery_index = "index.html" if english else "index.zh.html"
    return {
        "home": prefix + "index" + suffix,
        "gallery": prefix + "native-ui/" + gallery_index,
        "notes": prefix + "product-notes" + suffix,
        "essays": prefix + "index" + suffix + "#essays",
        "zh": (f"../{page}.zh.html" if nested else f"./{page}.html"),
        "en": ("./index.html" if nested else f"./{page}.en.html"),
        "essays_suffix": prefix,
        "essays_ext": suffix,
    }


def header(page, english=False, nested=False):
    t = LABELS["en" if english else "zh"]
    links = _targets(page, english, nested)
    current = lambda active: ' aria-current="page"' if active else ''
    markup = (
        '<header class="site-header"><div class="site-header-inner">'
        '<a class="site-brand" href="' + links["home"] + '">Beamhop</a>'
        f'<nav class="site-primary" aria-label="{t["nav_label"]}">'
        f'<a href="{links["home"]}"{current(page == "index" and not nested)}>{t["home"]}</a>'
        f'<a href="{links["essays"]}"{current(page in ESSAYS)}>{t["essays"]}</a>'
        f'<a href="{links["gallery"]}"{current(nested)}>{t["gallery"]}</a>'
        f'<a href="{links["notes"]}"{current(page == "product-notes")}>{t["notes"]}</a></nav>'
        '<nav class="site-external" aria-label="' + t["footer_project"] + '">'
        f'<a href="{REPO}">{t["github"]}&#8599;</a>'
        f'<a href="{RELEASES}">{t["releases"]}&#8599;</a></nav>'
        '<nav class="site-language" aria-label="Language">'
        f'<a href="{links["zh"]}" lang="zh-CN" hreflang="zh-CN"' + (' aria-current="true"' if not english else '') + '>中文</a>'
        '<span aria-hidden="true">/</span>'
        f'<a href="{links["en"]}" lang="en" hreflang="en"' + (' aria-current="true"' if english else '') + '>English</a></nav>'
        '</div></header>'
    )
    if page in ESSAYS:
        markup += f'<nav class="site-essays" aria-label="{t["series_label"]}"><div class="site-essays-inner">'
        for slug, label in zip(ESSAYS, t["series"]):
            markup += f'<a href="{links["essays_suffix"]}{slug}{links["essays_ext"]}"{current(page == slug)}>{label}</a>'
        markup += '</div></nav>'
    return markup


def footer(page, english=False, nested=False):
    t = LABELS["en" if english else "zh"]
    links = _targets(page, english, nested)
    sep = '<span class="site-footer-note" aria-hidden="true">·</span>'
    markup = (
        '<footer class="site-footer"><div class="site-footer-inner">'
        '<div class="site-footer-brand"><strong>Beamhop</strong><p>' + t["footer_tagline"] + '</p></div>'
        f'<nav class="site-footer-col" aria-label="{t["footer_site"]}"><p>{t["footer_site"]}</p>'
        f'<a href="{links["home"]}">{t["home"]}</a>'
        f'<a href="{links["essays"]}">{t["essays"]}</a>'
        f'<a href="{links["gallery"]}">{t["gallery"]}</a>'
        f'<a href="{links["notes"]}">{t["notes"]}</a></nav>'
        f'<nav class="site-footer-col" aria-label="{t["footer_project"]}"><p>{t["footer_project"]}</p>'
        f'<a href="{REPO}">{t["github"]}&#8599;</a>'
        f'<a href="{RELEASES}">{t["releases"]}&#8599;</a>'
        f'<a href="{CI}">{t["ci"]}&#8599;</a></nav>'
        f'<nav class="site-footer-col" aria-label="{t["footer_language"]}"><p>{t["footer_language"]}</p>'
        f'<a href="{links["zh"]}" lang="zh-CN" hreflang="zh-CN">中文</a>'
        f'<a href="{links["en"]}" lang="en" hreflang="en">English</a></nav>'
        '</div><div class="site-footer-base"><span>© 2026 Beamhop</span>'
        + sep + f'<span>{t["footer_tagline"]}</span></div></footer>'
    )
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
    # One shared site footer everywhere; drop the old minimal footer.
    # Stripping any previous site footer first keeps the build idempotent.
    source = re.sub(r'<footer class="site-footer">.*?</footer>', '', source, count=1, flags=re.S)
    source = re.sub(r'<footer class="home-end">.*?</footer>', '', source, count=1, flags=re.S)
    source = re.sub(r'</body>', footer(page, english, nested) + '</body>', source, count=1)
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
