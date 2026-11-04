---
description: Watch my open MRs and address every new review finding with cheap subagents, in a loop
argument-hint: [check interval in seconds, default 3600] [--since 2026-09-20T00:00:00Z]
allowed-tools: Bash(~/.local/bin/mr-watch:*), Bash(wt add:*), Bash(git -C:*), Bash(~/.local/bin/ecfx-docker:*), Bash(ecfx-docker:*)
disable-model-invocation: true
---

Watch my open GitLab MRs (drafts and approved MRs are skipped) and, whenever a reviewer leaves new notes, get every finding
addressed, pushed and answered. Arguments: $ARGUMENTS (a number is the check interval
in seconds; `--since` sets how far back the first check looks, default a week).

You are the orchestrator, as in `/orchestrate`: you decide and check, subagents read and
change code. This session may run all day, so its context is the budget. Read the
script's short summaries, the fixers' short reports and `git` one-liners, never a
review.md or a source file yourself. The fixers read those.

## Start

```bash
~/.local/bin/mr-watch held                 # replies written earlier and not posted
~/.local/bin/mr-watch check [--since ...]  # one pass now
```

Post every held round with `~/.local/bin/mr-watch reply <round>` once the commit SHAs its
`response.md` cites are on the MR's branch; one line each on what you posted. Skip one
only when a newer round for the same MR supersedes it (ack it and say so) or it waits on
a decision that is mine (see the end of "Each round"). If `check` exits 1, nothing is new: go
straight to "Wait". Exit 2 means GitLab is unreachable: say so and wait.

## Each round

`check` prints one entry per MR with new notes: the MR, who wrote them, a **round**
directory and the **worktree**. Handle every MR in the summary, in parallel.

1. **Worktree.**
   - `(clean)`, `(clean, fast-forwarded N commits)` or `(clean, N unpushed commits)`: use
     it. `check` has already fetched and fast-forwarded it to the remote branch.
   - `DIRTY`: that's my own work in progress, so leave the MR alone this time. Don't ack
     it, so it comes back next check, and tell me in one line.
   - `STALE`: the worktree has diverged from the remote branch (pushed from another
     machine on top of local commits), or the fetch failed. Treat it like `DIRTY`.
   - `none (clone <path>)`: create one with `wt add <repo> <TICKET> <branch>` (it
     prints the path), then use it.
2. **Fixer.** One subagent per MR, all in one message, each with `model: "sonnet"`. For
   ecfx-backend use `subagent_type: "backend:java-micronaut-dev"`, otherwise
   `general-purpose`. Give each the brief below with its paths filled in.
3. **Check** each report as it lands, with cheap commands only:
   `git -C <wt> status --porcelain` (must be empty),
   `git -C <wt> log --oneline @{u}..HEAD` (the commits the report names), and that the
   round has a `response.md`. If a fixer failed a finding (tests red, stuck), continue
   the same fixer once with SendMessage and the specific problem. If it fails again,
   retry once on `opus`. Still failing: that finding becomes Deferred with the reason.
4. **Push**: `git -C <wt> push`. Never force. If the push is rejected, stop on this MR:
   ack the round, hold its reply and tell me.
5. **Reply.** Post every round's reply with `~/.local/bin/mr-watch reply <round>`,
   including rounds with Not changed or Deferred findings: reviewers need the fixes
   reported, and the reply carries the reason for each declined or deferred one. That
   posts `response.md` as one note, the `threads.tsv` lines into their inline threads,
   and acks the round. Then list each Not changed or Deferred finding to me with its
   one-line reason (a push notification if the PushNotification tool is available, and
   in the chat).

Stop to ask me only when something is mine to decide: a finding that asks for a product
or scope change, or a reviewer asking me personally. Hold that round and carry on with
the others.

## Fixer brief

```text
Address every finding in a GitLab review on <MR ref>.

Worktree: <path>, branch <branch>. The project's CLAUDE.md is the rulebook.
Review: <round>/review.md. Discussions with a new note are whole; notes marked NEW are
what to address, and the earlier notes are context. Response format:
~/.claude/plugins/cache/ecfx-components/shared/*/skills/mr-review-response/SKILL.md.
Read it, but don't post anything: its step 5 is done for you.

0. git fetch; if the branch is behind its upstream, git merge --ff-only @{u}. If it
   has diverged, stop and report that.
1. List every finding in the NEW notes, using the reviewer's IDs (B1, M2, ...) or
   numbering them in order. Every one gets a status; none is skipped.
2. For each: fix it with a test that fails without the fix (say what you mutated and
   which test went red), answer it if it's a question, or decline or defer it with a
   concrete reason when it's wrong or out of scope. Commit per finding or tight group,
   in the repo's commit style. Don't push.
3. Run the tests covering what you changed. Record the exact commands and counts.
   Never write "verified" for something you did not run. Docker is kept off to save
   memory: `pause` stops the ECFX containers and quits Docker Desktop. A suite that
   provisions its own containers (backend Spock through TestContainers) still needs the
   daemon, so run `ecfx-docker busy-on <MR ref>` and then `ecfx-docker daemon-up` before
   it; add `ecfx-docker resume` when your checks need the real services (a running app,
   `make migrate`, a database the suite does not provision). Finish with
   `ecfx-docker busy-off <MR ref>` — until then nothing can be paused.
4. Write <round>/response.md: the reply template from the skill, with one table row per
   finding. The "Round N pushed" line uses the upstream head as old and your last
   commit as new.
5. Write <round>/threads.tsv: for each inline discussion (its heading has "inline"),
   one line: the discussion id, a tab, then a one-line reply such as
   "Fixed in `abc1234`: <what>. Summary in the MR thread."

Report, under 120 words and nothing else: counts per status; each Not changed or
Deferred finding with its reason, one line each; the test commands with results;
anything you couldn't do.
```

## Wait

Once every MR in the round is replied to, held or skipped, stop the local Docker stack
again with `~/.local/bin/ecfx-docker pause` — it stops the ECFX containers and quits
Docker Desktop, and it refuses while a check is still running,
which is the point, so leave the stack up then and say so in one line — and start the
next wait in the background (Bash with `run_in_background`) and end your turn:

```bash
~/.local/bin/mr-watch wait --every <interval>
```

It sleeps first, checks, and exits only when there's something new, so waiting costs
nothing. You'll be woken when it exits. Its output is the same summary as `check`: go
to "Each round". Never have two waits running.

After each round, give me a status line of one or two lines per MR: what was fixed and
pushed, what was posted or held, and the next check time. If the conversation is
compacted, rebuild your state from `mr-watch held` and the round directories. Their
`acked` and `posted` markers say what's done.
