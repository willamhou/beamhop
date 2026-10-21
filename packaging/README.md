# macOS packaging

Run `./packaging/build-app.sh` on macOS 14+ with Swift 5.10 or newer. It builds the menu-bar app plus the MCP helper, compiles the native-messaging host with `swiftc`, assembles `dist/Beamhop.app`, validates its plist, and applies either an ad-hoc signature or `BEAMHOP_CODESIGN_IDENTITY` when supplied.

To preserve a build under acceptance, set `BEAMHOP_OUTPUT_DIR` to a fresh directory, for example `BEAMHOP_OUTPUT_DIR="$PWD/dist/engineering-preview" ./packaging/build-app.sh`. An existing output app is never overwritten. Packaging embeds allowlisted `build-info.json`, strictly verifies the signature, and keeps a unique signed-binary receipt in `<output>/build-records/`. See [trial builds and diagnostic privacy](../docs/trial-builds.md) for fields, inspection and manual verification. Existing old packages do not acquire provenance retroactively.

After copying the app to `/Applications`, register Claude Code for the current user (S1-verified form — user scope is REQUIRED, default `local` is git-root-scoped and breaks cross-project use):

```bash
claude mcp add beamhop -s user -- "/Applications/Beamhop.app/Contents/MacOS/BeamhopMCP"
```

The bundled MCP server reads the default Inbox at `~/Library/Application Support/beamhop/inbox.sqlite` when launched without `--db`.

For an unpacked Chrome extension, copy its id from `chrome://extensions` and install the native manifest:

```bash
host/install-manifest.sh \
  --host "/Applications/Beamhop.app/Contents/MacOS/beamhop-bridge" \
  --extension-id YOUR_32_CHARACTER_EXTENSION_ID \
  --browser chrome
```

Release builds must use a Developer ID signature and notarization. The ad-hoc path is for local Spike/dogfood only.
