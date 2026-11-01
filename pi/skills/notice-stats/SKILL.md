---
name: notice-stats
description: >-
  Export per-processor notice-processing OUTCOME stats from DuploCloud prod Loki as a CSV — outcome buckets (success / system-failure / customer-action / retry / ignored / duplicate / unknown / in-progress) plus success & failure rates. The DuploCloud replacement for the CloudWatch Logs Insights export. Use when the user asks for notice processing stats, per-processor success/failure rates, "the notice CSV", processing buckets, or invokes /notice-stats. For attempts-to-success or processing-duration stats, use the separate `notice-attempts` skill instead.
---


# notice-stats

> **SCOPE — read this first.** This skill produces the **outcome-bucket report only**. If the user
> explicitly asks how many **attempts/retries** a notice takes to succeed, or how **long / the duration**
> a notice takes to process, STOP and use the sibling **`notice-attempts`** skill instead — do not
> produce the attempts report from here.

Produces the same per-processor CSV we used to export from CloudWatch Logs Insights, now sourced
from **DuploCloud prod Loki** (Grafana datasource `duplo-logging`, service
`ecfx-backend-receipt-processing-queue`).

The bucketing logic is a faithful port of the CloudWatch query: per `(inboxId, processor)` it takes
the **latest recognized state** plus duplicate/ignore/retry/customer-action precedence to compute one
`computedFinalResult`, then aggregates those per processor. This can't be done in pure LogQL (the
state/inbox/processor live in the log line, not labels), so the worker script pulls the matching
lines (paginated past Loki's 5k-per-query cap) and computes the buckets in Python.

## How to run

The worker is `notice_stats.py` in this skill's directory
(`${CLAUDE_SKILL_DIR}/notice_stats.py`). Default window is the last 24h; default target is
prod. Run it and write a CSV, then report the path + a short summary (top processors by terminal
failures, overall success rate).

```bash
# Last 24h (default), prod:
python3 ${CLAUDE_SKILL_DIR}/notice_stats.py --out ~/notice-stats_$(date -u +%Y%m%d).csv

# Explicit window (RFC3339, UTC):
python3 ${CLAUDE_SKILL_DIR}/notice_stats.py \
  --start 2026-06-14T00:00:00Z --end 2026-06-15T00:00:00Z --out ~/notice-stats.csv

# Last N hours:
python3 ${CLAUDE_SKILL_DIR}/notice_stats.py --hours 6 --out ~/notice-stats.csv

# BOTH reports out of ONE Loki pull — use this when the user wants outcomes *and* attempts:
python3 ${CLAUDE_SKILL_DIR}/notice_stats.py --hours 24 \
  --out ~/notice-stats.csv --also-attempts ~/notice-attempts.csv
```

> **If the user wants both reports, use `--also-attempts` — do not run both skills.** The Loki scan
> is the expensive part (~25s for 24h, minutes for a week) and both reports are computed from the
> same per-`(inboxId, processor)` reduction, so a second run doubles the cost for nothing.

**Auth (default):** the script runs `duplo-jit duplo --host https://duplo.cloud-prod.ecfxglobal.net
--interactive`, which uses the user's own DuploCloud login (cached, else opens a browser) and passes
that token as `Authorization: Bearer` to the Grafana datasource proxy — the same mechanism the
Grafana MCP wrapper uses. No stored secret. If a browser prompt is needed, tell the user to complete
the login. Progress (auth, volume estimate, pagination, parse counts) prints to stderr; the CSV goes
to `--out` (or stdout if omitted).

### Useful flags
- `--hours N` — window = last N hours (default 24).
- `--start` / `--end` — RFC3339 UTC bounds (`--end` defaults to now).
- `--out PATH` — CSV file (default: stdout).
- `--also-attempts PATH` — additionally write the **attempts-to-success** report from the same pull.
- `--token TOKEN` — pass a DuploCloud token directly and skip `duplo-jit` (e.g. for headless use; the
  prod `svc-sadron-monitor` token in `sadron-secrets/loki-token` also works).
- `--shard-hours N` — parallel time-shard size (default 1h). The window is split into shards pulled
  concurrently and merged losslessly (per-inbox reduction is associative). Smaller = more parallelism.
- `--workers N` — concurrent shard workers (default 8).
- `--namespace` / `--service` / `--grafana-base` / `--duplo-host` — target a different env (e.g.
  nonprod: `--grafana-base https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/datasources/proxy/uid/duplo-logging --namespace duploservices-dev01 --duplo-host https://duplo.cloud.ecfxglobal.net`).

## Output columns (one row per processor, sorted by terminal failures)

`processor, successCount, systemFailureCount, retryCount, customerActionCount, ignoredCount,
duplicateCount, unknownCount, noResultCount, inProgressCount, totalCount, totalTerminalFailures,
successRate, failureRate`

- `totalTerminalFailures` = systemFailureCount + unknownCount.
- `successRate` / `failureRate` = % over `(success + systemFailure + unknown)`; blank when that
  denominator is 0 (matches the CloudWatch division-by-zero behavior).
- Sort order: `totalTerminalFailures` desc, `systemFailureCount` desc, `successRate` asc,
  `successCount` desc.

## Notes / gotchas (best practices from the duplo migration)

- **Volume & performance**: this captures *every* lifecycle state (incl. `START PROCESSING` /
  `PROCESSING COMPLETE`), so ~170k+ lines/24h (~1.2M/week). Loki caps page size (~5k/query), so the
  script **parallelizes across time shards** (`--shard-hours`, default 1h; `--workers`, default 8)
  and merges losslessly. Measured: a 24h pull (~181k lines) completes in **~25s**; a week is roughly
  a couple of minutes. It estimates volume up front (cheap metric query), paginates by timestamp
  cursor (robust to many lines sharing one nanosecond), and reports true pulled/parsed counts so a
  low result is never confused with truncation. A shard that exhausts its retries under full
  concurrency is **retried serially**, and anything still missing prints a loud `DATA GAP` block
  naming the exact windows — results are never silently undercounted. For very large windows, raise
  `--workers` or shrink `--shard-hours`.
- **Auth type**: must be a *DuploCloud* token, NOT a Grafana service-account token (the proxy is
  SSO-gated; a `glsa_` token gets bounced to login).
- **Parsing**: the state set and the `computedFinalResult` precedence are ported verbatim from the
  CloudWatch query; keep them in sync if the query's state vocabulary changes.
