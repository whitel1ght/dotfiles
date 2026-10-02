---
name: notice-processing-metrics
description: >-
  Pull receipt/notice-processing metrics from production CloudWatch logs over a chosen time window and produce per-processor stats, an Excel workbook, a success-by-processor breakdown, and an executive chart deck. Use when asked for notice/receipt processing metrics, processing success rates, time-to-success, first-try vs retried, processing speed/latency by court processor, or "how are our notices processing" over a period (last N hours/days or an explicit date range).
---


# Notice-processing metrics

Computes how court notices are processed in production: are they processed correctly,
how often on the first try, how long until success (including retries), broken down by
processor — from the `receipt-process-queue` and `receipt-process-web-api` logs in
CloudWatch (log group `/aws/eks/ecfx-production/logs/workload/default`, account
278643824850, `us-west-2`).

## How to run

One command does everything (env bootstrap, pull, analyze, charts):

```bash
bash ${CLAUDE_SKILL_DIR}/run.sh --days 7
```

Pick the window with **one** of:
- `--hours N` (default 24)
- `--days N`
- `--start <UTC ISO> --end <UTC ISO>`  e.g. `--start 2026-05-27T00:00:00 --end 2026-05-28T00:00:00`

Notes before running:
- Confirm the requested window with the user if ambiguous; **default to `--hours 24`** if unspecified.
- It needs AWS creds for the prod log account (`aws sts get-caller-identity` must work for `us-west-2`); run.sh checks this and tells the user to log in if not.
- **Cost/time:** it scans ~2.6 GB of logs per hour of window (chunked, adaptive). 24h ≈ ~1 min and pennies; **7 days ≈ several minutes and a couple dollars** of CloudWatch Insights scan. Warn the user before running windows longer than ~3 days.
- Long runs: launch run.sh with `run_in_background: true` (or nohup) and poll, rather than blocking.

## What it produces

Everything lands in a fresh, timestamped run dir: `runs/<timestamp>_<window>/out/`.

- `report.md` — totals, the #5 state breakdown, top-20 processors, latency headlines.
- `notice_processing_metrics.xlsx` — sheets: totals, outcome_breakdown, per_processor
  (avg/median/p90/p99/std for received→start, first-attempt, residence), per_proc_excl_dup_ign, per_inbox_raw.
- `success_by_processor.{xlsx,csv,md}` — successes per processor: first-try vs after-retry, %first-try, avg/max tries, time-to-success median/p90/p99.
- `charts/` and `charts_excl_dup_ignored/` — PNGs + `00_dashboard.png` + `notice_processing_exec_deck.pdf`.
  Use the **`charts_excl_dup_ignored/`** deck for execs (duplicates & ignored removed so fast no-ops don't skew speed).

## Definitions (so results are explained consistently)

- **Processor** = `getFriendlyProviderName()` (e.g. PACER, NYSCEF, Tylers). Source: the
  `…completed in N ms with status <JobStatus> and disposition <Disposition> by <Class> for <Friendly>` line.
- **tries** = non-`DELAYED` jobs per notice (`DELAYED` = intentional dup-delay / stamp-wait reschedules).
- **received → start** = web-api `BACKEND RECEIPTS COMPLETED PROCESSING` ts → first job pickup.
- **time to success** = first attempt start → final success completion, **including retries**, on succeeded notices only — the truest "how long to process correctly" measure.
- **Actionable** notices exclude duplicates, ignored, and not-yet-processed.
- Outcome buckets: succeeded_first_try, succeeded_eventually, failed_our_fault, failed_court_fault,
  failed_client_action_required, pending_waiting_for_stamp / pending_retryable, duplicate, ignored.

## After running

1. Read `out/report.md` and `out/success_by_processor.md` and summarize the headline:
   total notices, % succeeding, % first-try, median & p90 time-to-success, and the top
   processors with the most retries / slowest time-to-success.
2. Offer to `open` the clean dashboard and PDF deck (macOS `open <path>`).
3. Flag the standing caveats: window-edge censoring (retried successes can exceed the
   window), and that long time-to-success is usually external waits (court stamp / case
   assignment), not compute. Attachment split isn't available from logs.

## Customizing

- Different env/log group: set `NPM_REGION` / `NPM_LOG_GROUP`.
- The two stages can be run independently: `pull_and_analyze.py {pull|analyze|all}` then
  `make_charts.py [--exclude-noise]` (set `NPM_RUN_DIR` to the run dir first).
