#!/usr/bin/env python3
"""
notice-stats: per-processor notice-processing OUTCOME stats from DuploCloud (Loki), as CSV.

Faithful port of the CloudWatch Logs Insights query we used to export. Because the
logic is per-inbox (latest state + duplicate/ignore/retry/customer-action precedence)
and inboxId/processor live in the log *line* (not Loki labels), LogQL can't do it —
so we pull the matching lines (paginated) and replicate the buckets in Python.

The pull and the per-inbox reduction live in lib/notice_loki.py, shared with the
notice-attempts skill. Pass --also-attempts PATH to get that report too, out of the
same scan — the scan is the expensive part, so this costs far less than a second run.

Auth: a DuploCloud token (NOT a Grafana SA token) as Bearer to the Grafana datasource
proxy. By default we obtain it via `duplo-jit duplo --host <prod> --interactive`.

Stdlib only.
"""

import sys
from pathlib import Path

# Find the shared library: repo-relative first, so a fresh clone works with no setup at all;
# then ~/.claude/lib, only for a library you placed there yourself (nothing here does).
for _candidate in (Path(__file__).resolve().parents[2] / "lib", Path.home() / ".claude" / "lib"):
    if (_candidate / "notice_loki.py").exists():
        sys.path.insert(0, str(_candidate))
        break

from notice_loki import run  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(run("outcomes", __doc__))
