---
name: mr-review-multi-agent
description: >-
  Run a thorough, multi-agent code review on a GitLab merge request — a panel of specialists (simplicity, prod-readiness, security, language-stack) reviews independently, then focused cross-examination resolves disputes, then a consolidated review is drafted and posted directly to the MR (no confirmation step) as exactly ONE summary comment containing every finding, and the MR is left with one clear status — ✅ Approved (approve + `approved` label) or 🔴 Changes requested (revoke + `needs-changes` label) — so the author knows what to do next. Requires a local checkout for source verification. Use when the user wants a deep / thorough / heavyweight review, asks to "multi-agent review", "have the agents look at this", "run reviewers against", or wants several specialists to weigh in on a high-stakes or cross-cutting MR. For a quick single-voice pass on a routine MR, prefer `/mr-review` instead.
---

> A sibling may legitimately be absent — the backend checklists are not installed in the
> dashboard, for instance. Treat a missing one as "that lens does not apply here" and
> carry on; never invent its contents.


# Multi-Agent MR Review

Run a structured, multi-round code review of GitLab merge requests using a panel of specialist agents. Agents review independently first; subsequent rounds are *focused* — only items with genuine cross-specialty value or severity disputes get re-examined. The skill produces **exactly one comment per MR** — a single consolidated summary carrying every blocker, major, minor, question, and kudos — plus a verdict action, posted directly to the MR without a confirmation step.

**One comment. Never more.** This skill does NOT post line-anchored discussion comments, one-finding-per-comment threads, or per-round notes. Every finding — however many there are, whatever files they touch — goes into the body of a single `glab mr note` (§8). Findings cite their location as `file:line` **inline in the text** of that one comment. If you catch yourself preparing a second API call to `.../discussions` or a second `glab mr note`, stop: that's the exact behavior this skill forbids.

**This is the heavyweight option.** For a single-voice, cheap pass on a routine MR, use `/mr-review` instead. This skill is what you reach for when the MR is high-stakes, complex, cross-cutting, or you want multiple specialist perspectives on the same change.

**Design priorities, in order:** correctness of the findings > converging the panel > total wall-clock. R2/R3 exist to resolve disagreements, not to re-derive context. Most MRs converge in R1; force R2 only when it'll change the verdict. **This skill posts only the final synthesized conclusion, and only after all rounds are in and the panel has converged** (§7). It never posts round-by-round or raw per-agent output. When it does post, it posts *directly* — meaning without a user-confirmation step, NOT early: the single summary comment and the verdict action land on the MR automatically once §7's consolidated review is built. §7.5 is a final *self*-review (your own last prune/calibration pass), not a user gate. The user has standing authorization to post; do not ask for confirmation before posting. (Reporting a one-line recap in chat *after* posting is fine.)

## When to use

- User says: "review this MR", "do a thorough review of MR !123", "multi-agent review", "have the agents look at this PR", "review @author's open MRs", "run reviewers against last hour of MRs in <project>"
- User wants more than one perspective on a non-trivial change
- User wants the review posted *to* the MR, not just reported back in chat

## When NOT to use

