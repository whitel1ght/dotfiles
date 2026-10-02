# subagents

Lets the model hand a self-contained task to a subagent — a separate `pi` run on a
cheaper model — and carry on while it works. Claude Code's Task tool, for Pi, except
that the parent picks the model.

| Tool | |
| --- | --- |
| `agent_spawn` | Start a subagent for `task` of a given `type`, on `model`; returns its id (`agent-N`) at once |
| `agent_list` | Status, type, model, runtime, tool calls and cost of every subagent |
| `agent_output` | The result if finished, recent activity if not; never waits |
| `agent_wait` | Block until the given (or all running) subagents finish, then return their results |
| `agent_stop` | Stop one, and everything it started |

`/agents` lists them for you; select one to see its task, activity and result
(`↑↓`/`jk` `ctrl+u`/`ctrl+d` scroll, `G` follow, `x` stop, `esc` back).

## Choosing the model

`~/.pi/agent/subagents.json` (from `pi/subagents.json`) is the roster. Each task type
has a description, a fixed tool set, and its models ranked best first for that kind
of work, with a `claude-bridge/*` model as the last fallback. The ranking comes from
public benchmarks; [`pi/subagents-research.md`](../../subagents-research.md) has the
numbers, the sources and the reasons.

| Type | Tools | Models, best first |
| --- | --- | --- |
| `implement` | read + edit | glm-5.3 → grok-4.7 → qwen3.8-max → mimo-v2.6-pro → Sonnet |
| `review` | read-only | qwen3.8-max → grok-4.7 → glm-5.3 → mimo-v2.6-pro → Sonnet |
| `reason` | read-only | mimo-v2.6-pro → grok-4.7 → kimi-k3 → qwen3.8-max → Opus |
| `explore` | read-only | glm-5.3-flash → qwen3.8-flash → mimo-v2.6-flash → deepseek-v4.1-flash → Sonnet |
| `text` | none | glm-5.3-flash → qwen3.8-flash → mimo-v2.6-flash → Haiku |

The parent picks only the type. The extension walks the list:

1. **Skip what cannot work**: the parent's own model, a model pi has no credentials
   for, the local model when it is busy, Ollama is down, or the task is too big for it.
2. **Ping**: the model must answer a one-line prompt through a child pi within
   `pingTimeoutSeconds` (20). Same pi, provider and credentials as the real run, so a
   401, an expired token, a privacy block or an overloaded provider is caught in
   seconds. Answers are remembered for `pingCacheSeconds` (300), failures for a minute.
3. **Run**, under a watchdog: a child silent for `stallSeconds` (120) while the model
   is generating, or `toolStallSeconds` (900) while one of its tool calls runs, or
   `localStallSeconds` (300) on the local model, is killed as stalled.
4. **Fall back** when the run fails, stalls, or ends without an answer: the next model
   gets the task, told how far earlier attempts got, since files may be half edited.

A subagent fails only when every model on its list has. `agent_output`, the wake-up
message and `/agents` show every model tried and why each was passed over.

`model` starts further down the list (or, for `text`, on the local model). The config
refuses a list without three models before its single Claude fallback, any
`anthropic/*` model (API billing), and the local model inside a list.

- **Local only by name.** `localModel` (`qwen2.5-coder:14b-16k`) is free but far
  weaker than the lists, and it cannot make tool calls — it prints them as JSON. So it
  is in no list: the parent can name it for a `text` task, its runs skip skills,
  context files and extensions, one runs at a time, and Ollama must be up.
- **A local task must fit.** Ollama does not reject an oversized prompt, it drops its
  start. So the local model is passed over when the task's estimate (3 bytes a token)
  exceeds the window less the answer (`maxTokens`) and pi's own prompt — about 10.8k
  tokens of 16k — and the chain goes on to the cloud models.

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
- **Profiles.** `profile` names a file in `~/.pi/agent/agents/` (the OpenCode agents);
  its body joins the child's system prompt, and `permission: edit: deny` removes
  `edit`/`write` from its tools.
- **Limits.** `maxRunning` (4) at once; a task over 200KB is refused — write it to a
  file and pass the path. Results over 16KB are cut, with the whole answer on disk.
- **Stopping is final.** `agent_stop` and `x` in `/agents` do not fall back.
- **Lifetime.** Running subagents and pings are killed when the session ends.

## Layout

`src/roster.ts` (the config and its rules), `src/invocation.ts` (the child command
line), `src/stream.ts` (reading the child's JSON events), `src/agents.ts` (the model
chain, watchdog and lifecycle, on top of `background-terminals`' `TerminalManager`), `src/profiles.ts`,
`src/ping.ts` (the ping and its cache), `src/budget.ts` (whether a task fits the local window),
`src/format.ts` and `src/prompt.ts` (everything the model reads), `src/ui/view.ts`
(the `/agents` viewer), `index.ts` (the only file that touches Pi's API).

Process handling, spill files, the wake queue and the viewer's windowing are imported
from `../background-terminals/src`, so the two extensions must stay side by side.

```sh
npm test    # node --test, in this directory; test/fake-pi.mjs stands in for pi
```
