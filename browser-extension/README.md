# Beamhop Chrome Extension

This is a Manifest V3 extension for Chrome, Arc, Brave, Edge, and Chromium. It captures only after the user clicks the popup or the Beamhop desktop app requests `browser.captureCurrentTab`.

HTTP(S) page access is declared as `optional_host_permissions`, not granted at install time. The first popup capture requests it from a direct user gesture. Until granted, desktop-triggered capture returns `PERMISSION_REQUIRED`; it does not silently read a page or return misleading partial data.

Captured fields include selected text, URL, title, canonical URL, language, meta description, a Mozilla Readability body converted to Markdown-like blocks, and GitHub-specific PR, issue, repository, and code metadata. A lightweight DOM extractor is retained only as a reported fallback. Body fields are capped at 100,000 characters and report `truncated: true` when capped. The vendored Readability runtime is built locally and the extension never loads extraction code from the network.

## Develop

1. Run `npm ci && npm run build` in this directory.
2. Open `chrome://extensions`, enable Developer mode, and choose **Load unpacked**.
3. Select this `browser-extension` directory.
4. Copy the generated extension id.
5. Build `BeamhopNativeHost`, then install its manifest with `Sources/BeamhopNativeHost/install-manifest.sh`.
6. Reload the extension after changing its manifest or service worker.

Chrome internal pages, the Chrome Web Store, and other non-HTTP(S) pages cannot be scripted. The popup reports this as a capture error instead of silently returning partial content.

## Protocol tests

```bash
npm test --prefix browser-extension
```

The tests exercise UTF-8/base64 chunking beyond 1 MiB, the enforced browser-to-host physical frame limit, out-of-order and duplicate chunks, metadata/checksum corruption, timeout cleanup, and retry with a new transfer id.