- For drafting an MR description (`/mr-description` covers that)
- For local code review of unstaged work (`/pre-commit-review` covers that)
- For security-only review (`/security-review` is cheaper if that's all you need)

## Input

The user invokes one of:

- **Specific MR**: a URL (`https://gitlab.com/group/project/-/merge_requests/123`), a `group/project!123` shorthand, or just `!123` (resolve against the current repo).
- **Project + filter**: `group/project` plus any of: `--since <duration>` (e.g. `1h`, `24h`, `last hour`), `--author <user>` (email or username), `--state opened` (default).
- **Filter only (no project)**: just the filters (`--author <user>`, `--since <duration>`, …) with no `group/project`. Resolve the project from the current directory (see "Default project" below).
- **Combinations**: a project + author + timeframe is valid and selects every matching MR.

**Default project — when no `group/project` is given** (a bare `!123`, a filter-only invocation, or no argument at all), derive it from the current directory's `origin` remote instead of asking:

```bash
git remote get-url origin | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##'
```

This yields the `group/project` path (subgroups included), e.g. `ecfx/ECFX-Categorization`. Print which project you resolved before proceeding ("No project given — using `ecfx/ECFX-Categorization` from the current directory's origin remote."). If the current directory is not a git repo or has no `origin` remote, that command fails — only then ask the user which project they meant. Never invent an MR number.

A truly empty invocation (no MR ref, no filters, no project) means "open MRs in the current repo": resolve the project as above and list open MRs, applying the >5-match confirmation gate in §0. If the argument is otherwise ambiguous, ask the user which form they meant before proceeding.

If the user wants ongoing monitoring ("watch this project for new MRs and review them"), tell them to combine this skill with `/loop` — this skill itself runs one pass and exits.

For batch targeting (project + author + since), each MR's review is posted directly as it completes — no per-MR confirmation. Review the MRs sequentially (never in parallel) so each consolidated review stays high-quality; posting is automatic per MR.

## Pre-flight

Run these **sequentially**, not in parallel. The Bash sandbox cancels the entire batch when any single parallel call errors, and you don't want a transient `glab` blip to wipe out a working checkout discovery. Don't proceed to the agent panel until pre-flight succeeds.

### P1. Identify the current `glab` user

```bash
glab api user | jq -r '"\(.username)\t\(.id)"'
```

Save **both** the username and the numeric **id** (`SELF_ID`). You'll use them for three things: (a) detecting follow-up mode reliably in §0.5 by filtering notes to those authored by *self* (username); (b) avoiding self-replies when scanning existing discussions (username); and (c) adding yourself to the MR's **Reviewers** field whenever you post feedback (the numeric id — see §8).

### P2. Locate the local checkout

```bash
bash ${CLAUDE_SKILL_DIR}/../mr-review/scripts/locate-checkout.sh <owner>/<repo>
```

This is the same discovery script `/mr-review` uses. It scans common source roots, matches the remote `origin` URL, caches the result to `~/.config/mr-review/paths.json`, and prints the absolute path on stdout.

**Shortcut — project derived from the current directory.** If the project was resolved from the current directory's `origin` remote (the "Default project" case in §0), then the current directory **is** the checkout — skip the discovery script. Confirm `origin` matches and record the mapping so later steps and future runs reuse it:

```bash
CHECKOUT=$(pwd)
git -C "$CHECKOUT" remote get-url origin   # sanity-check it matches the resolved project
mkdir -p ~/.config/mr-review
# merge the mapping into paths.json (jq if present, else write the single entry)
printf '{"%s": "%s"}\n' "$PROJECT" "$CHECKOUT" > ~/.config/mr-review/paths.json
```

Otherwise (an explicit `group/project` that isn't the current directory), use the discovery script:

```bash
bash ${CLAUDE_SKILL_DIR}/../mr-review/scripts/locate-checkout.sh <owner>/<repo>
```

Exit codes:
- **0** — single match, path on stdout. Use it.
- **1** — no match. First check whether the current directory's `origin` matches the target project — if so, use `pwd` as the checkout (the script only scans standard source roots, so a clone living elsewhere, like `/workspace/<repo>`, won't be found even though it's valid). Otherwise tell the user: *"No local clone of `<owner>/<repo>` found under the standard source roots. Either clone it, or add an explicit mapping to `~/.config/mr-review/paths.json`."* **Do not proceed without a checkout** — agents need to verify claims against actual source files, not just the diff. The multi-agent panel is too expensive to run on diff-only context.
- **2** — multiple matches. The script prints the candidates on stderr; show them to the user and ask which is canonical, then write to `~/.config/mr-review/paths.json` to lock it in.

Save the checkout path. It goes into `context.md` (§1) and every agent's brief (§3) so they can read source files outside the diff.

## Process

### 0. Resolve targets

First settle the **project**. If the input includes a `group/project` (explicitly or inside an MR URL), use it. Otherwise derive it from the current directory's `origin` remote — this is the default whenever no project is given:

```bash
PROJECT=$(git remote get-url origin | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')
echo "$PROJECT"   # e.g. ecfx/ECFX-Categorization — fails if cwd is not a git repo / has no origin
```

Announce it ("No project given — using `ecfx/ECFX-Categorization` from the current directory."). Only ask the user if that derivation fails.

Then parse the rest of the input into a concrete list of MR IIDs. Use `glab`:

```bash
# Single MR by URL or shorthand
glab mr view <iid> -R <group/project> --output json

# Project + filter
glab mr list -R <group/project> --state opened --output json \
  $( [ -n "$AUTHOR" ] && echo "--author $AUTHOR" ) \
  $( [ -n "$SINCE" ] && echo "--updated-after $(date -u -d "$SINCE ago" +%Y-%m-%dT%H:%M:%SZ)" )
```

Print the resolved list back to the user before starting reviews ("Found 3 MRs matching your filter: !123, !127, !131. Proceeding with multi-agent review of each."). If more than 5 MRs match, ask for confirmation before burning agent time.

For each MR, run steps 1–8 sequentially. Do NOT parallelize across MRs — the review depth matters more than throughput, and parallel reviews crowd context.

### 0.5. Detect follow-up vs fresh review (cheap branch)

Before spinning up the agent panel, check whether this skill has already reviewed this MR and the author has pushed fixes since. The full multi-round panel is expensive (~15–20 min wall-clock for 4 agents × 2 rounds); a follow-up after the author addressed prior findings doesn't need it.

Filter notes to those authored by *self* (from pre-flight P1) and look for this skill's signature header — this is more reliable than grepping the body across all authors, since other reviewers may have quoted the phrase in their own comments:

```bash
glab api "projects/:id/merge_requests/<iid>/notes?per_page=100" \
  | jq -r --arg self "$SELF_USERNAME" '
      .[]
      | select(.author.username == $self)
      | select(.body | test("Multi-Agent Review Summary|Follow-up review"))
      | "\(.created_at)\t\(.id)\t\(.body | split("\n")[0])"' \
  | sort | tail -1
```

If a prior review note exists, extract the head SHA it was reviewing (the summary comment quotes `head_sha` in its metadata footer — see §8). Compare to the current `diff_refs.head_sha`. **Follow-up mode applies when**:

- A prior `Multi-Agent Review Summary` or `Follow-up review` note authored by *self* exists, AND
- The current head SHA differs from the SHA at the time of that note, AND
- The new commits' diff is bounded (typically <500 net-new lines, mostly inside files the prior review flagged)

**In follow-up mode, skip the agent panel entirely.** Do this single-pass yourself, with the local checkout open (pre-flight P2):

1. Read the prior review summary comment's findings list — it contains every finding from that pass, since this skill posts one comment. (On MRs reviewed before this skill consolidated to a single comment, older passes may also have line-anchored discussions; fetch them via `glab api .../discussions` if the summary looks incomplete.) Carry forward the existing finding IDs (e.g. B1, M2, N3) — do not renumber.
2. `git -C <checkout> diff <prior-head> <current-head>` — read the actual changes against the working tree, not just the unified diff text.
3. For each prior finding, verify whether it's addressed. Read the changed source files in the checkout to confirm — don't trust commit messages.
4. Look for *new* code outside the addressed-findings scope. If the fix commit only touches files+ranges that map to prior findings, that's expected. If it adds materially new functionality (a new endpoint, a new dependency, >100 lines outside the prior-findings scope), **fall back to a fresh review** for the net-new code only (one focused agent if it's specialty-clear, otherwise the full R1 panel on the new code).
5. Draft a follow-up note in this shape — **one comment, same rule as §8** (post it directly, no confirmation step; no line-anchored discussions):

   ```markdown
   ## Follow-up review (head: <short-sha>)

   ### Status: ✅ Approved  <!-- or: 🔴 Changes requested -->
   <one line on what the author does next — e.g. "All blockers resolved; good to merge." or "B2 still open; fix it and re-request review.">

   [Two- to three-sentence summary: what's been resolved since the prior pass, headline judgment, recommendation.]

   ### Verified addressed
   - ✓ **B1** — <one-line summary>. Fixed in `<file>:<line>` (commit `<short-sha>`).
   - ✓ **M3** — <one-line summary>. Fixed in `<file>:<line>`.

   ### Still open
   - **B2** — <one-line summary>. Not addressed in this push.
   - **M1** — <one-line summary>. Partially addressed — <what's still missing>.

   ### Items deferred (acknowledged)
   - **N2** — Author noted they'll handle in follow-up ticket <link>. Acknowledged.

   ### New findings (this pass)
   - [If fresh review fired in step 4, list new findings here with fresh IDs continuing the sequence — e.g. M4, M5, N4.]

   ### What's done well on this pass
   - [Optional. Skip if there isn't anything notable — see anti-padding rule.]

   _Generated by `/mr-review-multi-agent` (follow-up mode). head_sha: `<full-sha>`._
   ```

6. Apply the verdict action exactly as in §8 — re-evaluate the status from the still-open findings and run the same `case "$VERDICT"` block. If every blocker is now resolved, the status flips to ✅ Approved: `glab mr approve` plus `--label "approved" --unlabel "needs-changes"`. If blockers remain, it stays 🔴 Changes requested. This keeps the MR's status label honest across passes — a follow-up that resolves the blockers must clear `needs-changes`, not leave it stuck.
7. After the follow-up note and verdict action are posted, **add yourself as a reviewer** the same way as §8's final sub-step. It's idempotent, so on a follow-up pass where you're already in the Reviewers set this is a no-op.

If the diff between prior-head and current-head is too large or sprawling for confident single-pass verification, say so in chat and ask the user whether to run a full fresh review instead.

### 1. Gather context for the MR

For each target MR, collect:

```bash
glab mr view <iid> -R <project> --output json   # title, description, author, labels, draft state, base/head SHAs
glab mr diff <iid> -R <project>                  # full unified diff
glab api projects/:id/merge_requests/:iid/changes   # structured per-file changes with line numbers
```

Extract from those:
- **MR title and description** — author's stated intent
- **Linked Jira ticket** — look for `ECFX-NNNN` or similar in title, description, branch name. If present and the Atlassian MCP is available, fetch the ticket via the Atlassian MCP’s matching tool for problem context (cloud ID `1c62390f-4296-41c6-ac4c-07fab33b5185`).
- **Files changed and languages** — drives agent selection (next step)
- **`diff_refs`** (`base_sha`, `start_sha`, `head_sha`) — `head_sha` goes in the summary comment's metadata footer and drives follow-up detection (§0.5); it's also the SHA the checkout must be on before agents read it
- **Existing discussions** — `glab api projects/:id/merge_requests/:iid/discussions` so you don't re-raise issues already addressed in earlier review rounds (human or agent)

If the project has a `AGENTS.md` at its root, read it — project-specific conventions (e.g. "no JPA, JDBC only", "TenantContext must be @RequestScope") feed directly into the review.

**Pre-stage shared context to a file** so R1 agents read it from one path instead of each receiving the same 2–3K-token preamble inline. Write `/tmp/mr-review-<iid>/context.md` containing:

- MR title, author, branch, stated intent (from the description)
- Linked Jira ticket summary (if fetched)
- Files changed (path + new/mod/del flag) and the `diff_refs` SHAs
- The relevant AGENTS.md conventions (excerpt — don't dump the whole file)
- Path to the full unified diff (`/tmp/mr-review-<iid>/full.diff`)
- **Absolute path to the local checkout** (from pre-flight P2), with a note that agents MUST verify cross-file claims by reading the actual source there
- A file map keyed by specialty: which files matter to which reviewer (e.g., "security cares most about: auth/, security/, *.yml configs")

Also write the full diff to `/tmp/mr-review-<iid>/full.diff`. Agents reference both files by absolute path in their briefs — they `Read` what they need rather than re-deriving from `glab` calls. This eliminates ~30–60s per agent of re-context work and shrinks each brief by ~2K tokens.

**Make sure the checkout is on the MR's head SHA before agents start reading it.** Otherwise an agent reads stale source and "verifies" against the wrong state:

```bash
git -C <checkout> fetch origin <source-branch>
git -C <checkout> checkout <head_sha>   # detached HEAD is fine — agents only read
```

If the checkout has uncommitted local changes, warn the user and stop — don't silently `stash`. The user may have in-progress work; ask before touching it.

### 2. Choose the agent panel

Always include these three:
- `shared:invent-simplify-reviewer` — challenges unnecessary complexity, asks whether the change fits the actual problem
- `shared:prod-readiness` — twelve-factor, scalability, resilience, observability, dev/prod parity
- `shared:security-compliance-reviewer` — security holes, SOC 2 compliance angle, data handling

Plus **stack specialists** chosen from what the diff actually touches. Pick real
agents wherever one matches; the `general-purpose` fallback is a last resort, not
a default.

**When the table below names an agent this session doesn't have** (its plugin isn't
installed here — e.g. the diff touches DuploCloud config and calls for
`infra:duplo-infra-specialist`, but this is a backend-only session): substitute
`general-purpose`, given that specialty's own review lens as its prompt (the same
way the language-specialist fallback below builds one), and **disclose the
substitution in the posted review** — a line naming which specialist was
unavailable and that a generalist stood in, so the reader knows to weight that
lens's findings accordingly. Don't silently drop the lens and don't silently pass
off the generalist's findings as the named specialist's.

