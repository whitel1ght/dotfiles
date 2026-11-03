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

`settings.json` is the one exception: Pi writes per-host state into it
(`lastChangelogVersion`, `extensionChangelogVersions`, device identity), so the
repo copy is only a seed. `install.sh` and `bin/plink` create it as a regular
file when absent and never replace an existing file; a legacy symlink owned by
this checkout is converted into a per-host copy of the same content, with the
old link recorded beside it. Edit `pi/settings.json` for the shared declaration
(packages, `subagents` policy, theme) and the per-host file for
`defaultProvider`, `defaultModel`, `enabledModels`, and machine keys.

| Agent-directory item | Source in this repo |
| --- | --- |
| `settings.json` | seeded from `pi/settings.json`: shared packages, `skills`, theme; provider/model and machine keys are per-host |
| `models.json` | `pi/models.json`: local models and OpenCode Go overrides |
| `mcp-servers.json` | `pi/mcp-servers.json`: MCP definitions with environment references |
| `APPEND_SYSTEM.md`, `model-selection.md` | `pi/`: global assistant rules and delegation policy |
| `AGENTS.md` | `claude/CLAUDE.md`: shared personal instructions |
| `skills/` | `pi/skills/`: pi-only skills (handle-ticket, jira-cli, qa-comment, …) |
| `skills-team/` | **generated** by `plink` from `~/projects/claude-components` (see below); not in git |
| `~/.agents/modules/` | `pi/modules/`: shared context files the skills and agents reference |
| `agents/` | **generated** by `plink`: the team agents from claude-components with pi's header, plus the pi-only ones in `pi/agents/` linked in |
| `prompts/` | `pi/prompts/`: slash-command templates |
| `extensions/` | `pi/extensions/`: local extensions and package configuration |
| `packages/` | `pi/packages/`: vendored packages |

The `packages/` link is required because `./packages/pi-recap` resolves relative
to the settings location in `~/.pi/agent/`. Project settings in `.pi/settings.json`
can override personal settings once the project is trusted. The `/status` prompt
is a read-only wrapper around the locally linked `day-status` helper; `/system`
marks the session for the daily extension's idle ideas review.

## Models and authentication

The startup default in the repo seed is **`opencode-go/longcat-2.5`**, authored on
the Mac. A host without that provider's login sets its own `defaultProvider`,
`defaultModel`, and `enabledModels` in its per-host `~/.pi/agent/settings.json`;
seeding never overwrites an existing file, so those host overrides survive
re-installs. On this Ubuntu host the default is `qwen-token-plan/qwen3.8-max`
with the pool `qwen-token-plan/qwen3.8-max` and
`qwen-token-plan/deepseek-v4.1-flash`. Changing the default affects new
sessions, not the model of an already running session.

The repo seed's session pool is:

- `openai/gpt-6.1-sol`
- `ollama/qwen2.5-coder:14b-16k`

The OpenAI model requires a usable OpenAI login. The Ollama model requires a
local Ollama service with that exact model loaded; it is not downloaded or
started by the dotfiles installer. The default model is not automatically added
to the scoped delegation pool. Use `/scoped-models` to change the live pool and
edit `enabledModels` for the persistent selection. Do not silently route a
missing model to a different provider or paid account.

### OpenCode Go

`models.json` overrides Pi's built-in `opencode-go` provider to use OpenCode
Console endpoints (`opencode.ai/inference/go/...`). Credentials come from
`bin/opencode-console-auth`, linked into `~/.local/bin/`: its `token` and `org`
commands read OpenCode's local credential and supply the bearer token and
`x-opencode-org-id` header. No token is committed in this repo.

Sign in with `opencode auth login opencode`. If the token expires, run OpenCode
to refresh it. Avoid a stale `opencode-go` key in Pi's `auth.json`, which can
supersede the configured credential source. `qwen3.8-flash` and `minimax-m3`
have full Anthropic-endpoint overrides; other models rely on Pi's registry plus
the provider-level overrides. The standalone `longcat` provider was removed.

### Local models and secrets

`models.json` also configures Ollama at `http://127.0.0.1:11434/v1`, including
`qwen3.6:35b` and `qwen2.5-coder:14b-16k`. Local use requires a running Ollama
server and the appropriate model. `install.sh` can build the 16k model from the
repo's Modelfile; `OLLAMA_SETUP=0` skips that setup.

