---
description: Hand one in-flight item to a side session — write the hand-off note, mark the run state external, tell the user how to pick it up. Only when the user explicitly asks to work this item themselves; never on your own initiative.
argument-hint: <KEY>
---

# /handoff <KEY>

Move an item out of this day's session so a side session can finish it, without losing context.
Run it in the main session (the one running `/run-day`). Writes the hand-off note, the run state and
the diary — asks nothing. Never write `~/wiki` beyond the item's diary line and the `day-agent` note, and never touch the
worktree's files.

Only when the user explicitly asks to work this item themselves; never on your own initiative.

`<KEY>` is the argument in uppercase (`ECFX-18169`); a bare number (`18169`) is `ECFX-` plus the number, `<key>` the lowercase form the run state uses.

Stop when any of these hold, and say which:

- no run-state file `~/.local/state/run-day/$(date +%F).md`, or no `- <key> | ...` line in it:
  say `/handoff needs an item tracked by /run-day`
- the line already has `owner=external:<KEY>` (already handed off): do step 6 again and change
  nothing
- `worktree=-` (nothing was dispatched; there is no work to hand over)

1. Collect progress from the worktree on that line, not from the agent, and do not wait for the
   agent — one command per call, no invented facts:

```bash
W=<worktree>
git -C "$W" branch --show-current
git -C "$W" log --oneline @{upstream}..HEAD 2>/dev/null || git -C "$W" log --oneline -10
git -C "$W" diff --stat
git -C "$W" status --short
```

2. If the line has an agent id (`agent=` not `-`) and that subagent is still running,
   `subagent_stop({ id: "<id>" })`. The worktree is kept exactly as the agent left it. If it already
   finished, skip this step.

3. Write `~/.local/state/run-day/handoff/<KEY>.md` (`mkdir -p` the directory), exactly this shape:

```markdown
# Hand-off: <KEY> — <one-line summary>
Handed off: <ISO timestamp>
Repo: <repo>
Worktree: <path>
Branch: <branch>
MR: <url or none>

## Original brief
<the filled brief from ~/.local/state/run-day/scratch/brief-<key>.md, verbatim; if it is gone, the plan line and the ticket summary>

## Progress so far
<what the collected git output actually shows: commits, diff --stat, dirty files; plus the agent's last report if this session received one>

## Open questions
<what the agent's last report said it could not decide, or "none recorded">
```

   `<repo>` is the name from the worktree's git remote, or, with no remote, the `<repo>` in the
   worktree path `.../worktrees/<repo>/<KEY>`.

4. Update the run-state line for `<key>`: `agent=-`, `needs_you=no`, `owner=external:<KEY>`. Leave
   every other field (`class`, `worktree`, `mr`, `retries`, ...).

   Withdraw the item's open decisions; the side session files its own cards from here on:

   ```bash
   for id in $(decide list --json | jq -r --arg k "<KEY>" '.[] | select(.key == $k) | .id'); do
     decide withdraw "$id" handed off && decide close "$id"
   done
   ```
5. Diary: set the item to `[/]` and run `day-agent note <key> with-you "<KEY>"` (`<key>` is the
   line's `<!-- pN -->` id when it has one, else the lowercase ticket key). The MR link is already
   in the agent file; the plan line keeps only its marker and its few words. Edit only that line.
   Old format (no `~/wiki/diary/.agent/<date>.md`): put ` · with you: <KEY>` first in the line's
   evidence, keeping any MR evidence after it, for example
   `- [/] ecfx-18169 fix the 3 majors · with you: ECFX-18169 · draft MR dashboard!2231  [↗][dashboard!2231]`;
   keep its trailing refs last, then run `~/.local/bin/diary-links ~/wiki/diary/$(date +%F).md`.

6. Open the side session, and tell the user to run `/report-back done` (or `handback`) in it when
   they stop. Run, with the literal key and the absolute worktree path from the run-state line
   (a leading `~` becomes `$HOME`):

```bash
~/.local/bin/handoff-open <KEY> "<worktree>" pi
```

   It finds this session's tmux session even when `$TMUX` is empty, focuses the ticket's window if
   one is open (never a second pi session), else opens one running `pi -n <KEY> "/pickup <KEY>"`.
   Say which window it opened or focused (`opened …` / `focused …`). Only when it prints
   `run: …` (no tmux at all) give the user that command to run in a new terminal. Never tell the
   user to open the window themselves after it printed `opened` or `focused`.
