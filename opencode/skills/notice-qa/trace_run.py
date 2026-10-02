#!/usr/bin/env python3
"""Step 3 of a notice-QA run: follow a send_bundle.py run through dev01 and record every outcome.

    trace_run.py <run manifest .json> [--timeout 600] [--interval 20]

Finds the parent inbox item the webhook created after the send, confirms it SPLIT, finds its
children, maps each child back to the prod notice it came from (creation order), and reports
each child's attempt history. Polls until every child has settled.

Duplicates are resolved to the dev item that already holds the document:
  * "duplicate of X" (Redis strong indicator) and "[DUPLICATE_ENVELOPE] … to original item X"
    name the original directly;
  * "Duplicate - Document already in system" (hasEnvelope true) does not, so the original is found
    in dev Loki: the latest item that checked the same (caseId, courtEnvelopeId), got "returning
    false" (i.e. created the envelope) and then SUCCEEDED.
Then each duplicate is classified:
  * sameTicket          — the original is a child from a run for the same ticket: a valid test of
                          dedup between the ticket's own notices;
  * previouslyProcessed — the original was processed before and outside this ticket's runs: the
                          notice was NOT re-tested; the original's dev id goes in the ticket so it
                          can be requeued manually.

Writes <manifest>.result.json beside the manifest and prints it.

Everything is read from dev Loki (survives pod restarts and dev redeploys; needs the DuploCloud
login that duplo-jit caches). Children are identified by their PublicId, which is a UUIDv1: they
are created inside the parent's split job, so their creation times fall inside that job's window,
and sorting them by UUID time gives attachment order. The one remaining guess is the parent: the
webhook logs nothing that identifies the email, so it is the first SPLIT parent for the firm after
the send with the right number of children (two such parents → a warning).
"""
import argparse
import base64
import datetime
import json
import pathlib
import re
import sys
import time
import uuid

import qa_common as qc

TS = r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})"
TERMINAL = {"SUCCEEDED", "FAILED", "MANUAL", "CANCELED", "POST_PROCESSING"}   # DELAYED / RETRY are not
# A FAILED CaseNotFound is not final when the firm has auto case creation for that jurisdiction:
# AutoCaseCreationConsumer creates the case and requeues within ~1 s (seen 2026-09-28).
AUTO_REQUEUE_GRACE_S = 180
LOKI_LOOKBACK_DAYS = 90
PARENT_WINDOW = datetime.timedelta(minutes=5)   # Postmark → webhook took 2–7 s in every test   # queried in 30-day slices; older than dev Loki retention simply returns nothing


