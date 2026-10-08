#!/usr/bin/env python3
"""
Notice-processing metrics driver.

Pulls raw events from CloudWatch Logs Insights (log group
/aws/eks/ecfx-production/logs/workload/default, us-west-2) in adaptive time
chunks, sessionizes them per inbox item, and computes per-processor statistics.

Stages:
  pull     -- run the chunked Insights queries, write data/*.pkl
  analyze  -- sessionize + compute stats, write out/*.xlsx and out/report.md
  all      -- pull then analyze

Usage:
  ./.venv/bin/python driver.py all --hours 24
  ./.venv/bin/python driver.py analyze            # reuse already-pulled data
"""
import argparse, concurrent.futures as cf, sys, time, os
from datetime import datetime, timezone, timedelta
import boto3, pandas as pd, numpy as np

REGION = os.environ.get("NPM_REGION", "us-west-2")
LOG_GROUP = os.environ.get("NPM_LOG_GROUP", "/aws/eks/ecfx-production/logs/workload/default")
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("NPM_RUN_DIR", HERE)   # output base, set by run.sh per run
DATA = os.path.join(BASE, "data")
OUT = os.path.join(BASE, "out")
CAP = 10000           # Insights max rows/query
MAX_CONCURRENCY = 8

logs = boto3.client("logs", region_name=REGION)

# ---- query bodies (the API adds start/end/limit) -------------------------------
Q_COMPLETIONS = r'''
fields @timestamp
| filter kubernetes.container_name like /receipt-process-queue/
| parse @message /:(?<inbox>inbox_[a-z0-9]+) job (?<jobid>inbox_job_[a-z0-9]+) completed in (?<ms>[0-9]+) ms with status (?<jstatus>[A-Z]+) and disposition (?<disp>[A-Z_]*) by (?<byClass>[^ ]+) for (?<provider>[^"\\]+)/
| filter ispresent(ms)
| sort @timestamp asc
| display @timestamp, inbox, jobid, ms, jstatus, disp, byClass, provider
'''

Q_INGESTS = r'''
fields @timestamp
| filter kubernetes.container_name like /receipt-process-web-api/
| parse @message /\| (?<inbox>inbox_[a-z0-9]+) \| BACKEND RECEIPTS COMPLETED PROCESSING/
| filter ispresent(inbox)
| sort @timestamp asc
| display @timestamp, inbox
'''

Q_STATUS = r'''
fields @timestamp
| filter kubernetes.container_name like /receipt-process-queue/
| parse @message / - [^|"]+\| (?<inbox>inbox_[a-z0-9]+) \| (?<status>[^"\\]*)/
| filter ispresent(inbox)
| filter status like /PROCESSING COMPLETE|FAILED TO PROCESS INBOX ITEM|FAILED TO PROCESS EMAIL|DOCUMENT STORAGE ERROR|UNKNOWN ERROR OCCURRED|FAILED to find ECFX jurisdiction|Undefined Exception for Logging|CASE NUMBER NOT FOUND|CASE NOT UNIQUE|COURT HAS NOT ASSIGNED|NOTICE FROM COURT IS UNSUPPORTED|Document not available|CUSTOMER ACTION REQUIRED|Account not authorized|ACCOUNT NOT ASSIGNED|FAILED to find Mapped Jurisdiction|STAMP not detected|Continue waiting for stamped|SERVICE UNAVAILABLE|RETRY SCHEDULED|DUPLICATE processed|IGNORING processing of notice|IGNORED PROCESSING|CASE SET TO IGNORED|Ignored Item/
| sort @timestamp asc
| display @timestamp, processor, inbox, status
'''

def run_one(query, start, end):
    """Run a single Insights query window; return list[dict]. Retries transient errors."""
    qid = logs.start_query(logGroupName=LOG_GROUP, startTime=int(start),
                           endTime=int(end), queryString=query, limit=CAP)["queryId"]
    while True:
        r = logs.get_query_results(queryId=qid)
        st = r["status"]
        if st in ("Complete", "Failed", "Cancelled", "Timeout"):
            break
        time.sleep(1.0)
    if st != "Complete":
        raise RuntimeError(f"query {st}")
    rows = []
    for rec in r["results"]:
        d = {f["field"]: f["value"] for f in rec if f["field"] != "@ptr"}
        rows.append(d)
    return rows

