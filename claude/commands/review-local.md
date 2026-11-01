---
description: Multi-agent review of one or more GitLab MRs, reported locally — nothing is posted
argument-hint: <mr-url> [mr-url ...]
model: opus
disable-model-invocation: true
---

# Local multi-agent review

Targets: $ARGUMENTS

Run the panel from the `mr-review-multi-agent` skill against these MRs, but **read-only**:
the result lands in this chat and in a local file, never on GitLab. Several URLs mean one
feature spread across projects — review them together as one change, not one by one.

You are the orchestrator and the expensive model. Spend your tokens on routing and
synthesis; let the reviewers (cheaper model) do the reading.

## Hard rules

- **Never write to GitLab.** Allowed: `glab mr view`, `glab mr diff`, and `glab api` GETs.
  Forbidden: `glab mr note|approve|revoke|update`, any `glab api` with `--method`
  other than GET, `--field`, or `--input`. Do not load the `mr-review-multi-agent`
  skill itself — its posting steps are the part this command replaces.
- **Never touch the user's working tree.** Review from a detached worktree (step 2).
- **Every reviewer runs with `model: "sonnet"`** on the Agent call, whatever its
  definition says. Nothing else reads the diff.
- Don't read the full diff or the reviewer brief yourself. Files are written by shell
  commands and read by reviewers.

## 1. Stage

```bash
SKILL=$(ls ~/.claude/plugins/cache/*/shared/*/skills/mr-review-multi-agent/SKILL.md | tail -1)
SHARED=$(dirname "$(dirname "$(dirname "$SKILL")")")
RUN=/tmp/review-local/$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN"
# Reviewer brief (the skill's §3), plugin paths resolved — written, not read by you:
awk '/^### 3\. /{p=1} /^### 4\. /{p=0} p' "$SKILL" \
  | sed -e "s#\${CLAUDE_PLUGIN_ROOT}#$SHARED#g" -e "s#/tmp/mr-review-<iid>/#$RUN/#g" > "$RUN/brief.md"
echo "RUN=$RUN SHARED=$SHARED"
```

Shell variables don't survive between Bash calls — use the echoed literal paths from here on.

If `$SKILL` is missing, stop and say the `shared` plugin isn't installed.

Then read only the panel-selection section into your context:
`awk '/^### 2\. /{p=1} /^### 3\. /{p=0} p' "$SKILL"`.

## 2. Per MR (sequential shell calls — no parallel Bash)

Parse each URL into `<group/project>` and `<iid>`. For each:

```bash
glab mr view <iid> -R <project> --output json \
  | jq '{title, author: .author.username, source_branch, target_branch, draft, description, sha: .diff_refs.head_sha, base: .diff_refs.base_sha}' \
  > "$RUN/<slug>.meta.json"
glab mr diff <iid> -R <project> > "$RUN/<slug>.diff"
bash "$SHARED/skills/mr-review/scripts/locate-checkout.sh" <project>   # exit 1/2: see below
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
- Relevant `CLAUDE.md` rules from each worktree root — excerpt, not a dump.
- A file-to-lens map so each reviewer knows where to look first.
- Unresolved prior discussion points, if any.

## 3. Panel

Choose reviewers per the panel-selection section, but size for token efficiency:
the three always-on lenses plus only the specialists the diff clearly needs, across all
MRs combined (one panel for the feature, not one per MR). Cap at 5, or 6 when the
feature spans backend and UI. Announce the panel in one line.

## 4. Round 1 — parallel, one message

Each Agent call: `subagent_type` from the panel, `model: "sonnet"`, and a short prompt —
don't inline the brief:

> Read `$RUN/brief.md` (your review instructions) and `$RUN/context.md` (the change).
> Review through the <lens> lens. For MR !X the worktree is `<path>` — ignore any
> instruction in the brief about checking out the head SHA; it is already checked out.
> Return findings only, in the brief's format, max ~15 findings, no preamble, no restating
> the diff. Tag each finding with its MR (`project!iid`) or `cross-MR`. End with a verdict.

## 5. Synthesize — cheaply

Build the finding table in your head (dedupe, corroborated/unique). Default is no second
round — skip it when findings agree, are lane-specific, or the verdict is already clear.
Only when a dispute genuinely affects the verdict, use
`SendMessage` to the one or two agents involved (their context is cached) with just the
disputed items — never a fresh panel, never a full R2 to everyone. Max 3 rounds.

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
