# pi-sub

Subagents as detached bare `pi` children that wake the session that launched them.

Tools (main session only; none are registered when `PI_SUBAGENT` is set):

- `subagent({ role, model, task, cwd?, skills?, with?, label?, idle_minutes?, max_minutes? })`
  launches a child and returns its id at once. `role` is a file in `~/.pi/agent/agents/`
  (`PI_SUB_AGENTS_DIR`); `model` must be in the live `<subagent_models>` list.
- `subagent_result({ id })`, `subagent_stop({ id })`.
- `subagent_handoff()` marks this session's agents for the next session;
  `subagent_adopt({ from })` takes them over.

`acp_delegate*` are removed from the main model's tools in `before_agent_start`.

The child runs `pi --mode json --no-session --no-extensions --no-skills --no-context-files
--no-prompt-templates --tools <role tools> --append-system-prompt <role body>` under
`run.mjs`, spawned detached in its own process group, so closing or crashing the window
does not kill it. Write-capable roles also load pi-lens with autofix, autoformat and
tests off. `with: ["web"]` adds pi-web-access; `with: ["playwright"]` adds its skill.

State lives in `~/.local/state/pi-sub/<id>/` (`PI_SUB_STATE_DIR`): `meta.json`,
`events.jsonl`, `result.md`, `exit.json`, and `delivered` once the owner has been told.
A watcher in the owning session sends one `[pi-sub]` message per exit with
`triggerTurn`, so the session reacts without anyone typing; the `delivered` marker keeps
it to one delivery across reopenings. A child quiet for `idle_minutes` (10) flags the
session; one past `max_minutes` (60) is stopped. Agents whose owner is gone appear as
orphans in a `session_start` notice and in the window.

`ctrl+space` toggles the window and `/agents [id]` opens it: `j/k` move, `l` open, `x` stop,
`m` flag to main, `/` filter, `zf` show finished, `q` close. Rebind keys under
`piSub.keys` in settings. `/agents adopt <session>` adopts from the command line.

Verified against Pi 1.2.0. Run `node --test *.test.ts` here; `bin/pi-contract` checks
the real behaviour (bare child, survives its launcher, wake-up once, pi-lens path).