def adaptive_pull(label, query, start_s, end_s, base_chunk_s):
    """Pull [start,end] in chunks; any chunk that hits the 10k cap is bisected."""
    work = []
    t = start_s
    while t < end_s:
        work.append((t, min(t + base_chunk_s, end_s)))
        t += base_chunk_s
    out = []
    done = [0]
    total = [len(work)]
    def handle(seg):
        a, b = seg
        rows = run_one(query, a, b)
        if len(rows) >= CAP and (b - a) > 30:           # hit cap -> split
            mid = (a + b) // 2
            return ("split", [(a, mid), (mid, b)], rows)
        return ("ok", rows, None)
    with cf.ThreadPoolExecutor(max_workers=MAX_CONCURRENCY) as ex:
        pending = {ex.submit(handle, s): s for s in work}
        while pending:
            for fut in cf.as_completed(list(pending)):
                seg = pending.pop(fut)
                kind, a1, a2 = fut.result()
                if kind == "split":
                    for s in a1:
                        pending[ex.submit(handle, s)] = s
                    total[0] += len(a1) - 1
                    print(f"  [{label}] cap hit on {fmt(seg)} -> bisecting", file=sys.stderr)
                else:
                    out.extend(a1)
                    done[0] += 1
                    print(f"  [{label}] {done[0]}/{total[0]} chunks, {len(out)} rows", file=sys.stderr)
                break
    return out

def fmt(seg):
    a, b = seg
    return f"{datetime.fromtimestamp(a, timezone.utc):%H:%M}-{datetime.fromtimestamp(b, timezone.utc):%H:%M}"

def resolve_window(a):
    """Return (start_epoch, end_epoch) from --hours/--days or explicit --start/--end (UTC ISO)."""
    if a.start or a.end:
        end = int(pd.Timestamp(a.end, tz="UTC").timestamp()) if a.end else int(datetime.now(timezone.utc).timestamp())
        if not a.start:
            raise SystemExit("--start is required when --end is given")
        start = int(pd.Timestamp(a.start, tz="UTC").timestamp())
        return start, end
    hours = a.days * 24 if a.days else a.hours
    end = int(datetime.now(timezone.utc).timestamp())
    return end - hours * 3600, end

def stage_pull(start, end):
    os.makedirs(DATA, exist_ok=True)
    hours = round((end - start) / 3600, 2)
    meta = pd.DataFrame([{"start_utc": datetime.fromtimestamp(start, timezone.utc).isoformat(),
                          "end_utc": datetime.fromtimestamp(end, timezone.utc).isoformat(),
                          "hours": hours}])
    meta.to_csv(os.path.join(DATA, "window.csv"), index=False)
    print(f"window {meta.start_utc[0]} -> {meta.end_utc[0]} ({hours}h)", file=sys.stderr)

    # chunk sizes tuned from measured volume (~28k completions, ~12k ingests, ~?k status / hr)
    jobs = ["completions", "ingests", "status"]
    for label, q, chunk in [("completions", Q_COMPLETIONS, 900),
                            ("ingests", Q_INGESTS, 1800),
                            ("status", Q_STATUS, 600)]:
        print(f"== pulling {label} ==", file=sys.stderr)
        rows = adaptive_pull(label, q, start, end, chunk)
        df = pd.DataFrame(rows)
        df.to_pickle(os.path.join(DATA, f"{label}.pkl"))
        print(f"== {label}: {len(df)} rows saved ==", file=sys.stderr)

