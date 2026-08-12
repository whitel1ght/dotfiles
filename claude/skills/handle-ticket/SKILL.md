---
name: handle-ticket
description: Drive a Jira ticket from "handed to me" to "reviewed MR pushed" — multi-agent investigation and brainstorming, a single approach gate, a feature branch off master, multi-agent implementation, the project's own checks, a draft MR, then a multi-agent review whose findings are evaluated and fixed locally instead of posted. Use when the user says "handle ticket ECFX-15234", "handle this ticket", "take this ticket", "work this ticket end-to-end", or pastes ticket text with a number and asks you to do it.
---

# Handle Ticket

Take a ticket the user hands you and drive it to a reviewed, pushed MR.

The shape of the work:

```
read ticket → multi-agent investigate + brainstorm → [ask only if genuinely unclear]
                              ↓
                    ✋ APPROACH GATE (the one pause)
                              ↓
      branch off master → multi-agent implement → project checks
                              ↓
                      draft MR, pushed
                              ↓
        /mr-review-multi-agent  ── findings NOT posted ──┐
                              ↓                          │
      superpowers:receiving-code-review evaluates them ──┘
                              ↓
        fix what survives → checks → push → undraft
                              ↓
                           report
```

**One gate, one review cycle, one MR.** Everything after the approach gate runs
unattended. Do not invent extra checkpoints — the user chose a single pause
deliberately.

## When to invoke

- "Handle ticket ECFX-15234" / "handle this ticket" / "take ECFX-15234"
- Pasted ticket text plus a number and an instruction to do the work
- "Work this end-to-end", "drive this to an MR"

Do NOT invoke for:

