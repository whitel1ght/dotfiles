# Subagent model selection

Delegation is the `subagent` tool (registered by `pi/extensions/pi-sub`). `pi-contract`
fails if a prompt names a tool that does not exist.

The parent chooses an explicit exact `provider/model` on every launch:

```
subagent({ role: "worker", model: "<provider/id from the live list>",
           task: "<self-contained brief>", cwd: "<worktree>", label: "<KEY>" })
```

The `session-models` extension injects the live **selected ∩ available** list before every
model request. Choose only from that list; `subagent` rejects a model that is not in it.
Available means configured with credentials according to Pi, not health-tested. If no IDs
are listed, do not launch; ask the user to repair the pool. There are no per-role default
models: `model` is required.

Choose the least expensive model likely to succeed:
- Simple extraction, supplied-text transformations, and bounded reading: a cheap
  model that supports the required tools and context.
- Implementation and debugging: a capable coding model; weigh test complexity,
  repository size, and ambiguity rather than provider name alone.
- Security-sensitive review, architecture, and subtle root-cause analysis: stronger
  reasoning and sufficient context. Do not save cost by guessing about capability.

There are no fixed provider tiers. Model names are not evidence of performance.
Use known capabilities and user preferences; if these are unknown, choose a
capable listed model conservatively. Providers not in the live list are not
options, and a model-selection policy never widens the pool.

## Roles and mechanics

A role is a file in `~/.pi/agent/agents/<role>.md` (linked from `pi/agents/`): its body is
appended to the child's system prompt and its `tools:` line is the child's tool allowlist.
`worker` (read, bash, edit, write, grep, find, ls) implements. `reviewer`, `researcher`,
`planner`, `oracle` and the named specialists — `security-compliance-reviewer`,
`prod-readiness`, `vue-expert`, `java-clean-code-purist`, … — are read-only (read, bash,
grep, find, ls). Tool restrictions are not a filesystem sandbox — a read-only role can still
shell out. An unknown role fails the launch and lists the available ones.

- The child starts empty: no conversation, no AGENTS.md or project context, no skills, no
  memory. The task must be self-contained: paths, goals, constraints, and the report format
  you expect. Add a skill with `skills: ["<path>"]`; add web access or a browser with
  `with: ["web"]` / `with: ["playwright"]`. Write-capable roles get pi-lens diagnostics.
- Parallel work is one `subagent` call per child, all in the same turn, each with its own
  `cwd`.
- Every launch returns at once with an id. When the child finishes, fails or is stopped, a
  `[pi-sub]` message wakes this session and names the result file and the activity log.
  End the turn after launching; never wait, sleep or poll. `subagent_result({ id })` shows
  the result, or the live activity tail while it runs.
- A child quiet for `idle_minutes` (default 10) flags this session; one running past
  `max_minutes` (default 60) is stopped. Raise `max_minutes` for long implementation work.
- Stop a run with `subagent_stop({ id })`. There is no resume: to fix or continue a
  finished run, launch a fresh child whose task carries the failure, the result path of
  the earlier run, and what to do next.
- Children outlive the window. `subagent_handoff()` marks this session's agents for the
  next session; that session calls `subagent_adopt({ from: "<old session id>" })`.
  `ctrl+space` or `/agents` shows them all.
- One launch uses one chosen model. If it fails, inspect the error and make an explicit
  informed retry (or report the failure); do not cycle through providers or run ping
  probes. There is no model-selection questionnaire or hidden fallback ladder.
