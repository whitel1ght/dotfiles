#!/usr/bin/env python3
"""Step 8 of a notice-QA run: delete the cached prod client data (review of !52, M9).

    purge.py ECFX-17643 --keep-report     # after posting: keep only what updating the Jira comment needs
    purge.py ECFX-17643                   # when the ticket is done: remove everything for it
    purge.py --older-than 30              # every ticket folder not touched for 30 days
    … --dry-run                           # show what would go

~/.cache/notice-qa/<TICKET>/ holds full prod legal notices (emls/), the bundles that were sent and
their manifests (runs/), and prod lookup output. --keep-report keeps only report-summary.json,
verdicts.json and the rendered report, which is what jira_post.py needs to update its comment and
what was already posted to the ticket. Nothing outside ~/.cache/notice-qa is ever touched.
"""
import argparse
import re
import shutil
import sys
import time

import qa_common as qc

KEEP_WITH_REPORT = {"report-summary.json", "verdicts.json"}
KEY_RE = re.compile(r"[A-Z][A-Z0-9]+-\d+")


def ticket_path(key):
    if not KEY_RE.fullmatch(key or ""):
        raise SystemExit(f"not a Jira key: {key!r}")
    p = (qc.QA_HOME / key).resolve()
    if p.parent != qc.QA_HOME.resolve():
        raise SystemExit(f"refusing to touch {p}: not a ticket folder under {qc.QA_HOME}")
    return p


def purge(key, keep_report=False, dry_run=False):
    """Returns the paths removed (or that would be)."""
    d = ticket_path(key)
    if not d.exists():
        return []
    if not keep_report:
        targets = [d]
    else:
        targets = [p for p in d.iterdir()
                   if p.name not in KEEP_WITH_REPORT and not (p.name.startswith("notice-qa-report-") and p.suffix == ".md")]
    for p in targets:
        if not dry_run:
            shutil.rmtree(p) if p.is_dir() else p.unlink()
    return targets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket", nargs="?")
    ap.add_argument("--keep-report", action="store_true")
    ap.add_argument("--older-than", type=int, metavar="DAYS", help="purge every ticket folder untouched for DAYS")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if bool(a.ticket) == bool(a.older_than):
        ap.error("give a ticket key, or --older-than DAYS")
    keys = [a.ticket] if a.ticket else [
        p.name for p in (qc.QA_HOME.iterdir() if qc.QA_HOME.exists() else [])
        if p.is_dir() and KEY_RE.fullmatch(p.name) and time.time() - max(
            (f.stat().st_mtime for f in p.rglob("*")), default=p.stat().st_mtime) > a.older_than * 86400]
    for key in keys:
        gone = purge(key, a.keep_report, a.dry_run)
        verb = "would remove" if a.dry_run else "removed"
        print(f"{key}: {verb} {len(gone)} path(s)" + ("" if not gone else ": " + ", ".join(p.name for p in gone)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
