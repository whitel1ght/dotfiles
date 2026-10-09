---
name: jira-write
description: Move a Jira ticket to a status or add a comment on it (ecfxdev.atlassian.net), always after the user confirms the exact change. Use when a plan item needs a Jira transition ("move ECFX-123 to In QA") or a Jira comment, for example a review-round one-liner with a new head SHA.
allowed-tools: Bash
---

# jira-write

Two writes, both over `~/bin/jira-api` (needs `JIRA_EMAIL` and `JIRA_API_TOKEN`). Jira writes are visible to other people, so **you never run one without the user's yes in this conversation for exactly that change**.

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/jira-write/scripts/jira-write"
```

## Transition

1. `"$S" --dry-run transition ECFX-123 "In QA"` resolves the status name to a transition id (case-insensitive) and prints what it would do. Exit 3 lists the statuses that are reachable from the ticket's current status: show them and ask which one.
2. Show the user the dry-run line and ask for confirmation.
3. On yes: `"$S" transition ECFX-123 "In QA"`.

## Comment

1. Write the comment text to a file in the scratchpad. Plain text; a blank line starts a new paragraph.
2. `"$S" --dry-run comment ECFX-123 <file>` and show the user the text that would be posted.
3. On yes: `"$S" comment ECFX-123 <file>`.

An exit code other than 0 means nothing was written (exit 1: Jira refused, its message is on stderr).
