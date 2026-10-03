---
name: frontend-panel
description: >-
  Convene a panel of frontend specialists (architecture, Vue, Vuetify, TypeScript, accessibility, UX, styling) on local, pre-MR frontend work — they review or design independently, disagreements get cross-examined, and you get one consolidated answer instead of seven opinions. Use for work in progress — "get the panel on this component", "frontend panel", "design review this screen", "is this any good before I push" — or to design an approach before code exists. Once the work is an open GitLab MR, use `/mr-review-multi-agent` instead: it routes to these same experts and posts one consolidated review comment and a verdict to the MR. For a single-domain question ("is this ARIA right?"), invoke that one expert directly.
---


# Frontend Expert Panel

Runs a structured multi-expert pass over frontend work in **ecfx-dashboard** (or
any Vue project). The experts do not talk to each other directly — Claude Code
subagents each get their own context window. This skill *is* the shared context:
it builds one brief, fans it out, reconciles the results, and returns a single
answer.

**Design priority: correctness of findings > panel convergence > wall-clock.**
Most tasks converge in one round. Round 2 exists to settle real disagreements,
not to re-derive context.

## When to use

- "Get the frontend panel on this", "frontend panel", "have the experts review this"
- A new screen or component where design, a11y, and implementation all matter
- A refactor with cross-cutting impact (state, styling, and types together)
- Before an MR on a high-visibility or complex UI change

## When NOT to use

- **Single-domain question** — invoke the one expert directly. "Is this ARIA
  correct?" is `ui-review:accessibility-expert`, not a seven-agent panel.
- **Reviewing a GitLab MR** — use `/mr-review-multi-agent`. It routes Vue / TS /
  SCSS diffs to **these same experts** and adds the MR mechanics this skill
  deliberately lacks: fetching the diff, pinning the checkout to the head SHA,
  posting one consolidated review comment, and setting approve /
  needs-changes. Reviewing an
  open MR here instead would duplicate that panel's work and post nothing.
- **Trivial changes** — a copy tweak or a one-line fix does not need a panel.
- **ecfx-admin / Python work** — use `/python-panel`.

## Input

The user gives a target and optionally a mode:

- **Target**: file path(s), a component or page name, a directory, a described
  change ("the jurisdiction preference card"), or the current working diff.
- **Mode** (infer if unstated):
  - `review` (default) — critique existing code
  - `design` — propose an approach before code exists
  - `focused` — user names the experts they want

If the target is ambiguous, resolve it by searching before asking. Only ask when
genuinely undeterminable.

## Process

### 1. Build the shared brief

This is the "common context" every expert receives. Write it to
`/tmp/frontend-panel-<slug>/brief.md`.

```bash
mkdir -p /tmp/frontend-panel-<slug>
```

Gather, in this order:

```bash
ROOT=$(git rev-parse --show-toplevel)
basename "$ROOT"                      # which project
git -C "$ROOT" rev-parse --short HEAD # pin the commit the panel reviewed
```

The brief must contain:

1. **Task** — what is being reviewed or designed, in one paragraph, plus the mode.
2. **Project** — repo name, absolute path, current SHA, branch.
3. **Target files** — absolute paths. For `design` mode, the closest existing
   analogues so experts can match established patterns.
4. **Project rule sources** — paths, not contents. Every expert reads these
   itself via the shared module:
   - `<ROOT>/AGENTS.md`
   - `<ROOT>/.claude/skills/` (ecfx-dashboard ships `vue3-guidelines`,
     `typescript-guidelines`, `web-search`)
   - `<ROOT>/eslint.config.js`, `stylelint.config.js`, `tsconfig.json`
   - `<ROOT>/docs/` (architecture notes, `code-quality-gates.md`)
5. **Installed versions** — from `package.json`, so nobody advises on the wrong
   major:
   ```bash
   jq -r '.dependencies + .devDependencies
          | to_entries[] | select(.key|test("^(vue|vuetify|typescript|pinia|vite|vitest|vue-i18n|vue-router)$"))
          | "\(.key) \(.value)"' "$ROOT/package.json"
   ```
6. **Gates that must pass** — `npm run lint`, `npm run lint:style`,
   `npm run type-check`, `npm test`.
7. **Prior context** — if this is a re-run after changes, what the panel said
   last time and what was addressed.

Keep the brief factual. Do not editorialize or pre-judge — that biases the panel
and defeats the point of independent review.

### 2. Select the panel

Do not run all seven every time. Cost scales linearly and irrelevant experts
produce noise. Choose by what the change actually touches:

| Signal in the target | Include |
|---|---|
| Any UI a user interacts with | `ui-review:accessibility-expert`, `ui-review:ux-expert` |
| `.vue` files, composables, reactivity | `dashboard:vue-expert` |
| Vuetify components, theming, `v-*` usage | `dashboard:vuetify-expert` |
| Types, generics, `any`, API contracts | `dashboard:typescript-expert` |
| SCSS, styles, tokens, layout | `dashboard:styling-expert` |
| Cross-module structure, state, data flow, routing, bundle | `dashboard:frontend-architect` |
| Security-sensitive (auth, `v-html`, tokens) | `shared:security-compliance-reviewer` |
| Pre-release / production risk | `shared:prod-readiness` |

Minimum useful panel is 3. If your selection is 1–2, tell the user a panel is
overkill and invoke those experts directly instead.

The last two rows pull in **existing repo agents** — reuse them rather than
duplicating security or production expertise.

State the selected panel and the reason before spawning. The user can veto.

