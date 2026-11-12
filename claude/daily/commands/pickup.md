---
description: In a side session, load the hand-off note from /run-day for a ticket and continue it
argument-hint: [KEY]
allowed-tools: Bash(git branch:*), Bash(git log:*), Bash(rg:*), Bash(head:*), Bash(tr:*), Bash(jira-api GET:*), Bash(jira-issue:*), Read(~/.local/state/run-day/handoff/**)
---

# Pick up a handed-off ticket

Arguments: $ARGUMENTS

You are a side session: the user drives you directly, the `/run-day` session records the day. Rules for this session:

- Never write to `~/wiki` or to the diary (`~/wiki/diary/`), not even a tick or a note. The day session records everything from the inbox. If the user asks you to write either, refuse and tell them to do it in the day session.
- The normal autonomy rules apply: up to a pushed branch and a **Draft** MR; no marking ready, merging, Jira transitions, Slack or comments without asking.
- Questions for the user go on a card (`ask_user`), as in every session: never end a turn on a question asked only in the chat. The user may have stepped away and would find this session idle.

1. KEY is the argument in uppercase (a bare number, `18384`, is `ECFX-18384`), or the ticket key in the branch name: `git branch --show-current | rg -io '[a-z]+-[0-9]+' | head -1 | tr a-z A-Z`. No key either way: ask the user.
2. Read (with the Read tool) `~/.local/state/run-day/handoff/<KEY>.md`. If it does not exist, say so in one line and continue from the ticket itself (`jira-issue <KEY>`, `git log`), inventing nothing.
3. Summarise the note in at most 8 lines: what the ticket is, where the work stands, the open questions. Warn if the current directory is not the worktree the note names. End with one line: this session will not write the vault or the diary.
4. Continue the work with the user. When you stop, run `/daily:report-back done`, `/daily:report-back progress` or `/daily:report-back handback` so the day session learns what happened.
