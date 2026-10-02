---
name: backend-panel
description: >-
  Convene a panel of backend specialists (Micronaut/Java, security, production-readiness, simplicity, clean code) on local, pre-MR backend work in ecfx-backend or any Micronaut service — they review independently against the real branch, disagreements are cross-examined, and you get one consolidated review-readiness report plus the must-fail evidence an MR reviewer will ask for. Use before opening an MR ("backend panel", "is this ready for review", "get the backend experts on this branch", "pre-MR review"), or to design an approach before code exists. Once the work is an open GitLab MR, use `/mr-review-multi-agent` instead — it routes to these same experts and posts one consolidated comment and a verdict to the MR.
---


# Backend Expert Panel

The backend counterpart of `/frontend-panel`. Runs the same five lanes `/mr-review-multi-agent`
uses **before** the MR exists, so the first posted review is not the first time a specialist sees
the branch. In one recent feature the MR review ran seven rounds; every blocker after round one
was something a pre-MR panel with the evidence rules below would have caught.

**Design priority: correctness of findings > convergence > wall-clock.** One round is normal.

## When to use

- "Backend panel", "pre-MR review", "is this branch ready for review", "have the backend experts look"
- Any change touching a controller's `@Secured` list, a credential type, encryption, RabbitMQ
  topology, config properties, a scheduled job, or a CLI/operational command
- Before an MR on a cross-cutting change, or before the *second* push to an MR that already has a
  review round (run it on the delta)

## When NOT to use

- The work is an open MR: `/mr-review-multi-agent` posts to the MR; this skill posts nothing.
- One-domain question ("is this `@Secured` list right?"): invoke that expert or the
  `secured-endpoint-contract` skill directly.
- Trivial changes.

## Input

A target (branch, diff range, files, or a described change) and an optional mode:
`review` (default), `design`, or `focused` (user names the lanes). Resolve ambiguity by
searching before asking.

## Process

### 1. Build the shared brief

Write `/tmp/backend-panel-<slug>/brief.md` containing:

1. **Task** and mode, one paragraph. No editorialising.
2. **Project** — repo, absolute path, branch, HEAD SHA, and the merge-base with `origin/master`:
   ```bash
   ROOT=$(git rev-parse --show-toplevel); git -C "$ROOT" fetch -q origin
   git -C "$ROOT" rev-parse --short HEAD; git -C "$ROOT" merge-base HEAD origin/master
   git -C "$ROOT" merge-tree --write-tree --name-only origin/master HEAD | tail -n +2   # conflicts NOW, not at merge time
   ```
3. **Changed files** — `git diff --name-status <merge-base>..HEAD`, plus the modules they belong to.
4. **Project rule sources** (paths, not contents): `<ROOT>/AGENTS.md`, `<ROOT>/projects/<module>/AGENTS.md`,
   `.claude/skills/` (notably `secured-endpoint-contract`, `deployment-parity-review`,
   `receipt-processor-guardrails`, `court-portal-processor-checklist`, `api-contract-fixtures`,
   `java-clean-code-commandments`).
5. **Evidence already gathered by the author** — the exact `--tests` commands run, reconciled counts
   (tests reported vs `where:` rows), and every must-fail check performed (what was reverted, which
   test went red). If this section is empty, say so in the brief; the panel will treat untested
   claims as untested.
6. **Contracts crossing a boundary** — for every DTO, wire field, env var, or config key the change
   adds or renames: the exact serialised name (naming strategy applied), which side consumes it, and
   where the real payload was captured (see `api-contract-fixtures`).

### 2. Select the panel

| Signal in the diff | Include |
|---|---|
| Any Java/Groovy change | `backend:java-micronaut-dev` |
| `@Secured`, roles, credentials, encryption, secrets, logging of user data | `shared:security-compliance-reviewer` |
| Config/env/yml, RabbitMQ, scheduled jobs, CLI or operational tooling, logging levels | `shared:prod-readiness` |
| New abstraction, new module, new tool, >300 lines | `shared:invent-simplify-reviewer` |
| Anything | `backend:java-clean-code-purist` (reads `java-clean-code-commandments`) |

