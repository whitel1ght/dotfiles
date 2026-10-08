#!/usr/bin/env python3
"""Research every inbox item referenced by a Jira bug, deduplicate the emails, and cluster the
failures into distinct issues.

The deterministic half of the `research-jira-bug` skill: fetch, scrape, download, deduplicate,
normalize, cluster, and write a factual draft. Naming each cluster and deciding what to do about
it is judgement, and stays with the model — see SKILL.md.

Output lands in <out>/<TICKET>/:
    <TICKET>.md               the draft report (the model finishes it)
    emls/                     one .eml per unique email, plus every .eml attached to the ticket
    raw/research.json         everything below, machine-readable
    raw/inbox_lookup.json     the untouched inbox-lookup output
    raw/attachments/          every attachment downloaded off the ticket

Stdlib only.
"""

from __future__ import annotations

import argparse
import email
import email.policy
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, OrderedDict
from pathlib import Path
from typing import Any

# ── locate the shared library ─────────────────────────────────────────────────
# Repo-relative first so a fresh clone runs with no setup, then the installed symlink.
for _lib in (Path(__file__).resolve().parents[2] / "lib", Path.home() / ".claude" / "lib"):
    if (_lib / "jira_metrics.py").exists():
        sys.path.insert(0, str(_lib))
        break
import jira_metrics as jm  # noqa: E402

# ── constants ─────────────────────────────────────────────────────────────────

# Admin ids are `inbox_` + 26 lowercase base32 chars. The negative lookahead keeps
# `inbox_job_<id>` (a processing attempt, not a notice) out of the results.
INBOX_ID_RE = re.compile(r"\binbox_(?!job_)([0-9a-z]{20,32})\b")
# ...and the same id pasted as an admin URL, where it may appear without the prefix.
ADMIN_URL_ID_RE = re.compile(r"inbox_item/(?:details/)?\??(?:id=)?(?:inbox_)?([0-9a-z]{20,32})\b")

TEXT_SUFFIXES = {".eml", ".txt", ".log", ".csv", ".json", ".md", ".html", ".htm", ".yaml", ".yml"}
MAX_SCAN_BYTES = 4 * 1024 * 1024

DEFAULT_APP_PACKAGE = "com.ecfx"

