---
description: Turn a proposed friction-ledger entry into a tested fix on a branch, stop for your test, and fast-forward it into local main on your approval
argument-hint: <F-NNN>
disable-model-invocation: true
---

# Fix a friction entry

Arguments: $ARGUMENTS

You orchestrate one fix. Follow `/orchestrate`'s rules (`~/.claude/commands/orchestrate.md`) for models, briefs and checking results. The fix ladder is the rule: a failure is handled by a **script** first (retry, health gate, preflight, cache, fallback, background waiter), then **config** (re-auth, env var, setting, dropping a dead step), and only then **prompt** text, when the problem is the model's judgement. Runtime handling spends no model tokens.

Write rules: the implementer never touches `~/wiki` except `~/wiki/work/system/` and `~/wiki/tools/` (only those), which it updates when the fix changes the system and commits with `~/.local/bin/wiki-commit --by claude -m "<msg>" -- <paths>`; only this session writes the ledger, and only in step 5. Never push. Never merge before the user's explicit approval in step 4. `F` is the argument (`F-007`), `W=~/projects/worktrees/dotfiles/friction-$F`.

## 1. Check

Read `~/wiki/work/friction/$F.md` (frontmatter, `## Evidence`, `## Diagnosis`, `## Proposal`). Refuse, saying why, and stop, when the file is missing or `status` is not `proposed`, `regressed` or `open`. If `$W` or branch `friction-$F` already exists, say so and ask whether to continue in it or start over.

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
4. Wiki (this session writes): in `~/wiki/work/friction/ledger.md` set the row's `status` to `fixed` and `fix` to `$SHA`; in `$F.md` set frontmatter `status: fixed`, `fix: $SHA`, `rung:` to the rung used, and add a `## History` line `- <date>: fixed in <sha> (<rung>)`. Then `git -C ~/wiki add work/friction && git -C ~/wiki commit -m "wiki: friction $F fixed"`.
5. Tell the user it is in local main and not pushed.

If the user rejects the change, leave the worktree and branch, set nothing in the ledger, and ask what to change.
