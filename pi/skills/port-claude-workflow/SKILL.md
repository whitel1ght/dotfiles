---
name: port-claude-workflow
description: Find what in the Claude Code setup has no pi counterpart yet — commands, skills, agents, hooks, plugin modules — and port it to pi properly, keeping Claude Code untouched and both harnesses on the same state files. Use when the user says "port X from Claude", "what's missing in pi compared to Claude", "pi doesn't do <thing> that Claude does", "check Claude/pi parity", after adding a Claude command or plugin, or after a Claude plugin update.
---

# Port a Claude Code workflow feature to pi

Claude Code is the reference and stays **exactly as it is**: never edit `~/.claude/`,
`~/projects/dotfiles/claude/`, or a Claude plugin cache. pi gets its own files, which read and
write the **same** state (`~/wiki`, `~/.local/state/run-day/`, `~/.claude/markers/`, …), so
either harness can drive a day.

Paths:

- Dotfiles: `~/projects/dotfiles` (`D`). pi sources live in `$D/pi/` and are linked into
  `~/.pi/agent/` by `bin/plink` (prompts, skills, extensions, agents).
- This skill: `$D/pi/skills/port-claude-workflow/` (`S`): `scripts/inventory`, `parity.md`,
  `tests/inventory.test.sh`.
- Claude sources: `~/.claude/commands/*.md` (symlinks into `$D/claude/commands`),
  `~/.claude/settings.json` (`hooks`, `enabledPlugins`), and each plugin at its
  `installPath` in `~/.claude/plugins/installed_plugins.json` (`commands/`, `skills/`,
  `agents/`, `hooks/hooks.json`, `modules`). Our own plugin sources are under `$D/claude/`
  (the `daily` plugin is `$D/claude/daily`).

Set `D` and `S` again in every bash call; shell state does not carry over.

## 1. Inventory

```bash
S=~/projects/dotfiles/pi/skills/port-claude-workflow
"$S/scripts/inventory" | awk -F'\t' '$3=="MISSING" || $3=="stale"'
```

