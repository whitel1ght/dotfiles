---
name: python-panel
description: >-
  Convene a panel of Python/Flask specialists (architecture, Flask, Jinja UI, SQLAlchemy, pytest, plus accessibility and UX for rendered pages) on local, pre-MR Python work — they review or design independently, disagreements get cross-examined, and you get one consolidated answer. Use for work in progress — "python panel", "get the python experts on this view", "is this query right before I push" — or when a change spans models, views, templates, and tests at once. Once the work is an open GitLab MR, use `/mr-review-multi-agent` instead: it routes to these same experts and posts one consolidated review comment and a verdict to the MR. For a single-domain question, invoke that one expert directly.
---


# Python Expert Panel

Runs a structured multi-expert pass over Python work in **ecfx-admin** (or any
Flask/SQLAlchemy project). Subagents cannot talk to each other — each has its own
context window. This skill *is* the shared context: one brief, fanned out,
reconciled into a single answer.

**Design priority: correctness of findings > panel convergence > wall-clock.**

## When to use

- "Python panel", "get the python experts on this", "review this Flask view"
- A change spanning models + views + templates + tests
- Query performance or loader-strategy problems
- A new admin view or a significant template change
- Before an MR on complex or data-sensitive admin work

## When NOT to use

- **Single-domain question** — invoke the expert directly. "Why is this query
  slow?" is `admin:sqlalchemy-expert`, not a six-agent panel.
- **Reviewing a GitLab MR** — use `/mr-review-multi-agent`. It routes Python /
  Jinja diffs to **these same experts** and adds the MR mechanics this skill
  deliberately lacks: fetching the diff, pinning the checkout to the head SHA,
  posting one consolidated review comment, and setting approve / needs-changes.
- **ecfx-dashboard / Vue work** — use `/frontend-panel`.
- **Trivial changes** — a one-line fix does not need a panel.

## Input

- **Target**: file path(s), a view/model/template name, a directory, a described
  change, or the current working diff.
- **Mode** (infer if unstated): `review` (default), `design`, or `focused`.

Resolve ambiguous targets by searching before asking.

## Process

### 1. Build the shared brief

Write to `/tmp/python-panel-<slug>/brief.md`.

```bash
ROOT=$(git rev-parse --show-toplevel)
basename "$ROOT"; git -C "$ROOT" rev-parse --short HEAD
```

The brief contains:

1. **Task** — what is under review or design, one paragraph, plus the mode.
2. **Project** — repo name, absolute path, SHA, branch.
3. **Target files** — absolute paths; for `design` mode, the closest analogues.
4. **Project rule sources** — paths only; each expert reads them itself:
   - `<ROOT>/AGENTS.md`
   - `<ROOT>/tests/TESTING.md` — canonical testing authority
   - `<ROOT>/ruff.toml`, `.djlintrc`, `pyrightconfig.json`
   - `<ROOT>/.claude/settings.json` and `.claude/hooks/` — the **active blocking
     hooks**
   - `<ROOT>/docs/`
5. **Installed versions** — advice for SQLAlchemy 1.x or Flask 1.x is actively
   harmful here:
   ```bash
   grep -iE '^(flask|sqlalchemy|wtforms|jinja2|pytest|Flask-Admin|Flask-SQLAlchemy)' \
     "$ROOT/requirements.txt" "$ROOT/requirements-test.txt" 2>/dev/null | sort -u
   ```
6. **Gates that must pass** — `ruff check .`, `djlint ecfx_admin/templates/`,
   `python -m pytest tests/unit/`. Note explicitly that this project's Claude
   Code hooks **block `git commit`** when ruff or unit tests fail, so a
   suggestion that breaks either cannot be committed at all.
7. **Multi-tenancy warning** — Firm is the tenant; a missing `firm_id` filter is
   a cross-tenant data-leak class bug. Flag it in the brief so every expert has
   it front of mind.
8. **Prior context** — for re-runs, what the panel said before and what changed.

Keep it factual. Do not pre-judge.

### 2. Select the panel

Do not run everyone every time. Choose by what the change touches:

| Signal in the target | Include |
|---|---|
| Models, queries, relationships, migrations | `admin:sqlalchemy-expert` |
| Views, routes, forms, auth, request handling | `admin:flask-expert` |
| Jinja2 templates, server-rendered markup | `admin:jinja-ui-expert` |
| Any change that should have tests | `admin:pytest-expert` |
| Module boundaries, cross-cutting structure, config | `admin:python-architect` |
| **Rendered UI a human uses** | `ui-review:accessibility-expert`, `ui-review:ux-expert` |
| Auth, sessions, secrets, tenant isolation, PII | `shared:security-compliance-reviewer` |
| Deploy/production risk | `shared:prod-readiness` |

`ui-review:accessibility-expert` and `ui-review:ux-expert` are shared with `/frontend-panel` —
ecfx-admin renders real UI that real people use, and its templates are the least
guarded surface in either project (excluded from ruff; only djlint formatting
applies; 1 of 49 templates uses ARIA). Include them whenever a template changes.

The last two rows reuse **existing repo agents** rather than duplicating security
and production expertise.

Minimum useful panel is 3. Below that, invoke experts directly. State the panel
and the reason before spawning.

