#!/usr/bin/env python3
"""Step 4 of a notice-QA run: render the QA report for a ticket from its traced runs.

    report.py ECFX-17643 [--runs RUN_ID …] [--verdicts verdicts.json] [--fix-commit SHA] [--draft]

Reads ~/.cache/notice-qa/<TICKET>/ticket.json (if fetched) and runs/*.result.json, writes
~/.cache/notice-qa/<TICKET>/notice-qa-report-<TICKET>-<date>.md and prints its path.

The script decides only what has a mechanical answer:
  * duplicate of an item from this ticket's runs    → PASS (dedup), linked to its sibling
  * duplicate of an item processed before           → NOT TESTED, original listed for manual requeue
  * child still retrying / delayed at trace end      → INCONCLUSIVE
Everything else needs a verdict against the ticket's expectations (QA notes, bot label, prod
outcome). Those come from --verdicts, a JSON map written by whoever ran the QA:

    {"<dev child id or prod source id>": {"expected": "...", "verdict": "PASS|FAIL|NOT TESTED|INCONCLUSIVE",
                                           "note": "..."}}

Without a verdict a row reads NEEDS VERDICT and the script exits 3 (unless --draft) — a report
is not finished while any remain.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

import qa_common as qc

def backend_repo():
    """An ecfx-backend checkout to answer 'is the fix commit in the dev image?' from.

    $ECFX_BACKEND_DIR, else the current directory if it is one, else ~/gitlab/ecfx-backend,
    else /workspace/ecfx-backend (claude-code-container)."""
    import os
    for c in (os.environ.get("ECFX_BACKEND_DIR"), pathlib.Path.cwd(),
              pathlib.Path.home() / "gitlab" / "ecfx-backend", pathlib.Path("/workspace/ecfx-backend")):
        if c and (pathlib.Path(c) / "projects" / "receipt_processing").is_dir():
            return pathlib.Path(c)
    return None
CREDENTIAL_EXCEPTIONS = {
    "MissingCourtCredentialsException", "InvalidCourtCredentialsException", "CourtCredentialsRejectedException",
    "LockedCourtCredentialsException", "SuspendedCourtCredentialsException", "MissingMatterForCredentialsException",
    "AccountNotAssignedToCaseException", "AccountUnauthorizedForDocumentException",
}
ORDER = {"FAIL": 0, "NEEDS VERDICT": 1, "INCONCLUSIVE": 2, "NOT TESTED": 3, "PASS": 4}


def dev_image_history(attempts=3):
    """[(created, sha), …] for the dev receipt-processing-queue ReplicaSets, oldest first."""
    import datetime as dt
    import time
    for i in range(attempts):
        try:
            out = subprocess.run(["kubectl", "--context", "dev01", "-n", qc.DEV_NS, "--request-timeout=30s", "get", "rs",
                                  "-o", "jsonpath={range .items[*]}{.metadata.name} {.metadata.creationTimestamp} "
                                        "{.spec.template.spec.containers[0].image}{'\\n'}{end}"],
                                 capture_output=True, text=True, timeout=60).stdout
            hist = []
            for line in out.splitlines():
                parts = line.split()
                if len(parts) == 3 and parts[0].startswith("ecfx-backend-receipt-processing-queue-") and ":" in parts[2]:
                    hist.append((dt.datetime.fromisoformat(parts[1].replace("Z", "+00:00")), parts[2].rsplit(":", 1)[-1][:40]))
            if hist:
                return sorted(hist)
        except Exception:   # noqa: BLE001 — retried, then reported as unknown
            pass
        time.sleep(3 * (i + 1))
    qc.log("! could not read the dev image history from kubectl (dev01) — the report will say 'unknown'")
    return []


def image_at(history, when):
    """The image dev was running at `when`: the newest ReplicaSet created before it."""
    import datetime as dt
    t = dt.datetime.fromisoformat(when)
    before = [sha for created, sha in history if created <= t]
    return before[-1] if before else None


def contains(fix, image):
    """-> (True | False | None, reason). None means "could not tell", never "no"."""
    if not (fix and image):
        return None, "no fix commit or no dev image"
    repo = backend_repo()
    if not repo:
        return None, "no ecfx-backend checkout found ($ECFX_BACKEND_DIR, cwd, ~/gitlab/ecfx-backend, /workspace/ecfx-backend)"
    f = subprocess.run(["git", "-C", str(repo), "fetch", "-q", "origin"], capture_output=True, timeout=120)
    r = subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", fix, image], capture_output=True, text=True)
    if r.returncode in (0, 1):
        return r.returncode == 0, "checked with git merge-base"
    why = "git fetch failed and " if f.returncode else ""
    return None, f"{why}git could not compare {fix} with {image} ({r.stderr.strip()[:120]})"


def batch_of(m):
    return m.get("batch") or re.sub(r"-p\d+$", "", m["run"])


def carry_posted(prev_summary, batches):
    """M8: keep the Jira comment id across re-renders of the SAME send, so judge → report → post
    updates one comment; a report over different batches is a new QA pass and gets a new comment."""
    posted = (prev_summary or {}).get("posted")
    if posted and (prev_summary.get("batches") or posted.get("batches")) == batches:
        return {**posted, "batches": batches}
    return None


def combine_deployed(values):
    """M5: any known NO wins; otherwise any unknown makes the whole answer unknown."""
    if not values:
        return None
    if any(v is False for v in values):
        return False
    if any(v is None for v in values):
        return None
    return True


def apply_log_checks(verdict, note, checks, override):
    """M5: a failed --expect-log/--forbid-log turns a PASS into FAIL unless the verdict carries an
    explicit logCheckOverride reason — the forbid line is usually the very regression signal."""
    failed = [f"{v['kind']} /{k}/ ×{v['count']}" for k, v in (checks or {}).items() if not v["ok"]]
    if failed and verdict == "PASS":
        if override:
            return verdict, f"{note} [log check overridden: {override}]"
        return "FAIL", f"{note} [FAILED log check: {'; '.join(failed)}]"
    return verdict, note


def missing_rows(results):
    """M5: one row per sent notice that no traced child accounts for. A notice re-sent and matched
    in another included run is not missing (that run's row covers it)."""
    matched_files = {c.get("file") for _, r in results for c in r.get("children", [])}
    rows = []
    for m, r in results:
        have = {c.get("file") for c in r.get("children", [])}
        for n in m["notices"]:
            if n["file"] in have or n["file"] in matched_files:
                continue
            why = ("the email never reached dev (Postmark held it or it failed)" if not r.get("parent")
                   else "ambiguous parent — check the dev admin" if r.get("ambiguous")
                   else "no child item matched this notice")
            rows.append({"run": r["run"], "firm": r["firm"], "verdict": "NOT TESTED", "expected": None,
                         "note": f"Sent in run {r['run']}, but {why}. This notice was not tested.",
                         "child": {"id": None, "source": n.get("sourceInboxId") or n["file"], "file": n["file"],
                                   "status": None, "attempts": []}})
    return rows


def auto_verdict(child):
    dup = child.get("duplicate")
    if dup and dup.get("classification") == "sameTicket":
        o = dup["originals"][0]["id"]
        return "PASS", f"Deduplicated against {o}, another notice from this ticket — dedup working as designed."
    if dup and dup.get("classification") == "previouslyProcessed":
        o = ", ".join(x["id"] for x in dup["originals"])
        return "NOT TESTED", (f"Already processed in dev before this run (original {o}), so the notice was not re-run. "
                              "Requeue the original to test it — see 'Manual requeue needed'.")
    if dup:
        return "NOT TESTED", "Deduplicated, but the original dev item could not be identified from logs."
    if child["status"] not in {"SUCCEEDED", "FAILED", "MANUAL", "CANCELED", "POST_PROCESSING"}:
        return "INCONCLUSIVE", f"Still {child['status']} when tracing ended."
    return None, None


def outcome(child):
    bits = [child["status"] or "?"]
    if child.get("disposition"):
        bits.append(child["disposition"])
    s = " / ".join(bits)
    if child.get("exception"):
        s += f" · `{child['exception']}`"
    return s


def history(child):
    return " → ".join(f"{a['at'][11:19]} {a['status'] or '…'}" + (f" ({a['exception']})" if a.get("exception") else "")
                      for a in child.get("attempts", []))


def md_cell(v):
    return str(v or "").replace("|", "\\|").replace("\n", " ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket")
    ap.add_argument("--runs", nargs="*", help="run ids to include (default: all traced runs for the ticket)")
    ap.add_argument("--verdicts", help="JSON map of child/source id → {expected, verdict, note}")
    ap.add_argument("--fix-commit", help="commit the ticket's fix landed as, to prove it is in the dev image")
    ap.add_argument("--all-runs", action="store_true", help="every traced run for the ticket, not just the latest batch")
    ap.add_argument("--from-ticket", metavar="KEY",
                    help="report on runs made under another ticket (e.g. a shared fix QA'd there) — nothing is re-sent")
    ap.add_argument("--only-sources", nargs="*", metavar="INBOX_ID",
                    help="keep only these prod notices from the selected runs (use with --from-ticket)")
    ap.add_argument("--draft", action="store_true", help="write even if some rows still need a verdict")
    a = ap.parse_args()

    tdir = qc.ticket_dir(a.ticket)
    ticket = json.loads((tdir / "ticket.json").read_text()) if (tdir / "ticket.json").exists() else {}
    on_ticket = {i["id"]: i for i in ticket.get("items", [])}
    verdicts = json.loads(pathlib.Path(a.verdicts).read_text()) if a.verdicts else {}

    results = []
    runs_dir = qc.ticket_dir(a.from_ticket) / "runs" if a.from_ticket else tdir / "runs"
    for f in sorted(runs_dir.glob("*.result.json")):
        r = json.loads(f.read_text())
        m = json.loads(f.with_name(f.name.replace(".result.json", ".json")).read_text())
        results.append((m, r))
    if a.runs:
        results = [(m, r) for m, r in results if r["run"] in a.runs or batch_of(m) in a.runs]
    elif not a.all_runs and results:
        # default: the most recent send (all of its bundles), not every run ever made for the ticket
        latest = max(results, key=lambda x: x[0]["sentAt"])[0]
        results = [(m, r) for m, r in results if batch_of(m) == batch_of(latest)]
    if a.only_sources:
        keep = set(a.only_sources)
        filtered = []
        for m, r in results:
            notices = [n for n in m["notices"] if (n.get("sourceInboxId") or n["file"]) in keep]
            if notices:
                filtered.append(({**m, "notices": notices},
                                 {**r, "children": [c for c in r.get("children", []) if c.get("source") in keep]}))
        results = filtered
    if not results:
        sys.exit(f"no traced runs under {runs_dir} (after filters) — run trace_run.py first")

    rows, requeue = [], []
    for m, r in results:
        for i, c in enumerate(r.get("children", [])):
            c.setdefault("file", m["notices"][i]["file"] if i < len(m["notices"]) else None)
    for m, r in results:
        for c in r["children"]:
            # N10: dev child id first, then the attachment file (unique per variant), then the prod id
            v = verdicts.get(c["id"]) or verdicts.get(c.get("file")) or verdicts.get(c.get("source")) or {}
            verdict, note = v.get("verdict"), v.get("note")
            if not verdict:
                verdict, note = auto_verdict(c)
            checks = c.get("logChecks") or {}
            if checks:
                summary_line = "; ".join(f"{'✓' if x['ok'] else '✗'} {x['kind']} /{k}/ ×{x['count']}" for k, x in checks.items())
                note = f"{note} [log checks: {summary_line}]" if note else f"[log checks: {summary_line}]"
                verdict, note = apply_log_checks(verdict, note, checks, v.get("logCheckOverride"))
            rows.append({"run": r["run"], "firm": r["firm"], "child": c, "verdict": verdict or "NEEDS VERDICT",
                         "expected": v.get("expected") or (on_ticket.get(c.get("source")) or {}).get("label"),
                         "note": note})
            dup = c.get("duplicate") or {}
            if dup.get("classification") == "previouslyProcessed":
                for o in dup["originals"]:
                    requeue.append((c.get("source"), c["id"], o))
    rows += missing_rows(results)
    rows.sort(key=lambda x: ORDER.get(x["verdict"], 9))

    # What this run could not exercise, whatever the verdicts say.
    not_covered, by_exc = [], {}
    for x in rows:
        c = x["child"]
        if c.get("exception") in CREDENTIAL_EXCEPTIONS:
            by_exc.setdefault((c["exception"], c.get("processor")), []).append(c.get("source"))
    for (exc, proc), srcs in sorted(by_exc.items()):
        not_covered.append(f"**The document download** for {len(srcs)} notice(s) ({proc}): the test firm has no usable "
                           f"court credential (`{exc}`), so parsing and link matching were exercised but no document was "
                           "retrieved. Add a credential to the test firm to cover it. Notices: "
                           + ", ".join(f"`{s}`" for s in srcs) + ".")
    # Coverage gaps only the judge can see (e.g. the test firm lacks the feature the fix lives behind),
    # given as "_notCovered": ["…", …] in verdicts.json.
    not_covered += [str(n) for n in verdicts.get("_notCovered", [])]
    copy_key = {n["file"]: n.get("copyKey") for m, _ in results for n in m["notices"]}
    groups = {}
    for x in rows:
        k = copy_key.get(x["child"].get("file"))
        if k and not k.endswith("-nolinks"):
            groups.setdefault(k, []).append(x["child"])
    for members in (g for g in groups.values() if len(g) > 1):
        ids = {c["id"] for c in members}
        deduped = any(o["id"] in ids for c in members for o in (c.get("duplicate") or {}).get("originals", []))
        stored = any(c.get("status") in ("SUCCEEDED", "POST_PROCESSING") and c.get("disposition") != "IGNORED" for c in members)
        if not deduped and not stored:
            not_covered.append("Dedup between recipient copies " + ", ".join(f"`{c.get('source')}`" for c in members) +
                               ": no copy stored a document (each failed before storing), so there was nothing to "
                               "deduplicate against.")

    counts = {k: sum(1 for x in rows if x["verdict"] == k) for k in ORDER}
    if counts["FAIL"]:
        overall = "FAIL"
    elif counts["NEEDS VERDICT"] or counts["INCONCLUSIVE"]:
        overall = "INCOMPLETE"
    elif counts["NOT TESTED"] and not counts["PASS"]:
        overall = "NOT TESTED"
    elif counts["NOT TESTED"]:
        overall = "PASS WITH NOTES"
    else:
        overall = "PASS"

    # notices sent as an edited copy (make_variant.py) — shown so nobody mistakes them for the raw prod email
    variant_of = {n.get("sourceInboxId") or n["file"]: n.get("variant") for m, _ in results for n in m["notices"] if n.get("variant")}
    # The image each run was processed by — from dev's deployment history at send time, not "now":
    # dev redeploys on every master merge, and a report is often rendered later (or for reused runs).
    image_history = dev_image_history()
    run_image = {r["run"]: (m.get("devImage") or image_at(image_history, m["sentAt"])) for m, r in results}
    images = sorted({v for v in run_image.values() if v})
    image = images[0] if len(images) == 1 else (", ".join(images) if images else None)
    deployed = None
    if a.fix_commit:
        checked = [(i, *contains(a.fix_commit, i)) for i in images]
        deployed = combine_deployed([v for _, v, _ in checked])
        for i, v, why in checked:
            if v is None:
                qc.log(f"! fix-in-image unverified for {i[:10]}: {why}")

    # "What was tested": how (mechanical, from the runs) + what passed (the judge's summary per QA test
    # from verdicts.json "_tested", else each passing notice's expectation).
    delivered = [(m, r) for m, r in results if r.get("parent")]
    n_sent = sum(len(m["notices"]) for m, _ in delivered)
    n_edit = sum(1 for m, _ in delivered for n in m["notices"] if n.get("variant"))
    checks = sorted({f"{v['kind']} /{k}/" for x in rows for k, v in (x["child"].get("logChecks") or {}).items()})
    how = ((f"No new send: reusing the run made under {a.from_ticket}, where " if a.from_ticket else "")
           + f"{n_sent} prod notice(s) from this ticket" + (f" ({n_edit} as an edited copy, as the QA notes prescribe)" if n_edit else "")
           + f" were replayed into dev01 firm {', '.join(sorted({r['firm'] for _, r in delivered}))}"
           + (f" (receipt-processing image `{', '.join(i[:10] for i in images)}` at the time)" if images else "")
           + f", each attached to an email sent to the firm's dev address ({len(delivered)} email(s))."
           + " Every notice's outcome, attempt history and log lines were read from dev Loki"
           + (f", with log checks: {'; '.join(checks)}." if checks else "."))
    if len(delivered) < len(results):
        how += f" {len(results) - len(delivered)} earlier send(s) never reached dev and were re-sent."
    passed = [str(t) for t in verdicts.get("_tested", [])] or [
        f"`{x['child'].get('source')}`: {x['expected'] or x['child'].get('outcome')}" for x in rows if x["verdict"] == "PASS"]
    date = qc.utcnow().strftime("%Y-%m-%d-%H%MZ")   # time too: a ticket can be QA'd more than once a day
    L = [f"# Notice QA — {a.ticket}: {overall}", ""]
    if ticket:
        L += [f"**{ticket.get('summary')}** · status *{ticket.get('status')}*", ""]
    L += [f"**Result: {overall}** — " + ", ".join(f"{n} {k.lower()}" for k, n in counts.items() if n), ""]

    L += ["## What was tested", "", f"**How:** {how}", ""]
    if passed:
        L += ["**Passed:**", ""] + [f"- {t}" for t in passed] + [""]
    if not_covered:
        L += ["## Not covered by this run", ""] + [f"- {n}" for n in not_covered] + [""]



    if requeue:
        L += ["## Manual requeue needed", "",
              "These notices had already been processed in dev before this run, so dev deduplicated them "
              "instead of re-running them. To test them against the current build, **Force Requeue** the "
              "original dev item:", ""]
        for src, child, o in requeue:
            L.append(f"- prod `{src}` → original dev item [{o['id']}]({o['devAdmin']})"
                     + (f" (firm {o['firm']}, first processed {o['createdEnvelopeAt'][:16].replace('T', ' ')} UTC)"
                        if o.get("createdEnvelopeAt") else "")
                     + f" · this run's duplicate: `{child}`")
        L.append("")

    L += ["## Context", "", "| | |", "|---|---|",
          f"| Environment | dev01 · firm(s) {', '.join(sorted({r['firm'] for _, r in results}))} |",
          f"| Dev receipt-processing image | `{image or 'unknown'}` |"]
    if a.fix_commit:
        L.append(f"| Fix `{a.fix_commit[:10]}` in dev image | "
                 f"{ {True: '✅ yes', False: '❌ **no — results do not test the fix**', None: 'unverified'}[deployed] } |")
    for m, r in results:
        if not r.get("parent"):
            L.append(f"| Run `{r['run']}` | sent {m['sentAt'][:19].replace('T', ' ')} UTC · **never reached dev** — "
                     f"{len(m['notices'])} notice(s) not tested (see the re-sent runs) |")
            continue
        L.append(f"| Run `{r['run']}` | sent {m['sentAt'][:19].replace('T', ' ')} UTC via {m['transport']} · "
                 f"parent [{r['parent']['id']}]({r['parent'].get('devAdmin', '')}) {r['parent'].get('disposition')} · "
                 f"{len(r['children'])} notice(s) |")
    L.append("")

    L += ["## Results", "",
          "| Verdict | Prod notice | On ticket | Dev item | Processor | Outcome (final) | Attempts | Expected | Notes |",
          "|---|---|---|---|---|---|---|---|---|"]
    for x in rows:
        c = x["child"]
        L.append("| " + " | ".join(md_cell(v) for v in (
            f"**{x['verdict']}**", f"`{c.get('source')}`" + (f" (edited copy: {variant_of[c.get('source')]})" if c.get("source") in variant_of else ""),
            "yes" if c.get("source") in on_ticket else "no",
            f"[{c['id']}]({qc.dev_admin_link(c['id'])})" if c.get("id") else "— (no dev item)", c.get("processor"), outcome(c) + (f" — {c['reason']}" if c.get("reason") else ""),
            history(c), x["expected"], x["note"])) + " |")
    L += ["", "## Method", "",
          "Each prod notice's original email was attached (as `message/rfc822`) to one email delivered to the "
          "firm's dev address; dev split it into one inbox item per notice with the court's original headers. "
          "Outcomes were read from dev Loki. Children are matched to their source notice by creation order; "
          "duplicates are traced to the dev item that first stored the document.", "",
          f"_Generated {qc.utcnow().strftime('%Y-%m-%d %H:%M UTC')} by notice-qa._"]

    out = tdir / f"notice-qa-report-{a.ticket}-{date}.md"
    out.write_text("\n".join(L) + "\n")
    # Everything the report says, as data: jira_post.py renders the full comment from this.
    summary = {
        "report": str(out), "ticket": a.ticket, "overall": overall, "counts": counts, "notCovered": not_covered,
        "reusedFrom": a.from_ticket,
        "tested": {"how": how, "passed": passed},
        "ticketSummary": ticket.get("summary"), "ticketStatus": ticket.get("status"),
        "firms": sorted({r["firm"] for _, r in results}), "devImage": image,
        "fixCommit": a.fix_commit, "fixDeployed": deployed,
        "runs": [{"run": r["run"], "sentAt": m["sentAt"], "transport": m.get("transport"), "notices": len(m["notices"]),
                  "parent": (r.get("parent") or {}).get("id"), "parentDisposition": (r.get("parent") or {}).get("disposition"),
                  "parentLink": (r.get("parent") or {}).get("devAdmin"), "children": len(r.get("children", [])),
                  "image": run_image.get(r["run"]),
                  "resentIn": sorted({r2["run"] for _, r2 in results if r2 is not r and r.get("parent") is None
                                      and {c.get("file") for c in r2.get("children", [])} & {n["file"] for n in m["notices"]}})}
                 for m, r in results],
        "requeue": [{"source": s, "duplicate": c, "original": o["id"], "devAdmin": o["devAdmin"], "firm": o.get("firm"),
                     "firstProcessed": o.get("createdEnvelopeAt")} for s, c, o in requeue],
        "rows": [{"verdict": x["verdict"], "source": x["child"].get("source"),
                  "variant": variant_of.get(x["child"].get("source")),
                  "onTicket": x["child"].get("source") in on_ticket, "devId": x["child"].get("id"), "file": x["child"].get("file"),
                  "devLink": qc.dev_admin_link(x["child"]["id"]) if x["child"].get("id") else None, "processor": x["child"].get("processor"),
                  "outcome": outcome(x["child"]).replace("`", ""), "reason": x["child"].get("reason"),
                  "attempts": history(x["child"]), "expected": x["expected"], "note": x["note"]} for x in rows],
        "method": ("Each prod notice's original email was attached (message/rfc822) to an email delivered to the firm's "
                   "dev address, 3 notices per email; dev split each into one inbox item per notice with the court's "
                   "original headers. Outcomes were read from dev Loki. Children are matched to their source notice by "
                   "creation order; duplicates are traced to the dev item that first stored the document."),
        "generatedAt": qc.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
    }
    summary["batches"] = sorted({batch_of(m) for m, _ in results})
    prev_path = tdir / "report-summary.json"
    posted = carry_posted(json.loads(prev_path.read_text()) if prev_path.exists() else {}, summary["batches"])
    if posted:
        summary["posted"] = posted          # re-judged the same send: jira_post updates that comment
    prev_path.write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return 3 if counts["NEEDS VERDICT"] and not a.draft else 0


if __name__ == "__main__":
    sys.exit(main())
