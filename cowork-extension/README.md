# Beamhop desktop extension

This MCPB exposes captures already stored by Beamhop to Claude Desktop and desktop-backed Cowork sessions. Mechanism confirmed by Week 0 Spike S2 (`.mcpb` desktop extension + legacy `claude_desktop_config.json`); end-to-end install verification is still fast-follow, so Cowork delivery inside the app degrades to clipboard until then.

## Features

- Fetch a Capture by its `cap_…` id, or the latest Capture when no id is supplied.
- Read `capture://latest` and `capture://{id}` MCP resources.

The extension is read-only. It does not capture screens, modify Inbox data, or send telemetry.

## Build and install

On macOS with Swift 5.10+ and Node 20+:

```bash
./cowork-extension/build.sh
```

Then double-click `cowork-extension/dist/beamhop.mcpb`, review its permissions, and install it. The bundled server runs with no arguments and reads Beamhop's default database at `~/Library/Application Support/beamhop/inbox.sqlite`.

## Examples

- “Use `fetch_capture` with id `cap_123456` and summarize its selected text.”
- “Fetch my latest Beamhop capture and identify its source URL.”
- “Read `capture://latest` and list the provenance fields that explain how it was captured.”

## Privacy

The server reads the local Beamhop Inbox only after a tool/resource call. It has no network or telemetry code. Capture content is handled by Claude according to the user's Claude account settings when the user invokes the connector.

## Support

Open an issue in the Beamhop source repository with the Claude Desktop version, macOS version, and local error text. Never attach Capture contents unless they are safe to share.
