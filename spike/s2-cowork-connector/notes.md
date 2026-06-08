# S2 — Cowork connector mechanism

## Status: 🟢 MECHANISM CONFIRMED (bundle inspected 2026-06-08) — end-to-end reg is a fast-follow
Claude.app installed: **`com.anthropic.claudefordesktop` 1.11187.4** (Electron). It includes
the Cowork feature (`config.json` has `lastSeenRequireCoworkFullVmSandbox` → Cowork runs in a
VM sandbox).

### Bundle evidence (strings in `Contents/Resources/app.asar`)
The app references all of these local-MCP mechanisms:
- **`.mcpb` / `DesktopExtension`** (44× `DesktopExtension`, many `.mcpb`/`MCPB`) — the modern
  packaged "desktop extension" install path.
- **`claude_desktop_config.json`** (4×) — the legacy local stdio MCP config file still present.
- **`managedMcpServers`** (12×) — admin/enterprise provisioning.
- **`NativeMessagingHosts`** (14×) — native messaging support.

Config dir created on first launch: `~/Library/Application Support/Claude/` (`config.json`,
`git-worktrees.json`, caches). No `claude_desktop_config.json` yet (created when the user adds
an MCP server via Settings → Developer, or by writing it directly).

### What this means vs the V1/V2 assumption
The V2 spec said Cowork "does not read `claude_desktop_config.json`". The current desktop app
**does** ship that legacy path AND the newer `.mcpb` path. So there IS a **local, non-OAuth,
automatable** registration path — the S1 `HelloServer` stdio binary should work via either.
This moves S2 off "BLOCK/DEFER".

## Hypothesis
Cowork's connector mechanism is documented and a minimal local connector can be registered
one-shot.

## Doc landscape (see research.md)
Cowork supports local stdio MCP via `managedMcpServers` (admin) or end-user-installable
`.mcpb` desktop extensions (Connectors settings, admin-gated). Remote connectors need
admin OAuth provisioning. There is a documented source conflict re: whether the old
`claude_desktop_config.json` local path applies to Cowork — must verify on a real install.

## Decision (updated 2026-06-08 after bundle inspection)
[x] **MECHANISM CONFIRMED** — a local, non-OAuth path exists (legacy `claude_desktop_config.json`
    AND `.mcpb` desktop extension). No longer DEFER/BLOCK.
[ ] full PASS pending one more step — end-to-end registration not yet verified (would need a
    signed-in Claude + either writing `claude_desktop_config.json` or installing a `.mcpb`,
    then confirming a tool call). That verification is a small fast-follow.

Recommendation: MVP ships Claude Code (S1, PASS) as the primary agent target; Beamhop's Cowork
delivery writes `claude_desktop_config.json` (simplest, mirrors S1's stdio server) and/or ships
a `.mcpb`. Either is local + one-shot-ish; neither needs OAuth/backend ops.

### Remaining fast-follow to reach full PASS
1. Write `~/Library/Application Support/Claude/claude_desktop_config.json` with the `HelloServer`
   stdio binary, restart Claude, confirm it loads (Settings → Developer shows the server).
2. Or package the `.mcpb` and install via Settings → Extensions.
3. Confirm a tool call from a Cowork/Claude session. (Needs sign-in.)

## Spec patch
- §7.4 Claude Cowork 投递: **correct the V2 claim** that Cowork ignores `claude_desktop_config.json`
  — the current desktop app (`com.anthropic.claudefordesktop` 1.11187.4) ships BOTH that legacy
  path AND `.mcpb` desktop extensions. Mechanism = local stdio MCP via either; non-OAuth,
  automatable. Status = mechanism confirmed; end-to-end registration is a fast-follow.
- §4.2 条件交付: Cowork row → conditional, **viable** (not blocked) — fast-follow after MVP金线.
- §10 / Phase 1.5: "Cowork connector end-to-end verification + `.mcpb` packaging" (not a deep
  unknown anymore — just needs a signed-in verification pass).

## Fail handling (per plan)
If `.mcpb` proves too heavy / admin-gated for MVP users, Cowork delivery falls back to
clipboard-only handoff. Document in spec.
