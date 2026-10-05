# subagents

Lets the model hand a self-contained task to a subagent — a separate `pi` run on a
separate model — and carry on while it works. Claude Code's Task tool, for Pi, except
that the parent picks the model for each subagent.

| Tool | |
| --- | --- |
| `agent_models` | The models this session may give a subagent right now, with catalogue notes |
| `agent_spawn` | Start a subagent for `task` of a given `type`, on a required `model` from that list; returns its id (`agent-N`) at once |
| `agent_list` | Status, type, model, runtime, tool calls and cost of every subagent |
| `agent_output` | The result if finished, recent activity if not; never waits |
| `agent_wait` | Block until the given (or all running) subagents finish, then return their results |
| `agent_stop` | Stop one, and everything it started |

`/agents` lists them for you; select one to see its task, activity and result
(`↑↓`/`jk` `ctrl+u`/`ctrl+d` scroll, `G` follow, `x` stop, `esc` back).

## Choosing the model

The parent picks the model for every subagent, by its own judgment of the task. There is
no ranking to follow and no automatic fallback.

- **The pool is the session's.** `agent_models` returns the session's scoped models (the
  `enabledModels` / `--models` set the user manages with `/scoped-models`) that pi has
  credentials for; an empty scope means every authenticated model. It is read from the live
  session on each call, so a changed scope or login shows at once. The extension never
  changes the session's models.
- **`model` is required** on `agent_spawn` and must be in that pool; otherwise the call
  fails and names the pool. The type's old model list is not a gate, and `modelProfile` is
  gone from the tool, so nothing bypasses the pool. (`modelProfiles` in `subagents.json`
  still parses and is ignored.)
- **One model, no switching.** The subagent runs on exactly that model, after a cheap
  preflight and a ping (below). If it does not answer, fails, stalls or ends without an
  answer, the agent fails with that reason and nothing else is tried; the parent decides
  whether to spawn again, on the same model or another. The parent's own model is allowed.
- **Overlapping roles.** The catalogue in `~/.pi/agent/subagent-models.json` (from
  `pi/subagent-models.json`) holds notes per model — quality, speed, cost, strengths, what
  to avoid it for — which `agent_models` shows next to each pool member. Reasoning-leaning
  models, coding-leaning ones and inexpensive ones overlap; the notes inform the choice and
  do not order it. [`pi/subagent-model-guide.md`](../../subagent-model-guide.md) is the
  generated human-readable view (`npm run generate-guide`);
  [`pi/subagents-research.md`](../../subagents-research.md) has the benchmark numbers and
  sources. `npm run check-models` checks that every catalogue model appears in
  `pi --list-models`.
- **Task types** (`implement`, `review`, `reason`, `explore`, `text`, from
  `~/.pi/agent/subagents.json`) fix the subagent's tools and nothing else.
- **`agent_select_models` is retired from the model's tool set.** The user-facing picker
  (`src/select-models-tool.ts`, `src/ui/`) is kept but registered with `exposure: "hidden"`,
  because a per-flow user gate contradicts the parent deciding. Skills whose model gate
  says "when `agent_select_models` is available; otherwise skip" therefore skip it. To
  bring the gate back, remove that line in `index.ts`.

The run, step by step:

1. **Preflight**: the model has credentials, and for the local model Ollama is up and the
   task fits.
2. **Ping**: it must answer a one-line prompt through a child pi within
   `pingTimeoutSeconds` (20). Same pi, provider and credentials as the real run, so a
   401, an expired token or an overloaded provider is caught in seconds. Answers are
   remembered for `pingCacheSeconds` (300), failures for a minute.
3. **Run**, under a watchdog: a child silent for `stallSeconds` (120) while the model
   is generating, or `toolStallSeconds` (900) while one of its tool calls runs, or
   `localStallSeconds` (300) on the local model, is killed as stalled.

`agent_output`, the wake-up message and `/agents` show the model and why a failed run failed.

- **Local only by name.** `localModel` (`qwen2.5-coder:14b-16k`) is free but far
  weaker, and it cannot make tool calls — it prints them as JSON. So it can run only a
  tool-less (`text`) task, its runs skip skills, context files and extensions, one runs
  at a time, and Ollama must be up.
- **A local task must fit.** Ollama does not reject an oversized prompt, it drops its
  start. So the local model is refused when the task's estimate (3 bytes a token)
  exceeds the window less the answer (`maxTokens`) and pi's own prompt — about 10.8k
  tokens of 16k.

## Behaviour worth knowing

- **A child is a process, not a session.** `pi --mode json -p --no-session` with the
  model, a `--tools` allowlist and a short "you are a subagent" system-prompt addition.
  A separate process is what lets `claude-bridge` models work: the bridge is loaded the
  normal way in the child, not a second time inside the parent.
- **Failure comes from the stream.** Pi exits 0 even when the provider rejects every
  request (a bad API key, say), so a run is failed when its last model call errored or
  it never produced a final answer, and the next model takes over.
- **Woken once**, exactly as background terminals are: a finish is delivered when the
  agent goes idle, unless `agent_output`/`agent_wait`/`agent_stop` already showed it.
- **No recursion.** Children run with `PI_SUBAGENT=1`, and the extension does nothing
  in a child.
- **Personas.** `profile` names a file in `~/.pi/agent/agents/` (the OpenCode agents);
  its body joins the child's system prompt, and `permission: edit: deny` removes
  `edit`/`write` from its tools.
- **Limits.** `maxRunning` (4) at once; a task over 200KB is refused — write it to a
  file and pass the path. Results over 16KB are cut, with the whole answer on disk.
- **Stopping is final.** `agent_stop` and `x` in `/agents` end the agent.
- **Lifetime.** Running subagents and pings are killed when the session ends.

## Layout

`src/pool.ts` (the session pool and the model check), `src/roster.ts` (the config and its rules), `src/invocation.ts` (the child command
line), `src/stream.ts` (reading the child's JSON events), `src/agents.ts` (the attempt,
watchdog and lifecycle, on top of `background-terminals`' `TerminalManager`), `src/profiles.ts`,
`src/ping.ts` (the ping and its cache), `src/budget.ts` (whether a task fits the local window),
`src/format.ts` and `src/prompt.ts` (everything the model reads), `src/ui/view.ts`
(the `/agents` viewer), `index.ts` (the only file that touches Pi's API).

Process handling, spill files, the wake queue and the viewer's windowing are imported
from `../background-terminals/src`, so the two extensions must stay side by side.

```sh
npm test    # node --test, in this directory; test/fake-pi.mjs stands in for pi
```
