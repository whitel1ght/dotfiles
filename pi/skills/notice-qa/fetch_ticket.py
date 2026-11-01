#!/usr/bin/env python3
"""Step 1 of a notice-QA run: read a Jira ticket and collect the notices it references.

    fetch_ticket.py ECFX-17643 [--ids inbox_a inbox_b] [--limit 25] [--no-lookup]

Writes ~/.cache/notice-qa/<TICKET>/ticket.json and emls/inbox_item_<id>.eml:

  * every inbox id in the description and comments, where it was found, and the logerr bot's
    label for it ("inbox_x - ECF" / "- Correspondence" / "- Unknown"), which is a hint at the
    expected outcome
  * the ticket's QA-notes comments verbatim (the main source of pass/fail criteria)
  * each notice's original bytes: reused from a local copy when one exists (the ticket folder,
    ~/Downloads, /workspace/shared/<TICKET>), otherwise downloaded from the prod admin site with
    the inbox-lookup skill, which also returns the prod status/processor/error

Exit codes: 0 ready · 3 needs a human (EMLs missing, or too many ids to QA without choosing).
"""
import argparse
import json
import pathlib
import re
import shutil
import sys

import qa_common as qc
import ecfx_tickets as et     # lib/: ticket reading, id collection, inbox-lookup runner (N2)

# The bot writes one id per line, then " - <label>". ADF renders it as "• `inbox_x` - ECF" (code mark)
# or "inbox_x <https://admin…?id=inbox_x>  - Correspondence → …" (link mark), so strip marks per line.
LABEL_RE = re.compile(r"^[\s•*`-]*(inbox_(?!job_)[0-9a-z]{20,32})[\s`]*[-–]\s*(.+?)\s*$")
LINK_MARK = re.compile(r"<https?://[^>]*>")


def labels_in(text):
    out = {}
    for line in text.splitlines():
        m = LABEL_RE.match(LINK_MARK.sub("", line))
        if m:
            out[m.group(1)] = m.group(2)
    return out
QA_NOTES_RE = re.compile(r"\b(QA notes|ADDENDUM to the QA notes|Test plan|How to test)\b", re.I)
NOT_IN_PROD = et.NOT_IN_PROD


def read_ticket(key):
    issue, texts = et.read_ticket(qc.jira_client(), key)
    return issue, issue["fields"], texts


OWN_COMMENT = re.compile(r"^\s*Notice QA \(dev01\)")          # jira_post.py's own comments
DEV_ADMIN_LINK = re.compile(r"<?https?://admin\.development\.[^\s>]*>?")   # dev ids are not prod notices


def collect(texts):
    """Inbox ids with where each was found. An id mentioned ONLY by customer (portal) accounts is
    flagged externalOnly: anyone who can comment on a ticket must not be able to choose which prod
    notices get downloaded and replayed into dev (Q2)."""
    items = {}
    for t in texts:
        text = t["text"]
        if OWN_COMMENT.match(text):
            continue
        text = DEV_ADMIN_LINK.sub("", text)
        labels = labels_in(text)
        external = (t.get("accountType") or "") in et.EXTERNAL_ACCOUNT_TYPES
        for iid in et.collect_inbox_ids(text):
            it = items.setdefault(iid, {"id": iid, "label": None, "sources": [], "sourceAuthors": [], "externalOnly": True})
            src = t["where"] if t["where"] == "description" else f"comment {t['id']} ({t['author']}, {(t['created'] or '')[:10]})"
            if src not in it["sources"]:
                it["sources"].append(src)
                it["sourceAuthors"].append({"author": t.get("author"), "accountType": t.get("accountType")})
            it["externalOnly"] = it["externalOnly"] and external
            if labels.get(iid) and not it["label"]:
                it["label"] = labels[iid]
    return list(items.values())


SECTION_RE = re.compile(r"^\s*\d+\.\s+\S", re.M)   # "1. The ticket's notice", "3. Duplicate copies", …


def qa_excerpts(iid, qa_notes, limit=1500):
    """The QA-notes section(s) that mention this inbox id — its expected result, verbatim."""
    out = []
    for note in qa_notes:
        text = note["text"]
        starts = [m.start() for m in SECTION_RE.finditer(text)] or [0]
        bounds = list(zip(starts, starts[1:] + [len(text)]))
        for a, b in bounds:
            if iid in text[a:b]:
                out.append(text[a:b].strip()[:limit])
    return out


def local_copy(iid, ticket):
    names = [f"inbox_item_{iid}.eml", f"inbox_item_{iid} (1).eml", f"{iid}.eml"]
    roots = [qc.ticket_dir(ticket) / "emls", pathlib.Path.home() / "Downloads",
             pathlib.Path("/workspace/shared") / ticket / "emls"]
    for root in roots:
        for name in names:
            if (root / name).exists():
                return root / name
        if root.exists() and root.name == "emls":
            hit = next(root.rglob(f"*{iid}*.eml"), None)
            if hit:
                return hit
    return None


