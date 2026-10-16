# Personal Instructions

Global instructions applied across all projects. Keep this short — project-level
`CLAUDE.md` files carry project-specific rules and take precedence.

## Preferences

- Prefer `rg` over `grep` and `fd` over `find` when available.
- Match the surrounding code's style, naming, and comment density.
- Don't add explanatory comments for self-evident code.
- Long-term memory: `~/wiki` — read `~/wiki/AGENTS.md` before searching it.

## System manual

- `~/wiki/tools/` is the manual for this whole setup (start at `index.md`). When a
  task changes how something is used — a script, alias, keybinding, plugin, model,
  sync or install step, in dotfiles or elsewhere — update the matching page in the
  same task, and the "Changes in progress" table in `index.md` when a planned
  change lands. Each page's `<!-- covers: -->` line says what it documents.
- dotfiles enforces this in its commit-msg hook (`docs-check`); a commit with no
  user-visible change carries a `Docs: none` line instead.

## Secrets

- Every secret lives in `~/.secrets/` (`secrets.env`, `recovery.md`). Never read,
  list, search or copy that folder or `~/.config/ecfx/jira.env` (a link into
  it); a hook and deny rules block it anyway. A command that needs a token takes
  it inline as `$(secret NAME)`; a bare `secret NAME` would print it and is
  blocked. When a secret is missing or expired, tell the user which name to fix
  with `secrets`.

## Artifacts

- Keep the source of every published claude.ai artifact in `~/artifacts/<name>/`:
  the page as `<name>.html` and its link in a `url` file (see the README there).
  Write new pages there, not in /tmp or a repo. To change one, edit that file
  and publish it with the link from `url`, so the same page updates.

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
