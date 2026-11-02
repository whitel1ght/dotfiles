---
description: Where are we? Today's plan joined with live MR, Jira and agent state
argument-hint: [--date YYYY-MM-DD]
model: haiku
allowed-tools: Bash(~/.local/bin/day-status:*)
disable-model-invocation: true
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/day-status $ARGUMENTS
```

The script has already read the plan and asked GitLab, Jira and the run-day state.
Don't re-run it, don't call Jira or GitLab yourself, don't read the diary, and don't fix anything.
`unknown` means that source failed for that item: say so, don't guess.

Reply with a short summary of its output, a few lines in all:

- **Done**: items marked `done`, as keys.
- **In progress**: items being worked, with the agent id when there is one and what the MR shows (failed pipeline, unresolved threads, draft).
- **Waiting on someone**: items with an approved or opened MR, or marked `blocked`, that wait for a review, an approval or an answer.
- **Left**: items still `todo`, and `deferred` ones.

If the script printed an error (no diary or plan), give that line and stop.
