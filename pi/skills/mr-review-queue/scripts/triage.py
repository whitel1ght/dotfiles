#!/usr/bin/env python3
"""
triage.py — fetch and categorize all GitLab MRs assigned to the current user as reviewer.

Outputs JSON to stdout. The skill body parses it and presents a human-readable
table to the user, then invokes the mr-review skill on whichever MR they pick.

Output structure:
{
    "self": "<username>",
    "fetched_at": "<ISO timestamp>",
    "total_count": <int>,
    "buckets": {
        "review_now":         [<entries>],   # never reviewed by you, ready
        "re_review_commits":  [<entries>],   # commits pushed since your last review
        "re_review_response": [<entries>],   # comments since your last review, no push
        "waiting_on_author":  [<entries>],   # you reviewed; ball in author's court
        "pipeline_red":       [<entries>],   # CI failed/canceled — author still iterating
        "pipeline_running":   [<entries>],   # CI running — wait
        "already_approved":   [<entries>],   # you've already approved
        "draft":              [<entries>],   # marked draft / WIP
        "conflict":           [<entries>]    # has merge conflicts
    }
}

Each entry:
{
    "ref":         "owner/repo!N",        # for invoking mr-review
    "iid":         <int>,
    "project_id":  <int>,
    "title":       "...",
    "author":      "<username>",
    "url":         "https://gitlab.com/...",
    "updated_at":  "<ISO timestamp>",
    "created_at":  "<ISO timestamp>",
    "context":     "<one-line human-readable detail>"
}

Priority order for display (top of table → bottom):
    review_now > re_review_commits > re_review_response >
    pipeline_running > waiting_on_author > pipeline_red >
    already_approved > draft > conflict

Within each bucket: sorted by updated_at descending (most recently active first).

Requires:
- glab CLI authenticated (`glab auth login`)
- Python 3.7+
- Network access to your GitLab instance
"""

import json
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import quote


# ── glab plumbing ───────────────────────────────────────────────────────────

def glab_api(path):
    """Run `glab api <path>` and return parsed JSON. Exits on error."""
    try:
        result = subprocess.run(
            ["glab", "api", path],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)
    except FileNotFoundError:
        print("ERROR: glab CLI not found. Install via `brew install glab` "
              "and authenticate with `glab auth login`.", file=sys.stderr)
        sys.exit(2)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: glab api {path} failed:\n{e.stderr}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON from glab api {path}: {e}", file=sys.stderr)
        sys.exit(2)


def get_self_username():
    return glab_api("user")["username"]


# ── per-MR categorization ───────────────────────────────────────────────────

def fetch_notes(project_id, iid):
    """Fetch non-system notes for an MR. System notes (auto-events like
    'approved', 'marked WIP') are filtered out so they don't count as
    'response from author'."""
    notes = glab_api(
        f"projects/{project_id}/merge_requests/{iid}/notes?per_page=100"
    )
    return [n for n in notes if not n.get("system", False)]


def fetch_mr_detail(project_id, iid):
    """Fetch the per-MR detail endpoint to get fields the list endpoint omits.

    GitLab's `/merge_requests` list response returns `head_pipeline: null`
    even when a pipeline exists — the list endpoint deliberately strips
    pipeline data for performance. The per-MR detail endpoint
    (`/projects/<id>/merge_requests/<iid>`) populates `head_pipeline` fully.

    Without this, the categorizer can't distinguish:
      - commits-pushed-since-last-review (needs `head_pipeline.created_at`)
      - red CI (needs `head_pipeline.status`)
      - running CI (same)

    All three buckets silently degraded to "no signal" — `re_review_commits`,
    `pipeline_red`, and `pipeline_running` would never fire from the list
    response alone."""
    return glab_api(f"projects/{project_id}/merge_requests/{iid}")


