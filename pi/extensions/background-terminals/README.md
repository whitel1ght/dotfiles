# background-terminals

Lets the model start long-running shell commands, keep working while they run,
and be woken when they finish — Claude Code's background shells, for Pi.

| Tool | |
| --- | --- |
| `bg_start` | Run `command` with `bash -c`, return its id (`bg-N`) at once |
| `bg_list` | Status, pid, runtime and cwd of every terminal |
| `bg_output` | Last N lines of stdout/stderr, never more than ~16KB per stream |
| `bg_stop` | SIGTERM to the whole process group, SIGKILL after 3s (or at once with `force`) |

`/ps` lists them for you; select one for a live, scrollable view
(`tab` stream, `↑↓`/`jk` and `ctrl+u`/`ctrl+d` scroll, `G` follow, `x` stop, `esc` back).
While any are running a line above the editor says so.

## Behaviour worth knowing

- **No stdin.** A process that reads input sees EOF, so it can never hang on a prompt.
- **Woken once.** A terminal that exits on its own sends the model one message with
  the exit status and the last lines of output. If the agent is busy the message waits
  for `agent_settled`; if the model already read the output (`bg_output`) or stopped it
  (`bg_stop`) in the meantime, nothing is sent. Several finishes become one message.
- **Nothing is lost.** Each stream is spilled to `$TMPDIR/pi-bg-*/bg-N.{stdout,stderr}`
  (capped at 64MB each); only a 64KB tail stays in memory. Results name the files so
  the model can `read` them.
- **Limits.** 8 running at once, 64 tracked (oldest finished are pruned).
- **Lifetime.** Everything is killed, and the spill files removed, when the session
  ends — including `/reload` and `/new`. A grandchild that outlives its parent
  (`cmd &`) is left alone once the parent exits.

## Layout

`src/manager.ts` (spawn, signals, lifecycle), `src/output.ts` (spill + tail),
`src/format.ts` and `src/prompt.ts` (everything the model reads),
`src/wake-queue.ts` (deferred delivery), `src/ui/view.ts` (the `/ps` viewer),
`index.ts` (the only file that touches Pi's API).

Everything outside `index.ts` and `src/ui/` is plain Node with no dependencies, and
the files avoid TypeScript syntax that Node's type stripping rejects, so the tests
run without a build step:

```sh
npm test    # node --test, in this directory
```
