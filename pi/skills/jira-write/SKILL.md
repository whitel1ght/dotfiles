---
name: jira-write
description: Move a Jira ticket to a status or add a comment on it (ecfxdev.atlassian.net), always after the user confirms the exact change. Use when a plan item needs a Jira transition ("move ECFX-123 to Ready for QA") or a Jira comment, for example a review-round one-liner with a new head SHA.
---

# jira-write

Two writes, both over `~/bin/jira-api` (it reads the Jira token from `~/.secrets` itself). Jira writes are visible to other people, so **you never run one without the user's yes in this conversation for exactly that change**. Always run the `--dry-run` form first and show its output.

The script is shared with Claude Code's `daily` plugin; use it in place:

```bash
J=~/projects/dotfiles/claude/daily/skills/jira-write/scripts/jira-write
```

Set `J` again in every bash call.

## Transition

When an MR merges, the ticket goes In MR → **Ready for QA** (transition "Code review completed"), not In QA or Done; it stays In MR while a follow-up MR or a manual check is still open (`~/wiki/projects/ecfx/decisions/0005-merged-tickets-go-to-ready-for-qa.md`).

1. `"$J" --dry-run transition ECFX-123 "Ready for QA"` resolves the status name to a transition id (case-insensitive) and prints what it would do. Exit 3 lists the statuses reachable from the ticket's current status: show them and ask which one.
2. Show the user the dry-run line and ask for confirmation.
3. On yes: `"$J" transition ECFX-123 "Ready for QA"`.

## Comment

1. Write the comment text to a file under `~/.local/state/run-day/scratch/` (or `/tmp`). Plain text; a blank line starts a new paragraph.
2. `"$J" --dry-run comment ECFX-123 <file>` and show the user the text that would be posted.
3. On yes: `"$J" comment ECFX-123 <file>`.

An exit code other than 0 means nothing was written (exit 1: Jira refused, its message is on stderr).
