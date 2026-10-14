# Subagent model selection

Delegation is `acp_delegate` (registered by the `billion-context` package). There is no
`subagent` tool, no `subagents_enable`, and no workflow runner in this install; `pi-contract`
fails if a prompt names a tool that does not exist.

The parent chooses an explicit exact `provider/model` on each launch:

```
acp_delegate({ agent: "worker", task: "<self-contained brief>",
               model: "<provider/id from the live list>", cwd: "<worktree>", async: true })
```

The `session-models` extension injects the live **selected ∩ available** list before every
model request. Choose only from that list. Available means configured with credentials
according to Pi, not health-tested. If no IDs are listed, do not launch; ask the user to
repair the pool.

`pi/billion-context.json` pins a default model per role (`pi.subagents.agents.<role>.model`),
so a launch that omits `model` runs on the pin instead of inheriting the parent's. The pin
is a floor, not enforcement: an explicit `model` wins, and nothing in Pi rejects an
out-of-pool model. Pass the model explicitly.

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

Five fixed roles, and only these: `reviewer`, `researcher`, `planner`, `oracle` (read-only:
read, bash, grep, find, ls) and `worker` (read, edit, write, bash). Tool restrictions are
not a filesystem sandbox — a read-only role can still shell out. Named specialists are not
launchable: put the specialist's guidance in the task text, or run that specialist's lens
through `reviewer`/`oracle` first and paste its findings into a `worker` brief.

- The delegate sees none of this conversation. The task must be self-contained: paths,
  goals, constraints, and the report format you expect.
- Parallel work is one `acp_delegate` call per child, all in the same turn. Each call takes
  its own `cwd`, which is why there is no shared-workflow form.
- `async: true` is the default and returns a `runId`. Fetch the result with
  `acp_delegate_wait({ runId, timeout })`, which blocks; if you let it time out, the
  completion notification still arrives and names the result file — `read` that instead of
  re-waiting. There is no non-blocking status call.
- Stop a run with `acp_delegate_cancel({ runId })`. Continue a failed or cancelled one with
  `acp_delegate({ resumeFrom: "<runId>", task: "<what to pick up>" })`; its output files
  survive the failure.
- One launch uses one chosen model. If it fails, inspect the error and make an explicit
  informed retry (or report the failure); do not cycle through providers or run ping
  probes. There is no model-selection questionnaire or hidden fallback ladder.
The role pins in `pi/billion-context.json` are read when `pi` starts — a session that was already running keeps its old defaults (it will inherit the parent model), so restart `pi` after changing a pin.
