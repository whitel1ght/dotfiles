#!/usr/bin/env python3
"""Time-in-status breakdown (waiting vs. development) for issues resolved in a window.

Port of getIssuesCycleTime() from the jiraparser TypeScript tool: walk each issue's changelog
and accumulate the hours spent in waiting-type statuses vs. active-development statuses.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

# Find the shared library: repo-relative first, so a fresh clone works with no setup at all;
# then ~/.claude/lib, only for a library you placed there yourself (nothing here does).
for _candidate in (Path(__file__).resolve().parents[2] / "lib", Path.home() / ".claude" / "lib"):
    if (_candidate / "jira_metrics.py").exists():
        sys.path.insert(0, str(_candidate))
        break
from jira_metrics import (  # noqa: E402
    JiraClient,
    closure_timestamp,
    filter_linked,
    first_entry_into,
    linked_keys,
    load_credentials,
    parse_jira_ts,
    priority_clause,
    resolve_window,
    status_category,
    status_transitions,
    utc_now_iso,
    write_csv,
)

WAITING_STATUSES = ["Open", "Awaiting Details", "Blocked", "To-Do"]
DEVELOPMENT_STATUSES = ["In Progress", "In MR", "In QA"]

COLUMNS = [
    "jiraId",
    "summary",
    "issuetype",
    "priority",
    "assignee",
    "cycleTime",
    "timeInWaiting",
    "timeInDevelopment",
    "totalTracked",
    "leadTime",
    "startedAt",
    "closedAt",
    "labels",
    "linkedIssues",
]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--start", help="Window start, YYYY-MM-DD (inclusive)")
    parser.add_argument("--end", help="Window end, YYYY-MM-DD (EXCLUSIVE)")
    parser.add_argument("--days", type=int, help="Window of the last N days instead of --start/--end")
    parser.add_argument(
        "--date-field",
        default="resolutiondate",
        choices=["resolutiondate", "createdDate"],
        help="Which date the window applies to (default: resolutiondate)",
    )
    parser.add_argument(
        "--closed-by",
        default="status",
        choices=["resolution", "status"],
        help="What counts as closed. 'status' (default) counts any Done status category, dated by "
        "statusCategoryChangedDate; 'resolution' uses the Resolution field, which misses issues "
        "closed without one.",
    )
    parser.add_argument(
        "--start-status",
        action="append",
        help="Status whose first entry starts the cycle-time clock; repeatable, earliest wins. "
        "Default: In Progress",
    )
    parser.add_argument("--project", default="ECFX")
    parser.add_argument("--issue-type", default="Bug")
    parser.add_argument(
        "--linked-project",
        default="CSR",
        help="Only include issues linked to this project. Pass '' to disable the link filter.",
    )
    parser.add_argument("--priority", action="append", help="Priority to include; repeatable. Default: all.")
    parser.add_argument("--extra-jql", default="")
    parser.add_argument(
        "--waiting-status",
        action="append",
        help=f"Override the waiting statuses; repeatable. Default: {', '.join(WAITING_STATUSES)}",
    )
    parser.add_argument(
        "--dev-status",
        action="append",
        help=f"Override the development statuses; repeatable. Default: {', '.join(DEVELOPMENT_STATUSES)}",
    )
    parser.add_argument("--out", help="CSV path (default: bugCycleTime_<start>_to_<end>.csv in cwd)")
    parser.add_argument("--no-csv", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--env-file")
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args(argv)


def status_durations(issue: dict, waiting: list[str], development: list[str]) -> tuple[float, float]:
    """Hours the issue spent in waiting-type and development-type statuses.

    Walks status transitions oldest-first. Each transition closes out the period that began at the
    previous transition (or at issue creation) and attributes it to the status being left.
    """
    time_waiting = 0.0
    time_development = 0.0
    last_ts = parse_jira_ts(issue["fields"]["created"])

    for current_ts, from_status, _ in status_transitions(issue):
        hours = (current_ts - last_ts).total_seconds() / 3600
        if from_status in waiting:
            time_waiting += hours
        elif from_status in development:
            time_development += hours
        last_ts = current_ts

    return round(time_waiting, 2), round(time_development, 2)


def cycle_time_hours(issue: dict, start_statuses: list[str], closed_by: str) -> tuple[float | None, str, str]:
    """Hours from first entering a start status until the issue closed.

    Returns (hours, startedAt, closedAt). Hours is None when the issue never entered a start status
    (nothing was ever picked up) or when it closed before doing so — both of which would otherwise
    contribute a meaningless or negative value to the average.
    """
    started = first_entry_into(issue, start_statuses)
    closed = closure_timestamp(issue, closed_by)
    started_str = started.astimezone().strftime("%Y-%m-%d %H:%M") if started else ""
    closed_str = closed.astimezone().strftime("%Y-%m-%d %H:%M") if closed else ""

    if started is None or closed is None or closed < started:
        return None, started_str, closed_str
    return round((closed - started).total_seconds() / 3600, 2), started_str, closed_str


def lead_time_hours(issue: dict, closed_by: str) -> float | None:
    closed = closure_timestamp(issue, closed_by)
    if not closed:
        return None
    delta = closed - parse_jira_ts(issue["fields"]["created"])
    return round(delta.total_seconds() / 3600, 2)


def describe(values: list[float]) -> dict[str, float]:
    if not values:
        return {"count": 0, "mean": 0.0, "median": 0.0, "p90": 0.0, "max": 0.0}
    ordered = sorted(values)
    p90_index = min(len(ordered) - 1, int(round(0.9 * (len(ordered) - 1))))
    return {
        "count": len(values),
        "mean": round(statistics.fmean(values), 2),
        "median": round(statistics.median(values), 2),
        "p90": round(ordered[p90_index], 2),
        "max": round(ordered[-1], 2),
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    start, end = resolve_window(args.start, args.end, args.days)
    waiting = args.waiting_status or WAITING_STATUSES
    development = args.dev_status or DEVELOPMENT_STATUSES
    linked_project = (args.linked_project or "").strip()

    client = JiraClient(*load_credentials(args.env_file), verbose=not args.quiet)

    if args.date_field == "resolutiondate" and args.closed_by == "status":
        window_clause = (
            f"statusCategory = Done AND statusCategoryChangedDate >= {start} "
            f"AND statusCategoryChangedDate < {end}"
        )
    else:
        window_clause = f"{args.date_field} >= {start} AND {args.date_field} < {end}"

    jql = (
        f'project = {args.project} AND issuetype = "{args.issue_type}"'
        f"{priority_clause(args.priority or [])}"
        f" AND {window_clause}"
    )
    if args.extra_jql:
        jql += f" AND ({args.extra_jql})"

    issues = client.search(jql, expand_changelog=True)
    if linked_project:
        issues = filter_linked(issues, linked_project)

    start_statuses = args.start_status or ["In Progress"]
    rows = []
    never_started = []
    for issue in issues:
        fields = issue["fields"]
        time_waiting, time_development = status_durations(issue, waiting, development)
        cycle, started_at, closed_at = cycle_time_hours(issue, start_statuses, args.closed_by)
        if cycle is None:
            never_started.append(issue["key"])
        rows.append(
            {
                "jiraId": issue["key"],
                "summary": fields.get("summary", ""),
                "issuetype": (fields.get("issuetype") or {}).get("name", ""),
                "priority": (fields.get("priority") or {}).get("name", ""),
                "assignee": (fields.get("assignee") or {}).get("displayName", "Unassigned"),
                "cycleTime": cycle if cycle is not None else "",
                "timeInWaiting": time_waiting,
                "timeInDevelopment": time_development,
                "totalTracked": round(time_waiting + time_development, 2),
                "leadTime": lead_time_hours(issue, args.closed_by) or "",
                "startedAt": started_at,
                "closedAt": closed_at,
                "labels": " ".join(fields.get("labels") or []),
                "linkedIssues": " ".join(linked_keys(issue, linked_project or None)),
            }
        )

    rows.sort(key=lambda r: r["totalTracked"], reverse=True)
    lead_times = [r["leadTime"] for r in rows if isinstance(r["leadTime"], float)]
    cycle_times = [r["cycleTime"] for r in rows if isinstance(r["cycleTime"], float)]
    by_priority = {
        priority: describe([r["cycleTime"] for r in rows if r["priority"] == priority and isinstance(r["cycleTime"], float)])
        for priority in sorted({r["priority"] for r in rows})
    }

    summary = {
        "generatedAt": utc_now_iso(),
        "window": {"start": start, "end": end, "dateField": args.date_field, "endExclusive": True},
        "filters": {
            "project": args.project,
            "issueType": args.issue_type,
            "linkedProject": linked_project or None,
            "priorities": args.priority or "all",
            "waitingStatuses": waiting,
            "developmentStatuses": development,
        },
        "issueCount": len(rows),
        "startStatuses": start_statuses,
        "closedBy": args.closed_by,
        "neverStarted": never_started,
        "stats": {
            "cycleTime": describe(cycle_times),
            "timeInWaiting": describe([r["timeInWaiting"] for r in rows]),
            "timeInDevelopment": describe([r["timeInDevelopment"] for r in rows]),
            "leadTime": describe(lead_times),
        },
        "cycleTimeByPriority": by_priority,
        "slowest": [
            {k: r[k] for k in ("jiraId", "summary", "timeInWaiting", "timeInDevelopment", "leadTime")}
            for r in rows[:10]
        ],
        "file": None,
    }

    if not args.no_csv:
        out = Path(args.out).expanduser() if args.out else Path(f"bugCycleTime_{start}_to_{end}.csv")
        summary["file"] = str(write_csv(out, rows, COLUMNS))

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print_report(summary)
    return 0


def fmt_hours(hours: float) -> str:
    if hours < 24:
        return f"{hours:.1f}h"
    return f"{hours / 24:.1f}d"


def print_report(summary: dict) -> None:
    window, filters, stats = summary["window"], summary["filters"], summary["stats"]
    link = f" linked to {filters['linkedProject']}" if filters["linkedProject"] else ""
    basis = window["dateField"]
    if basis == "resolutiondate":
        basis = "resolved" if summary["closedBy"] == "resolution" else "closed (status Done)"
    print(f"\n{filters['project']} {filters['issueType']}s{link} — {basis} in "
          f"[{window['start']}, {window['end']})")
    print(f"{summary['issueCount']} issues\n")

    started = " / ".join(summary["startStatuses"])
    print(f"  started = first entry into {started}\n")
    print(f"  {'':<24}{'n':>5}{'mean':>10}{'median':>10}{'p90':>10}{'max':>10}")
    labels = (
        ("Cycle (started→done)", "cycleTime"),
        ("  Waiting", "timeInWaiting"),
        ("  Development", "timeInDevelopment"),
        ("Lead (created→done)", "leadTime"),
    )
    for label, key in labels:
        s = stats[key]
        print(f"  {label:<24}{s['count']:>5}{fmt_hours(s['mean']):>10}{fmt_hours(s['median']):>10}"
              f"{fmt_hours(s['p90']):>10}{fmt_hours(s['max']):>10}")

    by_priority = summary.get("cycleTimeByPriority") or {}
    if len(by_priority) > 1:
        print("\n  Cycle time by priority:")
        for priority, s in by_priority.items():
            if s["count"]:
                print(f"    {priority:<22}{s['count']:>5}{fmt_hours(s['mean']):>10}"
                      f"{fmt_hours(s['median']):>10}{fmt_hours(s['p90']):>10}{fmt_hours(s['max']):>10}")

    if summary.get("neverStarted"):
        skipped = summary["neverStarted"]
        print(f"\n  {len(skipped)} issue(s) excluded from cycle time — never entered {started} "
              f"(or closed before it):")
        print("    " + " ".join(skipped[:12]) + (" …" if len(skipped) > 12 else ""))

    if summary["slowest"]:
        print("\n  Longest tracked time in status:")
        for row in summary["slowest"][:5]:
            print(f"    {row['jiraId']:<12} wait {fmt_hours(row['timeInWaiting']):>7}  "
                  f"dev {fmt_hours(row['timeInDevelopment']):>7}  {row['summary'][:60]}")

    if summary["file"]:
        print(f"\n  CSV: {summary['file']}")
    print()


if __name__ == "__main__":
    raise SystemExit(main())
