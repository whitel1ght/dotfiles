---
name: categorization-stats
description: >-
  Pull ECFX cat-svc (document categorization) health + metrics for a time window from DuploCloud prod01 Loki — the same data analyzed during go-live monitoring. Reports Categorize success/failure counts and success rate, known error classes (Anthropic 500s, RESOURCE_EXHAUSTED capacity rejections, SubmitCategorizationOverride FK failures / ECFX-16173), any ERROR-level lines, pod boots vs real crashes, per-firm and per-category-code breakdowns, category-source bands (AI_AUTO/AI_FLAGGED/AI_UNC), cost + token totals, which firms are enabled, and (optionally) iManage DMS filing health for a firm. Use when the user asks how categorization is doing / categorization stats / cat-svc metrics / categorize success rate / categorization cost over a period, or wants to check for categorization errors/issues over a window.
---


# categorization-stats

Time-windowed health + metrics snapshot for the production **categorization
service** (`ecfx-backend-categorization-queue`, the live gRPC `Categorize` path),
sourced from **DuploCloud prod01 Loki** via the Grafana datasource proxy. This is
the recurring go-live-monitoring analysis, packaged so it can be run for any
period on demand.

Everything is derived from log lines emitted by `CategorizationGrpcService` /
`CategorizationHandler`, so the query vocabulary tracks those loggers.

## How to run

The worker is `cat_stats.py` in this skill's directory
(`${CLAUDE_SKILL_DIR}/cat_stats.py`). Default window is the last
24h; default target is prod01. It prints a readable report to stdout (or `--json`).
Report the headline (OK / failures / success rate / any errors / restarts /
enabled firms) and call out anything non-zero in the error rows.

```bash
# Last 24h (default), prod01:
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py

# Explicit window (RFC3339, UTC):
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py \
  --start 2026-07-21T00:00:00Z --end 2026-07-22T00:00:00Z

# Last N hours / days:
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py --hours 12
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py --days 7

# Include iManage DMS filing health for a firm (tenant slug, e.g. Bilzin):
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py --hours 48 --dms-slug bilzin

# Machine-readable:
python3 ${CLAUDE_SKILL_DIR}/cat_stats.py --hours 24 --json
```

**Auth (default):** runs `duplo-jit duplo --host https://duplo.cloud-prod.ecfxglobal.net
--interactive`, which uses the user's own cached DuploCloud login (opens a browser
if needed) and passes that token as `Authorization: Bearer` to the Grafana
datasource proxy — the same mechanism the `notice-stats` skill uses. Must be a
*DuploCloud* token, NOT a Grafana SA token (`glsa_…` gets bounced to login). No
stored secret. If a browser prompt appears, tell the user to complete the login.

## Flags

- `--hours N` / `--days N` — window = last N hours/days (default 24h).
- `--start` / `--end` — RFC3339 UTC bounds (`--end` defaults to now). Override `--hours`/`--days`.
- `--dms-slug SLUG` — also report iManage/DMS filing health for a firm's tenant slug
  (from `ecfx-backend-dms-queue`): literal-`{{category}}` count, iManage 400s,
  `DMSHttpClientUploadError` count, and the distribution of `subclass` values.
- `--json` — emit JSON instead of the text report.
- `--out PATH` — write to a file instead of stdout.
- `--token TOKEN` — pass a DuploCloud token directly and skip `duplo-jit` (headless).
- `--namespace` / `--service` / `--grafana-base` / `--duplo-host` — target a
  different environment (e.g. nonprod/dev01: `--grafana-base
  https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/datasources/proxy/uid/duplo-logging
  --namespace duploservices-dev01 --duplo-host https://duplo.cloud.ecfxglobal.net`).

## What it reports

**Headline counters** (over the window):
- `Categorize OK` — successful `Categorize` RPCs; success rate = OK / (OK + failures).
- `Categorize failures` — `UNAVAILABLE` / `Categorize ERROR` (terminal RPC failures).
- `Override INTERNAL` — `SubmitCategorizationOverride INTERNAL` (the ECFX-16173
  custom-category FK failure; treat as a known issue unless the count jumps).
- `Anthropic HTTP 500` — upstream Anthropic 5xx (usually retried; a burst is the concern).
- `RESOURCE_EXHAUSTED` — capacity-backpressure rejections (queue full / wait timeout).
- `ANY ERROR-level lines` — catch-all for new/unknown error types not in the list above.
- `Pod boots` vs `Real crashes` — see gotchas.

**Breakdowns:** Categorize OK by firm; category-code distribution; category-source
bands (`AI_AUTO` / `AI_FLAGGED` / `AI_UNC`); cost (USD) + input/output token totals.

**Enabled firms:** firms whose `categories_extract_enabled` gate logged `enabled=true`
with inbox traffic in-window (from `ecfx-backend-receipt-processing-queue`).

**DMS filing health (optional, `--dms-slug`):** the downstream iManage picture for
one firm — should be 0 unrendered `{{category}}` and 0 iManage 400s (ECFX-16121).

## Notes / gotchas

- **Pod boots vs real crashes.** `Startup completed` counts each JVM boot; **two
  together = a rolling deploy or node recycle (benign)**, and a scale-up adds one.
  Only `real_crash` (CrashLoopBackOff / OOMKilled / `java.lang.OutOfMemoryError`)
  is an incident. Do NOT match bare `OutOfMemory` — the JVM boot banner echoes
  `-XX:+ExitOnOutOfMemoryError` and would false-positive (this bit us mid-monitoring).
- **`OK=0` with zero errors is a traffic lull, not an incident** — the service logs
  only on requests; an idle window is empty, not stuck.
- **Enabled-firm list is traffic-gated.** A firm only appears if it had inbox items
  in-window, so a firm dropping out is a quiet window, not a de-provisioning.
- **Metrics ≠ logs.** Micromenter metrics like `ecfx.dms.render.category_token_used`
  live in Mimir/Prometheus, not Loki — this skill reads *log lines* only. Cost/tokens
  come from unwrapping the `Categorize OK` line fields, which is why they're log-derived.
- **Long windows are sharded** (6h chunks, summed) so a single `count_over_time`
  range vector never exceeds Loki's max range; scalar sums and per-label merges are
  associative, so this is lossless. A multi-week window just means more calls.
- **DMS is a different service.** The `--dms-slug` section queries
  `ecfx-backend-dms-queue` (iManage filing), which is downstream of and independent
  from the categorization service — useful for confirming end-to-end (categorize →
  file) health for a specific firm.
- **Keep the vocabulary in sync** with `CategorizationGrpcService` /
  `CategorizationHandler` log strings if those loggers change (e.g. the
  `Categorize OK … categoryCode= categorySource= costMicroUsd= inputTokens= outputTokens=`
  line shape).