**Model gate (Pi, when `agent_select_models` is available; otherwise skip).** Once the panel is selected and before the Round 1 spawn, use the stable flow ID `python-panel:<target>` and one role key per expert (the agent's name). Call `agent_select_models` once, with one entry per role: key, title, task type, `recommendedModel` and a one-sentence recommendation. If it is cancelled or errors, stop the flow and spawn nothing. Pass each returned model as `model` on that role's spawn, and reuse it whenever the same known role is spawned again. A role that was not selected gets an automatic model from the usual policy, without another prompt. Unless a parent flow already gated: when a parent that already gated passes you its established selection context (its flow ID and role choices), do not call `agent_select_models` again; reuse the matching inherited choices as `model` and leave newly discovered roles automatic.

### 3. Round 1 — independent review (parallel)

Spawn **all selected experts in one message with parallel Agent calls**.
Independence is what makes corroboration meaningful.

```
You are serving on a Python expert panel reviewing work in <project>.

Read /tmp/python-panel-<slug>/brief.md first — it names the task, target files,
the project's own rule sources, installed versions, and the gates your
suggestions must pass. Note that this project's Claude Code hooks BLOCK
`git commit` on ruff or pytest failure — a suggestion that trips either is not
merely untidy, it is uncommittable.

Then read ~/.config/opencode/modules/ui-project-context.md (a real file in this plugin's own
`modules/`, not shared across plugins) and follow it. It governs how you
orient, verify, and report.

Review through the lens of <your specialty> only.

Ground every claim:
  - Before saying a helper/model/fixture exists, grep for it and cite path:line.
  - Before saying "this matches the pattern in X", open X and confirm.
  - Before asserting library behavior, check the installed version in the brief.
    SQLAlchemy 2.0 and Flask 3.x differ materially from their predecessors.
  - If you did not verify something, say so. A hedged accurate finding beats a
    confident wrong one.

Pay attention to multi-tenancy: this app is multi-tenant on Firm. A query or
view missing its tenant filter is a data-leak bug, not a style issue.

Stay in your lane. If you see something dangerous outside it, raise it once and
label it out-of-lane.

Do not restate the project's rules as findings. "The project uses ruff" is not a
finding. "views/invoice.py:88 shadows a builtin, which ruff's B rules reject"
is.

Use the output contract from the shared module (SEVERITY / Where / Why it
matters / Evidence / Suggested fix), then a one-line verdict.

In design mode, produce a recommendation with trade-offs instead of findings —
same evidence standard.
```

### 4. Synthesize

Build a finding table in working memory:

| ID | Finding | Raised by | Severity | Where | Status |
|---|---|---|---|---|---|

Classify **corroborated** / **unique** / **conflicting**.

Common conflicts in this panel:

- `admin:sqlalchemy-expert` wants eager loading for performance; `admin:python-architect`
  objects that it couples the query to one view's needs.
- `admin:flask-expert` wants logic in the view for clarity; `admin:python-architect` wants it
  extracted to a service module.
- `admin:pytest-expert` wants a test that requires refactoring for a seam;
  `admin:python-architect` says the seam is the right design anyway.
- `ui-review:ux-expert` wants richer interaction; `admin:jinja-ui-expert` notes it needs client
  JS the app deliberately avoids.

Tie-breakers, in order:

1. **A gate settles it.** Ruff, djlint, or a failing unit test is not negotiable —
   and here the hooks make it literally uncommittable.
2. **Correctness and tenant isolation beat everything.** A missing `firm_id`
   filter or an N+1 that will time out in production is not a trade-off.
3. **The narrower specialist wins on home turf** — loader strategy to
   `admin:sqlalchemy-expert`, request lifecycle to `admin:flask-expert`, template semantics
   to `admin:jinja-ui-expert`.
4. **Otherwise escalate to the user** with both positions and a recommendation.

### 5. Round 2 — only if it changes the answer

**Default is to skip.** Run only for genuine severity disputes that change the
verdict, incompatible recommendations unresolved by tie-breakers 1–3, or a
finding resting on an unverified fact. Re-spawn only the disputing experts with
the specific question and the opposing position quoted.

When skipped, note `Rounds: 1 (converged)`.

### 6. Report

```markdown
## Python panel — <target>

**Panel**: flask, sqlalchemy, pytest, a11y · **Rounds**: 1 · **Commit**: `abc1234`

### Verdict
<One paragraph.>

### Blockers
<Must not ship. Usually zero. Tenant-isolation and data-loss issues land here.>

### Should fix
<MAJOR, grouped by theme.>

### Consider
<MINOR, explicitly optional.>

### Disagreements
<Only if unresolved. Both positions plus a recommendation.>

### Verified good
<Real KUDOS only; omit the section if none.>
```

Group by **theme, not by expert**. Attribute only when it adds credibility.

Close with the exact gates to run before committing:

```bash
ruff check . && python -m pytest tests/unit/ -q
```

### 7. Calibration

Prune before returning:

- Findings that restate a project rule without a concrete violation.
- Duplicates that survived synthesis.
- Unverified claims — verify them or demote to QUESTION.
- BLOCKERs that are not blocking. More than two should make you re-check
  calibration.

A panel that returns forty findings has failed. Ten well-chosen ones get fixed.
