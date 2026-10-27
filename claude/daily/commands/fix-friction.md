---
description: Turn a proposed friction-ledger entry into a tested fix on a branch, stop for your test, and fast-forward it into local main on your approval (or, with --auto, build it unattended for coach-fix to land; with --revise, answer your questions on the card unattended)
argument-hint: <F-NNN> [--auto|--revise]
disable-model-invocation: true
---

# Fix a friction entry

Arguments: $ARGUMENTS

You orchestrate one fix. Follow `/orchestrate`'s rules (`~/.claude/commands/orchestrate.md`) for models, briefs and checking results. The fix ladder is the rule: a failure is handled by a **script** first (retry, health gate, preflight, cache, fallback, background waiter), then **config** (re-auth, env var, setting, dropping a dead step), and only then **prompt** text, when the problem is the model's judgement. Runtime handling spends no model tokens.

Write rules: the implementer never touches `~/wiki` except `~/wiki/work/system/` and `~/wiki/tools/` (only those), which it updates when the fix changes the system and commits with `~/.local/bin/wiki-commit --by claude -m "<msg>" -- <paths>` (if it exits 2 only because there is no wiki, carry on); only this session writes the ledger, and only in step 5. Never push. Never merge before the user's explicit approval in step 4. `F` is the argument (`F-007`), `W=~/projects/worktrees/dotfiles/friction-$F`.

When the arguments include `--auto`, skip steps 1–5 and follow **Auto mode** at the end instead; with `--revise`, skip them and follow **Revise mode** instead.

## 1. Check

Read `~/wiki/work/friction/$F.md` (frontmatter, `## Evidence`, `## Diagnosis`, `## Proposal`). Refuse, saying why, and stop, when the file is missing or `status` is not `proposed`, `regressed`, `open`, `offered` or `failed`. If `$W` or branch `friction-$F` already exists, say so and ask whether to continue in it or start over.

## 2. Worktree

Local main is ahead of origin, so the branch starts from local main, not origin's default:

```bash
git -C ~/projects/dotfiles branch friction-$F main && wt add dotfiles friction-$F
```

## 3. Implement

Dispatch one implementer with the `Agent` tool: `model: "sonnet"` (explicit), cwd `$W`. Brief (write it to the scratchpad first):

- **Goal:** implement the F-file's proposal, pasting its full content.
- **Rung:** use the lowest rung that works (script > config > prompt). Say which rung you chose and why each lower rung does not fit; a prompt-only fix needs that justification written out.
- **Test:** add a test that fails without the fix and passes with it. No test, no fix.
- **Suites:** run what the change touches: `bin/<x>.test.sh` for a changed script, `claude/daily/tests/run-all.sh` for the plugin, `node --test` in a touched pi extension, `bin/pi-contract` if pi prompts changed (it needs a live model; say if it could not run).
- **Constraints:** work only in `$W`, touch `~/wiki` only in `work/system/` and `tools/` (commit those with `wiki-commit --by claude`), never push, Conventional Commits, commit on the branch.
- **Report:** rung and justification, files changed, commit sha, how to test by hand, suite results.

Check the report yourself: `git -C $W log --oneline main..`, `git -C $W diff --stat main`, and re-run the suites. A failure goes back to a fresh implementer with the failure in the brief; a second failure escalates one tier.

## 4. Stop

Show the user: the rung and why, what changed (diff stat, the commit subjects), the manual test steps, the suite results. Then **stop and wait**. Merge nothing until the user says to.

## 5. On approval

1. If main moved, rebase the branch onto it in `$W` and re-run the suites.
2. Merge, never push:

```bash
git -C ~/projects/dotfiles merge --ff-only friction-$F
SHA="$(git -C ~/projects/dotfiles rev-parse --short HEAD)"
```

3. Clean up: `git -C ~/projects/dotfiles worktree remove $W && git -C ~/projects/dotfiles branch -d friction-$F`.
4. Ledger (this session writes, never by hand): `~/.local/bin/friction-ledger set $F --status fixed --fix $SHA --rung <the rung used>` (it holds the ledger lock, adds the dated History line and rebuilds `ledger.md`). Then `git -C ~/wiki add work/friction && git -C ~/wiki commit -m "wiki: friction $F fixed"`.
5. Tell the user it is in local main and not pushed.

If the user rejects the change, leave the worktree and branch, set nothing in the ledger, and ask what to change.

## Auto mode (`--auto`)

`coach-fix` starts this (as `/daily:fix-friction F-NNN --auto`) as a headless background process (`claude -p --permission-prompts none`, no window) after the user said yes to the coach's suggestion. It runs unattended: it never asks the user anything (nobody is watching), never merges, and never pushes (the claude-components branch below is the one exception). Anything that would ask for permission is denied: take a denial as a reason to `fail`, never work around it. The process ends when your turn ends, so dispatch every agent in the foreground (`run_in_background: false`) and wait for its result, and never end the turn before `built` or `fail` has run. It ends with exactly one of these, and only this session calls them:

- built: `~/.local/bin/coach-fix built $F --repo <repo> --branch coach-$F --worktree $W --test-cmd "<cmd>"`, or `~/.local/bin/coach-fix built $F --mr <url>` for claude-components;
- anything else: `~/.local/bin/coach-fix fail $F --reason "<one line: why>"`.

`coach-fix land` merges a built branch after the day and writes the ledger; the next /start-day reports the result. Do not write the ledger yourself. `F` is the first argument.