# Volatile fragments that make two identical failures look different. Order matters:
# URLs before ids, ids before bare numbers.
NOISE_PATTERNS = [
    (re.compile(r"https?://\S+"), "<URL>"),
    (re.compile(r"\binbox_job_[0-9a-z]{20,32}\b"), "<JOBID>"),
    (re.compile(r"\binbox_[0-9a-z]{20,32}\b"), "<INBOXID>"),
    (re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"), "<UUID>"),
    (re.compile(r"\b[0-9a-f]{16,}\b"), "<HEX>"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*"), "<TS>"),
    (re.compile(r"\b\d+\b"), "<N>"),
]


def log(message: str) -> None:
    print(message, file=sys.stderr)


# ── ticket ────────────────────────────────────────────────────────────────────

def collect_inbox_ids(text: str) -> list[str]:
    """Every inbox id in a blob of text, in first-seen order."""
    found: list[str] = []
    for match in INBOX_ID_RE.finditer(text or ""):
        found.append("inbox_" + match.group(1))
    for match in ADMIN_URL_ID_RE.finditer(text or ""):
        found.append("inbox_" + match.group(1))
    return list(OrderedDict.fromkeys(found))


def read_ticket(client: jm.JiraClient, key: str) -> dict[str, Any]:
    issue = client.get_issue(key)
    fields = issue.get("fields") or {}

    comments = []
    for comment in ((fields.get("comment") or {}).get("comments") or []):
        comments.append({
            "id": comment.get("id"),
            "author": ((comment.get("author") or {}).get("displayName")),
            "created": comment.get("created"),
            "text": jm.adf_text(comment.get("body")),
        })

    def name_of(value: Any) -> str | None:
        return value.get("name") if isinstance(value, dict) else None

    return {
        "key": issue.get("key", key),
        "summary": fields.get("summary"),
        "status": name_of(fields.get("status")),
        "priority": name_of(fields.get("priority")),
        "issueType": name_of(fields.get("issuetype")),
        "labels": fields.get("labels") or [],
        "created": fields.get("created"),
        "reporter": ((fields.get("reporter") or {}).get("displayName")),
        "assignee": ((fields.get("assignee") or {}).get("displayName")),
        "descriptionText": jm.adf_text(fields.get("description")),
        "comments": comments,
        "linkedKeys": jm.linked_keys(issue),
        "attachments": [{
            "id": att.get("id"),
            "filename": att.get("filename"),
            "size": att.get("size"),
            "mimeType": att.get("mimeType"),
            "content": att.get("content"),
        } for att in (fields.get("attachment") or [])],
    }


def download_attachments(client: jm.JiraClient, ticket: dict[str, Any], attach_dir: Path,
                         eml_dir: Path) -> list[dict[str, Any]]:
    """Save every attachment, scan the text-ish ones for inbox ids, and promote any attached
    .eml into emls/ — a ticket whose only artifact is an attached message is still reproducible."""
    saved: list[dict[str, Any]] = []
    for att in ticket["attachments"]:
        url, filename = att.get("content"), att.get("filename") or att.get("id")
        if not url:
            continue
        safe = Path(str(filename)).name or str(att.get("id"))
        target = attach_dir / safe
        try:
            attach_dir.mkdir(parents=True, exist_ok=True)
            target.write_bytes(client.get_bytes(url))
        except (SystemExit, jm.EndpointMissing, OSError) as error:
            log(f"  ! could not download attachment {safe}: {error}")
            continue

        record = dict(att)
        record["path"] = str(target)
        record["idsFound"] = []

        suffix = target.suffix.lower()
        if (suffix in TEXT_SUFFIXES or str(att.get("mimeType", "")).startswith("text/")) \
                and target.stat().st_size <= MAX_SCAN_BYTES:
            body = target.read_text(encoding="utf-8", errors="replace")
            record["idsFound"] = collect_inbox_ids(body + " " + safe)

        if suffix == ".eml":
            eml_dir.mkdir(parents=True, exist_ok=True)
            promoted = eml_dir / safe
            if not promoted.exists():
                shutil.copy2(target, promoted)
            record["emlPath"] = str(promoted)

        saved.append(record)
        log(f"  attachment {safe} ({target.stat().st_size} bytes)"
            + (f" — {len(record['idsFound'])} inbox id(s)" if record["idsFound"] else ""))
    return saved


# ── inbox-lookup ──────────────────────────────────────────────────────────────

def find_inbox_lookup() -> Path:
    for candidate in (Path(__file__).resolve().parents[1] / "inbox-lookup" / "inbox_lookup.py",
                      Path.home() / ".claude" / "skills" / "inbox-lookup" / "inbox_lookup.py"):
        if candidate.exists():
            return candidate
    sys.exit("Cannot find inbox_lookup.py — is the inbox-lookup skill installed?")


def run_inbox_lookup(ids: list[str], eml_dir: Path, json_out: Path, max_job_pages: int,
                     all_jobs: bool) -> list[dict[str, Any]]:
    """One process for the whole batch so the admin login happens once.

    A bad id makes inbox-lookup exit, taking the batch with it, so fall back to one process per
    id and keep going — a ticket that quotes one stale id should still yield the other five.
    """
    script = find_inbox_lookup()

    def invoke(batch: list[str], out: Path) -> list[dict[str, Any]] | None:
        cmd = [sys.executable, str(script), *batch,
               "--json", "--out", str(out), "--eml", str(eml_dir),
               "--max-job-pages", str(max_job_pages)]
        if all_jobs:
            cmd.append("--all-jobs")
        result = subprocess.run(cmd, text=True)
        if result.returncode != 0 or not out.exists():
            return None
        payload = json.loads(out.read_text(encoding="utf-8"))
        return payload if isinstance(payload, list) else [payload]

    eml_dir.mkdir(parents=True, exist_ok=True)
    json_out.parent.mkdir(parents=True, exist_ok=True)

    reports = invoke(ids, json_out)
    if reports is not None:
        return reports

    log("  batch lookup failed; retrying one id at a time")
    collected: list[dict[str, Any]] = []
    for inbox_id in ids:
        single = json_out.parent / f"inbox_lookup_{inbox_id}.json"
        one = invoke([inbox_id], single)
        if one is None:
            log(f"  ! {inbox_id} could not be fetched — skipping")
            continue
        collected.extend(one)
    json_out.write_text(json.dumps(collected, indent=2), encoding="utf-8")
    return collected


# ── email identity ────────────────────────────────────────────────────────────

def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip().lower()


def email_identity(path: Path) -> dict[str, Any]:
    """Identify an email by what it *is*, not by how it arrived.

    Two inbox items are the same reproduction when the sender, subject, body text and every
    attachment payload match. Message-ID is recorded but deliberately not the key: a court that
    resends the same notice mints a new one, and that is still one email to reproduce. Attachment
    payloads are hashed because sibling notices routinely share a body and differ only in the
    attached PDF.
    """
    info: dict[str, Any] = {"emlPath": str(path), "emlBytes": path.stat().st_size}
    try:
        message = email.message_from_bytes(path.read_bytes(), policy=email.policy.default)
    except Exception as error:  # a malformed .eml must not sink the run
        info["parseError"] = str(error)
        info["contentHash"] = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        return info

    info["messageId"] = (message.get("Message-ID") or "").strip() or None
    info["from"] = (message.get("From") or "").strip()
    info["to"] = (message.get("To") or "").strip()
    info["subject"] = (message.get("Subject") or "").strip()
    info["date"] = (message.get("Date") or "").strip()

    body_parts: list[str] = []
    attachments: list[str] = []
    for part in message.walk():
        if part.is_multipart():
            continue
        content_type = part.get_content_type()
        payload = part.get_payload(decode=True) or b""
        if content_type in ("text/plain", "text/html"):
            body_parts.append(normalize_text(payload.decode("utf-8", errors="replace")))
        else:
            attachments.append(f"{part.get_filename() or content_type}:"
                               f"{hashlib.sha256(payload).hexdigest()[:16]}")

    info["attachmentCount"] = len(attachments)
    info["attachmentNames"] = [a.split(":")[0] for a in attachments]

    fingerprint = "\n".join([
        normalize_text(info["from"]),
        normalize_text(info["subject"]),
        " ".join(sorted(body_parts)) or hashlib.sha256(path.read_bytes()).hexdigest(),
        " ".join(sorted(attachments)),
    ])
    info["contentHash"] = hashlib.sha256(fingerprint.encode()).hexdigest()[:16]
    return info


def locate_eml(inbox_id: str, eml_dir: Path) -> Path | None:
    matches = sorted(p for p in eml_dir.glob("*.eml") if inbox_id in p.name)
    return matches[0] if matches else None


# ── failure signatures ────────────────────────────────────────────────────────

def normalize_signature(message: str) -> str:
    out = message or ""
    for pattern, placeholder in NOISE_PATTERNS:
        out = pattern.sub(placeholder, out)
    return re.sub(r"\s+", " ", out).strip()


# Only fold a trailing `: value` away when the text before the colon is substantial enough to
# identify the failure on its own. Guards short messages like "Error: disk full", where the part
# after the colon *is* the message.
MIN_STEM = 20


def signature_template(message: str) -> str:
    """The reusable shape of an error message, with its per-notice payload removed.

    "Unable to determine county from Court Location: Fulton" and the same line ending in "Cobb"
    are one missing-mapping problem, not two — the court name is the data, not the defect. Numbers
    and ids are already handled by normalize_signature; this covers the alphabetic values that
    these messages append after a colon.
    """
    normalized = normalize_signature(message)
    stem, separator, value = normalized.rpartition(": ")
    if separator and len(stem) >= MIN_STEM and value:
        return f"{stem}: <VALUE>"
    return normalized


def top_app_frame(stack_trace: str, app_package: str) -> str:
    """The first frame in our own code — where the bug actually lives, as opposed to the
    framework frame that happened to raise."""
    for line in (stack_trace or "").splitlines():
        stripped = line.strip()
        if stripped.startswith("at ") and app_package in stripped:
            return stripped[3:]
    for line in (stack_trace or "").splitlines():
        if line.strip().startswith("at "):
            return line.strip()[3:]
    return ""


def summarize_item(report: dict[str, Any], eml_dir: Path, app_package: str) -> dict[str, Any]:
    fields = report.get("fields") or {}
    jobs = (report.get("processJobs") or []) + (report.get("dmsJobs") or [])
    failure = report.get("lastFailure") or {}

    histogram = Counter(job.get("errorException", "").strip()
                        for job in jobs if (job.get("errorException") or "").strip())

    exception = (failure.get("errorException") or "").strip()
    raw_message = (failure.get("errorMessage") or "").strip()
    trace = failure.get("stackTrace") or ""

    item = {
        "inboxId": report.get("inboxId"),
        "detailsUrl": report.get("detailsUrl"),
        "firm": fields.get("Firm"),
        "processor": fields.get("Processor"),
        "status": fields.get("Status"),
        "actionRequired": fields.get("Action Required"),
        "disposition": fields.get("Disposition"),
        "dispositionText": fields.get("Disposition Text"),
        "created": fields.get("Created"),
        # None, not 0, when inbox-lookup could not read the jobs table: a bare 0 reads as "this
        # notice never ran" and is exactly the confusion that cost the ECFX-17565 run its stack
        # traces. Rendered as "?" in the report.
        "attemptCount": None if report.get("jobsUnreadable") else len(jobs),
        "jobsUnreadable": bool(report.get("jobsUnreadable")),
        "exceptionHistogram": dict(histogram),
        "exception": exception,
        "errorMessage": raw_message,
        "normalizedMessage": normalize_signature(raw_message),
        "signatureTemplate": signature_template(raw_message),
        "topAppFrame": top_app_frame(trace, app_package),
        "stackTrace": trace,
        "stackHead": "\n".join(trace.splitlines()[:12]),
    }

    eml = locate_eml(str(report.get("inboxId")), eml_dir)
    item["email"] = email_identity(eml) if eml else None
    return item


def cluster_issues(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Group items that share a root cause.

    The key is exception class + message template + the first frame in our own code. Two items
    throwing the same exception from different call sites are different bugs; the same call site
    with a different court name or case number in the message is one.

    The grouping is deliberately conservative — it merges only what is provably the same shape.
    Every distinct raw message in a cluster is kept in `distinctMessages` so the model can split
    a cluster it can see is really two problems.
    """
    groups: "OrderedDict[tuple[str, str, str], list[dict[str, Any]]]" = OrderedDict()
    for item in items:
        key = (item.get("exception") or "(no exception recorded)",
               item.get("signatureTemplate") or "",
               item.get("topAppFrame") or "")
        groups.setdefault(key, []).append(item)

    ordered = sorted(groups.items(), key=lambda kv: len(kv[1]), reverse=True)
    issues = []
    for index, ((exception, template, frame), members) in enumerate(ordered, start=1):
        emails = {m["email"]["contentHash"] for m in members if m.get("email")}
        distinct = list(OrderedDict.fromkeys(
            m.get("errorMessage") for m in members if m.get("errorMessage")))
        issues.append({
            "id": f"issue-{index}",
            "exception": exception,
            "signatureTemplate": template,
            "distinctMessages": distinct,
            "topAppFrame": frame,
            "itemCount": len(members),
            "uniqueEmailCount": len(emails) or None,
            "inboxIds": [m["inboxId"] for m in members],
            "firms": sorted({m["firm"] for m in members if m.get("firm")}),
            "processors": sorted({m["processor"] for m in members if m.get("processor")}),
            "sampleErrorMessage": members[0].get("errorMessage"),
            "sampleStackHead": members[0].get("stackHead"),
            "emls": sorted({m["email"]["emlPath"] for m in members if m.get("email")}),
        })
    return issues


def dedupe_emails(items: list[dict[str, Any]], orphan_emls: list[Path]) -> list[dict[str, Any]]:
    """One entry per distinct email, listing every inbox item that carried it."""
    groups: "OrderedDict[str, dict[str, Any]]" = OrderedDict()

    for item in items:
        info = item.get("email")
        if not info:
            continue
        entry = groups.setdefault(info["contentHash"], {
            "contentHash": info["contentHash"],
            "subject": info.get("subject"),
            "from": info.get("from"),
            "date": info.get("date"),
            "attachmentNames": info.get("attachmentNames", []),
            "emlPath": info["emlPath"],
            "inboxIds": [],
            "messageIds": [],
            "source": "inbox-item",
        })
        entry["inboxIds"].append(item["inboxId"])
        if info.get("messageId") and info["messageId"] not in entry["messageIds"]:
            entry["messageIds"].append(info["messageId"])

    for path in orphan_emls:
        info = email_identity(path)
        entry = groups.setdefault(info["contentHash"], {
            "contentHash": info["contentHash"],
            "subject": info.get("subject"),
            "from": info.get("from"),
            "date": info.get("date"),
            "attachmentNames": info.get("attachmentNames", []),
            "emlPath": info["emlPath"],
            "inboxIds": [],
            "messageIds": [m for m in [info.get("messageId")] if m],
            "source": "jira-attachment",
        })
        entry.setdefault("alsoAttached", True)

    for entry in groups.values():
        entry["duplicateCount"] = max(len(entry["inboxIds"]) - 1, 0)
        entry["resend"] = len(entry["messageIds"]) > 1
    return list(groups.values())


# ── report ────────────────────────────────────────────────────────────────────

PENDING = "_(pending classification — see SKILL.md step 5)_"


def render_markdown(data: dict[str, Any]) -> str:
    ticket, issues = data["ticket"], data["issues"]
    emails, items = data["uniqueEmails"], data["items"]
    out: list[str] = []

    out.append(f"# {ticket['key']} — Inbox research\n")
    out.append(f"> {ticket.get('summary') or '(no summary)'}\n")
    out.append(f"- **Status:** {ticket.get('status')} · **Priority:** {ticket.get('priority')} "
               f"· **Type:** {ticket.get('issueType')}")
    if ticket.get("labels"):
        out.append(f"- **Labels:** {', '.join(ticket['labels'])}")
    out.append(f"- **Reporter:** {ticket.get('reporter')} · **Assignee:** {ticket.get('assignee')}")
    if ticket.get("linkedKeys"):
        out.append(f"- **Linked:** {', '.join(ticket['linkedKeys'])}")
    out.append(f"- **Generated by:** `research-jira-bug`\n")

    out.append("## Verdict\n")
    out.append(f"- **Inbox items examined:** {len(items)}")
    out.append(f"- **Unique emails (after dedupe):** {len(emails)}")
    out.append(f"- **Distinct failure signatures:** {len(issues)}")
    out.append(f"- **Assessment:** {PENDING}\n")

    if data.get("unresolvedIds"):
        out.append(f"> ⚠️ Referenced but not fetched: {', '.join(data['unresolvedIds'])}\n")

    out.append("## Issues\n")
    for issue in issues:
        out.append(f"### {issue['id']} — {PENDING}\n")
        out.append(f"- **Exception:** `{issue['exception']}`")
        out.append(f"- **Signature:** `{issue['signatureTemplate'] or '(no message)'}`")
        if issue.get("topAppFrame"):
            out.append(f"- **Throws at:** `{issue['topAppFrame']}`")
        out.append(f"- **Inbox items:** {issue['itemCount']} "
                   f"· **Unique emails:** {issue.get('uniqueEmailCount') or 0}")
        if len(issue.get("distinctMessages") or []) > 1:
            out.append(f"- **Message varies across {len(issue['distinctMessages'])} values:** "
                       + ", ".join(f"`{m[:60]}`" for m in issue["distinctMessages"][:6]))
        if issue["firms"]:
            out.append(f"- **Firms:** {', '.join(issue['firms'])}")
        if issue["processors"]:
            out.append(f"- **Processors:** {', '.join(issue['processors'])}")
        out.append(f"- **Taxonomy bucket:** {PENDING}")
        out.append(f"- **Root cause:** {PENDING}\n")

        out.append("<details><summary>Sample error + stack head</summary>\n")
        out.append("```")
        out.append((issue.get("sampleErrorMessage") or "(no message)")[:1500])
        out.append("")
        out.append(issue.get("sampleStackHead") or "(no stack trace captured)")
        out.append("```\n</details>\n")

        out.append("**Inbox items in this issue**\n")
        out.append("| Inbox id | Firm | Processor | Attempts | Status | EML |")
        out.append("|---|---|---|---|---|---|")
        for item in items:
            if item["inboxId"] not in issue["inboxIds"]:
                continue
            eml = Path(item["email"]["emlPath"]).name if item.get("email") else "—"
            out.append(f"| `{item['inboxId']}` | {item.get('firm') or '—'} "
                       f"| {item.get('processor') or '—'} | "
                       f"{'?' if item.get('jobsUnreadable') else item.get('attemptCount')} "
                       f"| {item.get('status') or '—'} | `emls/{eml}` |")
        out.append("")
        out.append(f"**Handoff:** `/fix-jira-bug {ticket['key']} --scope {issue['id']}` "
                   f"— reproduce with `{', '.join(f'emls/{Path(p).name}' for p in issue['emls'][:3]) or '(no EML)'}`\n")

    out.append("## Unique emails\n")
    out.append("| # | Subject | From | Carried by | Dupes | EML |")
    out.append("|---|---|---|---|---|---|")
    for index, entry in enumerate(emails, start=1):
        carried = ", ".join(f"`{i}`" for i in entry["inboxIds"]) or f"_{entry['source']}_"
        out.append(f"| {index} | {(entry.get('subject') or '(none)')[:70]} "
                   f"| {(entry.get('from') or '')[:40]} | {carried} "
                   f"| {entry['duplicateCount']}{' (resend)' if entry.get('resend') else ''} "
                   f"| `emls/{Path(entry['emlPath']).name}` |")
    out.append("")

    out.append("## Ticket description\n")
    out.append("```")
    out.append(ticket.get("descriptionText") or "(empty)")
    out.append("```\n")

    if ticket.get("comments"):
        out.append("## Comments\n")
        for comment in ticket["comments"]:
            out.append(f"**{comment.get('author')}** — {comment.get('created')}\n")
            out.append("```")
            out.append(comment.get("text") or "")
            out.append("```\n")

    if data.get("attachments"):
        out.append("## Attachments\n")
        for att in data["attachments"]:
            ids = f" — ids: {', '.join(att['idsFound'])}" if att.get("idsFound") else ""
            out.append(f"- `{att.get('filename')}` ({att.get('size')} bytes){ids}")
        out.append("")

    out.append("---\n")
    out.append("_Raw data: `raw/research.json`. Emails: `emls/`._")
    return "\n".join(out) + "\n"


# ── main ──────────────────────────────────────────────────────────────────────

def default_root() -> Path:
    """`/workspace/shared` is where fix-jira-bug looks; use it when it exists so the two skills
    chain with no argument passing, and fall back to the cwd on a developer machine."""
    if os.environ.get("TICKET_RESEARCH_DIR"):
        return Path(os.environ["TICKET_RESEARCH_DIR"])
    shared = Path("/workspace/shared")
    return shared if shared.is_dir() else Path.cwd()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ticket", help="Jira key, e.g. ECFX-16173")
    parser.add_argument("--out", type=Path, help="parent directory (default /workspace/shared "
                                                 "when it exists, else the cwd)")
    parser.add_argument("--ids", nargs="*", default=[], metavar="INBOX_ID",
                        help="extra inbox ids to include beyond those found on the ticket")
    parser.add_argument("--app-package", default=DEFAULT_APP_PACKAGE,
                        help=f"package prefix that marks our own stack frames "
                             f"(default {DEFAULT_APP_PACKAGE})")
    parser.add_argument("--max-job-pages", type=int, default=3,
                        help="attempt pages to open per item, newest failures first (default 3)")
    parser.add_argument("--all-jobs", action="store_true",
                        help="open every attempt (slow; use when the failure mode changed)")
    parser.add_argument("--no-attachments", action="store_true",
                        help="skip downloading Jira attachments")
    parser.add_argument("--skip-lookup", action="store_true",
                        help="reuse raw/inbox_lookup.json instead of hitting the admin site")
    parser.add_argument("--env-file", help="explicit Jira credentials file")
    args = parser.parse_args(argv)

    ticket_key = args.ticket.strip().upper()
    root = (args.out or default_root()) / ticket_key
    eml_dir, raw_dir = root / "emls", root / "raw"
    root.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    log(f"→ {root}")

    host, user, token = jm.load_credentials(args.env_file)
    client = jm.JiraClient(host, user, token, verbose=True)

    log(f"Reading {ticket_key} …")
    ticket = read_ticket(client, ticket_key)

    sources: dict[str, list[str]] = {}
    for found in collect_inbox_ids(ticket["descriptionText"]):
        sources.setdefault(found, []).append("description")
    for comment in ticket["comments"]:
        for found in collect_inbox_ids(comment["text"]):
            sources.setdefault(found, []).append(f"comment:{comment['id']}")

    attachments: list[dict[str, Any]] = []
    if not args.no_attachments and ticket["attachments"]:
        log(f"Downloading {len(ticket['attachments'])} attachment(s) …")
        attachments = download_attachments(client, ticket, raw_dir / "attachments", eml_dir)
        for att in attachments:
            for found in att.get("idsFound", []):
                sources.setdefault(found, []).append(f"attachment:{att.get('filename')}")

    for extra in args.ids:
        normalized = extra if extra.startswith("inbox_") else f"inbox_{extra}"
        sources.setdefault(normalized, []).append("--ids")

    inbox_ids = list(sources)
    log(f"{len(inbox_ids)} inbox id(s) referenced: {', '.join(inbox_ids) or '(none)'}")

    lookup_json = raw_dir / "inbox_lookup.json"
    reports: list[dict[str, Any]] = []
    if inbox_ids and args.skip_lookup and lookup_json.exists():
        payload = json.loads(lookup_json.read_text(encoding="utf-8"))
        reports = payload if isinstance(payload, list) else [payload]
        log(f"Reusing {lookup_json} ({len(reports)} report(s))")
    elif inbox_ids:
        log("Fetching inbox items (inbox-lookup handles the admin login) …")
        reports = run_inbox_lookup(inbox_ids, eml_dir, lookup_json,
                                   args.max_job_pages, args.all_jobs)

    items = [summarize_item(report, eml_dir, args.app_package) for report in reports]
    fetched = {item["inboxId"] for item in items}
    unresolved = [i for i in inbox_ids if i not in fetched]

    item_emls = {item["email"]["emlPath"] for item in items if item.get("email")}
    orphans = [p for p in sorted(eml_dir.glob("*.eml")) if str(p) not in item_emls]

    issues = cluster_issues(items)
    emails = dedupe_emails(items, orphans)

    if not items and not orphans:
        log("! No inbox items and no EMLs — the ticket may reference neither. "
            "Check the description, or pass --ids.")

    data = {
        "ticket": ticket,
        "generatedFor": ticket_key,
        "outputDir": str(root),
        "inboxIdSources": sources,
        "unresolvedIds": unresolved,
        "attachments": attachments,
        "items": items,
        "uniqueEmails": emails,
        "issues": issues,
        "verdict": {
            "itemCount": len(items),
            "uniqueEmailCount": len(emails),
            "issueCount": len(issues),
        },
    }

    (raw_dir / "research.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    (root / f"{ticket_key}.md").write_text(render_markdown(data), encoding="utf-8")

    log(f"\n{len(items)} item(s) · {len(emails)} unique email(s) · {len(issues)} issue(s)")
    for issue in issues:
        log(f"  {issue['id']}: {issue['exception']} ×{issue['itemCount']} "
            f"— {issue['signatureTemplate'][:80]}")
    if unresolved:
        log(f"  ! unresolved ids: {', '.join(unresolved)}")
    log(f"\nWrote {root / (ticket_key + '.md')}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
