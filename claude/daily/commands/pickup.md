---
description: In a side session, load the hand-off note from /run-day for a ticket and continue it
argument-hint: [KEY]
---

# Pick up a handed-off ticket

Arguments: $ARGUMENTS

You are a side session: the user drives you directly, the `/run-day` session records the day. Rules for this session:

- Never write to `~/wiki` or to the diary (`~/wiki/diary/`), not even a tick or a note. The day session records everything from the inbox.
- The normal autonomy rules apply: up to a pushed branch and a **Draft** MR; no marking ready, merging, Jira transitions, Slack or comments without asking.

1. KEY is the argument in uppercase, or the ticket key in the branch name: `git branch --show-current | rg -io '[a-z]+-[0-9]+' | head -1`. No key either way: ask the user.
2. Read `~/.local/state/run-day/handoff/<KEY>.md`. If it does not exist, say so in one line and continue from the ticket itself (`jira-api GET issue/<KEY>`, `git log`), inventing nothing.
3. Summarise the note in at most 8 lines: what the ticket is, where the work stands, the open questions. Warn if the current directory is not the worktree the note names.
4. Continue the work with the user. When you stop, run `/report-back done`, `/report-back progress` or `/report-back handback` so the day session learns what happened.
