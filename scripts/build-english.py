"""Build the English essays from reviewed translations; no runtime translation."""

from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
PAGES = ("handoff", "work-in-hand", "quiet-panel", "product-notes", "index")


def language_nav(page, english=False):
    current_zh = '' if english else ' aria-current="true"'
    current_en = ' aria-current="true"' if english else ''
    hint = "Switching language resets the demo" if english else "切换语言会重置本页演示"
    return (
        '<nav class="language-switch" aria-label="Language" title="' + hint + '">'
        f'<a href="./{page}.html" lang="zh-CN" hreflang="zh-CN"{current_zh}>中文</a>'
        '<span aria-hidden="true">/</span>'
        f'<a href="./{page}.en.html" lang="en" hreflang="en"{current_en}>English</a></nav>'
    )


def build(page):
    source = (ROOT / f"{page}.html").read_text(encoding="utf-8")
    source = re.sub(r'<nav class="language-switch".*?</nav>', '', source, flags=re.S)
    source = re.sub(r'<header\b[^>]*>.*?</header>', '<header></header>', source, count=1, flags=re.S)
    source = re.sub(r'<nav class="site-essays".*?</nav>', '', source, flags=re.S)
    translations = json.loads((ROOT / "translations" / f"{page}.en.json").read_text(encoding="utf-8"))
    if page == 'quiet-panel':
        translations.update(json.loads((ROOT / 'translations/quiet-flow.en.json').read_text(encoding='utf-8')))
    pattern = re.compile('|'.join(re.escape(key) for key in sorted(translations, key=len, reverse=True)))
    result = pattern.sub(lambda match: translations[match.group()], source)
    if page == 'quiet-panel':
        phrases = json.loads((ROOT / 'translations/quiet-flow.en.json').read_text(encoding='utf-8'))
        flow_pattern = re.compile('|'.join(re.escape(key) for key in sorted(phrases, key=len, reverse=True)))
        js = (ROOT / 'quiet-panel.js').read_text(encoding='utf-8')
        js = flow_pattern.sub(lambda match: phrases[match.group()], js)
        if re.search(r'[\u4e00-\u9fff]', js):
            raise ValueError('Untranslated flow script')
        (ROOT / 'quiet-panel.en.js').write_text(js, encoding='utf-8', newline='\n')
        result = result.replace('./quiet-panel.js', './quiet-panel.en.js')
    missing = re.findall(r'[^\n<>]*[\u4e00-\u9fff][^\n<>]*', result)
    if missing:
        raise ValueError(f"Untranslated text in {page}: {missing[:5]!r}")
    result = result.replace('lang="zh-CN"', 'lang="en"').replace('content="zh_CN"', 'content="en_US"')
    for name in PAGES:
        result = result.replace(f'href="./{name}.html"', f'href="./{name}.en.html"')
    canonical = 'https://willamhou.github.io/beamhop/' + ('' if page == 'index' else f'{page}.html')
    result = result.replace('"' + canonical + '"', '"https://willamhou.github.io/beamhop/' + page + '.en.html"')
    result = result.replace('</header>', language_nav(page, True) + '</header>', 1)
    # Chinese punctuation outside translated phrases is localized as well.
    result = result.replace('「', '“').replace('」', '”').replace('。', '.').replace('、', ', ')
    (ROOT / f"{page}.en.html").write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    for page in ("index", "handoff", "work-in-hand", "quiet-panel"):
        build(page)
