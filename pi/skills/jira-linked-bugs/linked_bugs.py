#!/usr/bin/env python3
"""Created / resolved / open bug counts for issues linked to a support project.

Port of the createdIssues + resolvedIssues + start-of-week-outstanding portion of the
jiraparser TypeScript tool.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

# Find the shared library: repo-relative first, so a fresh clone works with no setup at all;
# then ~/.claude/lib, only for a library you placed there yourself (nothing here does).
for _candidate in (Path(__file__).resolve().parents[2] / "lib", Path.home() / ".claude" / "lib"):
    if (_candidate / "jira_metrics.py").exists():
        sys.path.insert(0, str(_candidate))
        break
from jira_metrics import (  # noqa: E402
    JiraClient,
    closure_date,
    filter_linked,
    issue_date,
    issue_row,
    status_category,
    label_counts,
    load_credentials,
    month_buckets,
    priority_clause,
    resolve_window,
    utc_now_iso,
    write_csv,
)

COLUMNS = [
    "jiraId",
    "summary",
    "priority",
    "issuetype",
    "status",
    "assignee",
    "created",
    "resolved",
    "labels",
    "linkedIssues",
]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--start", help="Window start, YYYY-MM-DD (inclusive)")
    parser.add_argument("--end", help="Window end, YYYY-MM-DD (EXCLUSIVE)")
    parser.add_argument("--days", type=int, help="Window of the last N days instead of --start/--end")
    parser.add_argument("--project", default="ECFX", help="Project to pull bugs from (default: ECFX)")
    parser.add_argument(
        "--linked-project",
        default="CSR",
        help="Only count issues linked to this project. Use --linked-project '' to disable the link filter.",
    )
    parser.add_argument("--issue-type", default="Bug", help="Issue type (default: Bug)")
    parser.add_argument(
        "--priority",
        action="append",
        help="Priority to include; repeatable. Default: Highest and High.",
    )
    parser.add_argument("--all-priorities", action="store_true", help="Do not filter on priority")
    parser.add_argument("--extra-jql", default="", help="Extra JQL ANDed onto every query")
    parser.add_argument(
        "--closed-by",
        default="resolution",
        choices=["resolution", "status"],
        help="What counts as closed. 'resolution' (default) uses the Resolution field; 'status' "
        "counts anything whose status category is Done. Use 'status' when the workflow closes "
        "issues without setting a Resolution, which otherwise makes them look permanently open.",
    )
    parser.add_argument(
        "--monthly",
        action="store_true",
        help="Add a per-calendar-month table: created, resolved, and the open backlog remaining at "
        "each month end, broken out by priority",
    )
    parser.add_argument("--outdir", default=".", help="Directory for the CSV output (default: cwd)")
    parser.add_argument("--prefix", default="", help="Filename prefix for the CSVs")
    parser.add_argument("--no-csv", action="store_true", help="Print the summary only, write no files")
    parser.add_argument("--json", action="store_true", help="Emit the summary as JSON on stdout")
    parser.add_argument("--env-file", help="Path to a .env file with JIRA_HOST / JIRA_USER / JIRA_TOKEN")
    parser.add_argument("--quiet", action="store_true", help="Suppress per-query progress on stderr")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    start, end = resolve_window(args.start, args.end, args.days)
    priorities = [] if args.all_priorities else (args.priority or ["Highest", "High"])
    linked_project = (args.linked_project or "").strip()

    client = JiraClient(*load_credentials(args.env_file), verbose=not args.quiet)

    base = f'project = {args.project} AND issuetype = "{args.issue_type}"{priority_clause(priorities)}'
    if args.extra_jql:
        base += f" AND ({args.extra_jql})"

    def fetch(clause: str) -> list[dict]:
        issues = client.search(f"{base} AND {clause}")
        return filter_linked(issues, linked_project) if linked_project else issues

    if args.closed_by == "status":
        closed_between = lambda s, e: (  # noqa: E731
            f"statusCategory = Done AND statusCategoryChangedDate >= {s} AND statusCategoryChangedDate < {e}"
        )
        still_open_at = lambda d: (  # noqa: E731
            f"createdDate < {d} AND (statusCategory != Done OR statusCategoryChangedDate >= {d})"
        )
    else:
        closed_between = lambda s, e: f"resolutiondate >= {s} AND resolutiondate < {e}"  # noqa: E731
        still_open_at = lambda d: f"createdDate < {d} AND (resolutiondate >= {d} OR resolutiondate IS EMPTY)"  # noqa: E731

    created = fetch(f"createdDate >= {start} AND createdDate < {end}")
    resolved = fetch(closed_between(start, end))
    # Backlog snapshots: raised before the boundary and still open at it.
    open_at_start = fetch(still_open_at(start))
    open_at_end = fetch(still_open_at(end))

    monthly = None
    if args.monthly:
        # One query for every matching issue raised before the window closes, then bucket locally —
        # cheaper and more consistent than re-running an "open as of" query per month boundary.
        history = fetch(f"createdDate < {end}")
        monthly = monthly_rows(history, start, end, args.closed_by)

    summary = {
        "generatedAt": utc_now_iso(),
        "window": {"start": start, "end": end, "endExclusive": True},
        "filters": {
            "project": args.project,
            "issueType": args.issue_type,
            "linkedProject": linked_project or None,
            "priorities": priorities or "all",
            "extraJql": args.extra_jql or None,
        },
        "counts": {
            "created": len(created),
            "resolved": len(resolved),
            "net": len(created) - len(resolved),
            "openAtStart": len(open_at_start),
            "openAtEnd": len(open_at_end),
            "backlogChange": len(open_at_end) - len(open_at_start),
        },
        "labels": {
            "created": dict(label_counts(created).most_common()),
            "resolved": dict(label_counts(resolved).most_common()),
            "openAtEnd": dict(label_counts(open_at_end).most_common()),
        },
        "monthly": monthly,
        # Issues sitting in a Done status with no Resolution set. These look permanently open to
        # resolution-based counting and never appear in the resolved bucket, so they silently
        # inflate the backlog. Surfaced rather than corrected, because the fix belongs in Jira.
        "doneWithoutResolution": sorted(
            issue["key"]
            for issue in open_at_end
            if status_category(issue) == "Done" and not issue["fields"].get("resolutiondate")
        ),
        "files": {},
    }

    if not args.no_csv:
        outdir = Path(args.outdir).expanduser()
        for name, issues in (("created", created), ("resolved", resolved), ("open", open_at_end)):
            path = outdir / f"{args.prefix}{name}Issues_{start}_to_{end}.csv"
            rows = [issue_row(issue, linked_project or None) for issue in issues]
            summary["files"][name] = str(write_csv(path, rows, COLUMNS))

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print_report(summary)
    return 0


def monthly_rows(history: list[dict], start: str, end: str, closed_by: str = "resolution") -> list[dict]:
    """Per-month created / resolved / still-open counts, computed from the full issue history.

    "Open at month end" means raised before the boundary and either not yet closed or closed on or
    after it — the same predicate the headline open counts use, evaluated at each month boundary.
    """
    rows = []
    for label, bucket_start, bucket_end in month_buckets(start, end):
        created = resolved = 0
        open_by_priority: Counter = Counter()

        for issue in history:
            raised = issue_date(issue, "created")
            closed = closure_date(issue, closed_by)
            if raised is not None and bucket_start <= raised < bucket_end:
                created += 1
            if closed is not None and bucket_start <= closed < bucket_end:
                resolved += 1
            if raised is not None and raised < bucket_end and (closed is None or closed >= bucket_end):
                open_by_priority[(issue["fields"].get("priority") or {}).get("name", "Unknown")] += 1

        rows.append(
            {
                "month": label,
                "partial": (bucket_start.day != 1) or (bucket_end.day != 1),
                "created": created,
                "resolved": resolved,
                "net": created - resolved,
                "openAtEnd": sum(open_by_priority.values()),
                "openByPriority": dict(open_by_priority.most_common()),
            }
        )
    return rows


def print_monthly(rows: list[dict]) -> None:
    priorities = sorted({p for row in rows for p in row["openByPriority"]})
    header = f"  {'Month':<9}{'Created':>8}{'Resolved':>9}{'Net':>6}{'Open':>7}"
    header += "".join(f"{p:>10}" for p in priorities)
    print("\n  Per-month backlog (open = still unresolved at month end):")
    print(header)
    for row in rows:
        line = (
            f"  {row['month'] + ('*' if row['partial'] else ''):<9}"
            f"{row['created']:>8}{row['resolved']:>9}{row['net']:>+6}{row['openAtEnd']:>7}"
        )
        line += "".join(f"{row['openByPriority'].get(p, 0):>10}" for p in priorities)
        print(line)
    if any(row["partial"] for row in rows):
        print("  * partial month (window boundary falls mid-month)")


def print_report(summary: dict) -> None:
    window = summary["window"]
    filters = summary["filters"]
    counts = summary["counts"]
    link = f" linked to {filters['linkedProject']}" if filters["linkedProject"] else ""
    priorities = filters["priorities"]
    priorities = "all priorities" if priorities == "all" else "/".join(priorities)

    inclusive_end = (datetime.fromisoformat(window["end"]) - timedelta(days=1)).date().isoformat()
    print(f"\n{filters['project']} {filters['issueType']}s{link} — {priorities}")
    print(f"{window['start']} through {inclusive_end}  (end {window['end']} exclusive)\n")
    print(f"  Created           {counts['created']:>5}")
    print(f"  Resolved          {counts['resolved']:>5}")
    print(f"  Net              {counts['net']:>+6}")
    print(f"  Open at start     {counts['openAtStart']:>5}")
    print(f"  Open at end       {counts['openAtEnd']:>5}")
    print(f"  Backlog change   {counts['backlogChange']:>+6}")

    if summary.get("monthly"):
        print_monthly(summary["monthly"])

    for title, key in (("Created", "created"), ("Resolved", "resolved"), ("Still open", "openAtEnd")):
        labels = summary["labels"][key]
        if labels:
            print(f"\n  {title} by label:")
            for label, count in labels.items():
                print(f"    {label:<40} {count:>4}")

    stuck = summary.get("doneWithoutResolution") or []
    if stuck:
        print(f"\n  ⚠ {len(stuck)} issue(s) are in a Done status with no Resolution set, so they")
        print("    count as open above and never counted as resolved. Re-run with")
        print("    --closed-by status to exclude them, or set a Resolution in Jira:")
        for key in stuck:
            print(f"      {key}")

    if summary["files"]:
        print("\n  CSVs:")
        for name, path in summary["files"].items():
            print(f"    {name:<9} {path}")
    print()


if __name__ == "__main__":
    raise SystemExit(main())
