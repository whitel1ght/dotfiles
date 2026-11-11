---
description: Remove worktrees under ~/projects/worktrees whose MR was merged or closed, and reviews of such MRs
argument-hint: "[-n]"
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/clean-worktrees $ARGUMENTS
```

The script decides what is safe and has already removed it when it returns. Don't
remove, stash, commit or force anything yourself, even for worktrees it kept.

Reply with a short summary:

- **Removed**: one line each, `repo/name (!iid)`.
- **Kept, needs you**: worktrees kept because of uncommitted changes or commits that
  exist nowhere else, and directories that aren't worktrees, with the reason as printed.
- **Kept, still active**: a single line listing names with open MRs (reviews of open
  MRs included), no MR, a detached HEAD, not merged yet, or the default branch.
- The final count line.

If the script failed, show its error lines.
