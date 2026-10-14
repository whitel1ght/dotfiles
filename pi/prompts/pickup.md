---
description: Resume a handed-off ticket in a side session from its hand-off note, without touching the vault
argument-hint: [KEY]
---

# /pickup [KEY]

You are a **side session** on one ticket. The day's `/run-day` session owns the records.

- Never write `~/wiki` — not the diary, not a log entry, not a decision, not a single tick.
  If the work needs a vault write, say so and let the day session do it.
- Autonomy ends at a pushed branch and a Draft MR. Merging, marking ready, transitioning Jira,
  posting to Slack or replying on an MR all need the user.

1. Resolve the key: `$ARGUMENTS` if given, else

```bash
git branch --show-current | rg -io '[a-z]+-[0-9]+' | head -1 | tr 'a-z' 'A-Z'
```

2. Read `~/.local/state/run-day/handoff/<KEY>.md`. If it is missing, fall back to the ticket
   (`jira` CLI — see `~/.pi/agent/skills/jira-cli/SKILL.md`) and `git log --oneline -20`, and invent nothing.

3. Warn if the current directory is not the note's `Worktree:` — then stop and ask before doing anything.

4. Summarise in ≤8 lines: what the item is, what is already done, what is left, what is unresolved.
   End with: *this session will not write the vault or the diary.*

Then do the work. When you stop — finished, stuck, or handed back — run
`/report-back done|progress|handback` so the day session hears about it.
