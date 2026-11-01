---
description: Move my Jira tickets to match my GitLab MRs (since the last run)
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

Reply with a short summary of its output:

- **Moved** tickets, as `KEY: from → to`.
- **Linked** MRs, as a count per ticket.
- **Behind** tickets, verbatim, since they need a human decision.
- The final summary line.

Leave out skipped tickets unless `-v` was passed. If the script failed, show its error
line. If the error mentions an expired token, add that a new one comes from
https://id.atlassian.com/manage-profile/security/api-tokens and goes in
`~/.config/mrglass/secrets.env`.
