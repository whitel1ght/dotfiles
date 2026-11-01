---
name: research-jira-bug
description: >-
  Research every inbox item referenced by a Jira bug before anyone writes code — pull each notice's status, attempts, exception and stack trace off the admin site, download the emails, drop duplicate copies of the same email, cluster the failures into distinct root causes, and write a <TICKET>/<TICKET>.md dossier with the EMLs beside it. Answers "is this one bug or five?" and produces the reproduction set the fix skill needs. Use when the user asks to research / investigate / triage a ticket, asks what's going on with ECFX-NNNN, asks whether a ticket is one fix or several, or wants a ticket prepared before running `fix-jira-bug`.
---


# Research Jira Bug

The investigation pass that belongs in front of `fix-jira-bug`. That skill assumes you already
know what you are fixing and that the EMLs are sitting in the shared folder. This one earns both.

A ticket that quotes nine inbox items usually is not nine bugs. It is often the same email
delivered twice, one retry loop counted as eight failures, and two genuinely different root causes
that want two different MRs. Deciding that by hand is slow and easy to get wrong — and getting it
wrong means a fix that closes a third of the ticket.

## When to invoke

- "Research ECFX-16173" · "investigate this ticket" · "what's actually going on with ECFX-NNNN"
- "Is this one bug or several?" · "how many distinct issues are on this ticket?"
- "Get ECFX-NNNN ready to fix" — then chain into `fix-jira-bug`.
- A Processor Error ticket that quotes several inboxIds and you need the shape before triaging.

Do **not** invoke when:
- You already know the single failure and just want it fixed → `fix-jira-bug` directly.
- You have one inbox id and want its trace → `inbox-lookup` is lighter.
- The question is "is this ticket real or noise?" for a single auto-filed error →
  `processor-error-triage` answers that without downloading anything.

## Allowed tools

`Bash, Read, Write, Edit, Grep, Glob, Skill, AskUserQuestion, TaskCreate, TaskUpdate`

## How the work splits

`research_ticket.py` does everything that has a right answer: fetching, scraping ids, downloading,
deduplicating emails, normalizing exception signatures, clustering. It writes a **draft** report
with `_(pending classification …)_` in every slot that needs judgement.

You do the judgement: name each cluster, match it against the known-failure taxonomy, decide
whether the clusters are really one fix or several, and write the verdict. **The report is not
finished until no `_(pending classification` markers remain.**

Do not re-derive the script's output by hand, and do not let it make the call about scope.

---

## Step 1 — Run the researcher

```bash
python3 ${CLAUDE_SKILL_DIR}/research_ticket.py ECFX-16173
```

Output goes to `/workspace/shared/<TICKET>/` when that directory exists (exactly where
`fix-jira-bug` looks), otherwise `./<TICKET>/`. Override with `--out`.

```
<TICKET>/
├── <TICKET>.md              the report — you finish this
├── emls/                    one .eml per inbox item, plus any .eml attached to the ticket
└── raw/
    ├── research.json        everything, machine-readable
    ├── inbox_lookup.json    untouched inbox-lookup output
    └── attachments/         every attachment downloaded off the ticket
```

| Flag | Use it when |
| --- | --- |
| `--ids inbox_a inbox_b` | The ticket names items in prose the scraper missed, or you have ids from Loki |
| `--all-jobs` | You need to see whether the failure mode *changed* across attempts |
| `--max-job-pages N` | Default 3 attempt pages per item; raise for a long retry history |
| `--skip-lookup` | Re-run the analysis off cached `raw/inbox_lookup.json` without hitting the admin site |
| `--no-attachments` | The ticket has large irrelevant attachments |
| `--out DIR` | Writing somewhere other than the shared folder |
| `--app-package` | Non-`com.ecfx` codebase; sets which stack frames count as "ours" |

The first run may pause for an admin login — `inbox-lookup` owns that, and one login covers the
whole batch. Credentials and setup live in that skill's SKILL.md.

## Step 2 — Read `raw/research.json`, not just the draft

The draft markdown is a summary. The JSON has the full stack traces, every attempt's exception,
the per-item histogram, and `inboxIdSources` (where each id was found). Read it before classifying.

Pay attention to:

- **`unresolvedIds`** — referenced on the ticket but not fetchable. A typo, a lower-environment id,
  or a purged item. Say which in the report; do not silently drop them.
- **`exceptionHistogram`** per item — one exception repeated 40× is a retry loop, which is *one*
  observation, not 40. A histogram with two different exceptions means the failure mode changed
  mid-life and the newest is not necessarily the interesting one.
- **`distinctMessages`** per issue — the clusterer folds a trailing `: <value>` away, so
  `Court Location: Fulton` and `Court Location: Cobb` land together. Check the list. If those
  values imply genuinely different work, split the cluster yourself and say why.
- **`uniqueEmails[].duplicateCount` and `.resend`** — `resend: true` means the same content arrived
  with a fresh `Message-ID`. That is one email to reproduce, not two.

## Step 3 — Verify the clustering rather than trusting it

The script groups on exception class + message template + first stack frame in our own code. It is
deliberately conservative and it can be wrong in both directions:

- **Over-merged**: one generic exception (e.g. `ManualProcessNoticeException`) thrown from one
  place for several unrelated reasons. Read `distinctMessages`; split when the reasons differ.
- **Under-merged**: the same defect surfacing at two call sites, or a refactor that moved a line
  number. Read the two stack heads. If one cause fixes both, merge and say so.

