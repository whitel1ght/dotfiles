---
name: mr-review-response
description: >-
  Turn a posted code review into one accountable reply — read the latest review note on a GitLab MR, classify every finding as fixed (with commit SHA), already closed (by which SHA), declined (with the reason), or deferred, attach the must-fail and test evidence a reviewer can check, post it as a single reply in the review's own discussion, and never claim a verification that was not run. Use after addressing review feedback ("reply to the review", "post the round-N response", "address the findings on !123"), especially on MRs that have already had several rounds. Pair with `/mr-review-multi-agent` on the reviewing side.
---


# MR Review Response

The response format reviewers asked for by name across a seven-round MR series, extracted so it is
the default rather than something rediscovered. A review that gets a table of `finding → commit →
evidence` converges; a review that gets prose re-raises.

## When to use

- After pushing fixes for a review round on a GitLab MR
- When a review predates your latest push and some findings are already closed
- When you are declining or deferring a finding and need to say so accountably

## Input

An MR reference (`!123`, URL, or the current branch's MR) and the commit(s) that address the
review. The latest human review note is the target; find it:

```bash
TOKEN=$(sed -E 's#https://([^:]+):([^@]+)@.*#\2#' /run/secrets/git_credentials)
curl -s -H "PRIVATE-TOKEN: $TOKEN" "https://gitlab.com/api/v4/projects/$PID/merge_requests/$IID/discussions?per_page=100" \
 | jq -r '.[] | .notes[] | select(.system|not) | "\(.created_at) disc=\(.id[0:8]) \(.author.name): \(.body[0:80])"'
```

Take the newest note that is a review (not one of your own replies). Record its discussion id;
the reply goes **into that discussion**, not as a new top-level note.

## Process

### 1. Enumerate every finding

Extract every ID the review used (B1…, M7…, N12…, Q3…). If the review has no IDs, number them
yourself in the order they appear. Nothing is skipped; an unmentioned finding reads as ignored.

### 2. Classify each one

| Status | Meaning | Required evidence |
|---|---|---|
| **Fixed** | changed in this push | commit SHA + one line on what changed + how it was verified |
| **Already closed** | the review predates a push that fixed it | the SHA that closed it, and the fact the review reviewed an earlier head |
| **Not changed — reason** | deliberate pushback | the reason, and what would change your mind; accept the consequence explicitly |
| **Deferred** | valid, not this MR | one line why, and where it is tracked (ticket key or follow-up list) |
| **Reply only** | a question | the answer, with evidence |

Declining is legitimate and reviewers respect it when it is explicit. Silently dropping a finding
is what generates the next round.

### 3. Attach evidence, never assertions

For each guard-type finding ("add a test that fails without the fix"), state the mutation you
performed and the test that went red — the actual test name and the count — and how you restored
the code (copy the file back, never `git checkout --` on a file with other uncommitted work).

For test counts: the exact `--tests` filter or vitest path, and the reconciled number. If a suite
could not be run (environment), say so and say what you ran instead. **Never write "verified" for
something you did not run.** If a sub-agent reports a verification, treat it as unverified until
you have seen the command output yourself.

### 4. State what the head is

Old head → new head (short SHAs), whether it is a fast-forward or a force-push, and for a stacked
MR the target branch. If a review's blocker is already closed by a later push, say which SHA the
review was against.

### 5. Post one reply in the review's discussion

```bash
curl -s -X POST -H "PRIVATE-TOKEN: $TOKEN" --data-urlencode "body@reply.md" \
  "https://gitlab.com/api/v4/projects/$PID/merge_requests/$IID/discussions/$DISC/notes"
```

Do not change labels or approvals — that is the reviewer's action.

## Reply template

```markdown
**Round N pushed:** `<old>` → `<new>` (fast-forward on top of the reviewed SHA, no force-push). Target: `<branch>`.

| Finding | Status | Commit | What changed / evidence |
|---|---|---|---|
| B1 | Fixed | `abc1234` | <one line>. Must-fail: reverted <what> → `<test name>` red (n/n → n-1/n), restored. |
| M2 | Already closed | `def5678` | Review was against `<old>`; closed by the F2 push. |
| M3 | Not changed | — | <reason>. Consequence accepted: <what>. Would revisit if <condition>. |
| N4 | Deferred | — | Tracked as <ticket>. |
| Q5 | Reply | — | <answer with file:line>. |

**Test runs:** `<exact command>` → n/n. `<exact command>` → n/n. Not run: <what and why>.
**Operator items surfaced by the review** (not code): <list>.
```

Then post a one-line Jira comment on the ticket with the new head SHA.

## Anti-patterns

- Prose replies without IDs — the reviewer cannot tell what was skipped.
- "Addressed all feedback" — never true in a round with a deferral, and unverifiable anyway.
- Re-implementing a finding the reviewer already saw closed, because you did not check which head
  they reviewed.
- Quoting a sub-agent's "confirmed red" as your own evidence.