# ---- classification ------------------------------------------------------------
def classify_status(s):
    s = s or ""
    if "PROCESSING COMPLETE" in s: return "success"
    if "DUPLICATE processed" in s: return "duplicate"
    if any(k in s for k in ("IGNORING processing", "IGNORED PROCESSING", "CASE SET TO IGNORED", "Ignored Item")): return "ignored"
    if any(k in s for k in ("STAMP not detected", "Continue waiting for stamped")): return "waiting_for_stamp"
    if any(k in s for k in ("SERVICE UNAVAILABLE", "RETRY SCHEDULED", "COURT HAS NOT ASSIGNED")): return "retryable_transient"
    if any(k in s for k in ("CUSTOMER ACTION REQUIRED", "Account not authorized", "ACCOUNT NOT ASSIGNED", "FAILED to find Mapped Jurisdiction")): return "client_action_required"
    if any(k in s for k in ("CASE NUMBER NOT FOUND", "CASE NOT UNIQUE", "NOTICE FROM COURT IS UNSUPPORTED", "Document not available")): return "court_fault"
    if any(k in s for k in ("FAILED TO PROCESS INBOX ITEM", "FAILED TO PROCESS EMAIL", "DOCUMENT STORAGE ERROR", "UNKNOWN ERROR OCCURRED", "FAILED to find ECFX jurisdiction", "Undefined Exception")): return "our_fault"
    return "other"

# fine category severity order: when an inbox has several, pick the most "actionable" reason
FINE_PRIORITY = ["our_fault", "court_fault", "client_action_required", "waiting_for_stamp",
                 "retryable_transient", "duplicate", "ignored", "success", "other"]

def stats_block(series):
    s = series.dropna().astype(float)
    if len(s) == 0:
        return dict(n=0, avg=np.nan, median=np.nan, p90=np.nan, p99=np.nan, std=np.nan, max=np.nan)
    return dict(n=int(len(s)), avg=s.mean(), median=s.median(),
                p90=s.quantile(.90), p99=s.quantile(.99), std=s.std(ddof=0), max=s.max())

