# Personal Instructions

Global instructions applied across all projects. Keep this short — project-level
`CLAUDE.md` files carry project-specific rules and take precedence.

## Preferences

- Prefer `rg` over `grep` and `fd` over `find` when available.
- Match the surrounding code's style, naming, and comment density.
- Don't add explanatory comments for self-evident code.
- Long-term memory: `~/wiki` — read `~/wiki/AGENTS.md` before searching it.
- Read a file in this session before you Edit or Write it, state files a background
  session rewrites (the wiki's `state.md`, `index.md`) included.
- For an exact replacement in one file use the Edit tool, not a python heredoc or `sed -i`;
  keep python, jq or sed for bulk transforms (many files, JSON, CSV).
- When a step is denied or blocked, never reach for a destructive git or `rm` command to
  get past it; stop and ask me.
- Ask clarifying questions in plain text. Keep the question form for picking among fixed
  options, and never send again one I turned down.

## Shell

- The shell is zsh on macOS: unquoted variables are not word-split and `=word` expands.
  Run loops and bash-style scripts with `bash -c '…'`, or use arrays.
- `/bin/bash` is 3.2. Scripts that need bash 4+ (SDKMAN helpers, backend start scripts)
  run with `/opt/homebrew/bin/bash`. Prefix `nocorrect` if zsh autocorrect prompts.

## Evidence

- Before saying something does not exist, check every path it could come in by (e.g. the
  legacy Vue 2 → Segment → Mixpanel path, not only the current one).
- Label unverified claims as hypotheses. Fact-check an analysis draft before presenting it.

## Tests and tooling

- ecfx-backend tests need Java 25: every backend test command you give includes the setup
  (`sdk env` in the repo root, or `JAVA_HOME` set to `~/.sdkman/candidates/java/25.*`).
- Code on a branch is not live: pi and the daily plugin load from `main`. Merge it, or say
  plainly that it is not live yet.

## System manual

- `~/wiki/tools/` is the manual for this whole setup (start at `index.md`). When a
  task changes how something is used — a script, alias, keybinding, plugin, model,
  sync or install step, in dotfiles or elsewhere — update the matching page in the
  same task, and the "Changes in progress" table in `index.md` when a planned
  change lands. Each page's `<!-- covers: -->` line says what it documents.
- `~/wiki/work/system/` explains how each part works; its map is injected at session
  start. Read a part's page before changing or explaining it. A change to a system
  repo updates its `system/` page (and `tools/` when user-visible) in the same task.
- Commit those wiki edits with `wiki-commit --by <claude|pi> --session <id> -m … -- <paths>`.
  Lines from commits without an `Agent-edit:` trailer are mine: before rewriting a passage,
  check `git -C ~/wiki log -L`/`blame` and leave them alone; if one contradicts the code,
  ask me instead of overwriting it. A decision behind a change goes in
  `~/wiki/work/system/decisions/`, from `~/wiki/work/_templates/decision.md`.
- The commit-msg hook (`docs-check`) enforces this in dotfiles, decisions and articles.
  Opt-outs, one message line: `Docs: none` = no behaviour change at all (typo, formatting,
  tests only); `Docs: internal` = behaviour changed but not how it is used (the `system/`
  page is still required, `tools/` is not).

## Secrets

- Every secret lives in `~/.secrets/` (`secrets.env`, `recovery.md`). Never read,
  list, search or copy that folder or `~/.config/ecfx/jira.env` (a link into
  it); a hook and deny rules block it anyway. A command that needs a token takes
  it inline as `$(secret NAME)`; a bare `secret NAME` would print it and is
  blocked (right: `curl -H "PRIVATE-TOKEN: $(secret NAME)" …`; wrong: `secret NAME`,
  `secret NAME | …`). When a secret is missing or expired, tell the user which name to fix
  with `secrets`.

## Artifacts

- Keep the source of every published claude.ai artifact in `~/artifacts/<name>/`:
  the page as `<name>.html` and its link in a `url` file (see the README there).
  Write new pages there, not in /tmp or a repo. To change one, edit that file
  and publish it with the link from `url`, so the same page updates.
- When a publish is refused and hands back a newer live version, merge your change onto
  that version and publish again; never resend the refused content unchanged.

## GitLab MR references

- Every MR number in text I show the user is a markdown link with the repo in the link text:
  `[dashboard!2202](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2202)`. Never a
  bare `!2202`. Tables and summaries count; subagent briefs and internal logs don't.
- Known paths: `ecfx/ecfx-backend`, `ecfx/ecfx-dashboard`, `ecfx/ecfx-admin`,
  `ecfx/ecfx-protobufs`, `ecfx/claude-components`. Confirm any other with `glab repo view`.

## GitLab and Jira APIs

- GitLab API writes send `Content-Type: application/json`. Never pipe a request body in
  through stdin: write it to a file and pass that (`curl --data @file`, `glab api --input
  file`). `gitlab-api-guard` blocks both mistakes.
- Run `/mr-description` before any `glab mr create`, `glab mr update --description` or MR
  description write through `glab api`; the MR-description gate blocks them otherwise.
- When an API merge fails, report it and leave the merge to me; no retries with other flags.
- Never move a Jira ticket backwards (e.g. Done → In QA) without asking.

## Review replies

- Answer review findings on an MR with the `mr-review-response` skill, unasked. Show the
  drafted replies once per round as one batch; "yes", "post it" or "post both" posts
  exactly what was shown, through that skill, with no further question.

## Worktrees

- Every worktree lives at `~/projects/worktrees/<repo>/<name>`, never inside a repo or
  beside it. Create one with `wt add <repo> <name> [branch]` (name: the ticket key, e.g.
  `ECFX-17648`), move a stray one with `wt move <path>`, list them with `wt ls`.
- This overrides a skill's own default location, such as `.worktrees/`.