Pi/provider authentication stays outside the repo. MCP configuration uses
`${VAR}` references; export the required values from your local shell setup
(see `zsh/.zshrc.local.example`). MCP OAuth state lives in
`~/.pi/agent/mcp-auth.json`. Claude Bridge is no longer installed or required
by the active model-selection policy.

### Optional decisions deck MCP

The daily ask/follow-up workflow can use the `decisions` MCP server, but the
standalone decisions runtime is not installed by this configuration and the
server is deliberately absent from the default `mcp-servers.json`. Until you
have installed and verified `~/.local/bin/decisions mcp` on this machine, Pi
uses the normal chat fallback; no missing executable is launched at session
start. To opt in on a machine with that runtime, add this entry to its personal
MCP config (or to this repo only after intentionally choosing repo-wide
activation):

```json
"decisions": {
  "command": "~/.local/bin/decisions",
  "args": ["mcp"],
  "description": "Ask the user through the decisions deck",
  "timeout": 3600,
  "env": { "DECISIONS_WAIT": "3000" }
}
```

The `decisions` wrapper itself expects its external binary at
`$HOME/.local/share/decisions/bin/decisions` unless `DECISIONS_BIN` is set.
The wrapper, binary, and their runtime state are machine-local, not copied or
installed by Pi setup.

## Delegation

Delegation is **`extensions/pi-sub/`**, which registers `subagent`, `subagent_stop`,
`subagent_result`, `subagent_adopt` and `subagent_handoff`, and hides
`acp_delegate*` (still registered by `npm:billion-context`, kept for context
compression) from the main model. `bin/pi-contract` fails when a prompt names a tool
this install does not have. Nothing is installed from npm for it: the pinned
`pi-subagents` package and the `subagents.modelScope` policy are gone from
`pi/settings.json`.

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

A role is a file in `~/.pi/agent/agents/<role>.md`: its body is appended to the
child's system prompt and its `tools:` line is the allowlist. `worker` implements;
`reviewer`, `researcher`, `planner`, `oracle` and the named specialists are
read-only; `text` has no tools. Tool restrictions are not an operating-system
sandbox. See [model-selection.md](model-selection.md) for the selection rules and
[extensions/pi-sub/README.md](extensions/pi-sub/README.md) for the mechanics.

The `/orchestrate`, `/review-local` and `/watch-mrs` templates use `subagent` and
the live model pool (`/start-day` and `/fix-friction` name it too). Delegation
still requires operator approval through the request or applicable workflow
instructions. This branch has no `prompts/run-day.md` — main does — so the daily
extension's pointer at `~/.pi/agent/prompts/run-day.md` (`extensions/daily/index.ts`)
resolves to nothing here; `/run-day` in pi has no playbook until that prompt is
taken from main.

### Linux notes

- Node 24 lives under nvm here, so a bare non-login shell has no `node` on `PATH`.
  Run the tests and `bin/pi-contract` through `zsh -ic '…'` (or with nvm's node
  first on `PATH`).
- A child's ownership is proved from `/proc/<pid>/environ`, not `ps -E`: procps-ng
  rejects `-E` (`error: unsupported SysV option`), and `/proc` is readable only by
  the owner. `psForPlatform` picks the probe, so the macOS `ps -E` path is
  untouched. A pid that is gone, or belongs to someone else, reads as unowned and
  is never signalled.

## Team skills and agents

The team's skills and agents live in `claude-components`, which Claude Code loads
as a plugin marketplace. pi gets them **generated**, not copied: `plink` runs
[`gen/pi_skills.py`](gen/pi_skills.py), which copies every
`plugins/*/skills/<name>/` folder from the clone into `~/.pi/agent/skills-team/`
and rewrites the few Claude-only parts (`!`cmd`` context lines, `plugin:name`
prefixes, `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}`, `~/.claude/docs/`), plus
a short "In pi" note on skills that launch subagents. `settings.json` lists
`skills-team`. To pick up team changes:

```sh
git -C ~/projects/claude-components pull && plink
```

Agents come the same way: [`gen/pi_agents.py`](gen/pi_agents.py) writes every
`plugins/*/agents/*.md` into `~/.pi/agent/agents/` with pi's header (read-only
tools unless listed in `EDITORS`, the delegation keys pi-sub expects) above the
team body, rewritten like the skills; agents needing Claude-only MCP tools are
skipped. The pi-only agents in `pi/agents/` are linked in beside them; a file
there named like a team agent is refused.

