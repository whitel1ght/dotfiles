---
name: mr-review
description: >-
  Conduct a tiered code review on a GitLab merge request. Fetches the diff and prior comments via `glab`, auto-discovers the local clone, drafts a Blocker / Observation / Nit / What's-good review (or a re-review variant), gates on user approval, then posts via `glab mr note`. Use when the user asks to review a GitLab MR ("review MR 5348", "review !5348", "do another pass on 5330"), pastes a GitLab MR URL, or asks for a re-review pass on an MR you've already reviewed.
---


# MR Review

Conduct a tiered code review of a GitLab merge request. Mirrors the workflow of an experienced reviewer: fetch the diff and prior comments, verify suspicions against the local checkout, draft a structured review, gate on user approval, then post.

The value of this skill is in calibrated judgment, not formatting. The structure is fixed so colleagues' reviews are consistent; the content is yours.

## Inputs

The user will provide one of:

- **Full MR URL**: `https://gitlab.com/<owner>/<repo>/-/merge_requests/<N>`
- **Short reference**: `<owner>/<repo>!<N>` or `!<N>` (where `!N` reuses the most recent repo in the conversation, if known)
- **Just a number**: `<N>` — only valid if the user has already named the repo earlier in the conversation. If you can't determine `<owner>/<repo>` and `<N>` unambiguously, ask the user for the repo before continuing.

## Pre-flight: gather context

Run these **sequentially**, not in parallel. The Bash sandbox cancels the entire batch when any single parallel call errors — a transient failure on one (e.g., `locate-checkout.sh` returning no-match) wipes out the others, forcing a re-run. Sequential trades a small amount of latency for resilience and surfaces individual failures cleanly. Don't draft anything until pre-flight succeeds.

### 1. Identify the current `glab` user

```
glab api user | jq -r .username
```

Save the result. You'll use it to detect "is this a re-review by *me*?" — search the comment thread for prior notes by this username.

### 2. Fetch MR metadata, comments, and diff

```
glab mr view <N> --repo <owner>/<repo>
glab mr view <N> --repo <owner>/<repo> --comments
glab mr diff <N> --repo <owner>/<repo>
```

If the diff is large (>500 lines), tee to a workfile so you can re-read sections without re-fetching:

```
glab mr diff <N> --repo <owner>/<repo> > /tmp/mr-<N>.diff
```

### 3. Locate the local checkout

```
bash ${CLAUDE_SKILL_DIR}/scripts/locate-checkout.sh <owner>/<repo>
```

The script auto-discovers the local clone by scanning common source roots (`~/Documents/source`, `~/code`, `~/src`, `~/projects`, `~/work`) for a `.git` directory whose `origin` remote matches `<owner>/<repo>`. On success it prints the absolute path on stdout, caches the result to `~/.config/mr-review/paths.json` for next time, and exits 0.

Possible exit codes:
- **0** — single match, path printed on stdout. Use it.
- **1** — no match. Tell the user: *"No local clone of `<owner>/<repo>` found under the standard source roots. Either clone it, or add an explicit mapping to `~/.config/mr-review/paths.json` (e.g. `{\"owner/repo\": \"/abs/path\"}`)."* Do not proceed without a checkout — reading source files outside the diff is essential to a useful review.
- **2** — multiple matches. The script prints the candidates on stderr; show them to the user and ask which is canonical, then write to `~/.config/mr-review/paths.json` to lock it in.

### 4. Detect first-pass vs re-review

Scan the comment thread output from step 2:

- If `<self>` (from step 1) has previously posted a top-level note on this MR → **re-review**. Identify the prior items (yours and other reviewers') so you can structure around what's been addressed and what's new.
- Otherwise → **first-pass**.

## Review process

### Read the diff with intent

Don't just summarize. Identify the **load-bearing claims** of the MR — what would falsify each one?

For every concern that crosses your mind, ask:
- Is this actually broken? Or am I pattern-matching from a different MR?
- What's the blast radius if it ships?
- Is it reversible after merge?
- Is it introduced by this MR, or pre-existing?
- What would the author's defense be? Is it valid?

### Verify against the local checkout

For every claim that depends on code outside the diff, **read the actual source file in the local checkout** before asserting in the review. The diff alone is not enough. Common patterns that need source reading:

- A method signature change → read the callers.
- A new constructor parameter → read the bean wiring / DI graph.
- A regex change → read the pattern definition to verify anchoring/groups.
- A native query → read the entity to verify columns and types.
- A test that relies on a helper → read the helper's behavior.
- A claim like "this matches the pattern in X" → read X and confirm.

If you assert something in the review that you haven't verified, say so explicitly ("I haven't read the migrator schema; worth confirming"). Reviewers who hedge calibrated assertions are useful; reviewers who confidently make unverified claims are dangerous.

### Calibrate severity

- **Blocker** — actual bug that ships breakage, security exposure, data loss, or hard-to-reverse mistake. Be sparing. Most reviews have zero blockers; reaching three should make you re-check whether you're calibrating correctly.
- **Observation** — design concern, edge case, missing test, scope question. Should be addressed but not necessarily before merge if the author/team agrees on a follow-up.
- **Nit** — trivial preference, optional polish. The author should feel comfortable ignoring.

If you find yourself classifying everything as Observation, you're under-calibrating — push the trivial ones to Nit, and elevate the genuinely critical ones to Blocker.

### Number consistently

Use `O1, O2, ...` for Observations, `N1, N2, ...` for Nits, `B1, B2, ...` for Blockers. In a re-review, give new items fresh numbers (if first pass had `O1..O4`, the new ones start at `O5`). Cross-references in future passes will work.

### Structure the review

Pick the right template based on first-pass vs re-review.

#### First-pass template

```markdown
[Two- to three-sentence summary: what this MR does, the headline judgment, recommendation.]

## Blockers
[Either "None." or numbered B1, B2, ... — issues that must be fixed before merge.]

## Observations
[Numbered O1, O2, ... — design concerns, missed cases, doc gaps. Severity below blocker.]

## Nits
[Numbered N1, N2, ... — trivial preferences, optional polish.]

## What's good
[Bulleted list of genuinely strong choices in the MR. Skip if there isn't anything noteworthy — don't pad.]
```

#### Re-review template

```markdown
[Two- to three-sentence summary: what's been resolved since the prior pass, headline judgment, recommendation.]

## Blockers
[Either "None." or numbered. Carry forward unresolved blockers from the prior pass with their original numbers.]

## Verified addressed
[Bulleted list of items from prior reviews (yours and other reviewers') that are now resolved. Use ✓ marker. Be specific about what changed.]

## New observations
[Numbered O<n+1>, O<n+2>, ... — concerns introduced by the new revision, or items you missed last pass.]

## Nits
[Numbered, optional.]

## Items deferred (acknowledged)
[Bulleted list of items the author explicitly deferred to follow-up tickets. Acknowledge them so they don't get lost; don't re-litigate unless the deferral is wrong.]

## What's good on this pass
[Bulleted, optional. Worth highlighting if the author improved the MR meaningfully.]
```

### Output guidelines

- **Cite file:line** wherever possible. `ITAPoller.java:560` lets the reviewer navigate; "around the auth method" wastes their time.
- **Quote the relevant code** in fenced blocks for any non-trivial concern. The author shouldn't need to re-open the file to follow your point.
- **Name the load-bearing assumption** when raising a design concern. "This depends on X being atomic" is useful; "this might not work" is not.
- **Trust but verify other reviewers**. If a prior reviewer claims a fix is correct, don't re-litigate — but do flag if the fix is partial or introduces a different issue.
- **Don't pad "What's good"**. If you can't think of anything specific, omit the section. Generic praise dilutes the genuine compliments.

## Approval gate

Present the drafted review to the user **without posting**. End with:

> Want me to post? Same drill — flag any items to drop and I'll adjust before posting.

Wait for explicit confirmation. If the user asks to drop items, renumber to keep the sequence dense (drop `O3`, then `O4` becomes `O3`). Don't post until the user says yes.

## Post

Once approved, post via `glab mr note` using a HEREDOC so backticks, code blocks, and special characters survive shell quoting:

```bash
glab mr note <N> --repo <owner>/<repo> --message "$(cat <<'EOF'
[review body — exactly as drafted]
EOF
)"
```

The `'EOF'` (quoted) prevents variable expansion inside the HEREDOC. Always use the quoted form.

Capture the returned URL and confirm to the user:

```
Posted: <URL>
```

## When to push back vs defer vs escalate

- **Push back** when a prior reviewer's concern was resolved poorly. Re-raise it explicitly with the corrected reasoning, citing the specific gap.
- **Defer** when a concern is real but outside scope. Suggest a follow-up ticket — don't expand the MR.
- **Escalate to PM** when a concern is technically correct but depends on product judgment (e.g., "should we silently drop part `-04` if it appears later?"). Flag with "Worth confirming with PM" rather than asserting the technical answer is the product answer.

## Anti-patterns to avoid

- Drafting a review without reading source outside the diff.
- Padding "What's good" with generic praise.
- Treating every observation as equal severity (no Blocker calibration).
- Re-litigating items another reviewer already raised and the author resolved.
- Posting without the approval gate ("Want me to post?").
- Using `$(...)` command substitution inside the HEREDOC (it'll expand at the wrong time and mangle the message body).
