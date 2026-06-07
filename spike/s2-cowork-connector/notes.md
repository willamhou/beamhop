# S2 — Cowork connector mechanism

## Status: 🚧 RESEARCH DONE, RUNTIME BLOCKED — Claude (Cowork) not installed
No `Claude.app` in `/Applications`, no `~/Library/Containers/*claude*`, no Cowork app
support dirs. Bundle/string inspection (plan Steps 6.2–6.3) deferred until installed.
Doc research is complete — see `research.md`.

### To unblock
```bash
brew install --cask claude
# then inspect the bundle + try a minimal .mcpb connector:
defaults read "/Applications/Claude.app/Contents/Info.plist" CFBundleIdentifier
strings "/Applications/Claude.app/Contents/MacOS/Claude" | grep -iE "mcpb|managedMcpServers|connector" | sort -u | head
```

## Hypothesis
Cowork's connector mechanism is documented and a minimal local connector can be registered
one-shot.

## Doc landscape (see research.md)
Cowork supports local stdio MCP via `managedMcpServers` (admin) or end-user-installable
`.mcpb` desktop extensions (Connectors settings, admin-gated). Remote connectors need
admin OAuth provisioning. There is a documented source conflict re: whether the old
`claude_desktop_config.json` local path applies to Cowork — must verify on a real install.

## Decision (preliminary, pending runtime verification)
[ ] PASS — connector usable one-shot
[x] **DEFER** — a local path exists (`.mcpb` desktop extension), but it's heavier than
    Claude Code's CLI one-shot and may be admin-gated; the runtime install flow is
    unverified (app not installed). Recommend: MVP ships Claude Code (S1, PASS) as the
    primary agent target; Cowork `.mcpb` connector is a fast-follow once verified.
[ ] BLOCK — no discoverable path.

## Spec patch
- §7.4 Claude Cowork 投递: mechanism = `.mcpb` desktop extension (local stdio MCP); mark
  "DEFER — runtime install flow unverified, see spike S2 research.md".
- §4.2 条件交付: Cowork row → conditional / fast-follow (not blocking MVP).
- §10 Out of Scope or Phase 1.5: add "Cowork `.mcpb` connector verification + packaging".
- Roadmap Phase 1.5: add Cowork integration.

## Fail handling (per plan)
If `.mcpb` proves too heavy / admin-gated for MVP users, Cowork delivery falls back to
clipboard-only handoff. Document in spec.
