# Pi setup

Personal configuration for [Pi](https://pi.dev), managed in this dotfiles repo.
Pi supplies the agent harness; packages and local extensions add delegation,
web access, memory, background tasks, and context management.

## Install and link

Install Pi using its [official instructions](https://pi.dev), then run from the
repo root:

```sh
./bin/plink -n       # preview the links
./bin/plink          # install or repair them
pi update --extensions  # reconcile configured npm/git packages
pi                  # start a fresh session
```

`install.sh` also runs the linker. It links individual items into `~/.pi/agent/`,
not the whole directory: authentication, sessions, installed packages, and other
runtime state remain machine-local. Existing real config items are backed up;
wrong or broken links are repaired. Review the dry run before applying it.

| Agent-directory item | Source in this repo |
| --- | --- |
| `settings.json` | `pi/settings.json`: startup defaults, packages, scoped models, theme |
| `models.json` | `pi/models.json`: local models |
| `mcp-servers.json` | `pi/mcp-servers.json`: MCP definitions with environment references |
| `APPEND_SYSTEM.md`, `model-selection.md` | `pi/`: global assistant rules and delegation policy |
| `AGENTS.md` | `claude/CLAUDE.md`: shared personal instructions |
| `skills/` | `pi/skills/`: pi-only skills (handle-ticket, jira-write, qa-comment, …) |
| `skills-team/` | **generated** by `plink` from `~/projects/claude-components` (see below); not in git |
| `~/.agents/modules/` | `pi/modules/`: shared context files the skills and agents reference |
| `agents/` | **generated** by `plink`: the team agents from claude-components with pi's header, plus the pi-only ones in `pi/agents/` linked in |
| `prompts/` | `pi/prompts/`: slash-command templates |
| `extensions/` | `pi/extensions/`: local extensions and package configuration |

Project settings in `.pi/settings.json`
can override personal settings once the project is trusted.

## Models and authentication

The startup default is **`qwen-token-plan/qwen3.8-max`**. Changing the default affects
new sessions, not the model of an already running session.

The model-cycling/session pool in `settings.json` is separate from the default.
Currently it contains:

- `qwen-token-plan/qwen3.8-max`
- `qwen-token-plan/qwen3.8-flash`
- `qwen-token-plan/deepseek-v4.1-flash`

Use `/scoped-models` to change the live session pool; edit `enabledModels` for the
persistent selection.

### OpenCode Go (removed)

The `opencode-go` override is gone from `models.json` (2026-11-06). Its `apiKey` ran
`bin/opencode-console-auth`, so an expired Console token, or no `opencode` at all, made
every model refresh warn `Could not refresh opencode-go`. To bring it back, restore the
block from git history, sign in with `opencode auth login opencode`, and avoid a stale
`opencode-go` key in Pi's `auth.json`. The helper and its `~/.local/bin` link are still here.

### Local models and secrets

Local models come from LM Studio (`lmstudio` provider at `http://127.0.0.1:1234/v1`);
start it with `localai`. See the `pigm` profile below.

Pi/provider authentication stays outside the repo. MCP configuration uses
`${VAR}` references, filled from the environment (`zsh/.zshrc.local.example`)
or from `~/.secrets/secrets.env` (secrets such as the Slack client secret). MCP OAuth state lives in
`~/.pi/agent/mcp-auth.json`. Claude Bridge is no longer installed or required
by the active model-selection policy.

### Team skills

The team's skills live in `claude-components`, which Claude Code loads as a
plugin marketplace. pi gets the same skills **generated**, not copied:
`plink` runs [`gen/pi_skills.py`](gen/pi_skills.py), which copies every
`plugins/*/skills/<name>/` folder from the clone into `~/.pi/agent/skills-team/`
and rewrites the few Claude-only parts (`!`cmd`` context lines, `plugin:name`
prefixes, `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}`, `~/.claude/docs/`), plus
a short "In pi" note on skills that launch subagents. `team-skills.json` picks which
plugins and skills are copied. They are off by default: `settings.json` lists no
skill folder, and `pi --team` (the zsh function) adds `--skill ~/.pi/agent/skills-team`
for an ECFX session. To pick up team changes:

```sh
git -C ~/projects/claude-components pull && plink
```

Agents come the same way: [`gen/pi_agents.py`](gen/pi_agents.py) writes every
`plugins/*/agents/*.md` into `~/.pi/agent/agents/` with pi's header (read-only
tools unless listed in `EDITORS`, the delegation keys pi-sub expects) above the
team body, rewritten like the skills; agents needing Claude-only MCP tools are
skipped. The pi-only agents in `pi/agents/` are linked in beside them; a file
there named like a team agent is refused.

Playbooks (`pi/prompts/` and their twins in `claude/commands`,
`claude/daily/commands`) stay two files on purpose. `bin/pi-parity` reports the
ones whose Claude side changed since `pi/parity.json` last recorded them in step,
and the commit hook stops a Claude playbook change without its pi twin unless the
message says `Pi: later`.

Tests: `python3 -m unittest test_pi_skills test_pi_agents` (from `pi/gen`),
`bin/plink.test.sh`, `bin/pi-parity.test.sh`.

### Local-model profile (`pigm`)

`pigm` (zsh alias) runs Gemma 4 E4B from LM Studio with extensions, skills,
prompts, context files and MCP off, and loads one extension explicitly with
`-e`: `pi-web-access` (web search). It is for talking things through and
learning, not agent work. Measured prompt overhead: bare 1.9k tokens, with web
search 4.3k; loading the skills would add ~16k of Gemma's 32k window.
[`local-model/wiki-search`](local-model/wiki-search/README.md) (`wiki_search` /
`wiki_read` over `~/wiki` via qmd, +0.3k tokens) works but is left out of the
alias until secrets are moved out of the wiki: a model that can read private
notes and search the web is the combination that can leak them.

## Delegation

Delegation is **`extensions/pi-sub/`**, which registers `subagent`, `subagent_stop`,
`subagent_result`, `subagent_adopt` and `subagent_handoff`, and hides
`acp_delegate*` (still registered by `npm:billion-context`, kept for context
compression) from the main model. `bin/pi-contract` fails when a prompt names a tool
this install does not have.

1. `extensions/session-models/` injects `<subagent_models>` before each parent
   model request: the exact IDs in **selected scoped models ∩ available models**.
   Availability is registry/auth configuration, not a provider health check.
   On the first request of a session it also verifies that the section really is
   in the outgoing payload, and raises an error notification if Pi dropped it.
2. The parent chooses the least expensive suitable model from that live list and
   passes it as `model` on every `subagent` launch. `model` is required and must be
   in the live list; there are no per-role defaults.
3. Each child is a bare `pi --mode json` process (no session, extensions, skills,
   context files or memory) launched detached, so it survives the window closing.
   Its state lives in `~/.local/state/pi-sub/<id>/`. When it finishes, fails or is
   stopped, a `[pi-sub]` message wakes the owning session and starts a turn; it is
   delivered once, even across reopenings. A child quiet for `idle_minutes` (10)
   flags the session; one past `max_minutes` (60) is stopped.
4. `ctrl+space` or `/agents` opens the agents window (list, activity log, stop,
   flag to main). `subagent_handoff()` / `subagent_adopt({ from })` move agents to
   a new session; agents of a session that is gone show up as orphans to adopt or
   stop. There is no resume, model questionnaire, ping probe or provider fallback.

A role is a file in `~/.pi/agent/agents/<role>.md` (generated by `plink`, see above): its body is
appended to the child's system prompt and its `tools:` line is the allowlist.
`worker` implements; `reviewer`, `researcher`, `planner`, `oracle` and the named
specialists are read-only. Tool restrictions are not an operating-system sandbox.
See [model-selection.md](model-selection.md) for the selection rules and
[extensions/pi-sub/README.md](extensions/pi-sub/README.md) for the mechanics.

The `/orchestrate`, `/review-local`, `/run-day` and `/watch-mrs` templates use
`subagent` and the live model pool. Delegation still requires operator
approval through the request or applicable workflow instructions.

## Extensions and packages

Local components:

| Component | Purpose |
| --- | --- |
| [background-terminals](extensions/background-terminals/README.md) | `bg_start`, `bg_list`, `bg_output`, `bg_stop`, and `/ps`; completion wakes the parent |
| [session-models](extensions/session-models/README.md) | Live model-pool injection plus a runtime check that it reached the request; does not launch children or call providers |
| [daily](extensions/daily/README.md) | Injects the active `/run-day` state and plan block; blocks a diary `[X]` tick that carries no evidence |
| `mcp-env/` | Expands environment references and registers MCP servers; skips servers with missing variables |
| `inline-files/` | Expands `@path` into file contents when the model has no tools |
| [recap](extensions/recap/README.md) | One-line recap after idle and on `/recap`, on the session model; ours (forked from `@tifan/pi-recap` 0.4.7, upstream not tracked) |
| [session-summary](extensions/session-summary/README.md) | On session end, writes `~/wiki/work/sessions/<date>/<id>.md` (skips subagents, short sessions and the run-day session) |
| [claude-hooks](extensions/claude-hooks/README.md) | Runs Claude Code's `PreToolUse` hooks for `Bash` (from enabled plugins and `~/.claude/settings.json`) on pi's `bash` tool, with Claude's input and exit-code contract — the ECFX `/mr-description` gate holds in pi too |

`settings.json` also declares packages for web search/access, todo lists,
questions, browser artifacts, context display, memory, background tasks,
Superpowers skills, Ponytail, pi-lens, and Billion Context. npm declarations are
unversioned. `pi list` shows configured packages; `pi config` controls discovered
resources.

## Retired setup

The old custom subagent runtime (`pi/archive/`) was deleted; it is in git at `ed6ce1b`.
The retired `subagents.json`, `subagent-models.json`, `subagent-model-guide.md`,
`subagents-research.md` and `agents.test.mjs` are deleted; `model-selection.md` is
the live policy. `plink` still removes their stale links — only links owned by this
checkout, preserving real files and foreign links.

## Verification

From the repo root, with Node.js 24 (native TypeScript test support):

```sh
./bin/plink.test.sh
for extension in background-terminals daily inline-files mcp-env session-models; do
  (cd "pi/extensions/$extension" && npm test) || break
done
./bin/pi-contract
git diff --check
```

`pi-contract` is the only check that runs a real `pi`: it boots one in a throwaway
config dir with a probe extension and asserts, against the captured provider
payload, that the injected prompt sections land, that every tool the prompts name
exists, and that pi-sub children launch bare, outlive their launcher and wake the
owning session exactly once. Run it after any `pi update`.
The other checks cover linking and local extension behavior; none of them prove
remote provider authentication or model health.
