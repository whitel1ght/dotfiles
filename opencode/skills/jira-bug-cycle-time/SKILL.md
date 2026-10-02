---
name: jira-bug-cycle-time
description: >-
  Cycle time for bugs closed in a window — from first pickup (first entry into In Progress) to done, plus a waiting-versus-development split and created-to-done lead time, with mean/median/p90 overall and by priority, and a per-issue CSV. Use when the user asks about bug cycle time, average time to fix, how long from starting a bug to finishing it, time in status, time-to-resolution, lead time, how long bugs sit before someone picks them up, or invokes /jira-bug-cycle-time. For created-vs-resolved counts use `jira-linked-bugs`; for time-in-progress attributed to a sprint use `jira-sprint-cycle-time`.
---


# jira-bug-cycle-time

Answers: **for the bugs we closed this period, how long did they take once someone started, and how
much of their total elapsed time was queue time versus hands-on-keyboard time?**

Three different clocks, all reported together — don't confuse them:

| Metric | From | To |
|---|---|---|
| **Cycle time** | first entry into `In Progress` (`--start-status`) | closed |
| Waiting / Development | — | sum of time in each status group, over the issue's whole life |
| Lead time | created | closed |

Cycle time is the "how fast do we fix it once we start" number. Lead time includes the backlog wait
before pickup, so it is always larger. Issues that never entered a start status are **excluded from
the cycle-time average** (and listed), since most are duplicates or invalid tickets closed without
work — averaging in a zero would understate real fix time.

The waiting/development split reads each issue's changelog, walks status transitions oldest-first,
and attributes each interval to the status the issue was *leaving*. Two buckets:

- **Waiting** — `Open`, `Awaiting Details`, `Blocked`, `To-Do`
- **Development** — `In Progress`, `In MR`, `In QA`

Time in any other status (e.g. `Done`, custom states) is deliberately not counted in either bucket,
so `timeInWaiting + timeInDevelopment` is usually less than raw lead time. `leadTime` (created →
resolved, wall clock) is reported alongside so the gap is visible. Port of `getIssuesCycleTime()`
from the `jiraparser` TypeScript tool; verified to reproduce its numbers.

## How to run

Worker: `${CLAUDE_SKILL_DIR}/bug_cycle_time.py` (stdlib Python).

```bash
# Bugs resolved in a window (--end is EXCLUSIVE)
python3 ${CLAUDE_SKILL_DIR}/bug_cycle_time.py --start 2026-07-27 --end 2026-08-03

# Last 30 days, every bug not just customer-linked ones
python3 ${CLAUDE_SKILL_DIR}/bug_cycle_time.py --days 30 --linked-project ''

# Custom workflow states
python3 ${CLAUDE_SKILL_DIR}/bug_cycle_time.py --days 14 \
  --waiting-status 'To-Do' --waiting-status 'Blocked' --dev-status 'In Progress'
```

Key flags:

| Flag | Default | Notes |
|---|---|---|
| `--start` / `--end` / `--days` | — | `--end` is **exclusive**. |
| `--date-field` | `resolutiondate` | Switch to `createdDate` to measure the cohort raised in the window (many will still be open, so their tracked time is partial). |
| `--start-status` | `In Progress` | Repeatable — the cycle-time clock starts at the earliest entry into any of them. Add `In MR` / `In QA` to also count bugs that skipped `In Progress`. |
| `--closed-by` | `status` | Defaults to status-category `Done`, because the ECFX workflow closes issues without setting a Resolution. `resolution` uses the Resolution field. |
| `--linked-project` | `CSR` | Restrict to customer-linked bugs. `''` disables. |
| `--project` / `--issue-type` | `ECFX` / `Bug` | |
| `--priority` | all | Repeatable, e.g. `--priority Highest --priority High`. |
| `--waiting-status` / `--dev-status` | see above | Repeatable; each overrides its whole default list. |
| `--extra-jql` | — | ANDed onto the query. |
| `--out` / `--no-csv` / `--json` | | CSV path / skip files / machine-readable. |

## What it produces

Console: issue count, then mean/median/p90/max for waiting, development, and lead time (auto-formatted
h or d), then the five issues with the most tracked time. CSV columns: `jiraId, summary, issuetype,
priority, assignee, timeInWaiting, timeInDevelopment, totalTracked, leadTime, labels, linkedIssues` —
all times in **hours**, sorted by total tracked time descending.

## Reporting guidance

- Quote **median** cycle time as the headline; the mean is dragged badly by stragglers that sit in
  review for months. Report both when they diverge and say which is which.
- Always state the excluded count — "median 3.9d across 256 of 331 closed bugs; 75 never entered
  In Progress" is honest, a bare average is not.
- Cycle time and lead time answer different questions. If lead time is 26d and cycle time is 7d, the
  bottleneck is triage, not engineering.

- Median matters more than mean here; one 60-day straggler drags the mean badly. Report both and say
  so when they diverge.
- A large waiting-to-development ratio is a triage/prioritization problem, not an engineering-speed
  problem. That distinction is usually the point of running this.
- Watch for issues where lead time greatly exceeds `totalTracked` — that means significant time in a
  status outside both bucket lists, and the status lists may need extending for this workflow.
- This is changelog-heavy: expect it to be slower than `jira-linked-bugs` on wide windows.

## Credentials

Environment (`JIRA_HOST`, `JIRA_USER`, `JIRA_TOKEN`) → `--env-file` → `~/.claude/jira.env` →
`./.env` → `~/Desktop/jiraparser/.env`.

## Shared library

The Jira REST client, credential loading, changelog walking and CSV writing live in
`lib/jira_metrics.py` at the repo root, shared by all three `jira-*` skills. The worker resolves it
repo-relative (`Path(__file__).resolve().parents[2] / "lib"` — `plugins/ops/lib`, a real
directory copied along with the rest of the plugin, so this resolves the same way in a checkout
and in an installed copy with no setup step), falling back to the legacy `~/.claude/lib`.
