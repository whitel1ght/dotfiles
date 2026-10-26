# daily (pi extension)

The pi half of the daily-run system. Claude Code's `daily` plugin
(`~/projects/dotfiles/claude/daily`) stays untouched; this extension is the independent pi
glue over the **same** on-disk state, so either harness can drive a day and both read each
other's bytes.

Three jobs, all reusing Claude Code's harness-free parsers in place
(`../../../claude/daily/mod/*.ts` — diary, events, guard, inbox, runstate):

- **`before_agent_start`** — injects today's run state and diary plan block as the
  `<daily_run_state>` system section at the start of every turn. Replaces CC's `SessionStart`
  hook and, unlike it, refreshes after a compaction. (`context_with_system` looks like the
  right hook but its sections never reach the request — measured on pi 1.2.0.) Silent unless `~/.local/state/run-day/<today>.md` exists. Same 6000-char cap
  and the same trim order (diary block first, run state always survives). Also announces
  items whose `needs_you` flipped on, once each — pi's replacement for `PushNotification`.
- **`tool_call`** — the diary tick guard. Blocks an `edit`/`write` on today's diary that would
  newly tick `[X]` without evidence (an MR link, a `[↗]` ref, `merged`, or `· note:`), or that
  would delete the plan block. pi's edit tool takes `{path, edits:[{oldText,newText}]}`, so the
  edits are applied in order through CC's `applyEdit` before `checkTicks` judges the result.
- **`run_day_watch` tool** ([`watch.ts`](watch.ts)) — the event and inbox watcher, CC's
  `hooks/register.tsx` `watch`/`watchInbox` on the same code: the inbox every 30 s,
  `changes-since --cursor run-day` every 3 min, events classified by `mod/events.ts` into
  `[daily-event]` lines (start a turn) and `[daily-event:info]` lines (added for the next
  turn), `inbox: N new` for new messages. One notice when event checks start failing and one
  when they recover; a timeout is logged as friction (changes-since logs its own outages).
  Started by `/run-day` in its own session, so other pi sessions open the same day are never
  woken; `watch.lock` in the state dir keeps a second pi session from consuming the same
  cursor. Stops on `stop`, on session shutdown, and by itself once the run state is gone.

Everything else CC's plugin does is native pi or an existing repo tool: model tiers come from
the `session-models` extension's `<subagent_models>` list at run time, the plan display is `day-plan`
(tmux popup), running agents are the `pi-sub` footer and `/agents` overlay.

Playbooks: `~/projects/dotfiles/pi/prompts/{run-day,handoff,pickup,report-back}.md`
(symlinked to `~/.pi/agent/prompts/`).

Env overrides, honoured by both harnesses: `RUN_DAY_STATE_DIR`, `WIKI_DIR`, `RUN_DAY_DATE`.

Run one harness per day. Both write the same diary lines and the same run-state file; two
`/run-day` sessions on one day will fight. `/run-day` step 0 asks before taking over a day it
did not start.

```bash
npm test   # node --test *.test.ts
```