- **Questions about a ticket** ("what's going on with ECFX-15234?", "is this
  real?") — that's analysis. Use `/processor-error-triage` or just investigate.
- **A reproducible ECFX bug with EMLs in `/workspace/shared/<TICKET>/`** — use
  `/fix-jira-bug`. It reproduces from the EML first, which is a stronger
  workflow when the artifacts exist. This skill is the general-purpose sibling
  for feature work, refactors, and bugs with no EML reproducer.
- **Reviewing someone else's MR** — that's `/mr-review-multi-agent` directly.

## Input

The user gives you a ticket key (`ECFX-15234`, or bare `15234` — prefix `ECFX-`
if unprefixed), usually with pasted ticket text. Both are useful: the paste is
what the user actually read, the API has the fields, comments and links the
paste drops.

Parse the ticket key from the message. If there is genuinely no number and no
pasted content, ask for one — do not guess.

## Pre-flight

### P1. Resolve the repo

Work happens in the current directory's repo unless the ticket clearly belongs
elsewhere. Resolve the project path and default branch:

```bash
glab repo view --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['path_with_namespace'])"
git symbolic-ref refs/remotes/origin/HEAD | sed 's#refs/remotes/origin/##'
```

The default branch is `master` in the ECFX repos — read it, don't assume. Every
reference to "master" below means *the resolved default branch*.

If the current directory is not a git repo, or the ticket names a component
that clearly lives in another checkout under `~/projects/`, ask which repo
before doing anything else.

### P2. Working tree must be clean

```bash
git status --porcelain
```

If dirty: **stop and ask.** Do not `git stash` uncommitted work on the user's
behalf — it may be work in progress they care about. Offer to stash, but let
them decide.

### P3. Fetch the ticket

Jira lives at `https://ecfxdev.atlassian.net`, authenticated with `JIRA_EMAIL` /
`JIRA_API_TOKEN` from the shell environment (sourced from
`~/.config/mrglass/secrets.env`).

```bash
JIRA_BASE="https://ecfxdev.atlassian.net"
curl -s -w '\n%{http_code}' -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Accept: application/json" \
  "$JIRA_BASE/rest/api/3/issue/ECFX-15234?fields=summary,description,status,issuetype,priority,labels,components,assignee,reporter,comment,issuelinks,parent"
```

Walk the ADF `description` into plain text (`type: "text"` nodes; break on
`paragraph`). Extract: summary, type, status, priority, labels, components,
description, recent comments, linked issues, parent epic.

**If the API returns 401/403/404** — the token expires periodically, and it was
returning 401 when this skill was written — say so once, plainly, and continue
from the user's pasted text. Do not retry-loop, do not hunt for other
credentials, and do not stop: the paste is usually sufficient. Only stop if
there is no paste *and* no API access.

Note the issue type. A **Story/Task** is feature work — the flow below fits. A
**Bug** with EMLs in `/workspace/shared/<TICKET>/` should go to
`/fix-jira-bug` instead; say so and ask before continuing. An **Epic** is not a
unit of work — ask which child ticket is meant.

## Phase 1 — Investigate and brainstorm (multi-agent, parallel)

The goal of this phase is to arrive at the approach gate with a proposal that
is *grounded in this codebase*, not a plausible-sounding plan.

Do a quick orientation read yourself first — enough to know which files the
ticket touches and hand agents real paths. A `Grep`/`Glob` sweep and two or
three `Read`s, not a full survey.

Then spawn **3–4 agents in parallel — one message, multiple `Agent` calls.**
Sequential spawning wastes wall-clock for no benefit.

**Always include:**

| Agent | Job |
|---|---|
| `Explore` | Map every place the ticket's behaviour is implemented today. Find the *cousins* — sibling providers, other tenants, parallel implementations. Return `file:line` anchors, not prose. |
| `invent-simplify-reviewer` | Challenge the framing. Does the ticket describe the real problem? Is there a smaller change that solves it? Is anything here already solved elsewhere in the repo? |

**Add by change type:**

| Change type | Add |
|---|---|
| Java / Micronaut backend | `java-micronaut-dev` |
| Vue / TS / Vuetify frontend | `frontend-architect`, or `/frontend-panel` if it spans several frontend concerns |
| Python / Flask / SQLAlchemy | `python-architect`, or `/python-panel` if it spans several |
| Schema / migration | `java-micronaut-dev` + read `/flyway-migration-preflight` |
| Receipt / notice processing | `java-micronaut-dev` + read `/receipt-processor-guardrails` |
| Auth, tenancy, crypto, PII | `security-compliance-reviewer` |
| Infra / deployment | `aws-cloud-architect`, `prod-readiness` |

Each agent brief must carry: the ticket summary and description, the file paths
you found in orientation, the absolute repo path, and — critically — **"read
the actual source before asserting anything; a claim you did not verify against
a file is a guess."** Cap each at ~400 words, focused and actionable.

**Synthesize the responses yourself.** Do not delegate synthesis to another
agent, and do not paste agent output into the proposal verbatim. Where agents
disagree, prefer the argument citing a concrete `file:line` over the abstract
one. Where they disagree on something that actually changes the design, say so
at the gate rather than silently picking a side.

### Ask questions only if necessary

After investigation, not before. The bar: **would two reasonable readings of
the ticket produce materially different work?** If yes, ask. If you can pick a
sensible default and state it, do that instead.

Worth asking about: an ambiguous acceptance criterion, an unstated scope
boundary the ticket implies but doesn't fix, a product decision that isn't
yours (what should the user see when X fails?), a choice between two designs
with real trade-offs.

Not worth asking about: anything the code answers, anything with an obvious
convention in the repo, naming, or "should I write tests?" (yes).

Use `AskUserQuestion`, batch everything into one call, and offer concrete
options with a recommendation — not open-ended prompts.

## Phase 2 — ✋ Approach gate

Present the proposal and **wait**. This is the only pause in the skill; the
whole point is that a wrong turn here is far cheaper to correct than after
implementation.

```markdown
## ECFX-NNNNN — <summary>

**Understanding:** <what the ticket actually asks for, in your words>

**What exists today:** <current behaviour, with file:line anchors>

**Proposed change:**
- `path/to/File.java:120` — <what changes and why>
- `path/to/Other.vue:45` — <...>

**Why this shape:** <tie to existing convention or sibling code — cite it>

**Alternatives considered:** <what you rejected and why — one line each>

**Tests:** <what you'll add, and what each one actually guards>

**Risk:** <what could break; what the tests catch; what they don't>

**Out of scope:** <adjacent problems you found and are deliberately not fixing>

**Panel notes:** <any unresolved disagreement between the agents>
```

Then ask for a go/no-go. If the user redirects, revise and re-present — do not
proceed on a partially-approved approach.

## Phase 3 — Branch

Off the **resolved default branch**, never off whatever is currently checked
out:

```bash
git fetch origin master
git checkout master
git pull --ff-only origin master
git checkout -b dmitry/ECFX-15234_short-slug
```

Branch naming follows the repo's live convention: `dmitry/ECFX-NNNNN_slug`.
Check `git branch -r --sort=-committerdate | head` if unsure — the ECFX repos
use both `dmitry/...` and `claude/...`; prefer `dmitry/` for work the user is
driving.

If `pull --ff-only` fails, master has diverged locally. Stop and ask — do not
force anything.

## Phase 4 — Implement (multi-agent)

Split the approved approach into **independent** units of work. Independence is
the whole test: two agents editing the same file will clobber each other.

- **Genuinely independent units** (separate modules, separate layers with a
  settled interface between them, implementation vs. test-fixtures) → spawn
  agents in parallel, one per unit, each owning a disjoint file set. State the
  file ownership explicitly in each brief.
- **Anything coupled** — and most tickets are — → implement it yourself. A
  single coherent change is not improved by being split across agents that
  cannot see each other's edits.

Do not spawn implementation agents for a two-file change. The multi-agent
requirement is about investigation and review depth; implementation
parallelism is only worth it when the work genuinely decomposes.

Whoever writes the code:

- **Tests land in the same commit as the change.** A test that passes with the
  change reverted is not a test — verify that it fails first.
- Match the surrounding code's style, naming and comment density.
- Touch nothing outside the approved scope. If something blocks compilation,
  fix it surgically and call it out as incidental in the MR description.
- Consult the relevant repo skill where one exists —
  `/java-clean-code-commandments`, `/receipt-processor-guardrails`,
  `/flyway-migration-preflight`, `/secured-endpoint-contract`,
  `/transaction-boundary-validator`.

## Phase 5 — Project checks

Run **the project's own checks**, discovered rather than assumed. Look at
`CLAUDE.md`, `package.json` scripts, the Gradle tasks, the Makefile — in that
order — and run what the project actually defines.

Known defaults:

| Repo type | Checks |
|---|---|
| `ecfx-backend` (Gradle) | `GRADLE_OPTS="-Xms2048m -Xmx2048m" ./gradlew --no-daemon :<module>:test --console=plain` and `:<module>:checkstyleMain` |
| `ecfx-dashboard` (npm) | `npm run lint`, `npm run lint:style`, `npm test` |

Scope tests to the touched modules — a full `./gradlew test` is rarely worth
the wall-clock. Run the broader suite only if the change is cross-cutting.

**Everything must pass before the MR exists.** If a check fails on something
you did not touch, verify it fails on master too; if it does, note it as
pre-existing and continue. If it doesn't, you broke it — fix it.

## Phase 6 — Draft MR

Commit, push, open as **draft**. Draft matters: the review cycle in Phase 7 is
still going to push commits, and human reviewers should not be pinged into a
moving target.

```bash
git add <specific files>          # never `git add -A`
git commit -m "$(cat <<'EOF'
ECFX-15234: <short imperative subject>

<what was wrong / what was missing, and who it affects>

<what this change does and why it is the right shape>

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: <session url>
EOF
)"
git push -u origin dmitry/ECFX-15234_short-slug
```

Use `/commit-msg` if you want the message generated, and `/mr-description` for
the body. Then:

```bash
glab mr create --draft \
  --title "Draft: ECFX-15234: <subject>" \
  --description "$(cat /tmp/handle-ticket-ECFX-15234/mr-body.md)" \
  --target-branch master \
  --yes
```

Capture the MR IID and URL from the output — Phase 7 needs both.

## Phase 7 — Multi-agent review, findings **not** posted

Invoke `/mr-review-multi-agent` against the MR you just opened.

> ⚠️ **The review must not be posted to the MR.** That skill's default is to
> auto-post one consolidated comment plus a verdict action and a status label.
> Here it is being used as an *internal* quality gate on your own work — a
> review of your own MR, posted to it, is noise for the humans who review it
> next.

State the suppression explicitly and unmistakably when you invoke it:

> Run the full panel and cross-examination as normal, and produce the
> consolidated findings **as your reply to me**. Do NOT post anything to the
> MR: no `glab mr note`, no `glab api ... /discussions`, no approve, no revoke,
> no label changes, no reviewer assignment. Skip §8 entirely. The MR is mine
> and I am reviewing it before humans see it — the findings come back to me and
> I fix them locally.

Then **verify it obeyed**, because the suppression cuts against that skill's
own hard rule:

```bash
glab mr view <iid> --comments | head -40
```

If a review comment did land on the MR, delete it and say so in the final
report — don't leave it sitting there.

## Phase 8 — Evaluate the findings

Load `superpowers:receiving-code-review` and apply it to the returned findings.
Its rules govern here: verify before implementing, no performative agreement,
push back with technical reasoning where the finding is wrong.

For **each** finding, do the work of checking it before touching code:

1. **Read the actual source** the finding cites. Reviewers assert; files decide.
2. **Is it correct for *this* codebase?** Check conventions, the target
   language/framework version, and whether the concern is already handled
   elsewhere in the call path.
3. **Is it in scope?** A real problem that the ticket didn't ask about is a
   follow-up, not a reason to grow this MR.
4. **YAGNI check.** If a finding proposes "doing it properly" for something
   nothing calls, grep for callers before building it.

Assign each finding one disposition:

| Disposition | Meaning |
|---|---|
| **FIXED** | Verified real and in scope — fix it. |
| **REJECTED** | Verified wrong for this codebase — record the technical reason. |
| **DEFERRED** | Real but out of scope — note it for a follow-up ticket. |

Fix in order: blockers and anything that breaks or is unsafe first, then simple
corrections, then anything structural. **One at a time, re-running the relevant
test after each** — a batch of fixes that lands together hides which one broke
something.

If a finding is unclear enough that you can't tell what it's asking for, don't
guess at it and don't half-implement — ask the user about that one item while
proceeding with the rest.

## Phase 9 — Re-check, push, undraft

Re-run the Phase 5 checks in full. Then:

```bash
git add <files>
git commit -m "ECFX-15234: address review findings

<one line per fix — what changed and which finding it answers>"
git push
glab mr update <iid> --ready
```

Update the MR description with anything the review changed materially — a
reviewer reading the description should not be surprised by the diff.

Optionally transition the Jira ticket to *In MR* / *In Review* and attach the
MR link, if the API credentials worked in P3:

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE/rest/api/3/issue/ECFX-15234/transitions?includeUnavailableTransitions=true"
```

Look the transition ID up — never hardcode it. If the credentials are dead,
say so and let the user move the ticket.

## Phase 10 — Report

One compact summary in chat. No files, no artifacts.

```markdown
**ECFX-15234 — <summary>** → <MR URL> (ready for review)

**Changed:** <2–3 lines, plain language>
**Files:** <n> files, +<a>/−<b>
**Checks:** <what ran, and the result>

**Review:** <n> findings — <x> fixed, <y> rejected, <z> deferred
- REJECTED `F3` — <finding> → <why it's wrong here, citing file:line>
- DEFERRED `F4` — <finding> → <why it's out of scope>

**Follow-ups worth a ticket:** <or "none">
**Not verified:** <anything you couldn't check locally>
```

Report what actually happened. If checks were skipped, say which. If a phase
was degraded — no Jira access, review posted something it shouldn't have — say
that too. A clean-looking report that hides a skipped step is worse than no
report.

## Anti-patterns

- **Reviewing your own work with yourself.** Phases 1 and 7 need *other*
  agents. Reading your own diff again is not review.
- **Letting `/mr-review-multi-agent` post.** Its default is to post; you are
  overriding that. Verify it obeyed rather than assuming.
- **Implementing every finding.** Blind implementation is the failure mode
  `superpowers:receiving-code-review` exists to prevent. A reviewer that hasn't
  read the surrounding code can be confidently wrong.
- **Branching off the current branch.** Always off the resolved default branch,
  freshly pulled.
- **Adding gates.** One pause, at the approach. Asking "shall I proceed?" after
  every phase defeats the point of the skill.
- **Spawning implementation agents on coupled work.** Agents that cannot see
  each other's edits will clobber a shared file. Split only what genuinely
  decomposes.
- **`git add -A`.** Stage the files you meant to change.
- **Scope creep on the way past.** Adjacent problems become follow-up tickets,
  not extra commits.

## Companion skills

- `/fix-jira-bug` — the reproduction-first sibling for ECFX bugs with EMLs.
- `/mr-review-multi-agent` — Phase 7 (invoked with posting suppressed).
- `superpowers:receiving-code-review` — Phase 8.
- `/frontend-panel`, `/python-panel` — richer specialist panels for Phase 1.
- `/commit-msg`, `/mr-description` — Phase 6.
- `/qa-comment` — after the MR is ready, for the QA handoff.