def stage_analyze():
    os.makedirs(OUT, exist_ok=True)
    comp = pd.read_pickle(os.path.join(DATA, "completions.pkl"))
    ing = pd.read_pickle(os.path.join(DATA, "ingests.pkl"))
    stat = pd.read_pickle(os.path.join(DATA, "status.pkl"))
    win = pd.read_csv(os.path.join(DATA, "window.csv"))

    def to_ms(ts):  # "2026-06-02 20:21:44.716" UTC -> epoch ms (force ms resolution)
        return pd.to_datetime(ts, utc=True, format="mixed").dt.as_unit("ms").astype("int64")

    comp["ts"] = to_ms(comp["@timestamp"])
    comp["ms"] = comp["ms"].astype(float)
    comp["start_ts"] = comp["ts"] - comp["ms"]
    comp["provider"] = comp["provider"].str.strip()
    comp = comp.sort_values("ts")
    ing["ts"] = to_ms(ing["@timestamp"])
    stat["ts"] = to_ms(stat["@timestamp"])
    stat["cat"] = stat["status"].map(classify_status)

    # ---- de-dupe job rows (a job logs one completion; guard against overlap dupes) ----
    comp = comp.drop_duplicates(subset=["inbox", "jobid"], keep="first")

    real = comp[comp["jstatus"] != "DELAYED"].copy()      # real attempts (tries)

    # ---- per-inbox sessionization -------------------------------------------------
    g = comp.groupby("inbox")
    rg = real.groupby("inbox")
    sess = pd.DataFrame(index=g.size().index)
    sess["provider"] = rg["provider"].last().reindex(sess.index)
    sess["provider"] = sess["provider"].fillna(g["provider"].last())
    sess["n_jobs"] = g.size()
    sess["n_tries"] = rg.size().reindex(sess.index).fillna(0).astype(int)
    sess["n_delayed"] = sess["n_jobs"] - sess["n_tries"]
    sess["first_start_ts"] = g["start_ts"].min()
    sess["last_done_ts"] = g["ts"].max()
    # first real attempt
    first_real = real.sort_values("ts").groupby("inbox").first()
    sess["first_attempt_status"] = first_real["jstatus"].reindex(sess.index)
    sess["first_attempt_ms"] = first_real["ms"].reindex(sess.index)
    sess["first_attempt_disp"] = first_real["disp"].reindex(sess.index)
    # eventual outcome
    sess["ever_succeeded"] = rg["jstatus"].apply(lambda s: (s == "SUCCEEDED").any()).reindex(sess.index).fillna(False)
    last_real = real.sort_values("ts").groupby("inbox").last()
    sess["final_status"] = last_real["jstatus"].reindex(sess.index)
    sess["final_disp"] = last_real["disp"].reindex(sess.index)
    # residence time = received(ingest) or first start -> last completion
    ing_first = ing.groupby("inbox")["ts"].min()
    sess["received_ts"] = ing_first.reindex(sess.index)
    sess["recv_to_start_ms"] = sess["first_start_ts"] - sess["received_ts"]
    # the ingest log is flushed async at end of inbound handling, so a fast job can start a few
    # hundred ms "before" it -> floor small negatives to 0; drop large anomalies (re-ingest/skew).
    sess.loc[sess["recv_to_start_ms"] < -2000, "recv_to_start_ms"] = np.nan
    sess["recv_to_start_ms"] = sess["recv_to_start_ms"].clip(lower=0)
    sess["total_residence_ms"] = sess["last_done_ts"] - sess["first_start_ts"]

    # fine reason (from status text) per inbox: both the highest-priority single reason
    # and the *set* of every state the notice ever entered (for the #5 cross-cutting view).
    cat_sets = stat.groupby("inbox")["cat"].apply(lambda s: set(s))
    fine = (cat_sets.apply(lambda st: min(st, key=lambda c: FINE_PRIORITY.index(c) if c in FINE_PRIORITY else 99))
                    .reindex(sess.index))
    sess["fine_reason"] = fine
    cs = cat_sets.reindex(sess.index)
    for cat in ("waiting_for_stamp", "retryable_transient", "client_action_required",
                "court_fault", "our_fault", "duplicate", "ignored"):
        sess[f"ever_{cat}"] = cs.apply(lambda st, c=cat: isinstance(st, set) and c in st)

    # disposition-based duplicate / ignored flag (independent of status text)
    sess["is_dup_or_ignored"] = (sess["final_disp"] == "IGNORED")

    # ---- outcome classification per inbox ----------------------------------------
    def outcome(r):
        if r["n_tries"] == 0:
            if r["ever_waiting_for_stamp"]: return "pending_waiting_for_stamp"
            if r["ever_retryable_transient"]: return "pending_retryable"
            return "only_delayed_no_attempt"   # dup-delay pending / first real attempt outside window
        if r["final_disp"] == "IGNORED":
            # disambiguate dup vs ignored via status text where possible
            return "duplicate" if r["fine_reason"] == "duplicate" else "ignored"
        if r["ever_succeeded"]:
            if r["first_attempt_status"] == "SUCCEEDED":
                return "succeeded_first_try"
            return "succeeded_eventually"
        # never succeeded
        if r["fine_reason"] == "client_action_required":
            return "failed_client_action_required"
        if r["fine_reason"] in ("waiting_for_stamp", "retryable_transient"):
            return "pending_retryable"
        if r["fine_reason"] == "court_fault":
            return "failed_court_fault"
        if r["fine_reason"] == "our_fault":
            return "failed_our_fault"
        return "failed_unclassified"
    sess["outcome"] = sess.apply(outcome, axis=1)
    sess = sess.reset_index().rename(columns={"index": "inbox"})

    sess.to_pickle(os.path.join(DATA, "sessions.pkl"))
    write_reports(sess, comp, real, win)
    return sess