**Model gate (Pi, when `agent_select_models` is available; otherwise skip).** Once the panel is selected and before the Round 1 spawn, use the stable flow ID `frontend-panel:<target>` and one role key per expert (the agent's name). Call `agent_select_models` once, with one entry per role: key, title, task type, `recommendedModel` and a one-sentence recommendation. If it is cancelled or errors, stop the flow and spawn nothing. Pass each returned model as `model` on that role's spawn, and reuse it whenever the same known role is spawned again. A role that was not selected gets an automatic model from the usual policy, without another prompt. Unless a parent flow already gated: when a parent that already gated passes you its established selection context (its flow ID and role choices), do not call `agent_select_models` again; reuse the matching inherited choices as `model` and leave newly discovered roles automatic.

### 3. Round 1 — independent review (parallel)

Spawn **all selected experts in a single message with parallel Agent calls** so
they run concurrently and cannot influence each other. Independence is what makes
corroboration meaningful.

Each expert gets this brief:

```
You are serving on a frontend expert panel reviewing work in <project>.

Read /tmp/frontend-panel-<slug>/brief.md first — it names the task, the target
files, the project's own rule sources, the installed versions, and the gates
your suggestions must pass.

Then read ~/.config/opencode/modules/ui-project-context.md (a real file in this plugin's own
`modules/`, not shared across plugins) and follow it. It governs how you
orient, verify, and report.

Review through the lens of <your specialty> only.

Ground every claim:
  - Before saying a helper/composable/util exists, grep for it and cite path:line.
  - Before saying "this matches the pattern in X", open X and confirm.
  - Before asserting library behavior, check the installed version in the brief.
  - If you did not verify something, say so explicitly. A hedged accurate
    finding beats a confident wrong one.

Stay in your lane. Other specialists cover other angles; duplicated findings
waste the reader's attention. If you see something dangerous outside your lane
(security, data loss), raise it once and label it out-of-lane.

Do not restate the project's rules as findings. "The project requires SCSS
variables" is not a finding. "Foo.vue:42 uses a literal 16px, which stylelint
will reject — use v.$padding-general" is.

Use the output contract from the shared module (SEVERITY / Where / Why it
matters / Evidence / Suggested fix), then a one-line verdict.

In design mode, produce a recommendation with trade-offs instead of findings —
but hold the same evidence standard.
```

### 4. Synthesize

Read every expert's output and build a finding table in working memory:

| ID | Finding | Raised by | Severity | Where | Status |
|---|---|---|---|---|---|
| F1 | … | a11y, ux | BLOCKER | Foo.vue:42 | corroborated |
| F2 | … | vue | MAJOR | Bar.vue:88 | unique |

Classify:
- **Corroborated** — 2+ experts independently found it. Strong signal.
- **Unique** — one expert. Usually legitimate lane specialization; carry forward.
- **Conflicting** — experts disagree on severity or recommend incompatible fixes.

**Conflicts are the point of the panel.** They are common and healthy here:

- `ui-review:ux-expert` wants a richer custom control; `ui-review:accessibility-expert` and
  `dashboard:vuetify-expert` want the accessible built-in.
- `dashboard:frontend-architect` wants an abstraction; `dashboard:vue-expert` calls it premature.
- `dashboard:styling-expert` wants a new token; the project's rules say use an existing one.

Resolve with these tie-breakers, in order:

1. **A project rule or gate settles it.** If stylelint or the i18n rule rejects
   an option, it is not an option. This is not a judgment call.
2. **Accessibility beats aesthetics.** A control a keyboard user cannot operate
   is not a design trade-off — it is a defect. UX and a11y should converge on a
   solution that is both, not compromise on one.
3. **The narrower specialist wins on their home turf** — Vuetify component
   semantics go to `dashboard:vuetify-expert`, reactivity to `dashboard:vue-expert`.
4. **Otherwise, escalate to the user** with both positions stated fairly and a
   recommendation. Do not silently pick a side.

### 5. Round 2 — only if it changes the answer

**Default is to skip.** Run R2 only when:

- Two experts assigned materially different severities to the same finding, and
  the verdict depends on which is right.
- A recommendation is genuinely incompatible across experts and tie-breakers 1–3
  did not settle it.
- An expert's finding depends on a fact nobody verified.

When you do run it, re-spawn **only the experts in the dispute**, with the
specific question and the opposing position quoted. Not a full re-review.

When you skip, note it: `Rounds: 1 (converged)`.

### 6. Report

One consolidated answer. Never dump raw per-expert transcripts.

```markdown
## Frontend panel — <target>

**Panel**: vue, vuetify, accessibility, ux, styling · **Rounds**: 1 · **Commit**: `abc1234`

### Verdict
<One paragraph: ship it / fix these first / here is the recommended approach.>

### Blockers
<Only things that must not ship. Usually zero. Each with location and fix.>

### Should fix
<MAJOR findings, grouped by theme rather than by which expert said them.>

### Consider
<MINOR — explicitly marked as optional.>

### Disagreements
<Only if unresolved. State both positions and your recommendation.>

### Verified good
<KUDOS — real ones only. Skip the section if there are none.>
```

Group by **theme, not by expert** — the reader cares about the component, not
which agent spoke. Attribute only when the source adds credibility ("both a11y
and UX independently flagged the filter control").

Close with the gates the user should run before committing.

### 7. Calibration

Before returning, prune:

- Anything that merely restates a project rule without a concrete violation.
- Duplicates that survived synthesis.
- Findings the expert admitted it did not verify — either verify them yourself or
  demote them to QUESTION.
- BLOCKERs that are not actually blocking. If you have more than two, re-check
  your calibration; most reviews have zero.

A panel that returns forty findings has failed. Ten well-chosen ones get fixed.
