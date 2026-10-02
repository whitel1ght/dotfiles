---
description: Remove worktrees under ~/projects/worktrees whose MR has been merged
# argument-hint (inert in OpenCode): [-n]
# disable-model-invocation (structural): only ever reachable as a slash command.
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/clean-worktrees $ARGUMENTS
```

The script decides what is safe and has already removed it when it returns. Don't
remove, stash, commit or force anything yourself, even for worktrees it kept.

Reply with a short summary:

- **Removed**: one line each, `repo/name (!iid)`.
- **Kept, needs you**: worktrees kept because of uncommitted changes, unpushed
  commits or a closed MR, and directories that aren't worktrees, with the reason as
  printed.
- **Kept, still active**: a single line listing names with open MRs, no MR, a detached
  HEAD or the default branch.
- The final count line.

If the script failed, show its error lines.
