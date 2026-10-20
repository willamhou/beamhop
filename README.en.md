# Beamhop product essays and notes

[中文](./README.md) · English

Two interactive essays and notes from the product discussion. They explore sending material from the current app to an existing agent session while keeping the reader’s place and train of thought.

- [Essay 01 · Send the information. Stay where you are.](./index.en.html): finding a destination for the first time, sending from the source app, and keeping a shelf available when needed.
- [Essay 02 · Work can branch. Keep your train of thought.](./work-in-hand.en.html): select passages in the article, send beside the selection, and save in a corner shelf that retains selections and notes when collapsed.
- [Product notes · Get the handoff right.](./product-notes.en.html): ideas, product boundaries, design recommendations, and hypotheses to test. The [Markdown source](./product-notes.en.md) is also available.

This is a separate `gh-pages` branch for static publishing. The Beamhop application lives on [`main`](https://github.com/willamhou/beamhop/tree/main).

## Reading and maintenance

Open an HTML file in a browser; no installation or build is required to read it. The pages load no remote scripts, fonts, or analytics. A local static server gives the browser clipboard feature a more complete environment.

Use the language links in each page header to open the same article in Chinese or English. Series links stay in the chosen language. Opening another language reloads that version and resets the simulated interaction; it does not send anything.

The Chinese essays keep their prose, styles, and interactions in `index.html` and `work-in-hand.html`. Their reviewed English translations are in `translations/*.en.json`; `python scripts/build-english.py` generates the matching English HTML. Do not edit generated English pages directly.

The discussion sources are `product-notes.md` and `product-notes.en.md`. Run `python scripts/render-notes.py` to update both HTML versions, then run `python scripts/build-english.py` to update the English essays. The discussion pages reuse the first essay’s styles. Both scripts use only the Python standard library. Generated pages are committed, so readers need not run them.

All sessions, material, model suggestions, connection states, and receipts are simulated. The pages do not connect to real agents or send material to external tools. Demo state lasts only in the current page and resets on reload.

See [AGENTS.md](./AGENTS.md) for editing, translation, and verification instructions.

## Publishing status

The static files are committed to `gh-pages`. A repository administrator will arrange GitHub Pages separately; the public site has not been verified as live. If Pages is enabled later, use this branch’s root directory as its source. `.nojekyll` allows the static files to be published directly.
