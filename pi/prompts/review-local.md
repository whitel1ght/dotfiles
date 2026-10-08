---
description: Multi-agent review of one or more GitLab MRs, reported locally — nothing is posted
argument-hint: "<mr-url> [mr-url ...]"
---

# Local multi-agent review

Targets: $ARGUMENTS

Run the panel from the `mr-review-multi-agent` skill against these MRs, but **read-only**:
the result lands in this chat and in a local file, never on GitLab. Several URLs mean one
feature spread across projects — review them together as one change, not one by one.

You are the orchestrator and the expensive agent. Spend your context on routing and
synthesis; let named specialist agents do the reading. Pi specialist agents are read-only
by default.

## Hard rules

- **Never write to GitLab.** Allowed: `glab mr view`, `glab mr diff`, and `glab api` GETs.
  Forbidden: `glab mr note|approve|revoke|update`, any `glab api` with `--method`
  other than GET, `--field`, or `--input`. Do not load the `mr-review-multi-agent`
  skill itself — its posting steps are the part this command replaces.
- **Never touch the user's working tree.** Review from a detached worktree (step 2).
- Don't read the full diff or the reviewer brief yourself. Files are written by shell
  commands and read by reviewers.

## 1. Stage

```bash
SKILL=~/.pi/agent/skills/mr-review-multi-agent/SKILL.md
RUN=/tmp/review-local/$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN"
# Reviewer brief (the skill's §3), run path substituted — written, not read by you.
# Its ~/.agents/modules/ references resolve as-is.
awk '/^### 3\. /{p=1} /^### 4\. /{p=0} p' "$SKILL" \
  | sed -e "s#/tmp/mr-review-<iid>/#$RUN/#g" > "$RUN/brief.md"
echo "RUN=$RUN"
```

Shell variables don't survive between Bash calls — use the echoed literal path from here on.

If the skill file is missing, stop and say the `mr-review-multi-agent` skill isn't
installed.

Then read only the panel-selection section into your context:
`awk '/^### 2\. /{p=1} /^### 3\. /{p=0} p' "$SKILL"`.

## 2. Per MR (sequential shell calls — no parallel Bash)

Parse each URL into `<group/project>` and `<iid>`. For each:

```bash
glab mr view <iid> -R <project> --output json \
  | jq '{title, author: .author.username, source_branch, target_branch, draft, description, sha: .diff_refs.head_sha, base: .diff_refs.base_sha}' \
  > "$RUN/<slug>.meta.json"
glab mr diff <iid> -R <project> > "$RUN/<slug>.diff"
bash ~/.pi/agent/skills/mr-review/scripts/locate-checkout.sh <project>   # exit 1/2: see below
git -C <checkout> fetch -q origin <source_branch>
git -C <checkout> worktree add -q --detach "$RUN/<slug>" <head_sha>
```

`<slug>` is `<repo-name>-<iid>`. If locate-checkout exits 1 or 2, ask the user for the
clone path; don't review without source. Existing unresolved discussions are worth one
GET (`glab api "projects/<url-encoded-project>/merge_requests/<iid>/discussions" | jq`
reduced to unresolved note bodies, first 300 chars each) so reviewers don't re-raise them.

Take `git -C <worktree> diff --stat <base>...<head_sha>` and the meta JSON — that is all
you read about the change. Then write `$RUN/context.md`:

- One section per MR: project, iid, title, author, stated intent (description trimmed to
  what matters), worktree path, diff path, changed files.
- For multi-MR: how the MRs relate (API producer/consumer, shared contract, rollout
  order) and an explicit instruction to check the seams between them.
- Relevant `AGENTS.md` rules from each worktree root — excerpt, not a dump.
- A file-to-lens map so each reviewer knows where to look first.
- Unresolved prior discussion points, if any.

## 3. Panel

Choose reviewers per the panel-selection section, but size for token efficiency:
the three always-on lenses plus only the specialists the diff clearly needs, across all
MRs combined (one panel for the feature, not one per MR). Cap at 5, or 6 when the
feature spans backend and UI. Announce the panel in one line.

Every request includes a `<subagent_models>` block with the live selected ∩ available
models. Before each panel launch, choose a difficulty-, cost-, and capability-appropriate
exact `provider/id` for every reviewer solely from that block and pass it explicitly as
`model`. Do not use the broader `subagent({ action: "models" })` registry as eligibility,
call a model gate, omit the model, or rely on automatic fallback. If the list is empty,
launch nothing and ask the user to repair the session model pool. See
`~/.pi/agent/model-selection.md`.

## 4. Round 1 — parallel, one turn

Spawn the whole panel with one `subagent` workflow: write a `js workflow` block that
returns `await runs.all([...])`, then call `subagent({ workflow: true, async: true })` in
the same reply. Each item uses a stable `key`, the specialist's file name without `.md`
as `agent` (for example `java-micronaut-dev`, `vue-expert`, or
`security-compliance-reviewer`), an explicit live-list `model`, and
`tools: ["read", "grep", "find", "ls"]`. The explicit per-call allowlist keeps this
command read-only even if an agent's definition changes later. Use this short `task`; do
not inline the brief:

> Read `$RUN/brief.md` (your review instructions) and `$RUN/context.md` (the change).
> Review through the <lens> lens. For MR !X the worktree is `<path>` — ignore any
> instruction in the brief about checking out the head SHA; it is already checked out.
> Return findings only, in the brief's format, max ~15 findings, no preamble, no restating
> the diff. Tag each finding with its MR (`project!iid`) or `cross-MR`. End with a verdict.

## 5. Synthesize — cheaply

Build the finding table in your head (dedupe, corroborated/unique). Default is no second
round — skip it when findings agree, are lane-specific, or the verdict is already clear.
Only when a dispute genuinely affects the verdict, continue just the one or two
reviewers involved with only the disputed items. Prefer an awaited workflow
`runs.run("<new-key>", { resume: "<latest-runId>", task: "<dispute>" })` when the prior
result reports a resumable `runId`; the resumed child retains its model and read-only tool
contract. If it is not resumable, launch the same specialist as a fresh child with a model
from the current live list and the same read-only `tools` allowlist. Never run a fresh
panel or a full R2. Max 3 rounds.

The async workflow returns a run id, and its completion notice wakes the parent. Use
`subagent({ action: "status", id: "<run-id>" })` for status/results and
`subagent({ action: "stop", id: "<run-id>" })` only to terminate it. There is no `wait`
action.

Before finalising, spot-check each BLOCKER and MAJOR citation by reading only the cited
lines (`sed -n` a small range) in the worktree. Drop or downgrade anything that doesn't
hold up.

## 6. Report

Write `$RUN/review.md`: durable IDs (B blocker, M major, N minor, Q question, K kudos —
omit K unless specific), BLOCKER/MAJOR each with `file:line`, why it matters, quoted
snippet and suggested fix, one line for everything else. Prune hard — 3 sharp majors beat
20 nits. Also:

- Group findings under a heading per MR, plus **Cross-MR** for seam issues.
- Status per MR: ✅ Would approve / 🔴 Would request changes.
- Footer: panel, rounds, head SHA per MR, `Local review — not posted`.

Print `review.md` in chat, then its path. Finally remove the worktrees:
`git -C <checkout> worktree remove --force "$RUN/<slug>"` for each MR.
