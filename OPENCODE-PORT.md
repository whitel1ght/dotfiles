# OpenCode port — working plan

`claude-components/` and `claude/` stay untouched. `opencode/` becomes the
hand-maintained source of truth for OpenCode, tracked in git.

## Decisions (settled)

| Decision | Answer |
|---|---|
| Models | No `model:` key anywhere in `opencode/`. Commands and agents inherit the session model. |
| Names | Same as upstream, so the two trees are greppable against each other. Two exceptions, renamed because the name is itself the Claude mention: `claude-md-manager` → `project-memory-manager`, `claude-skills-expert` → `skills-architect`. |
| Agent frontmatter | `description` (folded `>-`) + `mode: subagent` + `permission.edit: deny`. No `name:` — OpenCode derives it from the filename. |
| Skill frontmatter | `name` must equal the directory. 41 upstream files need their `name:` rewritten to the dir slug. |
| `CLAUDE.md` | → `AGENTS.md` in bodies. |
| `${CLAUDE_PLUGIN_ROOT}/modules/` | → `~/.config/opencode/modules/` (ships locally; must resolve without the upstream clone). |
| other `${CLAUDE_PLUGIN_ROOT}/…` | → `/Users/dmitry/projects/claude-components`, where the hook scripts genuinely live. |
| `Task` tool | → `task` tool. `Skill` tool → `skill` tool. `AskUserQuestion` → `question`. |
| `allowed-tools` | dropped; tool access lives in `opencode.jsonc` `permission`. |
| Generators | Both retired and stripped from `install.sh` — they wrote into paths that are now hand-edited. |
| Vendored `teach` | Ported to `opencode/skills/teach/`, dropping `disable-model-invocation` / `argument-hint`, which OpenCode does not implement. |

## Module dedupe

13 upstream module files flatten to 8; every duplicate is byte-identical, so
there is no collision:

- `ui-project-context.md` — 4 identical copies → 1
- `backend-project-context.md` — 2 identical → 1
- `verified-ui-facts.md` — 2 identical → 1
- `MODULE_INDEX.md`, `controller-patterns.md`, `entity-patterns.md`,
  `repository-patterns.md`, `service-patterns.md` — unique

## Stage 1 — agents, commands, modules, install.sh — DONE

- [x] `opencode/agents/` — 30 agents (28 mechanical, 2 rewritten by hand)
- [x] `opencode/modules/` — 8 files
- [x] `opencode/commands/` — 7 hand-maintained, no Claude model pins
- [x] `opencode/skills/teach/` — vendored skill
- [x] `install.sh` — symlinks all four dirs, both generator calls removed
- [x] Retired both generators and their tests (moved to `../opencode-port-retired/`)
- [x] `README.md` — the "Slash commands" section rewritten as "OpenCode"
- [x] `opencode.jsonc` — no change needed; agents carry their own permissions

Verified: `opencode debug agents` resolves 30/30, all `mode: subagent`, none
carrying a `model`, 28 `edit: deny` + the 2 editors `edit: allow`. Skill
frontmatter checked: `name:` equals its directory in all cases.

### Fixes the mechanical port did not catch

- `invent-simplify-reviewer` carried upstream's author's absolute home directory
  (`/Users/levisiebens/.claude/agent-memory/…`) and claimed `MEMORY.md` is
  auto-loaded into the prompt. OpenCode does neither, so the section was
  rewritten to point at `~/.config/opencode/agent-memory/` and told the agent to
  read it itself.
- `accessibility-expert` explained why its context file was *not* shared across
  plugins. After flattening there is one shared `modules/` dir, so the rationale
  was obsolete and misleading — removed.
- `accessibility-expert` told the agent to add rows to `verified-ui-facts.md`,
  which `edit: deny` forbids. Reworded to report them.
- `git-gitlab-expert`'s description embedded Claude's `<uses Task tool …>`
  dispatch syntax, 8 times, in user-visible text.
- Five Claude tool names the retired generator never handled, still live in the
  9 skills it had written: `SendMessage`, "parallel Agent tool calls",
  "Claude's Skill tool" ×2, and two `mcp__plugin_atlassian_atlassian__*` ids for
  an MCP this config does not even have.

### Deliberately kept

- `aws-cloud-architect` names Claude as an Amazon Bedrock model. That is a fact
  about Bedrock's catalogue; dropping it would make the agent wrong.
- `vue-expert`, `pytest-expert` and the two context modules name `.claude/skills/`
  and `.claude/hooks/` paths. Those are real files in ecfx-dashboard and
  ecfx-admin, which stay on Claude Code. An OpenCode agent reviewing those repos
  should name the files that are actually there.
- `mr-review-multi-agent` and `mr-review` tell the reviewer to read the target
  repo's `CLAUDE.md`. Same reason: it is the rulebook those repos actually have.
- `skills-architect` and the 7 commands mention `allowed-tools` /
  `disable-model-invocation` on purpose, to explain why OpenCode ignores them.

## Stage 2 — skills

- [x] 9 shared-plugin skills already present as generator output — kept, with 5
      tool-name defects fixed by hand
- [x] `teach` vendored from `claude/vendor/mattpocock/`
- [ ] remaining 56 from claude-components
- [ ] 3 from `claude/skills/` (`handle-ticket`, `qa-comment`, `vendor-skill`)
- [ ] `name:` rewritten to match each directory slug
- [ ] `allowed-tools` dropped; `CLAUDE_PLUGIN_ROOT` / `CLAUDE.md` / `AskUserQuestion`
      / `Task` / `!`cmd`` / `Bash(` / `settings.json` translated

## Verification per stage

- [ ] `opencode debug config` shows no errors
- [ ] every skill and agent in the new tree appears in OpenCode's own tool description
- [ ] no `model:`, `CLAUDE.md`, `CLAUDE_PLUGIN_ROOT`, `allowed-tools`, or bare `Claude` left in `opencode/`