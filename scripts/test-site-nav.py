"""Regression checks for published navigation and reproducible static builds."""
from html.parser import HTMLParser
from importlib import import_module
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import unquote, urlsplit

import site_nav

ROOT = Path(__file__).resolve().parents[1]
PAGES = tuple(
    page + suffix
    for page in ("index",) + site_nav.ESSAYS
    for suffix in (".html", ".en.html")
) + ("native-ui/index.html", "native-ui/index.zh.html")
GALLERY_SHA = "81f23a6cd2abb81ace2463a526340b71a0ed1209"


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links = []
        self.headers = []
        self.footers = []
        self.ids = set()
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "href" in attrs:
            self.links.append(attrs)
        if tag == "header":
            self.headers.append(attrs)
        if tag == "footer":
            self.footers.append(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])


class SiteNavigationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="beamhop-site-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = (Path(cls.temporary.name) / "site").resolve()
        shutil.copytree(ROOT, cls.root, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        cls.before = {name: (ROOT / name).read_bytes() for name in PAGES}
        cls.build()
        cls.first = {name: (cls.root / name).read_bytes() for name in PAGES}
        cls.build()

    @classmethod
    def build(cls):
        subprocess.run([sys.executable, "scripts/build-site.py"], cwd=cls.root, check=True)

    def test_all_pages_have_one_shared_header_and_footer(self):
        for name in PAGES:
            with self.subTest(page=name):
                page = Page((self.root / name).read_text(encoding="utf-8"))
                self.assertEqual(page.headers, [{"class": "site-header"}])
                self.assertEqual(page.footers.count({"class": "site-footer"}), 1)
                if name.startswith("native-ui/"):
                    self.assertEqual(page.footers, [{"class": "site-footer"}])

    def test_relative_links_and_fragments_resolve(self):
        for name in PAGES:
            path = self.root / name
            for link in Page(path.read_text(encoding="utf-8")).links:
                url = urlsplit(link["href"])
                if url.scheme or url.netloc:
                    continue
                with self.subTest(page=name, href=link["href"]):
                    target = (path.parent / unquote(url.path)).resolve() if url.path else path
                    self.assertTrue(target.is_relative_to(self.root))
                    self.assertTrue(target.is_file(), link["href"])
                    if url.fragment and target.suffix == ".html":
                        self.assertIn(unquote(url.fragment), Page(target.read_text(encoding="utf-8")).ids)

    def test_matching_language_links_in_header_and_footer(self):
        for name in PAGES:
            if name.startswith("native-ui/"):
                targets = {"zh-CN": "native-ui/index.zh.html", "en": "native-ui/index.html"}
            else:
                stem = name.removesuffix(".en.html").removesuffix(".html")
                targets = {"zh-CN": stem + ".html", "en": stem + ".en.html"}
            path = self.root / name
            page = Page(path.read_text(encoding="utf-8"))
            for language, expected in targets.items():
                with self.subTest(page=name, language=language):
                    links = [link for link in page.links if link.get("hreflang") == language]
                    self.assertEqual(len(links), 2)
                    for link in links:
                        self.assertEqual((path.parent / link["href"]).resolve(), self.root / expected)

    def test_build_is_idempotent_and_published_pages_are_current(self):
        for name in PAGES:
            with self.subTest(page=name):
                self.assertEqual(self.first[name], (self.root / name).read_bytes())
                self.assertEqual(self.before[name], self.first[name])

    def test_gallery_retains_evidence_and_demo_links(self):
        for name, locale, demo in (("native-ui/index.html", "en", "quiet-panel.en.html"),
                                   ("native-ui/index.zh.html", "zh-Hans", "quiet-panel.html")):
            with self.subTest(page=name):
                source = (self.root / name).read_text(encoding="utf-8")
                links = {link["href"] for link in Page(source).links}
                self.assertIn(site_nav.REPO + "/tree/" + GALLERY_SHA, links)
                self.assertIn("./assets/report-" + locale + "-light.json", links)
                self.assertIn(site_nav.REPO + "/actions/runs/39581913976", links)
                self.assertIn("../" + demo, links)
                self.assertLess(source.index("Swift · 81f23a6"), source.index("</main>"))

    def test_legacy_gallery_footer_is_moved_into_main(self):
        with tempfile.TemporaryDirectory(prefix="beamhop-old-gallery-") as directory:
            root = Path(directory)
            (root / "native-ui").mkdir()
            path = root / "native-ui/index.html"
            path.write_text('<html><head></head><body><header></header><main>Evidence</main>'
                            '<footer class="foot"><a href="https://example.com/source">Swift source</a>'
                            '</footer></body></html>', encoding="utf-8")
            with patch.object(site_nav, "ROOT", root):
                site_nav.apply("native-ui", english=True, nested=True)
            source = path.read_text(encoding="utf-8")
            self.assertEqual(Page(source).footers, [{"class": "site-footer"}])
            self.assertLess(source.index("Swift source"), source.index("</main>"))

    def test_fresh_gallery_generation_has_one_footer(self):
        gallery = import_module("build-native-gallery")
        with tempfile.TemporaryDirectory(prefix="beamhop-new-gallery-") as directory:
            root = Path(directory)
            (root / "native-ui").mkdir()
            with patch.object(gallery, "ROOT", root), patch.object(site_nav, "ROOT", root):
                gallery.build(ROOT / "native-ui/assets", GALLERY_SHA, "39581913976")
                for english in (False, True):
                    site_nav.apply("native-ui", english, nested=True)
            for name in ("native-ui/index.html", "native-ui/index.zh.html"):
                source = (root / name).read_text(encoding="utf-8")
                self.assertEqual(Page(source).footers, [{"class": "site-footer"}])
                self.assertLess(source.index("Swift · 81f23a6"), source.index("</main>"))


if __name__ == "__main__":
    unittest.main()
