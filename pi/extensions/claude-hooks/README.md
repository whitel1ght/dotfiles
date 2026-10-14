# claude-hooks (pi extension)

Runs the `PreToolUse` hooks Claude Code registers for `Bash` on pi's `bash` tool, so a
guard written once for Claude holds in pi too. Today that is the ECFX `shared` plugin's
`/mr-description` gate (`hooks/mr-description-review.sh`): `glab mr create` and
description-writing updates are blocked until the `mr-description` skill records its marker.

Where the hooks come from, read at session start:

- `~/.claude/settings.json` → `hooks.PreToolUse` (`CLAUDE_CONFIG_DIR` overrides the dir);
- every plugin `settings.json` enables (`enabledPlugins`), at its `installPath` from
  `plugins/installed_plugins.json` → `hooks/hooks.json`, with `CLAUDE_PLUGIN_ROOT` set.

Only command hooks whose matcher matches `Bash` run. Claude's `if` rule is read loosely
(`Bash(glab *)` → the command mentions `glab`); when it cannot be read the hook runs, and the
hook script still decides. The hook gets Claude's JSON on stdin (`session_id`, `cwd`,
`hook_event_name`, `tool_name: "Bash"`, `tool_input.command`). Exit 2 blocks with stderr as
the reason; a JSON `hookSpecificOutput.permissionDecision: "deny"` blocks too; anything else
lets the call through.

Not covered: hooks for other tools (pi's `edit`/`write` take different input), and other
events (`SessionStart` and the rest) — `../../skills/port-claude-workflow/parity.md` says
where each one lives in pi.

```bash
npm test   # node --test *.test.ts
```
