#!/usr/bin/env python3
"""Days each issue spent in a given status inside a window, normalized per assignee.

Port of fetchIssuesWithCycleTimeDuration() + normalizeCycleTime() from the jiraparser
TypeScript tool. Only the portion of each in-status interval that falls inside the window is
counted, so an issue worked across two sprints is split between them.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict
from datetime import datetime, time, timedelta, timezone
from pathlib import Path

# Find the shared library: repo-relative first, so a fresh clone works with no setup at all;
# then ~/.claude/lib, only for a library you placed there yourself (nothing here does).
for _candidate in (Path(__file__).resolve().parents[2] / "lib", Path.home() / ".claude" / "lib"):
    if (_candidate / "jira_metrics.py").exists():
        sys.path.insert(0, str(_candidate))
        break
from jira_metrics import (  # noqa: E402
    JiraClient,
    load_credentials,
    parse_jira_ts,
    resolve_window,
    utc_now_iso,
    write_csv,
)

COLUMNS = ["jiraId", "summary", "issuetype", "priority", "assignee", "calculatedCycleTime", "rawCycleTime"]
SECONDS_PER_DAY = 86400


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--start", help="Window start, YYYY-MM-DD (inclusive)")
    parser.add_argument("--end", help="Window end, YYYY-MM-DD (EXCLUSIVE)")
    parser.add_argument("--days", type=int, help="Window of the last N days instead of --start/--end")
    parser.add_argument("--status", default="In Progress", help="Status to measure (default: In Progress)")
    parser.add_argument(
        "--tz",
        default="local",
        choices=["local", "utc"],
        help="Whether window boundaries mean local midnight (default, matches how Jira reads JQL "
        "dates for your account) or UTC midnight (what the original TypeScript tool used)",
    )
    parser.add_argument("--project", default="ECFX")
    parser.add_argument("--sprint", action="append", help="Sprint id to scope to; repeatable")
    parser.add_argument("--issue-type", help="Restrict to one issue type (default: all)")
    parser.add_argument("--exclude-assignee", action="append", help="Jira accountId to exclude; repeatable")
    parser.add_argument("--extra-jql", default="")
    parser.add_argument(
        "--no-normalize",
        action="store_true",
        help="Report raw in-status days without the per-assignee capacity normalization",
    )
    parser.add_argument("--out", help="CSV path (default: sprintCycleTime_<start>_to_<end>.csv in cwd)")
    parser.add_argument("--no-csv", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--env-file")
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args(argv)


def day_bounds(start: str, end: str, tz_mode: str = "local") -> tuple[datetime, datetime]:
    """Window boundaries as aware datetimes at midnight; `end` is exclusive."""
    tz = timezone.utc if tz_mode == "utc" else datetime.now(timezone.utc).astimezone().tzinfo
    to_dt = lambda d: datetime.combine(datetime.fromisoformat(d).date(), time.min, tzinfo=tz)  # noqa: E731
    return to_dt(start), to_dt(end)


def in_status_seconds(issue: dict, status: str, window_start: datetime, window_end: datetime) -> float:
    """Seconds this issue spent in `status` within [window_start, window_end)."""
    histories = (issue.get("changelog") or {}).get("histories") or []
    histories = sorted(histories, key=lambda h: h.get("created", ""))

    total = 0.0
    entered: datetime | None = None
    for history in histories:
        for item in history.get("items") or []:
            if item.get("field") != "status":
                continue
            changed_at = parse_jira_ts(history["created"])
            if item.get("toString") == status:
                if changed_at < window_end:
                    entered = max(changed_at, window_start)
            elif item.get("fromString") == status and entered is not None:
                if changed_at >= window_start:
                    total += (min(changed_at, window_end) - entered).total_seconds()
                entered = None

    if entered is not None and entered < window_end:
        total += (window_end - entered).total_seconds()
    return max(total, 0.0)


def normalize(rows: list[dict], window_days: float) -> list[dict]:
    """Scale each assignee's issues down when their total in-status time exceeds the window.

    An engineer can have several issues sitting in the status at once, so raw totals can exceed
    the calendar window. This preserves the relative split between their issues while capping
    the per-person total at the length of the window — the original tool's behaviour.
    """
    per_assignee: dict[str, float] = defaultdict(float)
    for row in rows:
        per_assignee[row["assignee"]] += row["rawCycleTime"]

    for row in rows:
        total = per_assignee[row["assignee"]]
        value = row["rawCycleTime"]
        if total > window_days and total > 0:
            value = value / total * window_days
        row["calculatedCycleTime"] = round(value, 4)
    return rows


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    start, end = resolve_window(args.start, args.end, args.days)
    window_start, window_end = day_bounds(start, end, args.tz)
    window_days = (window_end - window_start).total_seconds() / SECONDS_PER_DAY

    client = JiraClient(*load_credentials(args.env_file), verbose=not args.quiet)

    # `status WAS IN (...) DURING (...)` finds everything that touched the status in the window;
    # the changelog walk below decides how much of that time actually falls inside it.
    jql = f'status WAS IN ("{args.status}") DURING ("{start}", "{end}") AND project = {args.project}'
    if args.sprint:
        jql += " AND (" + " OR ".join(f"sprint = {s}" for s in args.sprint) + ")"
    if args.issue_type:
        jql += f' AND issuetype = "{args.issue_type}"'
    if args.exclude_assignee:
        jql += " AND assignee NOT IN (" + ", ".join(args.exclude_assignee) + ")"
    if args.extra_jql:
        jql += f" AND ({args.extra_jql})"

    issues = client.search(jql, expand_changelog=True)

    rows = []
    for issue in issues:
        fields = issue["fields"]
        raw_days = in_status_seconds(issue, args.status, window_start, window_end) / SECONDS_PER_DAY
        rows.append(
            {
                "jiraId": issue["key"],
                "summary": fields.get("summary", ""),
                "issuetype": (fields.get("issuetype") or {}).get("name", ""),
                "priority": (fields.get("priority") or {}).get("name", ""),
                "assignee": (fields.get("assignee") or {}).get("displayName", "Unassigned"),
                "rawCycleTime": round(raw_days, 4),
                "calculatedCycleTime": round(raw_days, 4),
            }
        )

    if not args.no_normalize:
        rows = normalize(rows, window_days)
    rows.sort(key=lambda r: r["calculatedCycleTime"], reverse=True)

    by_assignee = defaultdict(list)
    for row in rows:
        by_assignee[row["assignee"]].append(row)

    values = [r["calculatedCycleTime"] for r in rows]
    summary = {
        "generatedAt": utc_now_iso(),
        "window": {"start": start, "end": end, "days": window_days, "endExclusive": True},
        "status": args.status,
        "filters": {
            "project": args.project,
            "sprints": args.sprint or None,
            "issueType": args.issue_type,
            "excludedAssignees": args.exclude_assignee or None,
            "normalized": not args.no_normalize,
        },
        "issueCount": len(rows),
        "totalDays": round(sum(values), 2),
        "medianDays": round(statistics.median(values), 2) if values else 0.0,
        "byAssignee": [
            {
                "assignee": name,
                "issues": len(items),
                "days": round(sum(i["calculatedCycleTime"] for i in items), 2),
                "rawDays": round(sum(i["rawCycleTime"] for i in items), 2),
            }
            for name, items in sorted(by_assignee.items(), key=lambda kv: -sum(i["calculatedCycleTime"] for i in kv[1]))
        ],
        "file": None,
    }

    if not args.no_csv:
        out = Path(args.out).expanduser() if args.out else Path(f"sprintCycleTime_{start}_to_{end}.csv")
        summary["file"] = str(write_csv(out, rows, COLUMNS))

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print_report(summary, rows)
    return 0


def print_report(summary: dict, rows: list[dict]) -> None:
    window = summary["window"]
    inclusive_end = (datetime.fromisoformat(window["end"]) - timedelta(days=1)).date().isoformat()
    mode = "normalized" if summary["filters"]["normalized"] else "raw"
    sprints = summary["filters"]["sprints"]

    print(f"\nTime in \"{summary['status']}\" — {summary['filters']['project']}"
          f"{' sprints ' + ', '.join(sprints) if sprints else ''}")
    print(f"{window['start']} through {inclusive_end} ({window['days']:.0f} days, {mode})")
    print(f"{summary['issueCount']} issues, {summary['totalDays']} issue-days, "
          f"median {summary['medianDays']} days/issue\n")

    print(f"  {'Assignee':<26}{'Issues':>7}{'Days':>8}{'Raw':>8}")
    for entry in summary["byAssignee"]:
        print(f"  {entry['assignee'][:25]:<26}{entry['issues']:>7}{entry['days']:>8.2f}{entry['rawDays']:>8.2f}")

    if rows:
        print("\n  Longest-running issues:")
        for row in rows[:5]:
            print(f"    {row['jiraId']:<12}{row['calculatedCycleTime']:>7.2f}d  "
                  f"{row['assignee'][:18]:<19}{row['summary'][:50]}")

    if summary["file"]:
        print(f"\n  CSV: {summary['file']}")
    print()


if __name__ == "__main__":
    raise SystemExit(main())
