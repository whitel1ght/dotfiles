# MR Review — examples

Two worked examples showing the first-pass and re-review flows. Both were drawn from real reviews; details are abbreviated.

## Example 1: First-pass review

**User:** `review MR 5348`

**Claude (after pre-flight: glab fetch, locate-checkout, no prior note from `<self>` found → first-pass):**

> Tight, well-scoped hotfix. Two independent bugs, each fix collapses the user-visible duplicates on its own, doing both is defense-in-depth — exactly the right shape for an "uploaded three times to NetDocs" customer-impact ticket. Production evidence is concrete (CloudWatch query against case `A-580-878 REV` showing 12+ consecutive cycles of `newEntries: 3`).
>
> ## Blockers
>
> None.
>
> ## Observations
>
> **O1 — The "any prefix match = duplicate" rule depends on ITA filings being atomic-multi-part.**
>
> The fix's correctness rests on every part `-01..-NN` of a single filing being created at once on the court site. If a future court system reuses this pattern with non-atomic semantics, the same dedup will silently drop the new part. Worth pinning the assumption explicitly in the `collectBarcodePrefixes` javadoc.
>
> **O2 — `extractPrefix` uses `matcher.find()` rather than `matcher.matches()`.**
>
> ```java
> private static String extractPrefix(String barcode) {
>     Matcher matcher = ITAServiceCommon.DOCUMENT_NUMBER_FROM_BARCODE_PATTERN.matcher(barcode);
>     return matcher.find() ? matcher.group(1) : barcode;
> }
> ```
>
> `find()` succeeds on substring match. The pattern *is* anchored (`^([\d]+)-([\d]{2,3})$`) so the two are equivalent today, but `matches()` aligns with the javadoc's "unrecognized formats fall back" wording.
>
> ## What's good
>
> - Two-bug defense-in-depth — partial recurrence has lower cost.
> - Production CloudWatch query is reproducible by anyone with log access.
> - `buildCourtEnvelopeId` test set covers order-invariance, distinct-set, single doc, empty list, null filter, sort assertion.
>
> Want me to post? Same drill — flag any items to drop and I'll adjust before posting.

**User:** `yes`

**Claude:** Posts via `glab mr note 5348 --repo ecfx/ecfx-backend --message "$(cat <<'EOF' ... EOF)"`, captures the URL.

> Posted: https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/5348#note_3307311372

---

## Example 2: Re-review

**User:** `Adam has made updates, lets review again`

**Claude (pre-flight finds prior note from `<self>` → re-review; reads the prior items and the author's response):**

> All four addressable items from my first pass are landed cleanly in `3f77eecd5`, and the deferred items (O3, N1) are sensibly scoped out with explicit follow-up commitment. Approve.
>
> ## Verified addressed
>
> - **O1 (atomic-multi-part assumption)** — New "Load-bearing assumption" javadoc block on `collectBarcodePrefixes`. ✓
> - **O2 (`find()` → `matches()`)** — Switched, with javadoc explicitly calling out the strict-end-to-end-shape intent. Verified `DOCUMENT_NUMBER_FROM_BARCODE_PATTERN` is `^([\d]+)-([\d]{2,3})$` — fully anchored. ✓
> - **O4 (debug residue in regression test javadoc)** — Replaced with concise contract description. ✓
> - **O5 (visible-for-testing comment)** — Added. ✓
>
> ## Items deferred (acknowledged)
>
> - **O3 / Shoha #1** — Shared `ITAServiceCommon.extractDocumentPrefix(String)` helper + `@Deprecated(forRemoval = true)`. Reasonable to scope out.
> - **N1** — `buildCourtEnvelopeId` empty-list javadoc. Pre-existing behavior, safe to defer.
>
> ## What's good on this pass
>
> - The new "Load-bearing assumption" pattern is exactly the right shape — assumption stated, failure mode for a copy-paste, supporting evidence cited.
> - Posting the RCA correction on Jira to deflect the "speed hypothesis" before deploy is good incident discipline.
>
> Approve. Ready to merge.
>
> Want me to post? Same drill.

**User:** `yes`

**Claude:** Posts and confirms.

---

## What the skill does internally

```
[trigger detection: "review MR 5348" or paste URL]
    ↓
glab api user | jq -r .username                                → <self>
    ↓
glab mr view <N> --repo <owner>/<repo>                          → metadata
glab mr view <N> --repo <owner>/<repo> --comments               → comment thread
glab mr diff <N> --repo <owner>/<repo>                          → diff
    ↓
locate-checkout.sh <owner>/<repo>                               → /path/to/local/clone
    ↓
[detect re-review: scan thread for prior <self> notes]
    ↓
[read source files in /path/to/local/clone for any claim that depends on code outside the diff]
    ↓
[draft review using first-pass or re-review template]
    ↓
[present to user; wait for "yes" / "drop O3"]
    ↓
glab mr note <N> --repo <owner>/<repo> --message "$(cat <<'EOF' ... EOF)"
    ↓
[print posted URL]
```

## Tips

**Calibrating severity.** If you find Claude classifying everything as Observation, ask it to push trivial items to Nit. If three Blockers feel like too many, ask Claude to re-check whether each genuinely requires a fix-before-merge.

**Iterating on the draft.** You don't have to accept the first draft. Ask for specific changes — *"drop O4"*, *"add a nit about the imports order"*, *"move the V790 grant audit point higher"* — before approving the post.

**Handling controversial pushback.** If the author argues against an Observation in their re-review response and you think they're right, Claude should mark it as "deferred" or "withdrawn" in the next pass rather than re-litigating. If you think they're wrong, ask Claude to re-raise it with the corrected reasoning.

**For colleagues sharing the same MR.** The skill posts under whoever's `glab` is logged in. If two reviewers want independent threads, each should run the skill from their own session.
