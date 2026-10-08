---
name: mr-review-queue
description: >-
  List all open GitLab MRs where the current user is assigned as a reviewer, triage them into buckets (review-now / re-review / waiting / draft / etc.), and walk through actionable ones one at a time. Composes with the `mr-review` skill — once the user picks an MR, this skill hands off to `mr-review` for the actual review. Use when the user asks "what MRs do I owe a review on?", "daily review queue", "check my review backlog", "walk my review queue", or invokes `/mr-review-queue`.
---


# MR Review Queue

The daily-chore wrapper: figure out which MRs are actually waiting on you right now, present them in priority order, and run reviews back-to-back if asked. Composes with `mr-review` — this skill triages, `mr-review` does the actual review.

## Inputs

No required arguments. Optional flags the user might say:

- `walk` / `all` — after each review, automatically refresh the queue and present the next actionable MR. Stops when the user says stop or the actionable buckets empty.
- `quiet` / `actionable only` — hide the skipped buckets in the output. Useful when the queue is long.

If neither is given, default behavior: present the queue once, prompt for selection, run one review, return.

## Pre-flight

### 1. Run the triage script

```
python3 ${CLAUDE_SKILL_DIR}/scripts/triage.py
```

This:
- Calls `glab api user` to identify the current user.
- Calls `glab api /merge_requests?reviewer_username=<self>&state=opened&scope=all` to fetch every open MR across every project where the user is a reviewer.
- For each MR, fetches non-system notes (filters out auto-events like "approved" / "marked WIP").
- Categorizes each MR into one of nine buckets.
- Outputs JSON to stdout.

If the script exits with code 2, `glab` is not installed or not authenticated. Tell the user: *"`glab` CLI not installed or not authenticated. Run `brew install glab && glab auth login`, then retry."*

### 2. Parse the JSON

Expected structure (see `scripts/triage.py` docstring for full schema). The keys you need:

- `self` — the current user's GitLab username
- `total_count` — total MRs assigned as reviewer
- `buckets.<key>` — list of MR entries per bucket (see below)

Bucket keys, in display priority order:

| Key | Display label | Action |
|---|---|---|
| `review_now` | 🔴 REVIEW NOW | First time at you — top priority |
| `re_review_commits` | 🔄 RE-REVIEW | Author pushed commits since your last review |
| `re_review_response` | 💬 RE-REVIEW (response) | Author replied since your last review (no push) |
| `pipeline_running` | 🟡 PIPELINE RUNNING | CI not done yet — soft skip |
| `waiting_on_author` | ⏳ Waiting on author | You reviewed; nothing back yet — skip |
| `pipeline_red` | 🚧 Pipeline red | CI failed — author still iterating — skip |
| `already_approved` | ✅ Already approved by you | Skip; merge is on someone else |
| `draft` | 📝 Draft | Skip unless author pings |
| `conflict` | ⚠️ Conflict | Skip; needs rebase |

The first three are **actionable**. The rest are **informational** — they tell the user the state of the world but don't need action.

## Present the queue

Render the JSON as a human-readable table grouped by bucket. Match this format exactly so the output is consistent for colleagues:

```
Reviewer queue — <total_count> open MRs assigned to you (as of <fetched_at>)

🔴 REVIEW NOW (N)
  <ref>  <title-truncated-to-~50-chars>     <author>     <context>
  <ref>  <title-truncated-to-~50-chars>     <author>     <context>

🔄 RE-REVIEW (N)
  <ref>  <title>                              <author>     <context>

💬 RE-REVIEW — author responded (N)
  <ref>  <title>                              <author>     <context>

⏳ Skipped (N total: K waiting, L draft, M approved, ...)
  [list each skipped MR with its bucket reason, abbreviated]
```

Format hints:

- Pad columns to a reasonable width but don't get pedantic — fixed-width is fine.
- Truncate titles to ~50 characters with `…`.
- Use the `ref` field directly as the identifier (e.g., `ecfx/ecfx-backend!5409`). It's the form `mr-review` accepts.
- Show timestamps as relative ("3d ago", "yesterday", "14h ago") not raw ISO. Compute from `fetched_at` minus `updated_at`.
- Hide a bucket entirely if it's empty (no `(0)` rows).
- If the user said `quiet`, omit the `⏳ Skipped` section entirely.