def categorize(mr, self_username, notes):
    """Return (bucket_key, context_string).

    Order matters: earlier checks short-circuit. Don't reorder without
    thinking through the implications.
    """
    if mr.get("draft") or mr.get("work_in_progress"):
        return "draft", "WIP / marked draft"

    detailed = mr.get("detailed_merge_status") or ""
    if mr.get("merge_status") == "cannot_be_merged" or "conflict" in detailed:
        return "conflict", "has merge conflicts"

    pipeline = mr.get("head_pipeline") or {}
    pstatus = pipeline.get("status")
    if pstatus in ("failed", "canceled"):
        return "pipeline_red", f"pipeline {pstatus}"
    if pstatus == "running":
        return "pipeline_running", "pipeline running"

    approvals = (mr.get("approvals") or {}).get("approved_by") or []
    self_approved = any(
        (a.get("user") or {}).get("username") == self_username
        for a in approvals
    )
    if self_approved:
        return "already_approved", "you already approved"

    my_notes = [
        n for n in notes
        if (n.get("author") or {}).get("username") == self_username
    ]

    if not my_notes:
        return "review_now", "first time at you"

    last_my_review_at = max(n["created_at"] for n in my_notes)

    # Pipeline created_at is a reasonable proxy for "head commit pushed at" —
    # GitLab triggers a fresh pipeline on each push.
    pipeline_at = pipeline.get("created_at")
    commits_pushed = bool(pipeline_at and pipeline_at > last_my_review_at)

    other_responses = sorted(
        [
            n for n in notes
            if (n.get("author") or {}).get("username") != self_username
            and n["created_at"] > last_my_review_at
        ],
        key=lambda n: n["created_at"],
    )

    if commits_pushed:
        return "re_review_commits", "commits pushed since your last review"

    if other_responses:
        last = other_responses[-1]
        author = (last.get("author") or {}).get("username", "someone")
        return "re_review_response", f"{author} replied since your last review"

    return "waiting_on_author", "no activity since your last review"


# ── main ────────────────────────────────────────────────────────────────────

def main():
    self_username = get_self_username()

    # Cross-project listing of open MRs where I'm a reviewer.
    # `scope=all` ensures we get every project the user can see, not just the
    # current working directory's project.
    mrs = glab_api(
        f"merge_requests?reviewer_username={quote(self_username)}"
        f"&state=opened&scope=all&per_page=100"
    )

    bucket_keys = [
        "review_now",
        "re_review_commits",
        "re_review_response",
        "waiting_on_author",
        "pipeline_red",
        "pipeline_running",
        "already_approved",
        "draft",
        "conflict",
    ]
    buckets = {k: [] for k in bucket_keys}

    for mr in mrs:
        # The list endpoint omits `head_pipeline` (returns null) and stripped
        # versions of approvals — fetch the per-MR detail to get the fields
        # the categorizer actually needs. Skip for draft MRs since the early
        # return doesn't need pipeline data.
        notes = []
        if not (mr.get("draft") or mr.get("work_in_progress")):
            try:
                notes = fetch_notes(mr["project_id"], mr["iid"])
            except SystemExit:
                # Best-effort: a single failed note fetch shouldn't kill the
                # whole queue. Treat as if there are no notes.
                notes = []
            try:
                # Replace the stripped list-response MR with the fully-populated
                # detail. Fields like head_pipeline, detailed_merge_status, and
                # approvals are only correct on the detail endpoint.
                mr = fetch_mr_detail(mr["project_id"], mr["iid"])
            except SystemExit:
                # Degraded: keep the list-response MR. Categorizer will fall
                # through to notes-only buckets (no pipeline / approval signal).
                pass

        bucket, context = categorize(mr, self_username, notes)

        ref = (mr.get("references") or {}).get("full") or f"#{mr['id']}"
        entry = {
            "ref":          ref,
            "iid":          mr["iid"],
            "project_id":   mr["project_id"],
            "title":        mr.get("title", ""),
            "author":       (mr.get("author") or {}).get("username", "?"),
            "url":          mr.get("web_url"),
            "updated_at":   mr.get("updated_at"),
            "created_at":   mr.get("created_at"),
            "context":      context,
        }
        buckets[bucket].append(entry)

    # Within each bucket, most recently active first.
    for k in buckets:
        buckets[k].sort(key=lambda e: e.get("updated_at") or "", reverse=True)

    output = {
        "self":         self_username,
        "fetched_at":   datetime.now(timezone.utc).isoformat(),
        "total_count":  len(mrs),
        "buckets":      buckets,
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
