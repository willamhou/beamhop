"""Rebuild translated pages and apply the common static navigation."""
from importlib import import_module

notes = import_module("render-notes")
notes.main()
notes.main(english=True)
english = import_module("build-english")
for page in ("index", "handoff", "work-in-hand", "quiet-panel"):
    english.build(page)
import_module("site_nav").main()
