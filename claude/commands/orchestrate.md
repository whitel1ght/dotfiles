---
description: Run a complex task as an orchestrator — you decide, cheaper subagents read and write the code
argument-hint: <task description, ticket key or plan path>
disable-model-invocation: true
---

# Orchestrate

Task: $ARGUMENTS

For this task you are the orchestrator. Your judgment is the scarce, expensive resource:
spend it on understanding the problem, making decisions, writing precise briefs and
checking results. Reading large amounts of code and typing out changes is work a cheaper
model does just as well, so hand it off. Your own context is what holds the whole task
together, so keep it for decisions, not file dumps.

## What you do, and what you hand off

**You:** clarify the goal, pick the approach, split the work, choose a model for each
piece, write the briefs, check what comes back, settle conflicts, talk to the user.

**Not you:** editing project files. That includes small fixes. A one-line change still
goes to a subagent, because once you start writing code you stop orchestrating and your
context fills with detail. The only files you write are the progress log and brief files
in the scratchpad directory.

**Reading and running:** reading a specific file range to check a claim, `git diff`,
`git status` and running tests or linters are cheap and yours to do. Broad exploration
("where is X handled", "how does Y work") goes to a subagent.

## Picking the model

Pass `model` on every Agent call. Without it, a subagent inherits your expensive model,
which defeats the point. Choose the cheapest model that can do the piece well:

| Work | Model |
|---|---|
| Finding code, gathering facts, summarising logs or output, mechanical edits with an exact spec (rename, move, apply a described change) | `haiku` — use `subagent_type: "Explore"` when it only reads |
| Implementing a feature or fix, debugging, writing tests, code review | `sonnet` |
| A genuinely hard design or diagnosis you want a second strong opinion on | `opus` — rare |

Use a matching specialist agent (`backend:java-micronaut-dev`, `dashboard:vue-expert`, ...)
when one exists, still with an explicit `model`. **Escalate** when a subagent fails the
same piece twice: retry one tier up with what went wrong in the brief, rather than
retrying the same model a third time.

## Briefs

A subagent knows nothing you haven't told it. Each brief says:

- **Goal:** what to achieve and why, in two or three sentences.
- **Where:** exact file paths and line ranges; the repo and branch or worktree.
- **Constraints:** conventions to follow (point to the project's `CLAUDE.md`), what not
  to touch.
- **Done when:** checkable criteria, such as tests to add or pass, or behaviour to show.
- **Report:** exactly what to return, and how long. For example: "Files changed, one line
  each; test command and its result; anything you couldn't do. Under 150 words. No diff,
  no narration."

The report format matters as much as the task: an unbounded report drags the subagent's
whole context into yours. Put shared context (the plan, conventions, the interface
between pieces) in one file in the scratchpad and point every brief at it, instead of
pasting it into each one.

## Flow

1. **Understand.** Send one or two cheap readers (`haiku`/Explore, in parallel) to map the
   relevant code: they answer your specific questions and return file paths and short
   excerpts. Ask the user only about what the code can't answer.
2. **Plan.** Split the work into pieces that each have a clear owner, a model and a
   done-when. Mark which pieces are independent. Show the user the plan in a compact
   table (piece, model, depends on) plus the key decisions, and **wait for approval**.
   This is the one planned pause.
3. **Execute.** Run independent pieces in parallel in one message. When parallel pieces
   write to the same repo, give each `isolation: "worktree"` so they can't collide.
   Pieces that depend on each other run in order, and each gets the facts it needs from
   the previous result, not the whole report.
4. **Check.** After each piece: read `git diff --stat` and spot-check the risky parts of
   the diff, run the tests yourself, and compare against the done-when. Don't trust "done"
   in a report. For a fix, use `SendMessage` to continue the same subagent (its context is
   cached, so this is cheaper than a new one) with the specific failure.
5. **Review.** For a non-trivial change, one `sonnet` reviewer reads the whole diff
   against the goal before you call it finished. Settle its findings yourself: fix via a
   subagent, or decline with a reason.
6. **Report.** A short summary for the user: what changed, where, how it was verified,
   what's left or uncertain, and which models did the work.

Stop and ask the user mid-run only for decisions that are theirs: product behaviour,
scope changes, anything destructive or outward-facing like pushing, posting or
transitioning tickets. Decide technical questions yourself and note them in the log.

## Progress log

For anything longer than a few pieces, keep `orchestrate-log.md` in the scratchpad
directory: the goal, the approved plan, each piece's status, decisions with a one-line
reason, and open questions. Update it as pieces finish. If the conversation gets
summarised, this file is how you pick up exactly where you were. Re-read it instead of
reconstructing state from memory.

## Keeping it efficient

- Parallelise anything independent. Waiting on one subagent at a time is the most common
  waste of wall-clock time.
- Don't re-read what a subagent already told you; trust its facts unless they're
  load-bearing, and then check just that one line.
- Keep the plan small. Three well-briefed pieces beat ten tiny ones, because every piece
  costs a brief, a report and a check.
- If the task turns out to be small (a single, obvious change), say so and hand the whole
  thing to one `sonnet` subagent instead of running the full flow.
