---
name: jira-sprint-cycle-time
description: >-
  Measure how many days each issue spent in a given status (default "In Progress") inside a window or sprint, split per assignee, with the original tool's per-person capacity normalization. Use when the user asks about sprint cycle time, days in progress, work-in-progress load per engineer, how long issues were actively being worked during a sprint, throughput or WIP for a sprint, or invokes /jira-sprint-cycle-time. For created-vs-resolved bug counts use `jira-linked-bugs`; for waiting-vs-development split on resolved bugs use `jira-bug-cycle-time`.
---


# jira-sprint-cycle-time

Answers: **during this sprint, how many days did each issue actually sit in the working status, and
how does that distribute across the team?**

Unlike `jira-bug-cycle-time` (which measures an issue's whole life), this clips to the window: only
the portion of each in-status interval falling inside `[start, end)` counts. An issue worked across
two sprints is split between them. Port of `fetchIssuesWithCycleTimeDuration()` +
`normalizeCycleTime()` from the `jiraparser` TypeScript tool.

## How to run

Worker: `${CLAUDE_SKILL_DIR}/sprint_cycle_time.py` (stdlib Python).

```bash
# A sprint window, scoped to specific sprint ids (--end is EXCLUSIVE)
python3 ${CLAUDE_SKILL_DIR}/sprint_cycle_time.py \
  --start 2026-07-27 --end 2026-08-02 --sprint 1197 --sprint 1202

# Whole project, last two weeks, raw days with no normalization
python3 ${CLAUDE_SKILL_DIR}/sprint_cycle_time.py --days 14 --no-normalize

# A different status
python3 ${CLAUDE_SKILL_DIR}/sprint_cycle_time.py --days 14 --status 'In QA'
```

Key flags:

| Flag | Default | Notes |
|---|---|---|
| `--start` / `--end` / `--days` | — | `--end` is **exclusive**. |
| `--status` | `In Progress` | Any workflow status. |
| `--sprint` | — | Repeatable sprint id. Find ids in the board URL or via the sprint field. |
| `--project` / `--issue-type` | `ECFX` / all | Sub-tasks are included by default — that's usually what you want, since that's where the work lives. |
| `--exclude-assignee` | — | Repeatable Jira accountId, for leads or bots that skew the per-person view. |
| `--no-normalize` | off | Report raw days only. |
| `--tz` | `local` | `utc` reproduces the original TypeScript tool's boundaries exactly. |
| `--out` / `--no-csv` / `--json` | | |

## Normalization — read before reporting

An engineer can have several issues in the status simultaneously, so raw per-person totals routinely
exceed the calendar length of the window. Normalization scales each person's issues down by a common
factor so their total caps at the window length, preserving the relative split between their issues.

This means **`calculatedCycleTime` is a share-of-capacity number, not wall-clock time.** Both are in
the CSV (`calculatedCycleTime` and `rawCycleTime`) and both appear in the per-assignee table
(`Days` vs `Raw`). Say which one you're quoting.

A large `Raw` relative to `Days` is itself the signal: that person had a lot of work open at once.
Do not present normalized days as "how long they worked on it".

## What it produces

Console: issue count, total issue-days, median, a per-assignee table (issues / normalized days / raw
days), and the five longest-running issues. CSV columns: `jiraId, summary, issuetype, priority,
assignee, calculatedCycleTime, rawCycleTime` — days, sorted descending.

## Caveats

- `assignee` is the issue's **current** assignee, not who held it during the window. Reassignments
  after the fact move the days.
- The JQL is `status WAS IN (...) DURING (...)`, which finds candidates; the changelog walk decides
  how much time actually lands inside the window. Issues showing `0.00` touched the status only
  outside the window.
- Changelog-heavy; wide windows across a whole project are slow.

## Credentials

Environment (`JIRA_HOST`, `JIRA_USER`, `JIRA_TOKEN`) → `--env-file` → `~/.claude/jira.env` →
`./.env` → `~/Desktop/jiraparser/.env`.

## Shared library

The Jira REST client, credential loading, changelog walking and CSV writing live in
`lib/jira_metrics.py` at the repo root, shared by all three `jira-*` skills. The worker resolves it
repo-relative (`Path(__file__).resolve().parents[2] / "lib"` — `plugins/ops/lib`, a real
directory copied along with the rest of the plugin, so this resolves the same way in a checkout
and in an installed copy with no setup step), falling back to the legacy `~/.claude/lib`.