1. **Check.** Read `~/wiki/work/friction/$F.md` and `~/.local/state/coach/queue/$F.json`. Go on only when the entry's `status` is `landing` and the queue `state` is `running`; otherwise say so and stop without calling `coach-fix`. Then pick the repo from the proposal:
   - `dotfiles`, `decisions` or `articles` (main checkout `~/projects/<repo>`): steps 2–5.
   - `claude-components`: the draft MR path below.
   - anything that needs the user: a `secret` entry (signature `…:secret:…`; its fix is user steps), rotating or revoking a secret, an ECFX repo, a change in an outside account (GitHub, GitLab or Atlassian settings, the Chrome extension's own settings UI), a `brew` or package install, or any other repo. Do not start it: `~/.local/bin/coach-fix fail $F --reason "needs the user: <the exact steps, in order>"`, then stop.
2. **Worktree.** Read the system page for the part being changed (`~/wiki/work/system/`). Branch from local main, not origin's default, with `wt add <repo> coach-$F`:

   ```bash
   git -C ~/projects/<repo> branch coach-$F main && wt add <repo> coach-$F
   ```

   `W=~/projects/worktrees/<repo>/coach-$F`. If the branch or `$W` already exists, fail with "coach-$F already exists" instead of reusing it.
3. **Implement** as in step 3 above, with cwd `$W` (implementer `model: "sonnet"`, the same brief: lowest rung, a test that fails before the fix, the covering suites, commits on the branch). Add to the brief: change nothing the proposal does not ask for, and never loosen a guard, hook or permission rule it does not name. One change to the wiki rule: the fix has not landed yet, so do not rewrite any `work/system/` or `tools/` page; add one line under `## Unfinished` of each system page that covers the changed files, ``- `<repo>:coach-$F` <what changes>`` (docs-check accepts that on a branch), committed with `wiki-commit --by claude`. Once the branch has landed and is deleted, `system-check` reports the entry and /end-day's "Check the system" folds it into the page. Check the report yourself as in step 3.
4. **Review.** One fresh reviewer on a different model tier from the implementer: the `Agent` tool with `model: "opus"`, read-only, given the F-file, `git -C $W log --oneline main..` and `git -C $W diff main...`. It answers `approved` or numbered findings. Findings go to an implementer (the brief plus the findings), then the suites again, then the same review. At most two fix rounds; not approved after the second, or suites still red → `coach-fix fail $F --reason "<the open findings or the failing suite>"`.
5. **Built.** Green and approved, commit everything, then build `--test-cmd` from the covering suites: only `bash <path>` items joined by ` && `, each path a test file tracked in `$W`, relative to it, needing no live model or network (for example `bash bin/coach-fix.test.sh && bash bin/friction-ledger.test.sh`). Anything else is refused (exit 2): correct it and call `built` again. Landing re-runs it, with a time limit, if main moved. Commit nothing on the branch after `built`: landing refuses a branch that changed after review. Then:

   ```bash
   ~/.local/bin/coach-fix built $F --repo <repo> --branch coach-$F --worktree $W --test-cmd "<cmd>"
   ```

   If it exits 1 it has already marked the entry failed: say its message and stop.

**claude-components** (the team's repo; nothing from the fix is copied into dotfiles): `wt add claude-components coach-$F` (it branches from origin's default), `W=~/projects/worktrees/claude-components/coach-$F`; steps 3 and 4 there with that repo's tests. Then write the description with the `mr-description` skill, push the branch (`git -C $W push -u origin coach-$F`, the only push in this mode) and open a draft MR assigned to the user, with no reviewers, from the worktree (`--draft` adds the "Draft:" prefix itself):

```bash
cd "$W" && glab mr create --draft --source-branch coach-$F --assignee "$(glab api user | jq -r .username)" --title "<subject>" --description "$(cat <description file>)" --yes
```

Never undraft it, merge it or request reviewers. Then `~/.local/bin/coach-fix built $F --mr <the MR url>`.

Whatever blocks you (a missing tool, an unclear proposal, a failed command), fail with the reason rather than wait for an answer.

## Revise mode (--revise)

`friction-cards` starts this (as `/daily:fix-friction F-NNN --revise`) as a headless background process (`claude -p --permission-prompts none`, no window) when the user asks a question on the friction card; the process ends when your turn ends, so never end it before `revised` or `unrevised` has run. It runs unattended: it never asks the user anything (nobody is watching), never edits code, never merges or pushes, and never writes the ledger itself. `F` is the first argument.

1. Read `~/wiki/work/friction/$F.md` and the job file `~/.local/state/coach/replies/$F.json`; its `questions` array is what the user asked. You may read code, `~/wiki/work/system/` pages and `git log` to answer, read-only.
2. Answer the questions in plain language, at most 8 lines. If the answer changes the fix (an alternative the user proposed, a better rung, a missing exact change), also write a revised `## Proposal` body in the same format as the original: the rung line and, for a safety change, a `### Change` block of before → after lines.
3. Write the answer (and the revised proposal, if any) to files with the file-write tool, never via a shell command, then end with:

   ```bash
   ~/.local/bin/friction-cards revised $F --answer-file <A> [--proposal-file <P>]
   ```

4. If the questions cannot be answered (a missing entry, unreadable context), end with `~/.local/bin/friction-cards unrevised $F --reason "<one line: why>"` instead.

End with exactly one of those two calls.