On this host the clone is `~/projects/ecfx/claude-components`, so
`~/projects/claude-components` is a symlink to it (or set
`CLAUDE_COMPONENTS_DIR`); without either, `plink` warns and leaves the previous
generation in place.

Tests: `python3 -m unittest discover -s pi/gen` (28 tests), `bin/plink.test.sh`.

## Extensions and packages

Local components:

| Component | Purpose |
| --- | --- |
| [background-terminals](extensions/background-terminals/README.md) | `bg_start`, `bg_list`, `bg_output`, `bg_stop`, and `/ps`; completion wakes the parent |
| `daily/` | Daily run-state injection, diary edit guard and the `/run-day` event/inbox watcher; shares parser modules with Claude Code |
| `secrets-guard/` | Blocks Pi file tools from reading or writing `~/.secrets` and the Jira environment file; Bash guards run separately through `claude-hooks` |
| `artifacts-home/` | Keeps Pi artifacts under `~/artifacts/pi/` by linking the project artifact path |
| [session-models](extensions/session-models/README.md) | Live model-pool injection plus a runtime check that it reached the request; does not launch children or call providers |
| `mcp-env/` | Expands environment references and registers MCP servers; skips servers with missing variables |
| `inline-files/` | Expands `@path` into file contents when the model has no tools |
| [pi-recap](packages/pi-recap/README.md) | Vendored recap widget and `/recap`; uses Pi's model registry for requests |

The recap model is configured separately in `extensions/pi-recap.json` as
`opencode-go/space-bunny-free`. `/recap config` changes it; `/recap status`
reports its state. It does not inherit the startup default or subagent pool.

`settings.json` also declares packages for web search/access, todo lists,
questions, browser artifacts, context display, memory, background tasks,
Superpowers skills, Ponytail, pi-lens, and Billion Context. npm declarations are
unversioned. `pi list` shows configured packages; `pi config` controls discovered
resources.

### Daily workflow and local search

The `daily` extension uses `RUN_DAY_STATE_DIR`, `WIKI_DIR` and `RUN_DAY_DATE` when
set; otherwise it reads and writes the user's normal `~/.local/state/run-day/` and
`~/wiki/` state. Run only one `/run-day` session per day because the Pi and Claude
harnesses share state. Its tests use temporary state. The secrets guard protects Pi
file tools but is not a shell sandbox; Bash continues through the separately
configured Claude hook guards.

`artifacts-home` redirects `pi-artifacts` output into `~/artifacts/pi/` by default
(or `$ARTIFACTS_DIR` when set). Before it links an existing project `.pi/artifacts`
directory, it moves its contents into the store; collisions are left in place and
reported rather than overwritten.

The optional `pi/local-model/wiki-search` extension is for the `pigm` local-model
profile, loaded explicitly with `-e` rather than during ordinary Pi startup. It
provides `wiki_search` and `wiki_read` through `qmd`; it excludes the `pi-memory`
collection and does not copy wiki data into this repository.

## Retired setup

The old custom subagent runtime (`archive/subagents/`) is deleted, as are
`subagents.json`, `subagent-models.json`, `subagent-model-guide.md`,
`subagents-research.md` and `agents.test.mjs`; both are still in this branch's
history. `model-selection.md` is the live policy. The npm `pi-subagents` package
is no longer declared or installed, and `bin/pi-autoupdate` no longer guards the
release tree for `@earendil-works/chord` — pi-sub children import nothing from it.
`plink` still removes their stale links, only links owned by this checkout,
preserving real files and foreign links.

## Verification

From the repo root, with Node.js 24 (native TypeScript test support; under nvm
here, so through `zsh -ic`):

```sh
./bin/plink.test.sh
for extension in artifacts-home daily inline-files mcp-env pi-sub secrets-guard session-models; do
  (cd "pi/extensions/$extension" && npm test) || break
done
./bin/pi-contract
./bin/pi-autoupdate.test.sh
./ubuntu/install-missing.test.sh
git diff --check
```

`pi-contract` is the only check that runs a real `pi`: it boots one in a throwaway
config dir with a probe extension and asserts, against the captured provider
payload, that the injected prompt sections land, that every tool the prompts name
exists, and that pi-sub children launch bare, outlive their launcher and wake the
owning session exactly once. Run it after any `pi update`. Point it at this
checkout with `DOTFILES=$PWD ./bin/pi-contract`.
The other checks cover linking and local extension behavior; none of them prove
remote provider authentication or model health. The vendored recap package
currently has no test script.
