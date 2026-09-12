# macOS packaging

Run `./packaging/build-app.sh` on macOS 14+ with Swift 5.10 or newer. It builds the menu-bar app plus the MCP and Chrome native-host helpers, assembles `dist/Beamhop.app`, validates its plist, and applies either an ad-hoc signature or `BEAMHOP_CODESIGN_IDENTITY` when supplied.

After copying the app to `/Applications`, register Claude Code for the current user:

```bash
claude mcp add --transport stdio --scope user beamhop -- "/Applications/Beamhop.app/Contents/MacOS/beamhop-mcp"
```

For an unpacked Chrome extension, copy its id from `chrome://extensions` and install the native manifest:

```bash
Sources/BeamhopNativeHost/install-manifest.sh \
  --host "/Applications/Beamhop.app/Contents/MacOS/beamhop-native-host" \
  --extension-id YOUR_32_CHARACTER_EXTENSION_ID \
  --browser chrome
```

Release builds must use a Developer ID signature and notarization. The ad-hoc path is for local Spike/dogfood only.
