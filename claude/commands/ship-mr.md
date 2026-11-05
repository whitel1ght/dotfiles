---
description: Review your own MRs with the local panel, fix every finding, push, then undraft, assign and request reviewers
argument-hint: <mr-url> [mr-url ...]
disable-model-invocation: true
---

# Ship MRs

Targets: $ARGUMENTS

For each MR (your own, open, usually draft): review it, fix everything the review finds,
push, and only then take it out of draft. Several URLs are separate MRs shipped one after
another; if they are one feature, run the review for them together.

## 1. Check the MR

For each MR first run `~/.local/bin/mr-ship <repo> <iid> -n`. If it exits non-zero (merged,
closed or not yours), skip that MR entirely: no review, no commit, no push. Report it as
"skipped: <mr-ship's message>".

## 2. Review

Read `~/.claude/commands/review-local.md` (fallback: `~/projects/dotfiles/claude/commands/review-local.md`) and follow it on the MR. It is read-only and writes `review.md`. Never use the posting `mr-review-multi-agent` skill instead.
Keep its worktree rules: the review runs from a detached worktree, never your checkout.

## 3. Fix

Fix **every** finding (blocker, major, minor; questions only if they point at a real gap)
in the MR's own worktree (`wt ls`; create one with `wt add <repo> <name> <branch>` if
missing), never in the main checkout. Commit as the project's convention says. A finding
you decline to fix counts as unfixed, so say why and stop at step 5.

Run the project's checks (the commands in the project's `CLAUDE.md`: lint, unit tests,
type check). Then push the branch.

## 4. Ship

Only when no finding is left unfixed and all checks are green:

```bash
~/.local/bin/mr-ship <repo> <iid>        # -n prints the calls only
```

`mr-ship` marks the MR ready, assigns you and requests the standing reviewers. It refuses
an MR that is merged, closed or not yours.

A dependency is never a reason to stay in draft. Before `mr-ship`, when the MR waits on another
MR, a deploy or a release, put one line at the top of its description:
`Depends on: <repo>!<iid>, merge after it` (or the deploy or release it waits on). Write it the
way `/mr-description` says. A check that is red only because of that dependency does not stop
the ship; name the check on the same line. That line and `mr-ship` are the only GitLab writes
this command makes.

## 5. Stop conditions

Do not run `mr-ship` and leave the MR in draft when a finding is unfixed or a check is red for
any other reason. Say which finding or check, and why, in the report.

## 6. Report

Per MR: link, findings fixed (count by severity), checks run and result, pushed head SHA,
and either "shipped" or "left in draft: <the unfinished work>".
