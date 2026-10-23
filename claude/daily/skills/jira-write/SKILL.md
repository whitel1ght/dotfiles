---
name: jira-write
description: Move a Jira ticket to a status or add a comment on it (ecfxdev.atlassian.net), always after the user confirms the exact change. Use when a plan item needs a Jira transition ("move ECFX-123 to In QA") or a Jira comment, for example a review-round one-liner with a new head SHA.
allowed-tools: Bash(*/jira-write --dry-run:*)
---

# jira-write

Two writes, both over `~/bin/jira-api` (it reads the Jira token from `~/.secrets` itself). Jira writes are visible to other people, so **you never run one without the user's yes in this conversation for exactly that change**.

Each Bash call is a new shell, so every command below spells out the full script path, unquoted so the permission rule matches it. Only the `--dry-run` form is pre-approved; a real write always prompts.

## Transition

1. `${CLAUDE_PLUGIN_ROOT}/skills/jira-write/scripts/jira-write --dry-run transition ECFX-123 "In QA"` resolves the status name to a transition id (case-insensitive) and prints what it would do. Exit 3 lists the statuses that are reachable from the ticket's current status: show them and ask which one.
2. Show the user the dry-run line and ask for confirmation.
3. On yes: `${CLAUDE_PLUGIN_ROOT}/skills/jira-write/scripts/jira-write transition ECFX-123 "In QA"`.

A transition can be named by its name or by its target status ("Ready for QA" finds "Code review completed"); both match case-insensitively.

### Bug to Ready for QA or In QA

Jira refuses a Bug there without a Resolution Summary, and `jira-write` exits 4 before sending when it is missing. Always draft the summary in the house style: one or two plain-language sentences for CS and customers, "Fixed <area> to <what now happens>, so <symptom> no longer <happens>. MR !NNNN." No class or method names; add "deployed to dev01" only when verified. Write it to a file (blank line starts a new paragraph), pass it with `--resolution-summary <file>` in both the dry run and the real call, and show the summary with the dry-run line in the same confirmation.

## Comment

1. Write the comment text to a file in the scratchpad. Plain text; a blank line starts a new paragraph.
2. `${CLAUDE_PLUGIN_ROOT}/skills/jira-write/scripts/jira-write --dry-run comment ECFX-123 <file>` and show the user the text that would be posted.
3. On yes: `${CLAUDE_PLUGIN_ROOT}/skills/jira-write/scripts/jira-write comment ECFX-123 <file>`.

An exit code other than 0 means nothing was written (exit 1: Jira refused, its message is on stderr).
