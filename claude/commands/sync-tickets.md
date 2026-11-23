---
description: Verify my Jira tickets against my GitLab MRs and worktrees, and fix the drift (since the last run)
argument-hint: [--since 3d] [-n] [-v]
model: haiku
allowed-tools: Bash(~/.local/bin/sync-tickets:*)
disable-model-invocation: true
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/sync-tickets $ARGUMENTS
```

The script does all the work and has already applied its changes when it returns.
Don't re-run it, don't call Jira or GitLab yourself, and don't try to fix anything.
A ticket whose MRs are all merged goes to Ready for QA, never In QA: QA has not started,
and they move it on themselves.

During the day tickets move as their work does (`ticket-move`, from `wt add`, `mr-ship` and
run-day's merge handling), so this run is the check on that: a ticket it still has to move is
drift the day missed.

Reply with a short summary of its output:

- **Drift**: the `drift:` line, and each moved ticket as `KEY: from → to`. None means the day
  kept every ticket in step; say so.
- **Linked** MRs, as a count per ticket.
- **Behind** tickets, verbatim, since they need a human decision.
- **Needs summary** keys (the `needs summary:` line), verbatim: merged Bugs left in place
  because Jira wants a Resolution Summary first; the user drafts it and moves them with
  `jira-write --resolution-summary`.
- The final summary line.

Leave out skipped tickets unless `-v` was passed. If the script failed, show its error
line. If the error mentions an expired token, add that a new one comes from
https://id.atlassian.com/manage-profile/security/api-tokens and goes in
`~/.secrets/secrets.env` as `JIRA_TOKEN` (the user edits it with `secrets`; you never open it).
