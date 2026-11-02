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
| `settings.json` | seeded from `pi/settings.json`: shared packages, scoped `subagents` policy, theme; provider/model and machine keys are per-host |
| `models.json` | `pi/models.json`: local models and OpenCode Go overrides |
| `mcp-servers.json` | `pi/mcp-servers.json`: MCP definitions with environment references |
| `APPEND_SYSTEM.md`, `model-selection.md` | `pi/`: global assistant rules and delegation policy |
| `AGENTS.md` | `claude/CLAUDE.md`: shared personal instructions |
| `skills/` | `pi/skills/`: skills |
| `~/.agents/modules/` | `pi/modules/`: shared context files the skills and agents reference |
| `agents/` | `pi/agents/`: Pi-specific named subagent definitions |
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

Delegation uses the explicitly pinned **`npm:pi-subagents@0.76.0`** package, not the retired custom runtime. `pi/settings.json` declares this package so a package refresh installs the implementation described here.
It is declared in object form with empty `skills` and `prompts` filters
(`{"source": "npm:pi-subagents@0.76.0", "skills": [], "prompts": []}`), so its
bundled skills and prompts stay disabled and the shared skills and local prompt
templates remain authoritative.

1. `extensions/session-models/` injects `<subagent_models>` before each parent
   model request: the exact IDs in **selected scoped models ∩ available models**.
   Availability is registry/auth configuration, not a provider health check.
2. The parent chooses the least expensive suitable model from that live list
   and passes an explicit `provider/id` on each `subagent` launch.
3. `subagents.modelScope` uses `allow: ["scoped"]`, `enforce: true`, and
   `strict: true` to reject out-of-pool launches, including inherited models.
   If the session has no scope, only its available parent model is eligible.
4. A failed launch is inspected before an explicit retry. There is no model
   questionnaire, ping probe, fixed ranking, or automatic provider fallback.

Agent names define expertise and tools, not model routing. `scout`, `reviewer`,
`oracle`, and most specialists are read-only; `worker` handles implementation
with the needed specialist guidance in its brief. `text` has no tools. Tool
restrictions are not an operating-system sandbox.

`extensions/subagent/config.json` makes the tool eager and disables missions,
scheduled runs, and Orca progress tabs. No shared child extension allowlist is
configured: upstream discovery applies unless an agent declares its own policy.
See [model-selection.md](model-selection.md) for the full selection rules.

The `/orchestrate`, `/review-local`, and `/watch-mrs` templates use the named
upstream tool and live model pool. Delegation still requires operator approval
through the request or applicable workflow instructions.

## Extensions and packages

Local components:

| Component | Purpose |
| --- | --- |
| [background-terminals](extensions/background-terminals/README.md) | `bg_start`, `bg_list`, `bg_output`, `bg_stop`, and `/ps`; completion wakes the parent |
| `daily/` | Daily run-state injection, diary edit guard and the `/run-day` event/inbox watcher; shares parser modules with Claude Code |
| `secrets-guard/` | Blocks Pi file tools from reading or writing `~/.secrets` and the Jira environment file; Bash guards run separately through `claude-hooks` |
| `artifacts-home/` | Keeps Pi artifacts under `~/artifacts/pi/` by linking the project artifact path |
| [session-models](extensions/session-models/README.md) | Live model-pool injection; does not launch children or call providers |
| `mcp-env/` | Expands environment references and registers MCP servers; skips servers with missing variables |
| `inline-files/` | Expands `@path` into file contents when the model has no tools |
| [pi-recap](packages/pi-recap/README.md) | Vendored recap widget and `/recap`; uses Pi's model registry for requests |

The recap model is configured separately in `extensions/pi-recap.json` as
`opencode-go/space-bunny-free`. `/recap config` changes it; `/recap status`
reports its state. It does not inherit the startup default or subagent pool.

`settings.json` also declares packages for web search/access, todo lists,
questions, browser artifacts, context display, memory, background tasks,
Superpowers skills, Ponytail, pi-lens, and Billion Context. Except for the
pinned subagent package, npm declarations are unversioned. `pi list` shows
configured packages; `pi config` controls discovered resources.

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

`archive/subagents/` preserves the old custom runtime outside extension discovery.
Do not load it alongside upstream `pi-subagents`. The old `subagents.json`,
`subagent-models.json`, `subagent-model-guide.md`, and `subagents-research.md`
remain historical material, not active routing configuration. Their Claude
Bridge references do not enable that provider. The linker removes only retired
links owned by this checkout, preserving real files and foreign links.
See [archive/README.md](archive/README.md) for rollback notes.

## Verification

From the repo root, with Node.js 24 (native TypeScript test support) and the
configured subagent package installed:

```sh
./bin/plink.test.sh
PI_SUBAGENTS_PACKAGE="$HOME/.pi/agent/npm/node_modules/pi-subagents" \
  node --test pi/agents.test.mjs
for extension in artifacts-home daily inline-files mcp-env secrets-guard session-models; do
  (cd "pi/extensions/$extension" && npm test) || break
done
git diff --check
```

These checks cover linking, agent discovery, and local extension behavior; they
do not prove remote provider authentication, model health, or successful live
subagent execution. The vendored recap package currently has no test script.
