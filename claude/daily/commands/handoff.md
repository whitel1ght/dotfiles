---
description: For the /run-day session — hand a tracked ticket over to a Claude session the user drives ("hand off 18384", "I'll take ECFX-18384 myself"); opens it in a tmux window. Only when the user explicitly asks to work this item themselves; never on your own initiative.
argument-hint: KEY
allowed-tools: Bash(diary-links:*), Bash(git -C:*), Bash(mkdir:*), Bash(date:*), Bash(ls:*), Bash(handoff-open:*), Read, Edit, Write, TaskStop
---

# Hand off a ticket

Arguments: $ARGUMENTS

Run this in the main session (the one running `/run-day`). It moves one ticket from a background agent to a Claude session you drive yourself. The write rules of `/run-day` hold: here you edit only the diary plan block, the run-state file and the hand-off note. Never write to `~/wiki` beyond the diary line, and never touch the worktree's files.

Only when the user explicitly asks to work this item themselves; never on your own initiative.

Paths (`T` is `date +%F`): run state `~/.local/state/run-day/$T.md`, note `~/.local/state/run-day/handoff/<KEY>.md`. `<KEY>` is the argument in uppercase (`ECFX-18169`); a bare number (`18169`) is `ECFX-` plus the number, `<key>` the lowercase form used in the run state.

1. Check. No run-state file, or no `- <key> | ...` line in it: say `/daily:handoff needs an item tracked by /run-day` and stop. If that line already says `owner=external:<KEY>`, say it is already handed off, do step 7 again, and stop without changing anything. If the line has no worktree (`worktree=-`), say there is nothing to hand off yet and stop.
2. Collect the progress from the worktree, not from the agent, and do not wait for the agent:

```bash
W=<worktree from the run-state line>
git -C "$W" branch --show-current
git -C "$W" log --oneline @{upstream}..HEAD 2>/dev/null || git -C "$W" log --oneline -10
git -C "$W" diff --stat
git -C "$W" status --short
```

3. If the line has an agent id (`agent=` not `-`) and the agent is still running, stop it with `TaskStop` (load it with ToolSearch first if it is deferred). The worktree is kept exactly as the agent left it. If the agent already finished, skip this step.
4. Write the hand-off note (create the directory). `<repo>` is the name from the git remote, or, with no remote, the `<repo>` in the worktree path `.../worktrees/<repo>/<KEY>`. Original brief: the scratchpad file `brief-<key>.md` from dispatch when it exists, otherwise the plan line plus the Jira summary (`jira-api GET issue/<KEY>`). Open questions: what the agent's last report in this session said it could not decide, or `none recorded`.

```
# Hand-off: <KEY> — <summary>
Handed off: <ISO time>
Repo: <repo>
Worktree: <path>
Branch: <branch>
MR: <url or none>

## Original brief
<brief>

## Progress so far
<log, diff --stat, status, the agent's last report if this session received one>

## Open questions
<questions or "none recorded">
```

5. Run state: set `agent=-`, `needs_you=no`, `owner=external:<KEY>` on the line; leave `class`, `worktree`, `mr`, `retries`.
   Withdraw the item's open decisions; the side session asks the user directly:

   ```bash
   for id in $(decide list --json | jq -r --arg k "<KEY>" '.[] | select(.key == $k) | .id'); do
     decide withdraw "$id" handed off && decide close "$id"
   done
   ```
6. Diary: set the item's line to `[/]` and put `· with you: <KEY>` first in its evidence, keeping any MR evidence after it (for example `- [/] ecfx-18169 fix the 3 majors · with you: ECFX-18169 · draft MR dashboard!2231  [↗][dashboard!2231]`). Edit only that line, keep its trailing refs last, then run `diary-links ~/wiki/diary/$(date +%F).md`.
7. Open the side session, and tell the user to run `/daily:report-back done` (or `handback`) in it when they stop. Run, with the literal key and the absolute worktree path from the run-state line (a leading `~` becomes `$HOME`):

```bash
handoff-open <KEY> "<worktree>"
```

   It finds this session's tmux session even when `$TMUX` is empty, focuses the ticket's window if one is open (never a second claude session), else opens one running `claude -n <KEY> "/daily:pickup <KEY>"`. Say which window it opened or focused (`opened …` / `focused …`). Only when it prints `run: …` (no tmux at all) give the user that command to run in a new terminal. Never tell the user to open the window themselves after it printed `opened` or `focused`.
