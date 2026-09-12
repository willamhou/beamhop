# S2 — Cowork connector research

Documentation review: **COMPLETE 2026-08-23**. Cowork/Desktop app test: **NOT RUN**.

The June plan's premise is now partly stale. Current official documentation says:

- Local MCPB desktop extensions are one-click `.mcpb` packages, use stdio, run offline, and need no OAuth.
- Cowork can use local connectors/plugins through the Claude Desktop app; cloud-only sessions cannot run a local server without the desktop app.
- Legacy `claude_desktop_config.json` remains the wrong integration mechanism for Cowork. Beamhop therefore packages its server as MCPB instead.

Sources reviewed:

- https://claude.com/docs/connectors/building/mcpb
- https://support.claude.com/en/articles/15520349-use-claude-cowork-on-web-desktop-and-mobile
- https://support.claude.com/en/articles/11725091-when-to-use-desktop-and-web-connectors
- https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md

The implementation is under `cowork-extension/`. S2 still cannot be marked PASS until a built bundle is installed in Claude Desktop and a Cowork session calls `fetch_capture` successfully.

Still record on macOS:

- Cowork/Claude app version and bundle id
- Official documentation URLs and access date
- Whether local MCP/connectors are supported in Cowork
- Registration steps, OAuth/backend requirements, and whether one-shot automation is possible
- A fixed-payload connector transcript if a public SDK/path exists

Do not infer connector support from Claude Desktop legacy configuration.
