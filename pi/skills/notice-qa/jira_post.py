#!/usr/bin/env python3
"""Step 7 of a notice-QA run: post the full QA report to the ticket as a Jira comment.

    jira_post.py ECFX-17643 [--dry-run] [--attach] [--new]

Renders ~/.cache/notice-qa/<TICKET>/report-summary.json (written by report.py) as one native
Jira comment carrying the whole report, so nobody has to open an attachment:

    verdict + counts · context (environment, dev image, fix-in-image, every run and its parent) ·
    manual requeue list · what the run could not cover · the full per-notice results table
    (verdict, prod notice, dev item link, processor, final outcome, attempt history, expected,
    notes) · method

Re-running for the same report UPDATES the comment it posted earlier instead of adding another
(the comment id is remembered in report-summary.json); --new forces a fresh comment.
--attach additionally attaches the Markdown report file.
"""
import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request
import uuid

import qa_common as qc

MAX_BODY = 30000          # stay under Jira Cloud's ~32k-character comment limit
CELL_LIMIT = 600          # per-cell trim used only if the full body would exceed MAX_BODY


# ── ADF builders ─────────────────────────────────────────────────────────────

def text(t, marks=(), href=None):
    node = {"type": "text", "text": t}
    ms = [{"type": m} for m in marks]
    if href:
        ms.append({"type": "link", "attrs": {"href": href}})
    if ms:
        node["marks"] = ms
    return node


INLINE = re.compile(r"\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\((https?://[^)]+)\)")


def inline(s):
    """Markdown-ish inline → ADF text nodes: **bold**, `code`, [text](url)."""
    s = str(s or "")
    nodes, pos = [], 0
    for m in INLINE.finditer(s):
        if m.start() > pos:
            nodes.append(text(s[pos:m.start()]))
        if m.group(1):
            nodes.append(text(m.group(1), ["strong"]))
        elif m.group(2):
            nodes.append(text(m.group(2), ["code"]))
        else:
            nodes.append(text(m.group(3), href=m.group(4)))
        pos = m.end()
    if pos < len(s):
        nodes.append(text(s[pos:]))
    return nodes or [text(" ")]


def para(*nodes):
    return {"type": "paragraph", "content": [n for n in nodes if n.get("text") != ""] or [text(" ")]}


def heading(t, level=3):
    return {"type": "heading", "attrs": {"level": level}, "content": [text(t)]}


def bullets(items):
    return {"type": "bulletList", "content": [{"type": "listItem", "content": [para(*i)]} for i in items]}


def table(header, rows):
    def cell(kind, nodes):
        return {"type": kind, "attrs": {}, "content": [para(*nodes)]}
    trs = [{"type": "tableRow", "content": [cell("tableHeader", [text(h or " ", ["strong"])]) for h in header]}]
    trs += [{"type": "tableRow", "content": [cell("tableCell", c) for c in r]} for r in rows]
    return {"type": "table", "attrs": {"isNumberColumnEnabled": False, "layout": "full-width"}, "content": trs}


def trim(s, limit):
    s = str(s or "")
    return s if len(s) <= limit else s[:limit - 1] + "…"


# ── the comment ──────────────────────────────────────────────────────────────

def comment_body(s, cell_limit=None):
    cut = (lambda v: trim(v, cell_limit)) if cell_limit else (lambda v: str(v or ""))
    c = s["counts"]
    content = [heading(f"Notice QA (dev01): {s['overall']}")]      # fetch_ticket.py skips comments starting like this
    if s.get("ticketSummary"):
        content.append(para(text(s["ticketSummary"], ["strong"]), text(f" · status {s.get('ticketStatus')}")))
    content.append(para(text("Result: ", ["strong"]),
                        text(", ".join(f"{n} {k.lower()}" for k, n in c.items() if n) + f" ({sum(c.values())} notices).")))

    # What was tested (how + what passed), then what wasn't — the part most readers need
    t = s.get("tested") or {}
    if t:
        content.append(heading("What was tested", 4))
        content.append(para(text("How: ", ["strong"]), *inline(t.get("how"))))
        if t.get("passed"):
            content.append(para(text("Passed:", ["strong"])))
            content.append(bullets([inline(x) for x in t["passed"]]))
    if s.get("notCovered"):
        content += [heading("Not covered by this run", 4), bullets([inline(n) for n in s["notCovered"]])]

    if s.get("requeue"):
        content += [heading("Manual requeue needed", 4),
                    para(text("These notices had already been processed in dev before this run, so dev deduplicated them "
                              "instead of re-running them. To test them against the current build, Force Requeue the "
                              "original dev item:"))]
        content.append(bullets([[text("prod "), text(q["source"], ["code"]), text(" → original dev item "),
                                 text(q["original"], href=q["devAdmin"])]
                                + ([text(f" (firm {q['firm']}, first processed {q['firstProcessed'][:16].replace('T', ' ')} UTC)")]
                                   if q.get("firstProcessed") else [])
                                for q in s["requeue"]]))

    # context
    fix = {True: "yes", False: "NO — these results do not test the fix", None: "unverified"}[s.get("fixDeployed")]
    ctx = [[[text("Environment")], [text(f"dev01 · firm(s) {', '.join(s.get('firms') or [])}")]],
           [[text("Dev receipt-processing image (at run time)")], [text(s.get("devImage") or "unknown", ["code"])]]]
    if s.get("fixCommit"):
        ctx.append([[text("Fix "), text(s["fixCommit"][:10], ["code"]), text(" in dev image")],
                    [text(fix, ["strong"] if s.get("fixDeployed") is False else [])]])
    for r in s.get("runs", []):
        when = r["sentAt"][:19].replace("T", " ") + " UTC"
        if r.get("parent"):
            val = [text(f"sent {when} · {r['notices']} notice(s) · parent "), text(r["parent"], href=r.get("parentLink")),
                   text(f" {r.get('parentDisposition')} → {r['children']} child item(s)")]
            if r.get("image"):
                val += [text(" · image "), text(r["image"][:10], ["code"])]
        else:
            val = [text(f"sent {when} · {r['notices']} notice(s) · "), text("never reached dev", ["strong"])]
            val.append(text(f" — re-sent in {', '.join(r['resentIn'])}") if r.get("resentIn")
                       else text(" — these notices were NOT tested (see the results table)"))
        ctx.append([[text("Run "), text(r["run"], ["code"])], val])
    content += [heading("Context", 4), table(["", ""], ctx)]

    content.append(heading("Results", 4))
    rows = []
    for r in s.get("rows", []):
        rows.append([
            [text(r["verdict"], ["strong"])],
            [text(r["source"] or "—", ["code"])] + ([text(f" (edited copy — {r['variant']})", ["em"])] if r.get("variant") else []),
            [text("yes" if r["onTicket"] else "no")],
            [text(r["devId"], href=r["devLink"]) if r.get("devId") else text("— (no dev item)")],
            [text(r.get("processor") or "—")],
            [text(cut(r["outcome"] + (f" — {r['reason']}" if r.get("reason") else "")) or "—")],
            [text(cut(r.get("attempts")) or "—")],
            [text(cut(r.get("expected")) or "—")],
            [text(cut(r.get("note")) or "—")],
        ])
    content.append(table(["Verdict", "Prod notice", "On ticket", "Dev item", "Processor", "Outcome (final)",
                          "Attempts", "Expected", "Notes"], rows))

    content += [heading("Method", 4), para(text(s.get("method") or " ")),
                para(text(f"Generated {s.get('generatedAt')} by the notice-qa skill.", ["em"]))]
    return {"type": "doc", "version": 1, "content": content}


