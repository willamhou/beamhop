# S2 — Cowork connector mechanism: doc research

Date: 2026-06-07 · Source: web (app not installed, bundle inspection skipped — see notes.md)

## Doc landscape
- **Claude Cowork — MCP, plugins, skills, hooks** (authoritative):
  https://claude.com/docs/cowork/3p/extensions
- Get started with custom connectors using remote MCP (Claude Help Center):
  https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp
- Getting started with local MCP servers on Claude Desktop (Help Center):
  https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop
- Build a Custom Connector for Claude Cowork with the MCP TypeScript SDK (community):
  https://rebeccamdeprey.com/blog/build-custom-connector-claude-cowork

## Mechanism summary (from claude.com/docs/cowork/3p/extensions)
Cowork supports MCP servers as **remote HTTP/SSE OR local stdio command**, configured via
`managedMcpServers` (fields: `name`, `url`, `oauth`, `toolPolicy`; supports static headers,
OAuth, and a headers-helper executable for short-lived tokens). The in-app config window has
a "Test this connection" button.

Two registration audiences:
- **End users**: can install **local desktop extensions (`.mcpb`)** from the *Connectors*
  settings page — *if enabled by admin*. End users **cannot** add remote MCP servers.
- **Admins**: provision remote servers via `managedMcpServers` or org plugins.

## ⚠️ Source conflict (flag for runtime verification)
One Help-Center summary states local `claude_desktop_config.json` MCP servers "aren't
available in Cowork or claude.ai", while the Cowork extensions doc says local stdio IS
supported via `managedMcpServers` / `.mcpb`. Likely the distinction is:
`claude_desktop_config.json` (the old Claude **Desktop** path) ≠ Cowork's `managedMcpServers`
/ `.mcpb` path. Must confirm on a real Cowork install which path actually works for an
unmanaged personal account (no org admin).

## Implication for Beamhop MVP
- Beamhop's likely integration = ship the MCP server as a **`.mcpb` desktop extension**
  the user installs from Cowork → Connectors. This is heavier than Claude Code's
  `claude mcp add <name> -- <bin>` one-shot (must build/sign a `.mcpb` bundle; may be
  admin-gated on managed devices).
- Remote-connector path is out for MVP (needs Anthropic-side OAuth provisioning + a hosted URL).

## Open questions for the live test (once Claude is installed)
1. On a personal (non-org) account, can an end user install a `.mcpb` without admin enablement?
2. What does a minimal `.mcpb` for our stdio server look like (manifest format, packaging cmd)?
3. Does the same `HelloServer` stdio binary from S1 work unchanged inside a `.mcpb`?