Minimum useful panel is 3. State the selection before spawning.

### 3. Round 1 — independent review (parallel)

Spawn all selected experts **in one message**. Each gets:

```
You are serving on a backend expert panel reviewing work in <project>.

Read /tmp/backend-panel-<slug>/brief.md first, then
`~/.config/opencode/modules/backend-project-context.md` and follow it: it governs how you orient, verify and report.

Review through the lens of <your specialty> only.

Ground every claim: cite path:line for everything you assert about the code; open the
sibling you compare against; check the installed library version before asserting
behaviour. Never present an unverified claim as verified — mark it QUESTION. Never
describe a test as "goes red under mutation" unless you ran the mutation or the author's
evidence section shows it.

Report with the output contract from the shared module, then a one-line verdict.
```

### 4. Synthesize

Build the finding table (ID, finding, raised by, severity, where, status: corroborated /
unique / conflicting). Tie-breakers, in order: a project rule or gate settles it; a security or
data-loss finding beats convenience; the narrower specialist wins on their home turf; otherwise
escalate to the user with both positions.

### 5. Round 2 — only if it changes the answer

Re-spawn only the experts in a dispute, with the opposing position quoted. Default is to skip.

### 6. Review-readiness checklist (the part MR reviewers keep re-asking for)

Before reporting, check each item yourself — do not delegate this list to the panel:

- [ ] **Every new spec executed** — an explicit `--tests` filter per spec, counts reconciled with
      `where:` rows. A green module summary is not evidence (see ecfx-backend `AGENTS.md`).
- [ ] **Every guard proven** — for each test that exists to guard a regression, the author reverted
      the fix and the test went red. List the pairs.
- [ ] **Refactor blast radius** — for each changed public signature, `grep` for every caller
      including `*Test.java` and `*Spec.groovy`, and confirm those ran. A legacy JUnit file outside
      the `--tests` filter is the classic miss.
- [ ] **Contract fixtures come from real payloads** — no test fixture carries a value the API
      would never emit (e.g. a secret field value, a camelCase key when the wire is snake_case).
- [ ] **Config/env story** — every new `${VAR}` is in each deployed profile or has a safe default;
      the MR description names the exact variable names; a rename since the last push gets a
      standalone comment. Any property gated by `@Requires` is bound in every module that needs it.
- [ ] **Alerting reachability** — a log line that is meant to be seen uses a level the module's
      appender actually forwards (some modules filter Sentry at ERROR; WARN reaches nobody).
- [ ] **Operational commands verify their preconditions** — a tool that can silently report "0"
      when a dependency is misconfigured must detect that and fail loudly.
- [ ] **Provider-neutral shared code** — no provider or portal name in shared services, messages
      or dialogs; provider-specific text lives on that provider's own type.
- [ ] **Merge topology** — `merge-tree` against `origin/master` is clean; a stacked MR targets its
      parent branch; a split is create-then-remove with an empty-diff proof.
- [ ] **Comments describe the code** — especially security comments justifying a widened role list.

### 7. Report

```markdown
## Backend panel — <target>

**Panel**: micronaut, security, prod-readiness, simplicity, clean-code · **Rounds**: 1 · **Commit**: `abc1234`

### Verdict
### Blockers
### Should fix
### Consider
### Review-readiness checklist   <- each item PASS / FAIL with the evidence or the gap
### Disagreements                <- only if unresolved
### Verified good
```

Group by theme, not by expert. Prune anything that restates a rule without a violation, any
finding the expert admitted it did not verify (verify it yourself or demote to QUESTION), and any
BLOCKER that is not actually blocking.

Close with the exact commands the author should run before pushing.