End the queue presentation with a prompt:

```
Pick one to start (e.g. `!5409` or full `owner/repo!N`),
or say `walk` to step through actionable MRs top-down,
or `stop` to bail.
```

If actionable buckets are empty, say so directly: *"No actionable MRs right now — everything is either waiting on the author, draft, or already approved by you."* Don't prompt.

## Selection handling

The user replies with one of:

- **A specific ref** (`!5409`, `ecfx/ecfx-backend!5409`, full URL): invoke `mr-review` with that ref. After it completes, return to the queue prompt — they may want another.
- **`walk` / `all`**: enter walk mode (see below).
- **`stop` / `done` / silence**: end gracefully.
- **`refresh` / `again`**: re-run the triage script and re-present.

If the user picks an MR not in the actionable buckets (e.g., "review !5350" which is in `draft`): warn first — *"!5350 is currently in the `draft` bucket. Review anyway?"* — then proceed if they confirm.

## Walk mode

When the user picks `walk`:

1. Pick the first MR in the highest-priority actionable bucket (priority order: `review_now` > `re_review_commits` > `re_review_response`).
2. Invoke `mr-review` with that MR's ref. The `mr-review` skill handles the full review-and-post cycle, including its own approval gate.
3. After `mr-review` returns control:
   - Re-run the triage script (state may have changed — your post just landed, the author may have pushed in the meantime, another reviewer may have approved).
   - If actionable buckets are non-empty, present a brief status (*"Done with !5409. Next up: !5412 — review now (first time at you)"*) and pick the next.
   - If actionable buckets are empty, end with *"Queue cleared. <N> MRs remain in skipped buckets."*

The user can interrupt walk mode at any point by saying `stop`, `pause`, `enough`, etc. Be permissive about interruption phrasing.

## Composing with `mr-review`

When you invoke the `mr-review` skill, pass the MR ref as the input. `mr-review` parses it (URL, `owner/repo!N`, or just `!N` with conversation context) and runs its own pre-flight + draft + approval gate + post.

This skill does **not** duplicate `mr-review` logic. If you find yourself drafting a review here, you've gone too far — hand off to `mr-review` instead.

## Output guidelines

- **Don't editorialize.** The triage table is informational. Don't add "you should review !5409 first because…" — the bucket priority already says that.
- **Brief skipped-bucket lines.** "Waiting on author" is enough; don't expand to "the author Adam Warbington has not yet replied to your O3 observation about…". The user already knows context.
- **One actionable section per priority tier.** If there are 8 `re_review_commits` MRs, list all 8 — don't pick a "top one" for the user.
- **Never auto-invoke `mr-review`** without an explicit selection from the user (or explicit `walk` mode). Always let the user choose.

## Anti-patterns

- Re-fetching the queue mid-review without a state-changing event. The triage script is fast (a few hundred ms per MR) but each note fetch is a network call. Refresh after `mr-review` returns, not in the middle of a draft.
- Reading source files in the local checkout from this skill. That's `mr-review`'s job. This skill operates entirely off `glab` API output.
- Hardcoding repo paths or usernames. The triage script uses `glab api user` for self-identification and the GitLab API for everything else — fully portable across users.
- Letting the user accidentally review a draft MR without a confirmation prompt.

## Edge cases

- **Empty queue.** If `glab api` returns no MRs assigned, say: *"No open MRs assigned to you as a reviewer. 🎉"* and stop.
- **`glab` returns 401/403.** The script exits 2 with a stderr message. Surface that to the user verbatim and tell them to re-auth: `glab auth login`.
- **Same MR appears in multiple buckets.** Shouldn't happen — `categorize()` returns exactly one bucket. If you see it, treat as a bug.
- **`fetched_at` is stale.** The script re-runs on each invocation; the JSON is always fresh. If the user asks to refresh, just re-run.
- **`ref` is missing for an MR.** Falls back to `#<id>` in the JSON. If the user picks one of those, you'll need to ask them for the explicit `owner/repo!N` since `mr-review` can't resolve a numeric global ID.
