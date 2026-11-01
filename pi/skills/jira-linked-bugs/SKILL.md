---
name: jira-linked-bugs
description: >-
  Report ECFX bugs that are linked to a customer-support project (CSR) over a time window — how many were created, how many were resolved, the open backlog at each end of the window, and a breakdown by label — plus per-issue CSVs. Use when the user asks for created vs resolved bugs, customer-linked/support-linked bug counts, weekly or sprint bug metrics, backlog trend, "how many bugs did we open and close", or invokes /jira-linked-bugs. For time-in-status metrics use `jira-bug-cycle-time`; for time-in-progress-during-a-sprint use `jira-sprint-cycle-time`.
---


# jira-linked-bugs

Answers: **over this window, how many customer-linked bugs did we open, how many did we close, and
did the backlog grow or shrink?**

"Customer-linked" means the ECFX bug has a Jira issue link to an issue in the support project
(`CSR` by default). That link is the signal that a real customer reported it, so the report ignores
internally-found bugs. This is a port of the `createdIssues` / `resolvedIssues` / outstanding-issues
portion of the `jiraparser` TypeScript tool on the user's Desktop.

## How to run

Worker: `${CLAUDE_SKILL_DIR}/linked_bugs.py` (stdlib Python, no install step).

```bash
# A specific window — note --end is EXCLUSIVE
python3 ${CLAUDE_SKILL_DIR}/linked_bugs.py --start 2026-07-27 --end 2026-08-03

# Last 7 days, no files written
python3 ${CLAUDE_SKILL_DIR}/linked_bugs.py --days 7 --no-csv

# All priorities, different support project, CSVs into a folder
python3 ${CLAUDE_SKILL_DIR}/linked_bugs.py \
  --days 30 --all-priorities --linked-project CSR --outdir ~/reports
```

Key flags:

| Flag | Default | Notes |
|---|---|---|
| `--start` / `--end` | — | `YYYY-MM-DD`. **`--end` is exclusive** — use `2026-08-03` to include Aug 2. |
| `--days N` | — | Last N days ending today, instead of explicit dates. |
| `--project` | `ECFX` | Project the bugs live in. |
| `--linked-project` | `CSR` | Link filter. Pass `--linked-project ''` to count *all* bugs, linked or not. |
| `--issue-type` | `Bug` | e.g. `Story`, `Task`. |
| `--priority` | `Highest`, `High` | Repeatable. `--priority Medium --priority Low` to override. |
| `--all-priorities` | off | Drop the priority filter entirely. |
| `--closed-by` | `resolution` | `status` counts anything in a Done status category as closed. **ECFX needs `status`** — see below. |
| `--monthly` | off | Adds a per-calendar-month table: created, resolved, net, and the backlog still open at each month end, split by priority. |
| `--extra-jql` | — | ANDed onto every query, e.g. `--extra-jql 'labels = BugConnect'`. |
| `--outdir` / `--prefix` | `.` / none | CSV destination. |
| `--no-csv` / `--json` | off | Summary only / machine-readable output. |

## What it produces

Console summary: created, resolved, net, open-at-start, open-at-end, backlog change, then a label
breakdown for each bucket. Three CSVs (`createdIssues_…`, `resolvedIssues_…`, `openIssues_…`) with
columns `jiraId, summary, priority, issuetype, status, assignee, created, resolved, labels,
linkedIssues`.

With `--monthly`, a backlog table is printed above the labels. It costs one extra query — every
matching issue raised before the window closes is fetched once and bucketed locally, rather than
re-running an "open as of" query per boundary. "Open at month end" uses the same predicate as the
headline counts (raised before the boundary, and either unresolved or resolved on/after it), so the
last row's Open always equals the headline `Open at end`, and the Created/Resolved columns always
sum to the headline totals. Those three identities are a free correctness check — if they don't
hold, something is wrong.

The label breakdown is how the team attributes bugs to customers — labels like `Buchanan`, `Orrick`,
`Cooley` are firm names, and `BugConnect` marks bugs raised through that channel. Call out any firm
appearing repeatedly in the still-open bucket; that's usually the point of the report.

## Closed-by: resolution vs. status

The ECFX workflow can move an issue to **Done without setting a Resolution**. Such issues have
`resolutiondate = null` forever, so resolution-based counting treats them as open indefinitely and
never counts them as resolved — inflating the backlog and depressing the resolved total.

`--closed-by status` counts status category `Done` as closed instead, dated by
`statusCategoryChangedDate`. That matches what people see on boards and in ScriptRunner queries like
`issueFunction in linkedIssuesOf("project = CSR")` filtered to open items. **Prefer
`--closed-by status` for ECFX** unless you specifically want resolution-field semantics.

The report always lists any Done-without-Resolution issues it finds, under both modes, so the gap is
visible rather than silent. If the count is non-zero and the user is comparing against a board or a
ScriptRunner query, that list is almost always the whole discrepancy.

## Reporting guidance

- Lead with created vs resolved and whether the backlog grew or shrank — that's the headline.
- Name the CSV paths so the user can open them.
- Labels with a count of 1 are noise; summarize the tail rather than listing all of it.
- If created and resolved are both 0, sanity-check the window before reporting "a quiet week" —
  an `--end` typo (inclusive-vs-exclusive) is the usual cause.

## Credentials

Resolved in order: environment (`JIRA_HOST`, `JIRA_USER`, `JIRA_TOKEN`) → `--env-file` →
`~/.claude/jira.env` → `./.env` → `~/Desktop/jiraparser/.env`. The script exits with setup
instructions if none supply all three.

## Shared library

The Jira REST client, credential loading, changelog walking and CSV writing live in
`lib/jira_metrics.py` at the repo root, shared by all three `jira-*` skills. The worker resolves it
repo-relative (`Path(__file__).resolve().parents[2] / "lib"` — `plugins/ops/lib`, a real
directory copied along with the rest of the plugin, so this resolves the same way in a checkout
and in an installed copy with no setup step), falling back to the legacy `~/.claude/lib`.

## Fidelity notes vs. the original tool

- The original wrote `issuetype`/`assignee` CSV headers but filled them from a record that had
  neither, so those columns were always blank. Fixed here.
- The original's "outstanding" query used Jira's `startOfWeek()`, which only made sense for a
  week-long run. This reports the backlog at both window boundaries instead, so any window works.
- Link matching now requires the `CSR-` key prefix rather than a substring match on the key.