def prod_lookup(ids, eml_dir, out_json):
    """inbox-lookup for these ids: original .eml bytes plus prod status."""
    return et.run_inbox_lookup(ids, eml_dir, out_json, ["--no-email", "--max-job-pages", "1", "--quiet"], log=qc.log)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket")
    ap.add_argument("--ids", nargs="*", default=[], help="extra ids, or restrict to these when --only")
    ap.add_argument("--only", action="store_true", help="QA only the --ids given")
    ap.add_argument("--limit", type=int, default=25, help="refuse to proceed above this many ids without --only")
    ap.add_argument("--no-lookup", action="store_true", help="never call the prod admin site")
    ap.add_argument("--include-external", action="store_true",
                    help="also work on ids that only customer (portal) accounts mentioned — confirm with a human first")
    a = ap.parse_args()

    tdir = qc.ticket_dir(a.ticket)
    issue, f, texts = read_ticket(a.ticket)
    items = collect(texts)
    for iid in a.ids:
        if iid not in {i["id"] for i in items}:
            items.append({"id": iid, "label": None, "sources": ["--ids"]})
    # Keep what earlier fetches learned (downloaded emails, prod outcomes), so a later --only run
    # neither forgets the rest of the ticket nor re-downloads what is already here.
    prev_path = tdir / "ticket.json"
    if prev_path.exists():
        prev = {i["id"]: i for i in json.loads(prev_path.read_text()).get("items", [])}
        for it in items:
            for k in ("eml", "emlFrom", "prod", "skipped"):
                if k in prev.get(it["id"], {}) and k not in it:
                    it[k] = prev[it["id"]][k]
            if it.get("eml") and not pathlib.Path(it["eml"]).exists():
                it.pop("eml", None); it.pop("emlFrom", None)
    # --only restricts what is WORKED ON (downloaded / looked up); ticket.json still lists every id.
    work = [i for i in items if i["id"] in set(a.ids)] if a.only else items
    external = [i["id"] for i in work if i.get("externalOnly") and i["sources"] != ["--ids"]]
    if external and not a.include_external:
        work = [i for i in work if i["id"] not in external]

    qa_notes = [{"comment": {"id": t["id"], "author": t["author"], "created": t["created"]}, "text": t["text"]}
                for t in texts if t["where"] == "comment" and QA_NOTES_RE.search(t["text"])]
    for it in items:
        it["qaNotes"] = qa_excerpts(it["id"], qa_notes)
    result = {"key": issue["key"], "summary": f["summary"], "status": f["status"]["name"],
              "labels": f.get("labels", []), "fetchedAt": qc.utcnow().isoformat(),
              "qaNotes": qa_notes, "items": items, "selected": [i["id"] for i in work] if a.only else None,
              "missing": [], "needsHuman": [], "externalOnly": external}

    if len(work) > a.limit:
        result["needsHuman"].append(
            f"{len(work)} inbox ids on the ticket (limit {a.limit}). Choose a sample (one per distinct cause — "
            "research-jira-bug clusters them) and re-run with --only --ids ….")
    else:
        for it in work:
            p = local_copy(it["id"], a.ticket)
            if p:
                dest = tdir / "emls" / f"inbox_item_{it['id']}.eml"
                if p.resolve() != dest.resolve():
                    shutil.copyfile(p, dest)
                it["eml"], it["emlFrom"] = str(dest), str(p)
        want = [it["id"] for it in work if "prod" not in it and "skipped" not in it]
        looked, errors, fatal = (None, {}, None) if (a.no_lookup or not want) else prod_lookup(want, tdir / "emls", tdir / "prod_lookup.json")
        # ids quoted on the ticket that prod doesn't have: local/dev repro ids in comments, typos
        result["notInProd"] = sorted(i for i, e in errors.items() if NOT_IN_PROD in (e or ""))
        for it in work:
            if it["id"] in result["notInProd"]:
                it["skipped"] = "not a prod inbox item (local or dev id quoted in a comment, or a typo)"
        for rep in looked or []:
            fields = rep.get("fields", {})
            iid = rep.get("inboxId") or fields.get("ID")
            it = next((i for i in work if i["id"] == iid), None)
            if not it:
                continue
            last = rep.get("lastFailure") or {}
            it["prod"] = {"status": fields.get("Status"), "processor": fields.get("Processor"),
                          "disposition": fields.get("Disposition"), "dispositionText": fields.get("Disposition Text"),
                          "actionRequired": fields.get("Action Required"),
                          "lastError": (last.get("errorException"), last.get("errorMessage"))}
            dest = tdir / "emls" / f"inbox_item_{iid}.eml"
            if dest.exists():
                it["eml"], it["emlFrom"] = str(dest), "prod admin (inbox-lookup)"
        result["missing"] = [it["id"] for it in work if "eml" not in it and "skipped" not in it]
        if result["missing"] and fatal and "admin" not in fatal.lower() and "login" not in fatal.lower():
            result["needsHuman"].append(f"No email for {len(result['missing'])} id(s): {fatal}.")
        elif result["missing"]:
            result["needsHuman"].append(
                f"No email for {len(result['missing'])} id(s)" + (f" ({fatal})" if fatal else "") + ". The prod admin login may be missing or stale: "
                'download the Document "ecfx.env" from the shared 1Password vault to '
                f"{qc.creds.file_for('ecfx-admin')} (chmod 600) — re-download it if the shared password was "
                "rotated — or drop the files in ~/Downloads as inbox_item_<id>.eml. Run preflight.py to check.")

    (tdir / "ticket.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({k: result.get(k) for k in ("key", "summary", "status", "missing", "notInProd", "externalOnly", "needsHuman")}
                     | {"items": [{"id": i["id"], "label": i["label"], "eml": bool(i.get("eml")),
                                   "prod": (i.get("prod") or {}).get("status"),
                                   "from": [x["author"] for x in i.get("sourceAuthors", [])],
                                   "qaNoteSections": len(i.get("qaNotes") or [])} for i in work],
                        "ticketIds": len(items),
                        "qaNotes": len(qa_notes), "file": str(tdir / "ticket.json")}, indent=2))
    return 3 if result["needsHuman"] else 0


if __name__ == "__main__":
    sys.exit(main())
