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
| `models.json` | `pi/models.json`: local models and OpenCode Go overrides |
| `mcp-servers.json` | `pi/mcp-servers.json`: MCP definitions with environment references |
| `APPEND_SYSTEM.md`, `model-selection.md` | `pi/`: global assistant rules and delegation policy |
| `AGENTS.md` | `claude/CLAUDE.md`: shared personal instructions |
| `skills/` | `pi/skills/`: skills |
| `~/.agents/modules/` | `pi/modules/`: shared context files the skills and agents reference |
| `agents/` | `pi/agents/`: Pi-specific named subagent definitions |
| `prompts/` | `pi/prompts/`: slash-command templates |
| `extensions/` | `pi/extensions/`: local extensions and package configuration |

Project settings in `.pi/settings.json`
can override personal settings once the project is trusted.

## Models and authentication

The startup default is **`opencode-go/longcat-2.5`**. Changing the default affects
new sessions, not the model of an already running session.

The model-cycling/session pool in `settings.json` is separate from the default.
Currently it contains only:

- `openai/gpt-5.6-sol`
- `openai/gpt-5.6-terra`
- `openai/gpt-6-astra`
- `openai/gpt-6-luna`
- `openai/gpt-6-sol`
- `openai/gpt-6.1-sol`

LongCat is not in that pool. Use `/scoped-models` to change the live session pool;
edit `enabledModels` for the persistent selection. The default model setting
alone does not make LongCat eligible for scoped subagent launches.

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

A role is a file in `agents/<role>.md` (linked to `~/.pi/agent/agents`): its body is
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
| [daily](extensions/daily/README.md) | Injects the active `/run-day` state and plan block; blocks a diary `[x]` tick that carries no evidence |
| `mcp-env/` | Expands environment references and registers MCP servers; skips servers with missing variables |
| `inline-files/` | Expands `@path` into file contents when the model has no tools |
| [recap](extensions/recap/README.md) | One-line recap after idle and on `/recap`, on the session model; ours (forked from `@tifan/pi-recap` 0.4.7, upstream not tracked) |

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
remote provider authentication or model health. The vendored recap package currently has no test script.
