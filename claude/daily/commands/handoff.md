---
description: Hand a ticket that a /run-day agent is working over to a Claude session you drive yourself
argument-hint: KEY
disable-model-invocation: true
allowed-tools: Bash(git -C:*), Bash(mkdir:*), Bash(date:*), Bash(ls:*), Read, Edit, Write, TaskStop
---

# Hand off a ticket

Arguments: $ARGUMENTS

Run this in the main session (the one running `/run-day`). It moves one ticket from a background agent to a Claude session you drive yourself. The write rules of `/run-day` hold: here you edit only the diary plan block, the run-state file and the hand-off note. Never write to `~/wiki` beyond the diary line, and never touch the worktree's files.

Paths (`T` is `date +%F`): run state `~/.local/state/run-day/$T.md`, note `~/.local/state/run-day/handoff/<KEY>.md`. `<KEY>` is the argument in uppercase (`ECFX-18169`), `<key>` the lowercase form used in the run state.

1. Check. No run-state file, or no `- <key> | ...` line in it: say `/handoff needs an item tracked by /run-day` and stop. If that line already says `owner=external:<KEY>`, say it is already handed off, print the command of step 7 again, and stop without changing anything. If the line has no worktree (`worktree=-`), say there is nothing to hand off yet and stop.
2. Collect the progress from the worktree, not from the agent, and do not wait for the agent:

```bash
W=<worktree from the run-state line>
git -C "$W" branch --show-current
git -C "$W" log --oneline @{upstream}..HEAD 2>/dev/null || git -C "$W" log --oneline -10
git -C "$W" diff --stat
git -C "$W" status --short
```

3. If the line has an agent id (`agent=` not `-`) and the agent is still running, stop it with `TaskStop` (load it with ToolSearch first if it is deferred). The worktree is kept exactly as the agent left it. If the agent already finished, skip this step.
4. Write the hand-off note (create the directory). Original brief: the scratchpad file `brief-<key>.md` from dispatch when it exists, otherwise the plan line plus the Jira summary (`jira-api GET issue/<KEY>`). Open questions: what the agent's last report in this session said it could not decide, or `none recorded`.

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
6. Diary: set the item's line to `[/]` and put `· with you: <KEY>` first in its evidence, keeping any MR evidence after it (for example `- [/] ecfx-18169 fix the 3 majors · with you: ECFX-18169 · draft MR [dashboard!2231](url)`). Edit only that line.
7. Print, and tell the user to run `/report-back done` (or `handback`) in that session when they stop:

```
cd <worktree> && claude -n <KEY> "/pickup"
```