| Diff dominated by | Specialist agent(s) |
|---|---|
| Java + Micronaut | `backend:java-micronaut-dev` |
| AWS IaC (Terraform / CDK / CloudFormation) | `ops:aws-cloud-architect` |
| DuploCloud config / Kubernetes via Duplo | `infra:duplo-infra-specialist` |
| `.gitlab-ci.yml`, Git operations | `shared:git-gitlab-expert` |
| Gradle / Jib / build config | `backend:gradle-jib-deployer` |
| JReleaser / Maven Central publishing | `backend:jreleaser-maven-expert` |
| **Vue / TypeScript frontend** (`.vue`, `.ts`, `.scss`) | see **UI panel selection** below |
| **Flask / Python** (`.py`, Jinja `.html`) | see **UI panel selection** below |
| Anything else (Go, Rust, Ruby, Kotlin, C#, …) | `general-purpose` with a "Senior <Language> reviewer" prompt — see "Language specialist fallback prompt" below |

**Domain lenses (ecfx-backend)** — in addition to the stack specialist, add one of these when the diff matches. They count toward the agent cap:

| Diff touches | Domain lens |
|---|---|
| `projects/receipt_processing*`, `projects/poller_queue`, provider processors, the retry engine, or notice dedup | **Receipt-processing reviewer** — `general-purpose` agent instructed to first invoke the `backend:receipt-processor-guardrails` skill (and `backend:court-portal-processor-checklist` when a provider processor or browser automation changed) and review strictly against those checklists: exception classification (retryable vs terminal vs `@UserActionRequired`), USER-vs-ECFX failure routing, stable dedup keys, resource release on retry paths, listener registration |
| Framework/dependency upgrades — Micronaut, Hibernate, JDK, serde, or version-catalog bumps | **Migration-regression hunter** — `general-purpose` agent prompted to hunt the known upgrade pitfall shapes: form-body double-decode on typed `HttpRequest<>` co-injection (SAML, ECFX-14918), Micronaut Serde types missing `@Serdeable`/introspection, Hibernate JSONB deep-copy of non-`Serializable` graphs (ECFX-14913, `EcfxJsonSerializer`), native tuple element types changing (`Timestamp` → `LocalDateTime`, ECFX-14916), criteria-builder functions unsupported on array columns (`array_to_string`, ECFX-14138), `instanceof` checks against relocated/rewrapped exception types, and test assumptions broken by execution reordering. Instruct it to search the diff for these shapes and verify each against the checkout, not to review generally |
| Any non-trivial Java diff (default lens when a panel slot remains) | **Clean-code purist** — the `backend:java-clean-code-purist` agent. It invokes the `backend:java-clean-code-commandments` skill itself and audits the changed files against the Ten Commandments: type-system escapes, swallowed errors, event-loop blocking / singleton state, size and nesting, meaningless tests, layer violations, unjustified dependencies, junk-drawer naming, dead code, hardcoded secrets/config. If the cap is already bound by the other lenses, don't drop the doctrine — instead add one line to the `backend:java-micronaut-dev` brief: "Also invoke the `backend:java-clean-code-commandments` skill and fold commandment violations into your findings." |

#### UI panel selection

The UI codebases have dedicated experts (see `docs/EXPERT_PANELS.md`). Do **not**
send a Vue or Flask diff to the `general-purpose` fallback — these agents know
the frameworks, and they read the project's own `AGENTS.md`, local
`.claude/skills/`, and lint configs at runtime.

Select by what the diff actually contains, not by which repo it is in — a repo
can contain both:

| Files in the diff | Add |
|---|---|
| `.vue`, composables, `src/stores/` | `dashboard:vue-expert` |
| Vuetify components, theming, `v-*` usage | `dashboard:vuetify-expert` |
| `.ts`/`.tsx`, type definitions, `src/types/` | `dashboard:typescript-expert` |
| `.scss`, `<style>` blocks, style partials | `dashboard:styling-expert` |
| Routing, cross-module structure, state architecture, bundle config | `dashboard:frontend-architect` |
| `ecfx_admin/views/`, `app.py`, routes, forms | `admin:flask-expert` |
| `ecfx_admin/models/`, queries, migrations | `admin:sqlalchemy-expert` |
| `ecfx_admin/templates/` (Jinja2) | `admin:jinja-ui-expert` |
| `tests/` (Python) | `admin:pytest-expert` |
| Python package/module boundaries, config, services | `admin:python-architect` |
| **Any user-facing UI change** (Vue components or Jinja templates) | `ui-review:accessibility-expert` |
| **Any change to user-facing interaction or copy** | `ui-review:ux-expert` |

`ui-review:accessibility-expert` and `ui-review:ux-expert` serve both stacks. Include
`ui-review:accessibility-expert` whenever the diff changes rendered markup — it is the
least-covered risk in both projects (no a11y tooling is installed in either, and
a contrast regression has shipped before: ECFX-15857).

#### Panel size

Cap at **5 total agents** for a backend or infra MR — the 3 always-on plus 2
specialists/lenses. Convergence gets expensive past that.

**UI MRs may go to 7** (the 3 always-on plus up to 4 UI specialists). The UI
lanes are narrower and less overlapping than backend ones — a Vue reactivity bug,
a contrast failure, and a missing type are genuinely different findings that one
reviewer will not catch together. Prefer more specialists over a broader prompt
on a single agent.

When the cap binds:

- **Backend/infra** — prefer the **domain lens** over the stack specialist.
  `backend:java-micronaut-dev` overlaps more with the always-on reviewers than the domain
  checklists do. If more stacks are touched than fit, fold the extras into a
  single `general-purpose` "polyglot reviewer" prompt covering the secondary
  stacks.
- **UI** — drop the *least* relevant specialist rather than folding lanes
  together; a diluted reviewer produces diluted findings.
- **Mixed backend + frontend** — take at least one specialist from each side and
  note in the summary which lanes went unstaffed.

Announce the panel: "Reviewers for !123: invent-simplify, prod-readiness, security-compliance, vue-expert, accessibility-expert."

**Model gate (Pi, when `agent_select_models` is available; otherwise skip).** Once the panel is announced and before the Round 1 spawn, pick the stable flow ID from the invocation: single MR: `mr-review-multi-agent:<project>!<iid>`; batch: one flow ID for the whole invocation, `mr-review-multi-agent:<project>:<author>:<since>` (use the literal filter values, `-` for one not given); explicit list of MRs: `mr-review-multi-agent:<project>!<iid>+<project>!<iid>…` with the refs sorted. Use one role key per reviewer (the agent's name). Call `agent_select_models` once, with one entry per role: key, title, task type, `recommendedModel` and a one-sentence recommendation. If it is cancelled or errors, stop the flow and spawn nothing. Pass each returned model as `model` on that role's spawn, and reuse it whenever the same known role is spawned again. A role that was not selected gets an automatic model from the usual policy, without another prompt. Gate once, before the first MR's Round 1 spawn, and never per MR: later MRs in the batch reuse that same context, pass the same stored model for the same role and leave roles that were not selected automatic. If the gate is cancelled or errors in a batch, stop the whole batch and post nothing, since no MR has posted before the gate runs. Unless a parent flow already gated: when a parent that already gated passes you its established selection context (its flow ID and role choices), do not call `agent_select_models` again; reuse the matching inherited choices as `model` and leave newly discovered roles automatic.

### 3. Round 1 — independent reviews (parallel)

Spawn all selected agents **in a single message with parallel `task` tool calls**. Each agent gets the same brief:

```
You are reviewing GitLab MR !<iid> in <project>.

Read /tmp/mr-review-<iid>/context.md first — it has the MR brief, project conventions, the file-to-specialty map, the absolute path to the local checkout (already on the MR's head SHA), and a path to the full diff. Then review through the lens of <agent specialty>.

Read the diff with intent. Don't just summarize — identify the load-bearing claims of the MR. What would falsify each one?

Source verification (REQUIRED for any claim outside the diff):

The local checkout is at <CHECKOUT_PATH> on head_sha <HEAD_SHA>. For every concern that depends on code outside the diff, READ the actual source file in the checkout before asserting. The diff alone is not enough. Common patterns that need source reading:

  - A method signature change → read the callers.
  - A new constructor parameter → read the bean wiring / DI graph.
  - A regex change → read the pattern definition to verify anchoring/groups.
  - A native SQL query → read the entity to verify columns and types.
  - A test that relies on a helper → read the helper's behavior.
  - "This matches the pattern in X" → read X and confirm.

If you assert something you haven't verified, say so explicitly ("I haven't read the migrator schema; worth confirming"). Hedged calibrated assertions are useful; confident unverified claims are dangerous.

Findings format:

  [SEVERITY] <one-line summary>
  File: <path>:<line>   (omit if cross-cutting)
  Why it matters: <1-3 sentences — name the load-bearing assumption when raising a design concern. "This depends on X being atomic" is useful; "this might not work" is not.>
  Code:
    ```<lang>
    <quote the relevant snippet so the next reader doesn't need to re-open the file — required for non-trivial findings>
    ```
  Suggested fix: <concrete, actionable — code snippet if useful>

Severities (calibrate carefully):

  - BLOCKER — actual bug that ships breakage, security exposure, data loss, or hard-to-reverse mistake. Be sparing. Most reviews have ZERO blockers; reaching three should make you re-check whether you're calibrating correctly.
  - MAJOR — meaningful production risk: missing error handling on a hot path, missing test coverage for new logic, scalability cliff, observability gap. Should fix.
  - MINOR — style, naming, small refactor opportunity, redundant code. The author should feel comfortable ignoring.
  - QUESTION — you can't tell from the diff (plus the checkout) whether the change is correct. Author response needed.
  - KUDOS — explicit praise where the change is unusually well executed.

If you find yourself classifying everything as MAJOR, you're under-calibrating — push the trivial ones to MINOR, and elevate the genuinely critical ones to BLOCKER. If your finding is "the author should feel comfortable ignoring this" — that's a MINOR.

End with a one-line verdict: APPROVE / APPROVE_WITH_COMMENTS / REQUEST_CHANGES.

Verification budget — be deliberate about tool spend:

  - Reading source files in the local checkout is CHEAP and EXPECTED. Don't skip it to save tool calls.
  - Reach for heavy verification (bytecode disassembly, full dependency walks, unpacking JARs) ONLY when the finding is BLOCKER severity AND the fact you're verifying is a framework default or version-specific behavior that affects the verdict.
  - For MINOR/QUESTION findings, cite the docs or move on. Don't unpack a JAR to verify a "nice to have."
  - Budget guideline: ~20 tool calls is enough for most reviews. If you're past 40, you're probably re-deriving context the prior reviewer already established — re-read /tmp/mr-review-<iid>/context.md instead.

Be specific. Cite line numbers. Don't restate the diff. Skip findings outside your specialty.
```

For the language specialist fallback, prepend: "Act as a Senior/Principal <Language> engineer with 10+ years of production experience. Focus on idiomatic <Language>, common pitfalls, performance, and library/framework misuse."

For the **UI specialists** (`dashboard:vue-expert`, `dashboard:vuetify-expert`, `dashboard:typescript-expert`,
`dashboard:styling-expert`, `dashboard:frontend-architect`, `admin:flask-expert`, `admin:sqlalchemy-expert`,
`admin:jinja-ui-expert`, `admin:pytest-expert`, `admin:python-architect`, `ui-review:accessibility-expert`,
`ui-review:ux-expert`), append:

```
Also read ~/.config/opencode/modules/ui-project-context.md (a real file at
`~/.config/opencode/modules/`, in this plugin beside its agents) and follow it — it governs how you orient in the
project, verify claims, and defer to project-owned rules.

The checkout at <CHECKOUT_PATH> is on the MR's head SHA. Read the project's own
rules from there rather than relying on the context.md excerpt: its AGENTS.md,
its .claude/skills/ if present, and its lint configs (eslint.config.js,
stylelint.config.js, ruff.toml, .djlintrc). Those are the source of truth — the
excerpt in context.md is a summary, not a substitute.

A finding that would trip one of the project's gates (stylelint, the i18n
no-raw-text rule, ruff, vue-tsc) is at minimum MAJOR: the author literally
cannot merge it. Say which gate and why.
```

For the **backend specialists** (`backend:java-micronaut-dev`, `shared:security-compliance-reviewer`,
`shared:prod-readiness`, `shared:invent-simplify-reviewer`, `backend:java-clean-code-purist`), append:

```
Also read ~/.config/opencode/modules/backend-project-context.md (a real file at
`~/.config/opencode/modules/`, in this plugin beside its agents) and follow it. It lists the failure classes that
repeatedly survived multiple review rounds in these repos (fixtures that encode a
contract the API never produces, filtered test runs that miss legacy *Test.java,
WARN-level alerts a module's appender never forwards, tools that report "0" when
their dependency is misbound, provider-specific copy in shared code, security
comments that misdescribe the role model, merge-topology drift, runbook drift in
the description) and the evidence standard: never report a mutation as "verified
red" unless you ran it or the author's evidence shows it.

If the MR already has a prior round, read the author's reply table first and
check each "already closed by <sha>" claim against the current head before
re-raising a finding.
```

### 4. Synthesis after Round 1

Read all agent outputs. Build a finding table (in your own working memory — don't post anything yet):

| ID | Finding | Raised by | Severity | File:line | Status |
|---|---|---|---|---|---|
| F1 | … | invent-simplify | MAJOR | foo.java:42 | new |
| F2 | … | prod-readiness, security | BLOCKER | bar.java:88 | corroborated |
| … |

Classify each finding:
- **Corroborated** — 2+ agents independently raised it. Strong signal; carry forward.
- **Unique** — one agent raised it. Carry forward but ask other agents in round 2 whether they agree.
- **Disputed** — only happens after round 2+; mark for explicit reconciliation.

Decide whether a round 2 is needed. **Default is to skip R2.** Round 2 is expensive (~5–8 min wall-clock, plus a synthesis pass) and most of the agent time gets spent on AGREE / DEFER responses for findings outside the agent's lane.

**Skip R2 when any of these is true:**
- All findings are KUDOS or MINOR with no disputes.
- Findings are corroborated by 2+ reviewers AND the severities they assigned are consistent (no specialist treating it BLOCKER while another treats it MINOR).
- The remaining unique findings are clearly lane-specific — a security finding about JWT signature mechanics, a Micronaut finding about filter ordering bytecode. The other reviewers wouldn't have useful input on the technical detail.
- The verdict is already clear: e.g., 3+ corroborated BLOCKERs across reviewers means REQUEST_CHANGES regardless of what R2 would add.

**Run R2 only when at least one of these is true:**
- Two or more reviewers raised the *same* finding with *different* severities (genuine dispute that affects the verdict).
- A unique finding has cross-specialty relevance — e.g., simplicity argues "delete this whole abstraction," and security/prod-readiness should weigh in on whether the abstraction is load-bearing.
- The R1 verdicts diverge meaningfully (one APPROVE, one REQUEST_CHANGES) and the divergence isn't already explained by specialty.

When you skip R2, note it in the summary: `Rounds run: 1 (R1 convergence sufficient)`. This is not cutting corners — most well-scoped MRs converge in R1, and forcing R2 produces busywork.

### 5. Round 2 — focused cross-examination (parallel)

Before spawning R2, do the routing work yourself. For each finding that survived the R2 gate in step 4, decide *which* agents genuinely need to weigh in. Don't send every finding to every agent — that produced the bloat we saw in past runs (R2 agents using zero tool calls because the prompt was too large to do anything but skim).

**Per-agent R2 brief shape — lean and targeted:**

```
ROUND 2 — focused cross-examination

You reviewed this MR in R1. We're back only because a few findings need your specific input.

Findings routed to you (others were either corroborated or lane-specific to another reviewer):

[F4] <summary> — raised by <agent>, severity <X>.
  Why you: <one-line reason this specific reviewer's input is needed — e.g., "you flagged a related complexity concern", "this hinges on a Micronaut idiom", "security argues BLOCKER, prod-readiness argues MINOR — your specialty weighs in on which is right">
  Respond: AGREE / DISAGREE / DEFER (with one-line justification).

[F12] <summary> — disputed between <agent A> and <agent B>.
  Why you: <reason your lens matters here>

Your own R1 findings — revisit each:
  [F3] <your finding> — KEEP / REFINE / WITHDRAW (briefly justify).
  [F7] <your finding> — KEEP / REFINE / WITHDRAW.

Add NEW findings ONLY if R1's cross-examination prompted them (uncommon). Do not re-review the diff broadly.

End with an updated verdict.
```

Typical R2 brief should hand each agent **3–8 items** (a mix of routed-to-them + their own R1 findings). If you find yourself sending 15+ items to an agent, you're not routing — re-check whether R2 was actually needed (step 4 may have been too permissive).

Synthesize again. After R2 the finding table has explicit AGREE/DISAGREE columns for the disputed items only, plus withdrawals and refinements on each agent's own R1 work.

### 5b. Optional — micro-rounds for stubborn disagreements

If R2 narrowed the disputes to 1–2 items that two specific agents disagree on, **don't run a full R3** with everyone. Send a focused message just to those two agents (use SendMessage to continue the existing agent threads — they already have the R1+R2 context cached). One round of direct back-and-forth between the two specialists usually converges or surfaces the genuine disagreement faster than a full R3 of four agents.

### 6. Round 3 — rarely needed

Prefer the **micro-round** described in step 5b for stubborn 1–2-item disagreements between two specific agents — it's much cheaper than a full R3 panel.

Run a full R3 (all agents in parallel) **only if** after R2:
- Multiple findings still have genuine disagreement across 3+ agents, AND
- The verdicts diverge in a way that isn't explained by specialty differences, AND
- A micro-round between two agents wouldn't resolve it because the disagreement is genuinely panel-wide.

In practice, a full R3 is rare. **Cap at three rounds total.** If disagreement persists after the third pass, surface it honestly in the final review rather than forcing fake convergence.

### 7. Build the final consolidated review

**This synthesized review is the ONLY thing that ever gets posted to the MR, and it is ONE comment.** Nothing posts until every round has come back AND the panel has converged (or, after the 3-round cap, a remaining disagreement is honestly noted). You post the *conclusion*, not the data: the deduplicated, severity-calibrated findings (each a single durable-ID entry) gathered into a single summary comment, plus the verdict action. Never post raw per-agent output, round-by-round drafts, per-finding threads, or the same finding once per reviewer. "Posted directly / auto-post" (§7.5/§8) means *without a user-confirmation step* — it does NOT mean early; the sequencing here is unchanged.

Assign **durable finding IDs** as you aggregate. These get posted in the public review and must be stable across follow-up passes (§0.5) — never renumber across passes, only assign fresh IDs continuing the sequence:

| Prefix | Severity | Example |
|---|---|---|
| `B` | BLOCKER | B1, B2, … |
| `M` | MAJOR | M1, M2, … |
| `N` | MINOR (nit) | N1, N2, … |
| `Q` | QUESTION | Q1, Q2, … |
| `K` | KUDOS | K1, K2, … |

If a prior pass exists (caught by §0.5), continue its sequence — don't reset.

Aggregate the converged findings into:

- **Blockers** — must fix before merge. Include the corroborated ones plus any unique BLOCKER that survived cross-examination. Number `B1, B2, …`.
- **Major** — strong recommendations. Number `M1, M2, …`.
- **Minor** — optional improvements. Number `N1, N2, …`.
- **Open questions** — things the author should clarify. Number `Q1, Q2, …`.
- **What's done well** — explicit praise where agents called it out. Number `K1, K2, …`. **Don't pad** — if there isn't anything genuinely notable, omit the section entirely. Generic praise dilutes the genuine compliments.
- **Unresolved disagreement** (only if round 3 didn't converge) — present both sides honestly. Don't force consensus.

Decide the verdict:
- **APPROVE** — no BLOCKER/MAJOR findings, only MINOR/KUDOS
- **APPROVE_WITH_COMMENTS** — MAJOR findings but author can fix in follow-up; nothing blocking
- **REQUEST_CHANGES** — any surviving BLOCKER, or unresolved disagreement on a critical point

**Every review resolves to one of exactly two author-facing statuses**, so the author always knows what to do next:

| Verdict | Author-facing status | What the author does next |
|---|---|---|
| APPROVE | ✅ **Approved** | Merge it. |
| APPROVE_WITH_COMMENTS | ✅ **Approved** | Address the MAJOR/MINOR comments (in this MR or follow-up), then merge. |
| REQUEST_CHANGES | 🔴 **Changes requested** | Fix the blockers and re-request review. Do not merge yet. |

This binary status is the headline of the summary comment (§8) and is enforced as a label on the MR (`approved` vs. `needs-changes`), so it's glanceable without reading the whole review.

### 7.5. Final self-review before posting (NO user gate)

**This skill auto-posts — do not ask the user to confirm.** The user has standing authorization to post the review (the single summary comment and the verdict action). §7.5 is your own last quality pass, not a checkpoint you wait on. Run through this silently, fix what needs fixing, then go straight to §8.

Before posting, do a final self-review of the drafted output as it will land on the MR:

1. **Prune.** Drop redundant or low-value findings — 3 sharp MAJORs beats 20 MINORs. This matters more now that everything shares one comment: a bloated finding list is a wall of text the author skims past. This is the last place to cut noise, since there's no user gate to catch it. Keep IDs dense within each prefix after dropping (drop `N4` → `N5` becomes `N4`).
2. **Re-check citations.** Every `file:line` cited in the comment must be real — verify against the diff or the checkout. Never invent a line number. A finding that genuinely can't be located just omits the citation rather than guessing.
3. **Confirm it's one comment.** The drafted output must be a single note body. If you've drafted separate per-finding comments, merge them now.
4. **Re-confirm the verdict** matches the surviving findings (a dropped/downgraded finding can flip `REQUEST_CHANGES` → `APPROVE_WITH_COMMENTS`, which also flips the author-facing status from 🔴 Changes requested to ✅ Approved). The verdict drives the §8 action; the verdict→status→action mapping is automatic and applies whatever the verdict is.
5. **Calibrate severity** one last time — no BLOCKER that's really a MAJOR, no MAJOR that's really a MINOR.

Then post everything in §8 directly. After posting, give the user a one-line recap in chat (§9) — that recap is *after the fact*, not a request for permission.

This applies **per MR** in batch mode too — each MR's review posts directly as it completes; no per-MR confirmation.

### 8. Post to the MR and act on the verdict

Enter this step directly once §7.5's self-review is done — no user confirmation. Three sub-steps: **the single summary comment** → verdict action + status label → add self as reviewer. Post all of them; the verdict action (and the ✅ Approved / 🔴 Changes requested status label it sets) and the reviewer self-assignment are part of the auto-post, not optional extras. Every review must leave the MR in exactly one of the two statuses.

**Exactly one comment.** Do NOT call `projects/:id/merge_requests/<iid>/discussions`. Do NOT split findings across multiple notes, one note per severity band, or a note per file. There is a single `glab mr note` call per MR per pass, and every finding lives inside its body. Location goes inline as `` `<file>:<line>` `` in the finding's own bullet — that is how the author navigates, in place of a line-anchored thread.

**The one comment** carries the full rollup: verdict, reviewer panel, and every finding with its detail. Reference findings by their durable IDs so follow-up passes (§0.5) can cite them precisely. Embed the `head_sha` in the metadata footer — the follow-up detector reads this to know which SHA the review was anchored to.

Give each BLOCKER and MAJOR its own detail block (why it matters, the quoted snippet, the suggested fix) so nothing is lost by dropping inline threads. Keep MINOR / QUESTION / KUDOS to one line each — they don't earn a code block.

In the template below, ```` ``` ```` marks a fenced code block **in the posted comment body** — write real triple-backtick fences there. (They're shown here inside an outer `bash` block; that outer fence is just this document's formatting.)

```bash
glab mr note <iid> -R <project> -m "$(cat <<'EOF'
## Multi-Agent Review Summary

### Status: ✅ Approved  <!-- or: 🔴 Changes requested -->
<one line telling the author what to do next — e.g. "No blockers; address the comments below at your discretion, then merge." or "Fix the blockers below and re-request review before merging.">

**Verdict:** <APPROVE | APPROVE_WITH_COMMENTS | REQUEST_CHANGES>
**Rounds run:** <1/2/3>
**Reviewers:** invent-simplify-reviewer, prod-readiness, security-compliance-reviewer, <specialist(s)>

### Blockers

**B1 — <one-line summary>** — `<file>:<line>`

Why it matters: <load-bearing assumption, blast radius, reversibility>

```<lang>
<quoted snippet from the file — so the author doesn't need to reopen it>
```

Suggested fix:
```<lang>
<concrete code or steps>
```

_Raised by: <agents>._

**B2 — <one-line summary>** — `<file>:<line>`

<same shape as B1>

### Major

**M1 — <one-line summary>** — `<file>:<line>`

Why it matters: <…>

```<lang>
<snippet>
```

Suggested fix: <concrete>

_Raised by: <agents>._

### Minor
- **N1** — <one-line summary>. `<file>:<line>`

### Open questions
- **Q1** — <one-line summary>. `<file>:<line>`

### What's done well
- **K1** — <specific praise>. [Omit the whole section if you can't be specific.]

<if unresolved disagreement: include a section explaining it, naming which reviewers disagreed and why>

_Generated by `/mr-review-multi-agent`. All findings are in this comment; locations are cited inline as `file:line`._
_head_sha: `<full-sha>`_
EOF
)"
```

**Always use the quoted `'EOF'` form of the HEREDOC.** Unquoted `EOF` triggers shell expansion inside the body, which mangles `$variables`, backticks, and command substitutions in your findings' code snippets. Do not use `$(...)` inside the HEREDOC for the same reason — it'll expand at the wrong time and corrupt the posted message.

If the body is large enough to be awkward on a single command line, write it to a file (`/tmp/mr-review-<iid>/summary.md`) and post with `glab mr note <iid> -R <project> -m "$(cat /tmp/mr-review-<iid>/summary.md)"`. That is still one comment — length is never a reason to split into a second note. If the review has so many findings that the comment feels unwieldy, prune (§7.5), don't split.

**Act on the verdict** — always apply the action that matches the computed verdict (this is part of the auto-post; never skip it). The verdict collapses to exactly two author-facing statuses (see §7): **Approved** (APPROVE and APPROVE_WITH_COMMENTS) or **Changes requested** (REQUEST_CHANGES). Each status both performs the GitLab approve/revoke action AND sets a matching status label, so the outcome is glanceable on the MR list without opening it. Crucially, **clear the opposite status label** so a re-review that flips the verdict doesn't leave the MR showing both `approved` and `needs-changes`. APPROVE_WITH_COMMENTS still approves — it means "MAJORs exist but nothing blocks merge." The only verdict that does NOT approve is REQUEST_CHANGES (which requires a surviving BLOCKER or unresolved critical disagreement), so the BLOCKER guard is preserved automatically:

```bash
case "$VERDICT" in
  APPROVE|APPROVE_WITH_COMMENTS)
    # Author-facing status: ✅ Approved. APPROVE_WITH_COMMENTS still approves —
    # MAJORs exist but nothing blocks merge; author addresses comments at their discretion.
    glab mr approve <iid> -R <project>
    # Mark the status and clear any stale "needs-changes" from a prior pass:
    glab mr update <iid> -R <project> --label "approved" --unlabel "needs-changes" || true
    ;;
  REQUEST_CHANGES)
    # Author-facing status: 🔴 Changes requested.
    # GitLab CE has no hard "request changes" state, so use the label convention
    # and revoke any prior approval. Clear any stale "approved" label too:
    glab mr update <iid> -R <project> --label "needs-changes" --unlabel "approved" || true
    glab mr revoke <iid> -R <project> 2>/dev/null || true
    ;;
esac
```

The `--label`/`--unlabel` flags are best-effort (`|| true`) — GitLab auto-creates a label the first time it's applied, but if the project restricts label management, the approve/revoke action and the status header in the summary comment still convey the verdict. If your `glab` build doesn't support `--unlabel`, fetch the current labels and re-set them without the opposite status label instead.

If `glab mr approve` fails because the user lacks approve permission on this project, post the summary comment anyway and tell the user in chat: "Verdict was APPROVE but I don't have approve permission on `<project>`; please approve manually." The status label and summary header still mark the MR as approved.

**Finally, add yourself as a reviewer** — whenever you post feedback (the summary comment, an approval, or both), record that you reviewed this MR by adding the self user (numeric `SELF_ID` from pre-flight P1) to the MR's **Reviewers** field. This is part of the auto-post; it fires for every verdict, including REQUEST_CHANGES. Setting `reviewer_ids` **replaces** the whole set, so fetch the current reviewers first and append self (deduped) to avoid dropping anyone already assigned.

**Send `reviewer_ids` as a JSON array body — NOT via `--field`.** GitLab's MR-update endpoint types `reviewer_ids` as an integer array, and `glab`'s form encoding does not satisfy that:

| Form | What `glab` sends | Result |
|---|---|---|
| `--field reviewer_ids=<id>` | scalar string | HTTP **200** but GitLab strong-params expects an array, so it **silently drops** the field — reviewers stay empty (looks like a permission block, isn't one) |
| `--field "reviewer_ids[]=<id>"` | bracket key `glab` won't parse | HTTP **400** "at least one parameter must be provided" |
| JSON body `{"reviewer_ids":[<id>]}` + `Content-Type: application/json` via `--input -` | proper JSON array | ✅ **works** |

So build the deduped id list with `jq` and pipe a JSON body into `glab api --input -`:

```bash
# Current reviewer ids + self, deduped → set the Reviewers field via a JSON array body
glab api "projects/:id/merge_requests/<iid>" \
  | jq -c --argjson self "$SELF_ID" '{reviewer_ids: ([.reviewers[].id] + [$self] | unique)}' \
  | glab api "projects/:id/merge_requests/<iid>" --method PUT \
      --header "Content-Type: application/json" --input -
```

Then **verify it stuck** (`glab api "projects/:id/merge_requests/<iid>" | jq '.reviewers | map(.username)'`) rather than trusting the HTTP 200 — the scalar-`--field` failure mode returns success with an empty field. This same JSON-body-via-`--input -` pattern is the reliable way to set any array-typed *or* nested-object param (`assignee_ids`, and so on). Treat "`--field` returned 2xx" as no evidence at all for those; always read the field back.

It's idempotent — re-running on a later pass is a no-op because self is already in the set. If you genuinely lack permission to set reviewers (some project configs restrict it — confirm via the verify step above, not by a silent 200), skip and mention it in the chat recap: it's a "who looked at this" marker, not a gate, so never fail or block the review over it. This **also applies in follow-up mode (§0.5)** — once the follow-up note and any re-approval are posted, add self as reviewer the same way.

### 9. Report back to the user

One short paragraph per MR reviewed. Lead with the author-facing status (✅ Approved / 🔴 Changes requested) so the next step is obvious:

> **!123** in `group/project` — ✅ **Approved** (APPROVE_WITH_COMMENTS). Findings: B1–B2, M1–M4, N1–N6, Q1. 2 rounds. Posted the consolidated review comment, approved the MR, and labeled it `approved`.

If multiple MRs were targeted, list one bullet per MR. No long summary at the end.

## Pushing back, deferring, escalating

These are not severity decisions — they're judgment calls about *what to do* with a finding. They apply in the synthesis (§7) and follow-up (§0.5) passes.

- **Push back** when a prior reviewer's concern (human or earlier agent pass) was resolved poorly. Re-raise it explicitly with the corrected reasoning, citing the specific gap in the fix. Carry forward the original finding ID so the conversation thread is coherent ("**B2 (re-raised)** — the new code addresses the symptom in `auth.go:42` but the underlying race in `session.go:88` is untouched").
- **Defer** when a concern is real but outside scope. Suggest a follow-up ticket in the finding text; don't expand the MR. Mark it `MINOR` (not `MAJOR`) if it's pure scope creep — the severity should reflect the impact of *not* fixing it inside this MR, not the absolute severity of the underlying issue.
- **Escalate to PM** when a concern is technically correct but depends on product judgment (e.g., "should we silently drop part `-04` if it appears later?"). Use the `QUESTION` severity and start the finding with "Worth confirming with PM:" rather than asserting the technical answer is the product answer. Don't approve while this is open unless the user explicitly says the PM call has been made.

## Severity reference for agents

- **BLOCKER** — bug, security hole, broken build, broken contract, lost data risk, regression of existing behavior. Cannot merge.
- **MAJOR** — meaningful production risk: missing error handling on a hot path, missing test coverage for new logic, scalability cliff, observability gap. Should fix.
- **MINOR** — style, naming, small refactor opportunity, redundant code. Nice to have.
- **QUESTION** — reviewer can't tell from the diff whether the change is correct. Author response needed.
- **KUDOS** — explicit praise where the change is unusually well executed (good test design, elegant simplification, defensive thinking).

## Quality bar

- **Cite `file:line` wherever possible.** "Around the auth method" wastes the reader's time; `ITAPoller.java:560` lets them navigate.
- **Quote the relevant code in fenced blocks** for any non-trivial concern. The author shouldn't need to reopen the file to follow your point.
- **Name the load-bearing assumption** when raising a design concern. "This depends on X being atomic" is useful; "this might not work" is not.
- **Verify cross-file claims against the local checkout.** A finding asserted without reading the source it depends on is a guess, not a finding.
- Don't post a finding you can't explain in two sentences.
- Never restate the diff back at the author — that's noise.
- **Don't pad "What's done well"** with generic praise. If you can't be specific about why something is notable, omit the section. Generic praise dilutes the genuine compliments.
- If two agents disagree, prefer the more specific argument (concrete file:line, citing the codebase) over the more abstract one.
- A round 1 finding that no agent corroborates in round 2 and no agent defends in round 2 should drop out, not be posted.
- Listing 30 MINOR findings on a 50-line diff is worse than 3 good MAJOR ones. Edit aggressively before posting — that pruning is the job of §7.5's self-review, since there's no user gate to catch it. With everything in one comment, length is the cost the author pays for your lack of editing.
- If round 3 ends without convergence on a critical point, **say so** in the summary. Forced consensus is worse than honest disagreement.

## Things this skill must NOT do

- **Never post more than one comment per MR per pass.** No line-anchored discussions (`.../discussions`), no per-finding threads, no per-severity notes, no "part 1 / part 2" split for length. Every finding goes in the body of a single `glab mr note`, citing `file:line` inline. This is the hard rule of this skill.
- **Always post the completed review directly** — the single summary comment AND the verdict action — without asking the user to confirm. The user has standing authorization; a "want me to post?" prompt is friction they've explicitly opted out of. Report a one-line recap in chat only *after* posting.
- **Always leave the MR in exactly one clear status** — ✅ Approved or 🔴 Changes requested — via the verdict action plus matching status label (§8). Never finish a review without setting it, and always clear the opposite label so the MR never shows both `approved` and `needs-changes`.
- Do not post round-by-round drafts to the MR — post only the final consolidated review, once the panel has converged (§7.5 self-review done).
- Do not run more than 3 rounds.
- Do not parallelize across MRs when multiple were resolved — review them sequentially, posting each MR's review directly as it completes.
- Do not skip pre-flight (P1, P2). Running agents without a local checkout to verify against produces low-quality reviews and is the most common cause of unverified-claim findings.
- Do not invent line numbers when citing locations — verify each against the diff or the checkout. If a finding genuinely can't be located, state it without a citation rather than guessing.
- Do not reach for line-anchored discussions as a "nicer" alternative to the one comment. Beyond the one-comment rule, `glab` can't post them reliably: `position` is a nested object, and `--field "position[...]"` returns **201 with `position: null`** — the comment silently lands unanchored, with no error. Anchoring correctly needs a hand-built JSON body plus a read-back check on every single comment. That machinery is exactly what the consolidated comment exists to avoid.
- Do not approve an MR with a surviving BLOCKER.
- Do not skip the language specialist just because no local agent matches — spawn `general-purpose` with the fallback prompt.
- Do not modify the MR's source branch or push commits — review only.
- Do not `git stash` or otherwise discard uncommitted local changes in the checkout to get it onto the head SHA. Stop and ask the user.
- Do not use `$(...)` command substitution inside the `'EOF'` HEREDOC body — it expands at the wrong time and mangles the posted message.

## Language specialist fallback prompt

When no specialized agent exists for the dominant language in the diff, spawn a `general-purpose` agent with this leading instruction:

> Act as a Senior/Principal `<LANGUAGE>` engineer with 10+ years of production experience. You are reviewing a code change for a colleague. Focus on:
> - Idiomatic `<LANGUAGE>` (does this read like a native of the language wrote it?)
> - Common pitfalls and footguns specific to `<LANGUAGE>` and its standard library
> - Misuse of popular `<LANGUAGE>` frameworks/libraries visible in the diff
> - Concurrency, memory, and resource handling concerns
> - Test design and coverage gaps
>
> Do NOT comment on cross-cutting concerns (security, production readiness, simplicity) — other specialists own those. Stay in your lane.

Then append the standard reviewer brief from step 3.
