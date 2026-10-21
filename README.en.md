# Beamhop website and interactive essays

[中文](./README.md) · English

This is Beamhop’s static `gh-pages` website. The native application lives on [`main`](https://github.com/willamhou/beamhop/tree/main).

- [Home](./index.en.html): one entry point for the current app, native interface and design explorations.
- [Essay 03 · Respond, then understand](./quiet-panel.en.html): a lighter panel, direct prompt input and local recommendations without model dependencies.
- [Essay 02 · When work branches](./work-in-hand.en.html): handoff beside a selection and a corner shelf opened only when needed.
- [Essay 01 · Send the information](./handoff.en.html): recognize a destination and reduce repeated searching.
- [Product notes](./product-notes.en.html): decisions, evidence and hypotheses to test.
- [Native interface](./native-ui/index.html): actual AppKit / SwiftUI screenshots using fixture data.

Navigation returns to the homepage in the same language, and language links open the matching article. Legacy `index.en.html#finding`, `#sending`, `#delivery-log` and `#pocket` links forward to the original essay at its new address. The homepage’s `#essays` stays on the index.

## Maintenance

Pages load no remote scripts, fonts or analytics and can be read directly as HTML. Material, suggestions, sessions and receipts in the interactions are simulated; nothing is sent to external tools. Essay 03’s delay demonstrates background indexing, not a model call or measured performance. Its recommendations are fixed examples. Reloading resets the current page’s simulated state.

Chinese sources are `index.html`, `handoff.html`, `work-in-hand.html` and `quiet-panel.html`. English translations live in `translations/*.en.json`; do not edit generated English pages directly. Discussion sources are `product-notes.md` and `product-notes.en.md`. Essay 03 uses `quiet-panel.js` and `quiet-panel.css`; dynamic copy is in the script’s bilingual dictionary.

After editing, run `python scripts/build-site.py` to rebuild discussion pages, English pages and shared navigation in order. `scripts/site_nav.py` is the single source for navigation; `site-nav.css` provides its styles. Generated output is committed, so readers do not need a build step.

Before publishing, verify language links, legacy bookmarks, static resources, simulated handoff and recovery, narrow layouts and light/dark appearances. Report a deployment as live only after the site returns the new content. See [AGENTS.md](./AGENTS.md) for detailed constraints.

Public site: [willamhou.github.io/beamhop](https://willamhou.github.io/beamhop/index.en.html). New design explorations do not imply that the native app already implements these capabilities.