When you split or merge, renumber the issues in the report and keep the mapping obvious. The inbox
ids are the source of truth for what belongs where.

## Step 4 — Confirm each issue is reproducible

For each issue, at least one EML must exist in `emls/`. An issue whose items produced no email
(e.g. the notice was purged, or the failure happened before the message was stored) cannot be
reproduced by `fix-jira-bug`, whose whole strategy is EML-driven. Mark those explicitly:

> **Not reproducible from artifacts** — no stored message. Needs a log-side repro or a synthetic EML.

Do not hand a non-reproducible issue to `fix-jira-bug` and let it discover this in Phase 2.

## Step 5 — Classify each issue

Match every cluster against the taxonomy in the `processor-error-triage` skill — read it, don't
recall it. That skill's table maps a signature to a class and a disposition (missing mapping,
known transient, infra readiness, unregistered exception type, document-download defect,
product-decision-pending, novel).

For each issue, fill in:

- **Name** — a human sentence, not the exception class. "Georgia court locations missing from the
  county map", not "CountyDeterminationException".
- **Taxonomy bucket** — the matching row, or "novel" with a reason.
- **Root cause** — what is actually broken, as far as the trace and code show. If you have the
  ecfx-backend checkout, open the throwing frame and confirm before asserting.
- **Disposition** — fix here / route to `add-signature-mapping` / duplicate of an existing ticket /
  product decision pending / not reproducible.

A bucket with a standing umbrella ticket should be linked, not re-fixed. Search Jira before
declaring anything novel — `processor-error-triage` step 3 has the JQL.

## Step 6 — Write the verdict

Replace the `_(pending classification …)_` markers. The verdict answers, in this order:

1. How many distinct issues are on this ticket.
2. Which of them this ticket should actually fix — often fewer than the total.
3. What happens to the rest (duplicate, umbrella, separate ticket, mapping work, no repro).
4. Which issue to start with, and why.

State it plainly:

> **3 distinct issues across 9 inbox items (4 unique emails).** Issue 1 (6 items, 2 emails) is the
> ticket's actual subject and is fixable here. Issue 2 (2 items) is the known NJ browser-transient
> cluster — link to ECFX-XXXXX and leave alone. Issue 3 (1 item) is a different defect in a
> different processor and deserves its own ticket. **Start with issue 1.**

If the ticket genuinely is one issue, say that in one line and move on — do not manufacture
structure that isn't there.

## Step 7 — Hand off

Each issue section carries a handoff line naming its EMLs. To chain:

```
/fix-jira-bug ECFX-16173 --scope issue-1
```

`fix-jira-bug` reads `<TICKET>/<TICKET>.md` when it exists and uses the scoped issue's EMLs as its
reproduction set, skipping its own Phase 2 discovery. Without `--scope` it uses every EML in
`emls/`, which is right only when the research found a single issue.

When the user asks to chain both skills in one go, run this skill to completion first — including
the verdict — then invoke `fix-jira-bug`. If research found more than one fixable issue and the
user did not say which, **ask** before starting a fix. Fixing the wrong cluster wastes the whole
downstream review cycle.

---

## Reporting back

In chat, give the user the short version: issue count, unique email count, the one-line verdict per
issue, and the path to the report. Do not paste the report — it contains firm names, addresses and
legal-notice content, and it is a file they can open.

## Failure modes

| Symptom | Cause and fix |
| --- | --- |
| `Missing Jira credentials` | Set `JIRA_HOST`/`JIRA_USER`/`JIRA_TOKEN`, or `~/.claude/jira.env`. In the container, `JIRA_URL`/`JIRA_USERNAME`/`JIRA_TOKEN_FILE` are picked up automatically. |
| `Cannot find inbox_lookup.py` | The `inbox-lookup` skill isn't installed. Register the marketplace (`./setup.sh` in claude-components) if you haven't, then `claude plugin install ops@ecfx-components`. |
| Admin login fails / hangs | An `inbox-lookup` problem — see its Authentication section. `--cookie` bypasses the browser. |
| `0 inbox id(s) referenced` | The ticket names items in prose or an image. Check `raw/attachments/`, then pass `--ids`. |
| Batch lookup fails, then retries one id at a time | Normal recovery from one bad id — check `unresolvedIds` in the report for which. |
| An issue has no EML | Not reproducible from artifacts; see Step 4. |

## Anti-patterns

- **Trusting the cluster count as the answer.** The script groups by signature; only you can tell
  whether two signatures share a cause. Step 3 exists for this.
- **Counting retries as evidence.** Forty attempts of one exception is one failure with a retry
  loop. Report the attempt count as a *symptom*, not as blast radius.
- **Reproducing every inbox item.** Reproduce one email per issue. The duplicates are duplicates.
- **Leaving `_(pending classification` in the file.** A draft handed off as a finished report sends
  `fix-jira-bug` after an unnamed cluster.
- **Chaining into `fix-jira-bug` with multiple fixable issues and no scope.** Ask first.

## Companion skills

- **`inbox-lookup`** — does the admin fetch; owns login and the `.eml` download.
- **`processor-error-triage`** — the taxonomy for Step 5, and the right skill when the question is
  only "real or noise" for one auto-filed ticket.
- **`fix-jira-bug`** — the downstream consumer; Step 7.
- **`add-signature-mapping`** — where missing-county-mapping issues go instead of a code fix.
