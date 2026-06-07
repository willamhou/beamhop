# S1 — Claude Code MCP registration

## Hypothesis
`claude mcp add` registers our stdio server one-shot; tool callable from a fresh session.

## Method
- Built a minimal newline-delimited JSON-RPC stdio MCP server (`HelloServer`).
- Registered via `claude mcp add` (discovered actual syntax — see below).
- Verified `claude mcp list` health = Connected.
- Verified tool call from a fresh non-interactive `claude -p` session.

## Initial state
- CLI: `claude` 2.1.168 at `/Users/willamhou/.nvm/versions/node/v24.16.0/bin/claude`
- `~/.claude.json` already existed (26 KB); existing servers were the 3 claude.ai remote
  connectors (Drive/Gmail/Calendar), all "Needs authentication". No prior local stdio servers.

## Evidence
- **Register command (verified):**
  ```
  claude mcp add beamhop-hello -- /abs/path/to/.build/release/HelloServer
  ```
- **Config landed in:** `~/.claude.json`, under
  `projects["/Users/willamhou/Codes/beamhop"].mcpServers["beamhop-hello"]`:
  ```json
  { "type": "stdio", "command": "/abs/.../HelloServer", "args": [], "env": {} }
  ```
- **`claude mcp list`:** `beamhop-hello: /abs/.../HelloServer - ✓ Connected`
- **Tool-call transcript:** see `transcript.txt` — returned exactly
  `SPIKE_S1_OK: this is the fixed capture payload from hello-server.`

## Conclusion
[x] **PASS** — one-shot registration + callable tool confirmed, **with two implementation
corrections** the spec must bake in (both already cost us a 30s-timeout false-fail here).

### ⚠️ Correction 1 — CLI syntax (spec §7.3 had it wrong)
The plan/spec assumed `claude mcp add <name> --transport stdio --command <bin>`.
**There is no `--command` flag in CLI 2.1.168.** Actual grammar:
```
claude mcp add [options] <name> <commandOrUrl> [args...]
# stdio command must follow `--`:
claude mcp add beamhop-hello -- <absolute-bin-path>
```
Transport defaults to stdio; `--transport` is optional. Scope defaults to `local`.

### ⚠️ Correction 2 — stdio framing + non-blocking read (would have failed silently)
1. **Framing:** MCP stdio transport is **newline-delimited JSON**, NOT LSP-style
   `Content-Length` framing (which the plan's draft `main.swift` used). Content-Length
   framing → Claude's client never parses a message → 30s connection timeout.
2. **Reading:** Swift `FileHandle.read(upToCount:)` blocks until the count is filled OR
   EOF — so a single `initialize` on a still-open stdin is never delivered, again →
   30s timeout / "✗ Failed to connect". Must use raw POSIX `read(0, …)` (or
   `availableData`) which returns as soon as any bytes arrive. The real Beamhop MCP
   server must use a streaming line reader.

   Root cause was diagnosed from `~/Library/Caches/claude-cli-nodejs/<project>/mcp-logs-beamhop-hello/*.jsonl`:
   `"connection timed out after 30000ms"`. (Useful debugging path for the real product.)

### Scope/path notes
- "local" scope is keyed by the **git repo root**, not cwd: registering from
  `spike/s1-claude-code-mcp` stored the entry under project `/Users/willamhou/Codes/beamhop`.
- The stored `command` is an **absolute path**. If the binary moves, the server breaks —
  Beamhop must register a stable install location (e.g. inside the app bundle / a fixed
  `~/Library/Application Support/Beamhop/bin` path), not a build-dir path.

## Spec patch needed (for Task 7)
- §7.3 「前置条件」: replace `claude mcp add --command` with
  `claude mcp add <name> -- <abs-bin>`; note stdio is default transport, local scope
  is git-root-keyed, and the binary path must be stable/absolute.
- §9.4 step 4①: the one-click "register" helper shells out to the `-- <abs-bin>` form.
- §14.1 S1: RESULT = PASS (with the two corrections above folded into impl notes).

## Compatibility Matrix v0 entry
```json
"claude_code": {
  "cli_version": "2.1.168",
  "mcp_add_command": "claude mcp add <name> -- <abs-bin>",
  "config_path": "~/.claude.json (projects[<git-root>].mcpServers)",
  "stdio_framing": "newline-delimited JSON (NOT Content-Length)",
  "status": "PASS"
}
```