def ts(line):
    return datetime.datetime.strptime(re.match(TS, line).group(1), "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=datetime.timezone.utc)


# ── outcomes ─────────────────────────────────────────────────────────────────

def child_outcome(cid, firm, lines):
    """Per-attempt history for one child; the top-level fields are the LAST attempt's."""
    jobs, cur, dup = [], None, {"envelopes": [], "originals": []}
    for l in lines:
        if cid in l:
            m = re.search(r"hasEnvelope called: inboxId=\S+ caseId=(\S+) courtEnvelopeId=(\S+)", l)
            if m:
                dup["envelopes"].append({"caseId": m.group(1), "courtEnvelopeId": m.group(2), "exists": None})
            m = re.search(r"hasEnvelope returning (true|false): inboxId=\S+ courtEnvelopeId=(\S+)", l)
            if m:
                for e in dup["envelopes"]:
                    if e["courtEnvelopeId"] == m.group(2) and e["exists"] is None:
                        e["exists"] = m.group(1) == "true"
            m = (re.search(rf"{cid}, classifying item as duplicate of (inbox_\w+)", l)
                 or re.search(rf"[Ll]inked inbox item {cid} to original item (inbox_\w+)", l))
            if m:
                dup["originals"].append({"id": m.group(1), "via": "logged by the duplicate path"})
        s = re.search(rf"{firm}:{cid} Job (\S+) starting", l)
        if s:
            cur = {"job": s.group(1), "at": l[:23], "status": None, "reason": None, "exception": None}
            jobs.append(cur)
            continue
        if not cur:
            continue
        if cur["job"] in l:
            for key, pat in (("reason", r"(?:reason|error)=(.*)$"), ("exception", r"exceptionType=(\w+)")):
                r = re.search(pat, l)
                if r and not cur[key]:
                    cur[key] = r.group(1)
            if "Delaying job" in l:
                cur["reason"] = cur["reason"] or "delayed by subject/sender dedup window"
        c = re.search(rf"{firm}:{cid} job \S+ completed in \d+ ms with status (\w+) and disposition (\w*) by (\S+)", l)
        if c:
            cur.update(status=c.group(1), disposition=c.group(2) or None,
                       processor=None if c.group(3) == "null" else c.group(3))
    last = jobs[-1] if jobs else {}
    # WARN/ERROR lines and [MARKER] lines: QA notes often name a log marker to look for
    markers = [l[:300] for l in lines if (" WARN " in l or " ERROR " in l or re.search(r"\[[A-Z][A-Z0-9_-]{4,}\]", l))
               and "ECFX-14435-DIAG" not in l]
    out = {"id": cid, "logMarkers": markers[:15], "status": last.get("status"), "disposition": last.get("disposition"),
           "processor": last.get("processor"), "reason": last.get("reason"), "exception": last.get("exception"),
           "attempts": jobs}
    if (out["reason"] or "").startswith("Duplicate"):
        out["duplicate"] = dup
    return out


def is_settled(child):
    if child["status"] not in TERMINAL:
        return False
    if child["exception"] == "CaseNotFoundException":
        return (qc.utcnow() - ts(child["attempts"][-1]["at"])).total_seconds() > AUTO_REQUEUE_GRACE_S
    return True


# ── duplicate resolution ─────────────────────────────────────────────────────

def envelope_creator(case_id, env_id, before):
    """Dev item that created (caseId, courtEnvelopeId) most recently before `before` and SUCCEEDED."""
    since = before - datetime.timedelta(days=LOKI_LOOKBACK_DAYS)
    lines = qc.loki_query('{namespace="%s"} |= "courtEnvelopeId=%s" |= "hasEnvelope"' % (qc.DEV_NS, env_id), since, before)
    in_case = {m.group(1) for l in lines if (m := re.search(rf"called: inboxId=(\S+) caseId={case_id} ", l))}
    creators = [(ts(l), m.group(1)) for l in lines
                if (m := re.search(r"returning false: inboxId=(\S+) ", l)) and m.group(1) in in_case]
    for at, iid in sorted(creators, reverse=True):
        done = qc.loki_query('{namespace="%s"} |= "%s job" |= "completed in"' % (qc.DEV_NS, iid), at - datetime.timedelta(minutes=1), before)
        final = [re.search(r"^(?:.*? - )?(\w+):\S+ job .* with status (\w+) and disposition (\w*)", l) for l in done]
        final = [f for f in final if f]
        if final and final[-1].group(2) == "SUCCEEDED":
            return {"id": iid, "firm": final[-1].group(1), "createdEnvelopeAt": at.isoformat(),
                    "disposition": final[-1].group(3) or None, "via": "dev Loki: first to create the envelope"}
    return None


def batch_of(manifest):
    return manifest.get("batch") or re.sub(r"-p\d+$", "", manifest["run"])


def classify_duplicate(origins, same_batch_children):
    """B1: a duplicate is a valid in-run dedup test ONLY when its original is a child of this same
    send (batch). An original from an earlier batch — e.g. the first QA pass before a fix was
    deployed — means this notice was never processed by the current image: NOT TESTED, requeue it."""
    if not origins:
        return "unresolved"
    return "sameTicket" if origins <= same_batch_children else "previouslyProcessed"


def same_batch_children(result, manifest, runs_dir):
    ids = {c["id"] for c in result["children"]}
    for f in runs_dir.glob("*.result.json"):
        mf = f.with_name(f.name.replace(".result.json", ".json"))
        if mf.exists() and batch_of(json.loads(mf.read_text())) == batch_of(manifest):
            ids |= {c["id"] for c in json.loads(f.read_text()).get("children", [])}
    return ids


def resolve_duplicates(result, manifest, runs_dir):
    same = same_batch_children(result, manifest, runs_dir)
    for c in result["children"]:
        dup = c.get("duplicate")
        if not dup:
            continue
        if not dup["originals"]:
            for e in dup["envelopes"]:
                if e["exists"]:
                    o = envelope_creator(e["caseId"], e["courtEnvelopeId"], ts(c["attempts"][-1]["at"]))
                    if o and o["id"] not in {x["id"] for x in dup["originals"]}:
                        dup["originals"].append(o)
        dup["classification"] = classify_duplicate({o["id"] for o in dup["originals"]}, same)
        for o in dup["originals"]:
            o["devAdmin"] = qc.dev_admin_link(o["id"])
            o["fromThisBatch"] = o["id"] in same


# ── trace ────────────────────────────────────────────────────────────────────

def uuid_time(public_id):
    """Creation time of a PublicId: they are UUIDv1 (100 ns resolution, monotonic per JVM)."""
    e = public_id.rsplit("_", 1)[1].upper()
    u = uuid.UUID(bytes=base64.b32decode(e + "=" * ((8 - len(e) % 8) % 8)))
    return u.time if u.version == 1 else None


def uuid_dt(public_id):
    t = uuid_time(public_id)
    return datetime.datetime(1582, 10, 15, tzinfo=datetime.timezone.utc) + datetime.timedelta(microseconds=t // 10)


def q(filters, since, until=None):
    return qc.loki_query('{namespace="%s"} %s' % (qc.DEV_NS, filters), since, until, limit=2000)


def webhook_parents(firm, since, until):
    """Inbox ids the webhook created for this firm in the window, oldest first.

    The webhook logs "Subdomain <firm> fetched" and then "| <inboxId> | BACKEND RECEIPTS COMPLETED
    PROCESSING" on the same virtual thread; it logs nothing that identifies the email itself.
    """
    lines = q('|= "PostmarkController" |~ "Subdomain %s fetched|BACKEND RECEIPTS COMPLETED"' % firm, since, until)
    pending, out = {}, []
    for l in lines:
        thread = re.search(r"\[(virtual-executor[^\]]*)\]", l)
        thread = thread.group(1) if thread else None
        if f"Subdomain {firm} fetched" in l:
            pending[thread] = ts(l)
        m = re.search(r"\| (inbox_\w+) \| BACKEND RECEIPTS COMPLETED PROCESSING", l)
        if m and thread in pending:
            out.append(m.group(1)); pending.pop(thread)
    return out


def split_children(firm, parent, n, until):
    """(split info, [child ids in attachment order]) for a parent, or (info, None) if not a split."""
    lines = q('|= "%s:%s "' % (firm, parent), uuid_dt(parent) - datetime.timedelta(seconds=5), until)
    # receipt job lines only — the DMS job logs "<firm>:<id> DMS Job … starting / … completed in" too
    start = next((ts(l) for l in lines if re.search(r" Job inbox_job_\S+ starting", l)), None)
    done = [l for l in lines if re.search(r" job inbox_job_\S+ completed in \d+ ms with status", l)]
    if not (start and done):
        return None, None
    m = re.search(r"with status (\w+) and disposition (\w*) by (\S+)", done[-1])
    info = {"id": parent, "status": m.group(1), "disposition": m.group(2) or None, "processor": m.group(3),
            "devAdmin": qc.dev_admin_link(parent)}
    if info["disposition"] != "SPLIT":
        return info, None
    lo, hi = uuid_time_of(start), uuid_time_of(ts(done[-1]))
    # Children are created inside the split job, so their UUID times fall in [job start, job end];
    # sorting by UUID time recovers attachment order exactly (verified 2026-09-28).
    starts = q('|~ `%s:inbox_[a-z0-9]+ Job [^ ]+ starting`' % firm, start, until)
    ids = {mm.group(1) for l in starts if (mm := re.search(rf"{firm}:(inbox_\w+) Job", l))}
    kids = sorted((i for i in ids if i != parent and lo <= uuid_time(i) <= hi), key=uuid_time)
    info["childCount"] = len(kids)
    return info, kids


def uuid_time_of(dt):
    return int((dt - datetime.datetime(1582, 10, 15, tzinfo=datetime.timezone.utc)).total_seconds() * 1e7)


def child_lines(cid, until):
    """Every line about one child: its own id, plus the per-job lines that only carry the job id."""
    since = uuid_dt(cid) - datetime.timedelta(seconds=5)
    lines = q('|= "%s"' % cid, since, until)
    jobs = {m.group(1) for l in lines if (m := re.search(rf"{cid} Job (\S+) starting", l))}
    if jobs:
        lines += q('|~ "%s"' % "|".join(sorted(jobs)), since, until)
    # Only application log lines. The id also appears in ecfx-admin access-log lines, which have no
    # leading timestamp: any view of the item's admin page ("GET /inbox_item/details/?id=<id>") or a
    # Prevent Requeue click ("POST /inbox_item/get/<id>/prevent_requeue"). Those crashed the sort
    # below (2026-09-28: 36 such lines for one child).
    return sorted({l for l in lines if re.match(TS, l)}, key=ts)


LOG_CHECKS = {"expect": [], "forbid": []}   # set from --expect-log / --forbid-log


def log_checks(lines):
    """Count each --expect-log / --forbid-log pattern in a child's lines (all levels, INFO included)."""
    out = {}
    for kind in ("expect", "forbid"):
        for pat in LOG_CHECKS[kind]:
            n = sum(1 for l in lines if re.search(pat, l))
            out[pat] = {"kind": kind, "count": n, "ok": (n > 0) if kind == "expect" else (n == 0)}
    return out


def claimed_parents(manifest):
    """Parents already attributed to some other run (any ticket) — never adopt those."""
    claimed = set()
    for f in qc.QA_HOME.glob("*/runs/*.result.json"):
        r = json.loads(f.read_text())
        if r.get("run") != manifest["run"] and r.get("matched") and (r.get("parent") or {}).get("id"):
            claimed.add(r["parent"]["id"])
    return claimed


def chunk_window_end(manifest):
    """A chunk's parent must arrive before the NEXT chunk of the same batch was sent (chunks go out
    20 s apart; Postmark delivered in 2–7 s every time measured). Without this, a chunk Postmark held
    silently adopts the next chunk's parent (M7). A chunk delayed past that point is reported as not
    delivered rather than mis-attributed."""
    sent = datetime.datetime.fromisoformat(manifest["sentAt"])
    runs_dir = qc.ticket_dir(manifest["ticket"]) / "runs" if manifest.get("ticket") else None
    later = []
    if runs_dir:
        for f in runs_dir.glob("*.json"):
            if f.name.endswith(".result.json"):
                continue
            m = json.loads(f.read_text())
            if batch_of(m) == batch_of(manifest) and m["run"] != manifest["run"]:
                t = datetime.datetime.fromisoformat(m["sentAt"])
                if t > sent:
                    later.append(t)
    return min(later + [sent + PARENT_WINDOW])


def select_candidates(parents, sent, upper, claimed, limit=5):
    """parents: [(inbox id, created)] from the webhook. Keep unclaimed ones created in [sent-5s, upper)."""
    lo = sent - datetime.timedelta(seconds=5)
    return [p for p, at in parents if lo <= at < upper and p not in claimed][:limit]


def trace(manifest, known_parent=None):
    firm, notices = manifest["firm"], manifest["notices"]
    sent = datetime.datetime.fromisoformat(manifest["sentAt"])
    until = qc.utcnow()
    result = {"run": manifest["run"], "ticket": manifest.get("ticket"), "firm": firm,
              "parent": None, "children": [], "mappedBy": "UUIDv1 creation time within the parent's split job"}

    if known_parent:
        candidates = [known_parent]
    else:
        upper = chunk_window_end(manifest)
        seen = webhook_parents(firm, sent - datetime.timedelta(seconds=5), until)
        candidates = select_candidates([(p, uuid_dt(p)) for p in seen], sent, upper, claimed_parents(manifest))
    result["parentCandidates"] = candidates
    matches = []
    for p in candidates:
        info, kids = split_children(firm, p, len(notices), until)
        if info and kids is not None and len(kids) == len(notices):
            matches.append((info, kids))
        elif info and not result["parent"]:
            result["parent"] = info          # e.g. IGNORED wrapper — reported, not adopted as a match
    if len(matches) > 1:
        # M7: never guess — two unclaimed parents with the right child count in this chunk's window
        # means the attribution is unknowable from logs; report it instead of taking the earliest.
        result["ambiguous"] = [info["id"] for info, _ in matches]
        result["warning"] = ("ambiguous: several unclaimed SPLIT parents with the right child count arrived in this "
                             "send's window (" + ", ".join(result["ambiguous"]) + ") — check them in the dev admin")
        return result
    if matches:
        result["matched"] = True
        info, kids = matches[0]
        result["parent"] = info
        for n, cid in zip(notices, kids):
            lines = child_lines(cid, until)
            child = child_outcome(cid, firm, lines)
            if LOG_CHECKS["expect"] or LOG_CHECKS["forbid"]:
                child["logChecks"] = log_checks(lines)
            child["source"] = n.get("sourceInboxId") or n["file"]
            child["file"] = n["file"]          # N10: an original and its make_variant copy share a source id
            result["children"].append(child)
    elif result["parent"] and result["parent"]["disposition"] != "SPLIT":
        result["parent"]["problem"] = "wrapper was not split — check the firm's accepted sender list"
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--timeout", type=int, default=0,
                    help="seconds; default scales with the notice count (each extra copy of a notice from the same "
                         "sender+subject is delayed ~90 s by dev's dedup window, and CaseNotFound gets 3 min)")
    ap.add_argument("--interval", type=int, default=20)
    ap.add_argument("--expect-log", action="append", default=[], metavar="REGEX",
                    help="a line the QA notes say must appear for each notice (any level, e.g. an INFO line); repeatable")
    ap.add_argument("--forbid-log", action="append", default=[], metavar="REGEX",
                    help="a line that must NOT appear for any notice (e.g. the old error); repeatable")
    a = ap.parse_args()
    LOG_CHECKS.update(expect=a.expect_log, forbid=a.forbid_log)
    mpath = pathlib.Path(a.manifest)
    manifest = json.loads(mpath.read_text())
    timeout = a.timeout or min(1800, 300 + 120 * len(manifest["notices"]))
    deadline = time.time() + timeout
    known = None
    sent = datetime.datetime.fromisoformat(manifest["sentAt"])
    while True:
        r = trace(manifest, known)
        if not r["parentCandidates"] and qc.utcnow() > sent + PARENT_WINDOW:
            # Postmark accepted the SMTP transaction but never called the dev webhook for this firm.
            r.update(settled=False, problem=(
                f"no inbox item was created for {manifest['firm']} within {PARENT_WINDOW} of the send: Postmark "
                "accepted the message but did not deliver it to dev (spam-blocked, held, or failing). Check the dev "
                "inbound server's activity in Postmark for this subject and Retry/Bypass it, or resend in smaller "
                "bundles (send_bundle.py --max-per-bundle)."))
            mpath.with_suffix(".result.json").write_text(json.dumps(r, indent=2))
            print(json.dumps(r, indent=2))
            return 4
        if r.get("matched"):
            known = r["parent"]["id"]
        kids = r["children"]
        done = bool(r.get("matched")) and len(kids) == len(manifest["notices"]) and all(is_settled(k) for k in kids)
        if done or time.time() > deadline:
            r["settled"] = done
            if r["parent"] and r["parent"]["disposition"] == "SPLIT" and len(kids) != len(manifest["notices"]):
                r["warning"] = f"expected {len(manifest['notices'])} children, found {len(kids)}"
            resolve_duplicates(r, manifest, mpath.parent)
            out = mpath.with_suffix(".result.json")
            out.write_text(json.dumps(r, indent=2))
            print(json.dumps(r, indent=2))
            return 0 if done else 2
        qc.log(f"waiting: parent={bool(r['parent'])} children={len(kids)}/{len(manifest['notices'])}")
        time.sleep(a.interval)


if __name__ == "__main__":
    sys.exit(main())