def plain_length(node):
    if isinstance(node, dict):
        return len(node.get("text", "")) + sum(plain_length(c) for c in node.get("content", []))
    return 0


def as_text(node):
    """Readable rendering for --dry-run."""
    t = node.get("text", "")
    kids = "".join(as_text(c) for c in node.get("content", []))
    kind = node.get("type")
    if kind in ("tableCell", "tableHeader"):
        return kids.strip() + " | "
    if kind in ("paragraph", "heading", "tableRow", "listItem"):
        return ("- " if kind == "listItem" else "") + (t + kids).rstrip() + "\n"
    return t + kids


# ── Jira calls ───────────────────────────────────────────────────────────────

def request(client, method, path, body=None, headers=None, allow_404=False):
    h = dict(client.headers)
    h.update(headers or {})
    data = json.dumps(body).encode() if isinstance(body, dict) else body
    req = urllib.request.Request(client.base + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if allow_404 and e.code == 404:
            return None
        sys.exit(f"Jira {method} {path} failed: {e.code} {e.read().decode(errors='replace')[:400]}")


def attach(client, key, path):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: text/markdown\r\n\r\n").encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return request(client, "POST", f"/rest/api/3/issue/{key}/attachments", body,
                   {"Content-Type": f"multipart/form-data; boundary={boundary}", "X-Atlassian-Token": "no-check"})[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket")
    ap.add_argument("--dry-run", action="store_true", help="print the comment as text instead of posting")
    ap.add_argument("--attach", action="store_true", help="also attach the Markdown report file")
    ap.add_argument("--new", action="store_true", help="post a new comment even if this report was posted before")
    ap.add_argument("--update", metavar="COMMENT_ID", help="replace this earlier notice-qa comment in place")
    a = ap.parse_args()

    spath = qc.ticket_dir(a.ticket) / "report-summary.json"
    s = json.loads(spath.read_text())
    if "rows" not in s:
        sys.exit("report-summary.json predates full-comment support — re-run report.py first")
    body = comment_body(s)
    if plain_length(body) > MAX_BODY:
        body = comment_body(s, CELL_LIMIT)
        if plain_length(body) > MAX_BODY:
            sys.exit(f"report too large for one Jira comment ({plain_length(body)} chars) — split the runs "
                     "(report.py --runs …) and post each, or use --attach")

    if a.dry_run:
        print(as_text(body))
        print(f"[{plain_length(body)} characters]")
        return 0

    client = qc.jira_client()
    previous = s.get("posted") or {}
    if a.update:
        previous = {"commentId": a.update}
    res, action = None, "posted"
    if previous.get("commentId") and not a.new:
        res = request(client, "PUT", f"/rest/api/3/issue/{a.ticket}/comment/{previous['commentId']}", {"body": body},
                      allow_404=True)
        action = "updated" if res is not None else "posted (the earlier comment was gone)"
    if res is None:
        res = request(client, "POST", f"/rest/api/3/issue/{a.ticket}/comment", {"body": body})
    # M8: remember the comment the moment it exists, before anything else can fail
    s["posted"] = {"report": s["report"], "commentId": res.get("id"), "batches": s.get("batches")}
    spath.write_text(json.dumps(s, indent=2))
    out = {"action": action, "commentId": res.get("id"),
           "url": f"{client.base}/browse/{a.ticket}?focusedCommentId={res.get('id')}"}
    if a.attach:
        att = attach(client, a.ticket, pathlib.Path(s["report"]))
        out.update(attachment=att.get("filename"), attachmentId=att.get("id"))
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