def write_reports(sess, comp, real, win):
    # ===== per-processor stats tables =====
    rows = []
    for prov, grp in sess.groupby("provider"):
        succ_first = (grp["outcome"] == "succeeded_first_try").sum()
        succ_ever = grp["outcome"].isin(["succeeded_first_try", "succeeded_eventually"]).sum()
        # "could have succeeded first time but didn't" = retryable-state, not client action
        retry_excl_client = grp["outcome"].isin(["succeeded_eventually", "pending_retryable",
                                                  "failed_court_fault", "failed_our_fault",
                                                  "failed_unclassified"])
        d = dict(
            provider=prov,
            notices=len(grp),
            tries_avg=grp["n_tries"].mean(),
            tries_max=int(grp["n_tries"].max()),
            succeeded_first_try=int(succ_first),
            succeeded_eventually=int(succ_ever - succ_first),
            pct_first_try_of_success=(100*succ_first/succ_ever) if succ_ever else np.nan,
            failed_our_fault=int((grp["outcome"] == "failed_our_fault").sum()),
            failed_court_fault=int((grp["outcome"] == "failed_court_fault").sum()),
            failed_client_action=int((grp["outcome"] == "failed_client_action_required").sum()),
            pending_retryable=int((grp["outcome"] == "pending_retryable").sum()),
            pending_waiting_for_stamp=int((grp["outcome"] == "pending_waiting_for_stamp").sum()),
            duplicate=int((grp["outcome"] == "duplicate").sum()),
            ignored=int((grp["outcome"] == "ignored").sum()),
            ever_waiting_for_stamp=int(grp["ever_waiting_for_stamp"].sum()),
            ever_client_action=int(grp["ever_client_action_required"].sum()),
            ever_court_fault=int(grp["ever_court_fault"].sum()),
            ever_our_fault=int(grp["ever_our_fault"].sum()),
        )
        for prefix, col in [("recv2start", "recv_to_start_ms"),
                            ("first_attempt", "first_attempt_ms"),
                            ("residence", "total_residence_ms")]:
            for k, v in stats_block(grp[col]).items():
                d[f"{prefix}_{k}"] = v
        rows.append(d)
    proc = pd.DataFrame(rows).sort_values("notices", ascending=False)

    # excl. duplicates/ignored variant of first-attempt duration
    clean = sess[~sess["outcome"].isin(["duplicate", "ignored", "only_delayed_no_attempt"])]
    rows2 = []
    for prov, grp in clean.groupby("provider"):
        d = {"provider": prov, "notices_excl_dup_ign": len(grp)}
        for k, v in stats_block(grp["first_attempt_ms"]).items():
            d[f"first_attempt_{k}"] = v
        rows2.append(d)
    proc_clean = pd.DataFrame(rows2).sort_values("notices_excl_dup_ign", ascending=False)

    # overall totals (retryable basis, excluding client-action-required)
    tot = dict(
        total_notices=len(sess),
        succeeded_first_try=int((sess["outcome"] == "succeeded_first_try").sum()),
        succeeded_eventually=int((sess["outcome"] == "succeeded_eventually").sum()),
        failed_our_fault=int((sess["outcome"] == "failed_our_fault").sum()),
        failed_court_fault=int((sess["outcome"] == "failed_court_fault").sum()),
        failed_client_action_required=int((sess["outcome"] == "failed_client_action_required").sum()),
        pending_retryable=int((sess["outcome"] == "pending_retryable").sum()),
        duplicate=int((sess["outcome"] == "duplicate").sum()),
        ignored=int((sess["outcome"] == "ignored").sum()),
        only_delayed_no_attempt=int((sess["outcome"] == "only_delayed_no_attempt").sum()),
    )
    totals = pd.DataFrame([tot])

    outcome_counts = sess["outcome"].value_counts().rename_axis("outcome").reset_index(name="count")

    # ===== write Excel =====
    xlsx = os.path.join(OUT, "notice_processing_metrics.xlsx")
    with pd.ExcelWriter(xlsx, engine="openpyxl") as xw:
        totals.T.rename(columns={0: "count"}).to_excel(xw, sheet_name="totals")
        outcome_counts.to_excel(xw, sheet_name="outcome_breakdown", index=False)
        proc.to_excel(xw, sheet_name="per_processor", index=False)
        proc_clean.to_excel(xw, sheet_name="per_proc_excl_dup_ign", index=False)
        sess.to_excel(xw, sheet_name="per_inbox_raw", index=False)
    print(f"wrote {xlsx}", file=sys.stderr)
    proc.to_csv(os.path.join(OUT, "per_processor.csv"), index=False)
    sess.to_csv(os.path.join(OUT, "per_inbox.csv"), index=False)

    # ===== markdown summary =====
    def secs(ms):
        return "n/a" if pd.isna(ms) else (f"{ms/1000:.1f}s" if ms < 60000 else f"{ms/60000:.1f}m")
    md = []
    md.append(f"# Notice processing metrics\n")
    md.append(f"Window (UTC): **{win.start_utc[0]} → {win.end_utc[0]}** ({int(win.hours[0])}h)\n")
    md.append(f"Total distinct notices observed (had >=1 job): **{len(sess):,}**\n")
    md.append("\n## Totals (all processors)\n")
    md.append("| outcome | count | % |\n|---|--:|--:|")
    for _, r in outcome_counts.iterrows():
        md.append(f"| {r['outcome']} | {r['count']:,} | {100*r['count']/len(sess):.1f}% |")
    succ_ever = tot["succeeded_first_try"] + tot["succeeded_eventually"]
    md.append("\n**Headline:**")
    md.append(f"- Succeeded **first try**: {tot['succeeded_first_try']:,}")
    md.append(f"- Succeeded **eventually** (>1 try): {tot['succeeded_eventually']:,}")
    md.append(f"- First-try rate among successes: {100*tot['succeeded_first_try']/succ_ever:.1f}%" if succ_ever else "- n/a")
    fail_retryable = tot["failed_our_fault"] + tot["failed_court_fault"] + tot["pending_retryable"]
    md.append(f"- Failed/pending on a **retryable, non-client-action** basis: {fail_retryable:,} "
              f"(our_fault {tot['failed_our_fault']:,}, court_fault {tot['failed_court_fault']:,}, pending_retryable {tot['pending_retryable']:,})")
    md.append(f"- Failed needing **client action** (creds/jurisdiction): {tot['failed_client_action_required']:,}")
    md.append(f"- Duplicates: {tot['duplicate']:,} | Ignored: {tot['ignored']:,}")

    # ===== #5 cross-cutting: states a notice ever entered (independent of terminal outcome) =====
    md.append("\n## #5 State sections (notices that EVER entered each state)\n")
    md.append("Counted from the ProcessorLogger status text; a notice can appear in more than one row. "
              "This is the 'why didn't it sail through first time' view, separate from the final outcome above.\n")
    md.append("| state | notices | % of all |\n|---|--:|--:|")
    n_all = len(sess)
    for label, col in [("waiting for stamp", "ever_waiting_for_stamp"),
                       ("retryable / transient (court-not-assigned, service unavailable, retry scheduled)", "ever_retryable_transient"),
                       ("client action required (creds / jurisdiction mapping)", "ever_client_action_required"),
                       ("court-side fault (case not found / not unique / unsupported)", "ever_court_fault"),
                       ("our fault (server / parse / storage / unknown)", "ever_our_fault"),
                       ("duplicate", "ever_duplicate"),
                       ("ignored", "ever_ignored")]:
        c = int(sess[col].sum())
        md.append(f"| {label} | {c:,} | {100*c/n_all:.1f}% |")
    # "could have succeeded first time but didn't" = needed >1 try OR still pending, on a retryable
    # (non-client-action, non-dup, non-ignored) basis.
    retryable_basis = sess["outcome"].isin(
        ["succeeded_eventually", "pending_retryable", "pending_waiting_for_stamp",
         "failed_our_fault", "failed_court_fault", "failed_unclassified"])
    md.append(f"\n**Could have succeeded on the first attempt but didn't** (retryable state, not client-action, "
              f"not dup/ignored): **{int(retryable_basis.sum()):,}** ({100*int(retryable_basis.sum())/n_all:.1f}% of all notices). "
              f"Breakdown by terminal/latest state:")
    oc = sess["outcome"].value_counts()
    md.append(f"  - eventually succeeded after >1 try: {int(oc.get('succeeded_eventually',0)):,}")
    md.append(f"  - latest state court-side (case not found/unique/unsupported — many auto-retry for days): {int(oc.get('failed_court_fault',0)):,}")
    md.append(f"  - latest state our-fault (server/parse/storage/unknown): {int(oc.get('failed_our_fault',0)):,}")
    md.append(f"  - failed, reason not in status text (likely pending or transient): {int(oc.get('failed_unclassified',0)):,}")
    md.append(f"  - still actively retrying (waiting-for-stamp / transient): "
              f"{int((sess['outcome']=='pending_waiting_for_stamp').sum())+int((sess['outcome']=='pending_retryable').sum()):,}")
    md.append(f"\n  *Separately, {int(sess['ever_waiting_for_stamp'].sum()):,} notices entered the waiting-for-stamp state "
              f"at some point (most resolve into 'succeeded eventually' once the stamped doc appears).*")

    g = sess
    md.append("\n## Latency / duration (all processors, median · p90 · p99)\n")
    for label, col in [("#1 received → processing start", "recv_to_start_ms"),
                       ("#2 first-attempt processing duration", "first_attempt_ms"),
                       ("total residence (start → last done)", "total_residence_ms")]:
        s = stats_block(g[col])
        md.append(f"- **{label}** (n={s['n']:,}): "
                  f"median {secs(s['median'])} · p90 {secs(s['p90'])} · p99 {secs(s['p99'])} · avg {secs(s['avg'])} · std {secs(s['std'])}")

    md.append("\n## Top 20 processors by volume\n")
    md.append("| processor | notices | first-try | eventual | our_fail | court_fail | client_action | retry_pend | dup | ign | 1st-attempt p50/p90/p99 | recv→start p50/p90 |\n|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|---|")
    for _, r in proc.head(20).iterrows():
        md.append("| {p} | {n:,} | {ft:,} | {ev:,} | {of:,} | {cf:,} | {ca:,} | {rp:,} | {dp:,} | {ig:,} | {a50}/{a90}/{a99} | {r50}/{r90} |".format(
            p=r["provider"], n=int(r["notices"]), ft=int(r["succeeded_first_try"]), ev=int(r["succeeded_eventually"]),
            of=int(r["failed_our_fault"]), cf=int(r["failed_court_fault"]), ca=int(r["failed_client_action"]),
            rp=int(r["pending_retryable"]), dp=int(r["duplicate"]), ig=int(r["ignored"]),
            a50=secs(r["first_attempt_median"]), a90=secs(r["first_attempt_p90"]), a99=secs(r["first_attempt_p99"]),
            r50=secs(r["recv2start_median"]), r90=secs(r["recv2start_p90"])))
    md.append("\n*Full per-processor table (avg/median/p90/p99/std for each of the three durations, "
              "with-and-without duplicates/ignored) is in `out/notice_processing_metrics.xlsx`.*\n")
    md.append("\n### Notes / caveats\n")
    md.append("- `received → start` uses the web-api `BACKEND RECEIPTS COMPLETED PROCESSING` log as received-time; "
              "notices ingested via a path that doesn't emit that line have no recv-time (counted in n only when present).")
    md.append("- `tries` excludes `DELAYED` jobs (dup-delay / stamp-wait reschedules), matching the code's attempt count.")
    md.append("- Notices whose lifecycle crosses the window edge are partially observed (first/last event may be outside the window).")
    md.append("- `pending_retryable` = never-succeeded-yet but in a retryable state (stamp-wait / transient) — not a terminal failure.")
    md.append("- Attachment breakdown is omitted: the completion log carries no attachment flag and only some processors emit "
              "'PROCESSING email with attachments', so a reliable per-notice attachment split isn't available from logs.")
    md.append("- All duration columns in the Excel/CSV are in **milliseconds**; this markdown humanizes them (s/m).")
    md.append("- `received → start` measures time to *first job pickup* (first touch). The first job is often an intentional "
              "dup-delay (quick), so this reflects queue responsiveness; intentional delays before real processing are separate.")
    with open(os.path.join(OUT, "report.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"wrote {os.path.join(OUT,'report.md')}", file=sys.stderr)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Pull receipt-processing logs and compute per-notice metrics.")
    ap.add_argument("stage", choices=["pull", "analyze", "all"])
    ap.add_argument("--hours", type=int, default=24, help="window length in hours (default 24)")
    ap.add_argument("--days", type=int, help="window length in days (overrides --hours)")
    ap.add_argument("--start", help="explicit window start, UTC ISO e.g. 2026-05-27T00:00:00")
    ap.add_argument("--end", help="explicit window end, UTC ISO (default: now)")
    a = ap.parse_args()
    if a.stage in ("pull", "all"):
        start, end = resolve_window(a)
        stage_pull(start, end)
    if a.stage in ("analyze", "all"):
        stage_analyze()
