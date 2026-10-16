---
description: Turn a proposed friction-ledger entry into a tested fix on a branch, stop for your test, and fast-forward it into local main on your approval
argument-hint: <F-NNN>
---

# /fix-friction <F-NNN>

You orchestrate one fix; a subagent writes it. Follow `/orchestrate` for briefs and checking results,
and `~/projects/dotfiles/pi/model-selection.md` for the model. The fix ladder is the rule: a failure is
handled by a **script** first (retry, health gate, preflight, cache, fallback, background waiter), then
**config** (re-auth, env var, setting, dropping a dead step), and only then **prompt** text, when the
problem is the model's judgement. Runtime handling spends no model tokens.

Write rules: the implementer never touches `~/wiki`; only this session writes the ledger, in step 5.
Never push. Never merge before the user's explicit approval in step 4. Below, `F` is the argument
(`F-007`) and `W=~/projects/worktrees/dotfiles/friction-$F`.

## 1. Check

Read `~/wiki/work/friction/$F.md`. Refuse, saying why, and stop, when it is missing or `status` is not
`proposed`, `regressed` or `open`. If `$W` or branch `friction-$F` already exists, ask whether to
continue in it or start over.

## 2. Worktree

Local main is ahead of origin, so the branch starts from local main:

```bash
git -C ~/projects/dotfiles branch friction-$F main && wt add dotfiles friction-$F
```

## 3. Implement

Launch one `subagent({ role: "worker", model, task, cwd: "<W>", label: "$F", max_minutes: 90 })`.
`model` is an exact `provider/id` from the live list, a capable coding model. The task is
self-contained, since the child starts empty:

- **Goal:** implement the F-file's proposal; paste the full F-file content.
- **Rung:** lowest rung that works (script > config > prompt). Report the rung and why each lower
  rung does not fit; a prompt-only fix needs that justification written out.
- **Test:** add a test that fails without the fix and passes with it. No test, no fix.
- **Suites:** what the change touches: `bin/<x>.test.sh` for a changed script,
  `claude/daily/tests/run-all.sh` for the plugin, `node --test` in a touched pi extension,
  `bin/pi-contract` if pi prompts changed (needs a live model; say if it could not run).
- **Constraints:** work only in `<W>`, never touch `~/wiki`, never push, Conventional Commits,
  commit on the branch.
- **Report:** rung and justification, files changed, commit sha, how to test by hand, suite results.

Then end the turn. The `[pi-sub]` message wakes you: `read` the result, check it yourself
(`git -C $W log --oneline main..`, `git -C $W diff --stat main`, re-run the suites). A failure goes to
a fresh child carrying the failure and the earlier result path; a second failure, one tier up.

## 4. Stop

Show the user: the rung and why, what changed (diff stat, commit subjects), manual test steps, suite
results. Then **stop and wait**. Merge nothing until the user says to.

## 5. On approval

1. If main moved, rebase the branch onto it in `$W` and re-run the suites.
2. Merge, never push:

```bash
git -C ~/projects/dotfiles merge --ff-only friction-$F
SHA="$(git -C ~/projects/dotfiles rev-parse --short HEAD)"
```

3. Clean up: `git -C ~/projects/dotfiles worktree remove $W && git -C ~/projects/dotfiles branch -d friction-$F`.
4. Wiki (this session writes): in `~/wiki/work/friction/ledger.md` set the row's `status` to `fixed` and
   `fix` to `$SHA`; in `$F.md` set frontmatter `status: fixed`, `fix: $SHA`, `rung:` to the rung used,
   and add a `## History` line `- <date>: fixed in <sha> (<rung>)`. Then
   `git -C ~/wiki add work/friction && git -C ~/wiki commit -m "wiki: friction $F fixed"`.
5. Tell the user it is in local main and not pushed.

If the user rejects the change, leave the worktree and branch, set nothing in the ledger, and ask
what to change.