Each row is `kind  name  status  source`. `ported` means pi already has a prompt, skill or
agent of that name (pi's own dir or any installed pi package); a skill copied into
`pi/skills/` must also match its Claude source by content (`scripts/skill-digest` ignores
the `name` field, frontmatter folding and blank lines). `adapted` is a pi skill that differs
on purpose and whose `adapted:` line in `parity.md` carries the digest of the Claude source it
was adapted from. `stale` is a pi skill that differs with no such record, or whose Claude
source changed since: see what moved with
`"$S/scripts/skill-digest" <claude skill dir> ~/projects/dotfiles/pi/skills/<name>`, port
the upstream change, keep the pi adaptations, then write the new digest
(`"$S/scripts/skill-digest" <claude skill dir>`) into the `adapted:` line, or delete the line
when the copies match again. The source column names the plugin; its skill dir is
`<installPath>/skills/<name>` from `~/.claude/plugins/installed_plugins.json`. `accepted` means `parity.md`
says where it lives in pi or why it is not ported. `disabled` is an installed Claude plugin
that `settings.json` does not enable: ignore it unless the user asks. Hooks never match by
name, so each one is `MISSING` until `parity.md` accounts for it.

When the user named one feature, port that one; otherwise show the `MISSING` rows grouped by
kind and ask which to do. A `ported` prompt can still be behind its Claude twin. `pi-parity`
tracks that: it lists every pi prompt whose Claude command changed since the pi side last
caught up (or was never compared), and `pi-parity diff <name>` shows what moved on the Claude
side since then:

```bash
cd ~/projects/dotfiles && bin/pi-parity && bin/pi-parity diff <name>
```

For a pair never compared there is no baseline: read both files whole and port every
difference that is not a harness mechanic.

Read the whole Claude source and anything it calls (scripts, skills, modules) before writing.

## 2. Map each Claude mechanism to pi

Prefer, in order: a native pi mechanism, an installed pi package, a small file in
`$D/pi/`. Never add a pi package without asking.

| Claude | pi |
| --- | --- |
| command `commands/<n>.md` | prompt template `$D/pi/prompts/<n>.md`, same name (frontmatter `description`, `argument-hint`; `$ARGUMENTS`) |
| skill `skills/<n>/SKILL.md` | `$D/pi/skills/<n>/SKILL.md`; scripts stay where they are and are called by absolute path, so the two harnesses share one copy |
| `Task` / `Agent` tool, subagents | `subagent({role, model, task, cwd, label})` from `pi-sub`; returns at once, the `[pi-sub]` wake-up continues the turn. Roles: `$D/pi/agents/*.md`. Model from the live `<subagent_models>` list, by `~/.pi/agent/model-selection.md` |
| `TodoWrite` | `todo` |
| `AskUserQuestion` | `ask_user_question` |
| `PushNotification`, sounds | `ctx.ui.notify` in an extension (see `pi/extensions/daily`) |
| `SessionStart` hook that injects context | `before_agent_start` in an extension, mutating `event.systemPromptOptions.sections` (not `context_with_system`: it never reaches the request on pi 1.2.0) |
| `PreToolUse` hook on `Bash` | already generic: `pi/extensions/claude-hooks` runs it. Add a `parity.md` line |
| `PreToolUse` on `Edit`/`Write` | `tool_call` handler; pi's `edit` input is `{path, edits:[{oldText,newText}]}`, not Claude's |
| `PostToolUse` | `tool_result` handler |
| `Stop` / `SessionEnd` | `session_shutdown` (see `pi/extensions/session-summary`) |
| claude-code mod `register.tsx` (`on('tool.call')`, `on('session.start')`, panels) | a pi extension: `pi.on("tool_call")`, `pi.on("session_start")`, `ctx.ui.setStatus` / `setWidget` / `custom` overlay |
| `Skill` tool, "use the X skill" | same words; pi lists skills and the model reads the file |
| `WebFetch` / `WebSearch` | `web_enable`, then the web tools |
| `${CLAUDE_PLUGIN_ROOT}` | an absolute path into `$D/claude/...` |

Claude tool names that do not exist in pi must not appear in pi prose: `Task`, `Agent`,
`SendMessage`, `TodoWrite`, `AskUserQuestion`, `Skill`, and Billion Context's delegate tool
(hidden in pi; `bin/pi-contract` fails if prose names it). Write the pi tool, or the plain
action.

Things that are Claude-only by nature (cache warming, claude.ai account skills, Claude's own
worktree tool) are not ported: add a `parity.md` line saying why.

## 3. Port

Work in a worktree (`wt add dotfiles <name>`), not the main checkout. If a `/run-day`
session is live (`~/.local/state/run-day/<today>.md` exists), do not touch the main
checkout's `pi/prompts`, `pi/extensions`, `pi/settings.json`, the run-day state or `~/wiki`.

- **Prompt:** copy the Claude command's structure and wording, then change only what the
  harness forces: tool names, subagent launch and wake-up (end the turn after `subagent`,
  continue on the wake-up; never sleep or poll), paths. Keep every guard and verification step.
- **Skill:** same name; keep scripts in place. If Claude's copy needs a change to work in pi,
  ask first: Claude's files are not ours to edit.
- **Extension:** `$D/pi/extensions/<n>/` with `index.ts`, logic in a separate testable module,
  `*.test.ts` (`node --test`), `package.json` (`"pi": {"extensions": ["./index.ts"]}`) and a
  `README.md`; add a row to the Local components table in `$D/pi/README.md`. Pi's types:
  `~/.pi/agent/install/releases/<version>/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts`;
  docs in `docs/extensions.md` beside it. Read them, do not guess.
- **Hook:** if the Claude hook is a script, run it rather than rewriting it, the way
  `claude-hooks` does, so a fix in one place fixes both harnesses.
- Then add or edit the `parity.md` line if the inventory cannot see the counterpart by name,
  and an `adapted:` line with the source digest for every skill whose pi copy differs.
- **Prompt brought in step:** `bin/pi-parity mark <name>` and commit `pi/parity.json` with the
  prompt. The commit hook stops a commit that changes a Claude command without this (unless
  its message says `Pi: later`).
- **Agents** need no porting: plink generates every team agent into `~/.pi/agent/agents`
  (`pi/gen/pi_agents.py`). Change a team agent in claude-components; only pi-only agents
  live in `pi/agents/`.

## 4. Verify

```bash
D=~/projects/worktrees/dotfiles/<name>
"$D/pi/skills/port-claude-workflow/tests/inventory.test.sh"
PI_DIR="$D/pi" "$D/pi/skills/port-claude-workflow/scripts/inventory" | awk -F'\t' '$3=="MISSING" || $3=="stale"'
(cd "$D/pi/extensions/<n>" && npm test)        # for each extension touched
cd "$D" && DOTFILES="$PWD" bin/pi-contract     # boots real pi; must end "All checks passed"
```

`bin/pi-contract` boots real pi and checks the tools, the injected prompt sections, the
extensions' live behaviour, and that no prompt or skill tells the model to use the hidden
delegate tool. Run it from the worktree with `DOTFILES="$PWD"`; the default checks the main
checkout. It takes a few minutes: run it with `bg_run` and end the turn.

When the port has a runnable entry point that does not write live state (a prompt in a
sandbox: `RUN_DAY_STATE_DIR`, `WIKI_DIR` and `RUN_DAY_DATE` point the daily system
elsewhere), run it once. Otherwise say plainly that it is untested.

## 5. Commit and report

Commit in the worktree, one commit per feature, Conventional Commits (`feat(pi): …`). Report
what was ported, where, what was accepted as not portable and why, and how it was verified.
Merging into the main checkout is a separate step the user asks for.
