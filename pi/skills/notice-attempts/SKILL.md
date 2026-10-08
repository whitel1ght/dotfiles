---
name: notice-attempts
description: >-
  Export per-processor ATTEMPTS-TO-SUCCESS and processing-DURATION stats for court notices from DuploCloud prod Loki as a CSV. For each processor, over notices that truly succeeded — min / max / average / median attempts-to-success, % that succeeded on the first attempt, and duration-from-first-attempt (min / max / avg / median, human-readable). Use ONLY when the user explicitly asks how many attempts/retries notices take to process successfully, or how long / the duration / time it takes a notice to process. For the outcome-bucket report (success / failure / customer-action / ignored / duplicate counts + success & failure rates) use the separate `notice-stats` skill instead.
---


# notice-attempts

> **SCOPE — read this first.** This skill produces ONLY the attempts-to-success / duration report. If
> the user wants the **outcome-bucket report** (success / system-failure / customer-action / ignored /
> duplicate counts + success & failure rates, "the notice CSV", "processing buckets"), STOP and use
> the sibling **`notice-stats`** skill instead — do not run this one.

Answers "how many attempts does a notice take to succeed, and how long does it take?" — broken down
per processor, sourced from **DuploCloud prod Loki** (Grafana datasource `duplo-logging`, service
`ecfx-backend-receipt-processing-queue`). Population = notices that **truly succeeded**
(`computedFinalResult == PROCESSING COMPLETE`); failed / customer-action / ignored / duplicate /
never-succeeded notices are excluded from the stats by design.

The script pulls the matching log lines (paginated past Loki's 5k-per-query cap, parallelized across
time shards) and computes the per-processor statistics in Python — the inbox/processor/state live in
the log *line*, not Loki labels, so this can't be done in pure LogQL.

## How to run

The worker is `notice_attempts.py` in this skill's directory; the attempts report is what it
produces by default. Default window is the last 24h; for attempts a **7-day window (`--hours 168`)
is recommended** so multi-attempt retry chains fall fully inside it. Run it, write a CSV, then
report the path + a short summary (busiest processors, those needing the most attempts, slowest
median durations).

```bash
# Recommended: last 7 days, prod:
python3 ${CLAUDE_SKILL_DIR}/notice_attempts.py --hours 168 \
  --out ~/notice-attempts_$(date -u +%Y%m%d).csv

# Explicit window (RFC3339, UTC):
python3 ${CLAUDE_SKILL_DIR}/notice_attempts.py \
  --start 2026-06-08T00:00:00Z --end 2026-06-15T00:00:00Z --out ~/notice-attempts.csv

# BOTH reports out of ONE Loki pull — use this when the user wants attempts *and* outcomes:
python3 ${CLAUDE_SKILL_DIR}/notice_attempts.py --hours 168 \
  --out ~/notice-attempts.csv --also-outcomes ~/notice-stats.csv
```

> **If the user wants both reports, use `--also-outcomes` — do not run both skills.** The Loki scan
> is the expensive part (minutes for a week) and both reports are computed from the same
> per-`(inboxId, processor)` reduction, so a second run doubles the cost for nothing.

**Auth (default):** the script runs `duplo-jit duplo --host https://duplo.cloud-prod.ecfxglobal.net
--interactive`, which uses the user's own DuploCloud login (cached, else opens a browser) and passes
that token as `Authorization: Bearer` to the Grafana datasource proxy. No stored secret. If a browser
prompt is needed, tell the user to complete the login. Progress prints to stderr; the CSV goes to
`--out` (or stdout if omitted).

### Useful flags
- `--hours N` — window = last N hours (default 24; use 168 for a full week).
- `--start` / `--end` — RFC3339 UTC bounds (`--end` defaults to now).
- `--out PATH` — CSV file (default: stdout).
- `--also-outcomes PATH` — additionally write the **outcome-bucket** report from the same pull.
- `--attempts` — accepted but no longer needed; this entry point already produces the attempts
  report. Kept so older documented invocations keep working.
- `--token TOKEN` — pass a DuploCloud token directly and skip `duplo-jit` (headless use; the prod
  `svc-sadron-monitor` token in `sadron-secrets/loki-token` also works).
- `--shard-hours N` — parallel time-shard size (default 1h). Smaller = more parallelism.
- `--workers N` — concurrent shard workers (default 8).
- `--namespace` / `--service` / `--grafana-base` / `--duplo-host` — target a different env (e.g.
  nonprod: `--grafana-base https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/datasources/proxy/uid/duplo-logging --namespace duploservices-dev01 --duplo-host https://duplo.cloud.ecfxglobal.net`).

## Output columns (one row per processor)

`processor, n, attemptsMin, attemptsMax, attemptsAvg, attemptsMedian, pctFirstAttempt,
durSecMin, durSecMax, durSecAvg, durSecMedian, durAvgHms, durMedianHms, successNoStartExcluded`

- `n` = successful notices counted; `pctFirstAttempt` = % that succeeded on attempt 1.
- **attempts** = count of `START PROCESSING` lines for that `(inboxId, processor)` (one per real run;
  intentional dupe-delay self-requeues that never run don't emit it).
- **duration** = `(PROCESSING COMPLETE ts) − (first START PROCESSING ts)`. This is
  **duration-from-first-attempt**, NOT true ingestion→complete — ingestion lives in
  `inbox_item.created_at` (DB), so the in-code Micrometer Timer is the durable path for true
  ingestion→complete. Columns are named `dur…` to keep this honest.
- `dur…Hms` = human-readable (`Nd HH:MM:SS`); `durSec…` = raw seconds.
- `successNoStartExcluded` = succeeded but had no `START PROCESSING` in the window (window-edge
  truncation) — excluded from the stats; **left-pad the window** for long retry chains to minimize it.
- Sort: busiest (`n` desc) then highest avg attempts.

## Notes / gotchas

- **Window choice matters.** Attempts/duration span the whole retry chain; too short a window
  truncates early attempts (inflates `successNoStartExcluded` and undercounts attempts). Prefer
  `--hours 168`+ and left-pad generously for slow processors.
- **Auth type**: must be a *DuploCloud* token, NOT a Grafana service-account token (the proxy is
  SSO-gated; a `glsa_` token gets bounced to login).
- **Shared parsing with `notice-stats`.** The state set (`STATES`) and the `computedFinalResult`
  precedence are identical to the `notice-stats` skill (this skill's `notice_attempts.py` was forked
  from it). If the log vocabulary changes, update BOTH scripts so the two reports stay consistent.
