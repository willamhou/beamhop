# S1 — Claude Code MCP registration

Status: **NOT RUN**

## macOS protocol

1. `swift build -c release --product beamhop-mcp`
2. Record `claude --version` and `claude mcp add --help`.
3. Register with the syntax shown by the installed CLI. Current expected form:
   `claude mcp add --transport stdio --scope user beamhop -- "$PWD/.build/release/beamhop-mcp"`
4. Start a fresh Claude Code session and call `fetch_capture` after inserting a fixture capture.
5. Save exact registration output and tool-call transcript here.
6. Remove only the test registration: `claude mcp remove beamhop`.

## Evidence

- CLI version: not run
- Exact registration command: not run
- Config path: not run
- Fresh-session tool call: not run
- PATH-missing fallback: not run

## Conclusion

- [ ] PASS
- [ ] FAIL
- [x] NOT RUN
