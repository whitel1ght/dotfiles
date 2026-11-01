#!/usr/bin/env python3
"""
notice-attempts: per-processor ATTEMPTS-TO-SUCCESS and processing-DURATION stats from
DuploCloud (Loki), as CSV.

Population is the notices that truly succeeded (computedFinalResult == PROCESSING COMPLETE).
For each processor: min / max / average / median attempts-to-success, the share that succeeded
on the first attempt, and duration-from-first-attempt.

NOTE this is duration-from-first-attempt, NOT true ingestion→complete — ingestion lives in
inbox_item.created_at in the DB, and the in-code Micrometer Timer is the durable path for that.

The pull and the per-inbox reduction live in lib/notice_loki.py, shared with the notice-stats
skill. Pass --also-outcomes PATH to get the outcome-bucket report too, out of the same scan —
the scan is the expensive part, so this costs far less than a second run.

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
    raise SystemExit(run("attempts", __doc__))
