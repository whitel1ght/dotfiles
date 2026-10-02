# Personal Instructions

Global instructions applied across all projects. Keep this short — project-level
`CLAUDE.md` files carry project-specific rules and take precedence.

## Preferences

- Prefer `rg` over `grep` and `fd` over `find` when available.
- Match the surrounding code's style, naming, and comment density.
- Don't add explanatory comments for self-evident code.

## GitLab MR references

- Every MR number in text I show the user is a markdown link with the repo in the link text:
  `[dashboard!2202](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2202)`. Never a
  bare `!2202`. Tables and summaries count; subagent briefs and internal logs don't.
- Known paths: `ecfx/ecfx-backend`, `ecfx/ecfx-dashboard`, `ecfx/ecfx-admin`,
  `ecfx/ecfx-protobufs`, `ecfx/claude-components`. Confirm any other with `glab repo view`.

## Worktrees

- Every worktree lives at `~/projects/worktrees/<repo>/<name>`, never inside a repo or
  beside it. Create one with `wt add <repo> <name> [branch]` (name: the ticket key, e.g.
  `ECFX-17648`), move a stray one with `wt move <path>`, list them with `wt ls`.
- This overrides a skill's own default location, such as `.worktrees/`.
