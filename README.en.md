# Beamhop website and interactive essays

[中文](./README.md) · English

Essay 03 now keeps editing within one panel: edit selected text while retaining the original, type additional material directly, select or drop files/images and paste images. The destination menu includes project and session creation. Pocket restores whole batches or copies only materials. Draft preparation, clipboard copy and receipt confirmation remain distinct; inspecting history does not move current input.

Demo text uses the current browser tab's session storage. Files stay in memory and must be reselected after reload. App capabilities and creation are simulated. The [Swift implementation branch](https://github.com/willamhou/beamhop/tree/codex/inline-hop-workflow) uses existing text handoffs; attachments and new sessions still require manual action in the receiving app.

Run `python scripts/build-site.py` to generate English pages and scripts. Review dynamic English copy in `translations/quiet-flow.en.json`, not the generated `quiet-panel.en.js`. Run `node scripts/test-quiet-flow.cjs` with Playwright for bilingual edit, creation, restore, failure, attachment and narrow-screen paths. Set `PLAYWRIGHT_MODULE` and `CHROMIUM_EXECUTABLE` to use local dependencies.

This is Beamhop’s static `gh-pages` website. The native application lives on [`main`](https://github.com/willamhou/beamhop/tree/main).

- [Home](./index.en.html): one entry point for the current app, native interface and design explorations.
- [Essay 03 · Respond, then understand](./quiet-panel.en.html): a compact panel, mixed material, explicit instructions, multiple receiving apps and local recommendations without model dependencies.
- [Essay 02 · When work branches](./work-in-hand.en.html): handoff beside a selection and a corner shelf opened only when needed.
- [Essay 01 · Send the information](./handoff.en.html): recognize a destination and reduce repeated searching.
- [Product notes](./product-notes.en.html): decisions, evidence and hypotheses to test.
- [Native interface](./native-ui/index.html): actual AppKit / SwiftUI screenshots using fixture data.

Navigation returns to the homepage in the same language, and language links open the matching article. Legacy `index.en.html#finding`, `#sending`, `#delivery-log` and `#pocket` links forward to the original essay at its new address. The homepage’s `#essays` stays on the index.

## Maintenance

Pages load no remote scripts, fonts or analytics and can be read directly as HTML. Preset material, suggestions, sessions, receiver capabilities and receipts are simulated; nothing is sent to external tools. Essay 03 supports adding text and editing captured copies while retaining the original text and source. It also accepts files selected or dropped into the page, and pasted images, without uploading them. Its manual-copy path only attempts to write to the clipboard after a user clicks. Essay 03’s delay demonstrates background indexing, not a model call or measured performance. Its recommendations are fixed examples. Reloading resets the current page’s state, including local material, held batches and handoff records. Background handoff, draft preparation, copy and unsupported attachments are separate example paths, not claims about those apps’ interfaces.

Chinese sources are `index.html`, `handoff.html`, `work-in-hand.html` and `quiet-panel.html`. English translations live in `translations/*.en.json`; do not edit generated English pages directly. Discussion sources are `product-notes.md` and `product-notes.en.md`. Essay 03 uses `quiet-panel.js` and `quiet-panel.css`; dynamic copy is in the script’s bilingual dictionary.

After editing, run `python scripts/build-site.py` to rebuild discussion pages, English pages and shared navigation in order. `scripts/site_nav.py` is the single source for navigation; `site-nav.css` provides its styles. Generated output is committed, so readers do not need a build step.

Before publishing, verify language links, legacy bookmarks, static resources, simulated handoff and recovery, narrow layouts and light/dark appearances. Report a deployment as live only after the site returns the new content. See [AGENTS.md](./AGENTS.md) for detailed constraints.

Public site: [willamhou.github.io/beamhop](https://willamhou.github.io/beamhop/index.en.html). New design explorations do not imply that the native app already implements these capabilities.
