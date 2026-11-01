#!/usr/bin/env python3
"""
categorization-stats — pull ECFX cat-svc (categorization) health + metrics for a
time window from DuploCloud prod Loki, the same data we analyze during go-live
monitoring.

Source: prod01 Loki via the Grafana datasource proxy. Service
`ecfx-backend-categorization-queue` (the live gRPC Categorize service) plus, for
the firm-enablement gate, `ecfx-backend-receipt-processing-queue`. Optional DMS
iManage filing-health for a tenant slug via `ecfx-backend-dms-queue`.

Auth: a *DuploCloud* token (NOT a Grafana SA token) passed as `Authorization:
Bearer` to the datasource proxy. By default obtained via
`duplo-jit duplo --host <prod> --interactive` (cached; opens a browser if needed).
Pass --token to skip duplo-jit (e.g. headless).

Everything is derived from log lines emitted by CategorizationGrpcService /
CategorizationHandler, so the vocabulary below must track those loggers.

Usage:
  # Last 24h (default), prod, human-readable report:
  python3 cat_stats.py

  # Explicit window (RFC3339 UTC):
  python3 cat_stats.py --start 2026-07-21T00:00:00Z --end 2026-07-22T00:00:00Z

  # Last N hours / days:
  python3 cat_stats.py --hours 12
  python3 cat_stats.py --days 7

  # Machine-readable:
  python3 cat_stats.py --hours 24 --json

  # Include iManage DMS filing-health for a firm (tenant slug):
  python3 cat_stats.py --hours 48 --dms-slug bilzin

  # Target a different environment (e.g. nonprod/dev01):
  python3 cat_stats.py --grafana-base https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/datasources/proxy/uid/duplo-logging \
                       --namespace duploservices-dev01 --duplo-host https://duplo.cloud.ecfxglobal.net
"""
import argparse, json, subprocess, sys, time, urllib.request, urllib.parse
from datetime import datetime, timezone

DEFAULT_GRAFANA_BASE = ("https://grafana-proxy-otel-prod01.cloud-prod.ecfxglobal.net"
                        "/api/datasources/proxy/uid/duplo-logging")
DEFAULT_DUPLO_HOST = "https://duplo.cloud-prod.ecfxglobal.net"
DEFAULT_NAMESPACE = "duploservices-prod01"
DEFAULT_SERVICE = "ecfx-backend-categorization-queue"
GATE_SERVICE = "ecfx-backend-receipt-processing-queue"
DMS_SERVICE = "ecfx-backend-dms-queue"

# Shard long windows so a single count_over_time range vector never exceeds
# Loki's max range; per-shard scalar sums and per-label dict merges are both
# associative, so sharding is lossless.
SHARD_SECONDS = 6 * 3600


def eprint(*a):
    print(*a, file=sys.stderr, flush=True)


def get_token(duplo_host):
    eprint(f"Authenticating to DuploCloud ({duplo_host}) via duplo-jit …")
    try:
        out = subprocess.run(["duplo-jit", "duplo", "--host", duplo_host, "--interactive"],
                             capture_output=True, text=True)
    except FileNotFoundError:
        eprint("ERROR: duplo-jit not found on PATH. Install it or pass --token.")
        sys.exit(2)
    if out.returncode != 0:
        eprint("ERROR: duplo-jit failed:\n" + out.stderr.strip())
        sys.exit(2)
    try:
        d = json.loads(out.stdout)
    except json.JSONDecodeError:
        eprint("ERROR: could not parse duplo-jit output")
        sys.exit(2)
    tok = d.get("DuploToken") or d.get("Token") or d.get("token")
    if not tok:
        eprint("ERROR: no token field in duplo-jit output")
        sys.exit(2)
    return tok


def loki_instant(base, token, query, at_epoch, attempts=4):
    params = {"query": query, "time": str(at_epoch)}
    url = base + "/loki/api/v1/query?" + urllib.parse.urlencode(params)
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry any transient failure
            last = e
            time.sleep(1.5 * (i + 1))
    raise RuntimeError(f"Loki query failed after {attempts} attempts: {last}\nquery={query}")


def shards(start_dt, end_dt):
    s = int(start_dt.timestamp())
    e = int(end_dt.timestamp())
    cur = s
    while cur < e:
        nxt = min(cur + SHARD_SECONDS, e)
        yield cur, nxt
        cur = nxt


def scalar_over_window(base, token, selector, line_filter, start_dt, end_dt):
    """sum(count_over_time(<selector> <line_filter> [shard])) summed across shards."""
    total = 0.0
    for s, e in shards(start_dt, end_dt):
        dur = e - s
        q = f"sum(count_over_time({selector} {line_filter} [{dur}s]))"
        d = loki_instant(base, token, q, e)
        res = d.get("data", {}).get("result", [])
        if res:
            total += float(res[0]["value"][1])
    return int(total)


def bylabel_over_window(base, token, selector, pipeline, label, start_dt, end_dt):
    """sum by (label)(count_over_time(<selector> <pipeline> [shard])) merged across shards."""
    acc = {}
    for s, e in shards(start_dt, end_dt):
        dur = e - s
        q = f"sum by ({label}) (count_over_time({selector} {pipeline} [{dur}s]))"
        d = loki_instant(base, token, q, e)
        for row in d.get("data", {}).get("result", []):
            key = row["metric"].get(label, "(none)")
            acc[key] = acc.get(key, 0.0) + float(row["value"][1])
    return {k: int(v) for k, v in acc.items()}


def unwrap_sum(base, token, selector, line_filter, regexp, field, start_dt, end_dt):
    """sum(sum_over_time(<selector> <line_filter> | regexp | unwrap field [shard]))."""
    total = 0.0
    ok = False
    for s, e in shards(start_dt, end_dt):
        dur = e - s
        q = (f"sum(sum_over_time({selector} {line_filter} | regexp `{regexp}` "
             f"| unwrap {field} [{dur}s]))")
        try:
            d = loki_instant(base, token, q, e)
        except Exception:
            return None
        res = d.get("data", {}).get("result", [])
        if res:
            total += float(res[0]["value"][1]); ok = True
    return int(total) if ok else 0


def collect(base, token, namespace, service, start_dt, end_dt, dms_slug=None):
    sel = '{namespace="%s", service_name="%s"}' % (namespace, service)
    gate = '{namespace="%s", service_name="%s"}' % (namespace, GATE_SERVICE)

    out = {
        "window": {"start": start_dt.isoformat(), "end": end_dt.isoformat(),
                   "hours": round((end_dt - start_dt).total_seconds() / 3600, 2)},
        "service": service,
        "namespace": namespace,
    }

    # ---- headline counters ----
    eprint("Collecting headline counters …")
    counters = {
        # Categorize outcomes
        "categorize_ok":        '|= `Categorize OK`',
        "categorize_start":     '|= `Categorize START`',
        "categorize_fail":      '|~ `UNAVAILABLE|Categorize ERROR`',   # Categorize RPC terminal failures
        # Known error classes
        "override_internal":    '|= `SubmitCategorizationOverride INTERNAL`',  # ECFX-16173 (custom-cat FK)
        "anthropic_500":        '|= `Anthropic API error httpStatus=500`',
        "resource_exhausted":   '|= `RESOURCE_EXHAUSTED`',             # capacity backpressure rejections
        # Any ERROR-level line (catch-all for new/unknown issues)
        "any_error_level":      '|~ ` ERROR `',
        # Pod lifecycle. NOTE: do NOT match bare "OutOfMemory" — the JVM boot
        # banner echoes -XX:+ExitOnOutOfMemoryError and false-positives. Count
        # clean boots separately from real crashes.
        "pod_boots":            '|= `Startup completed`',
        "real_crash":           '|~ `CrashLoopBackOff|OOMKilled|java.lang.OutOfMemoryError`',
    }
    out["counters"] = {k: scalar_over_window(base, token, sel, f, start_dt, end_dt)
                       for k, f in counters.items()}

    # ---- breakdowns ----
    eprint("Collecting breakdowns …")
    out["ok_by_firm"] = bylabel_over_window(
        base, token, sel, '|= `Categorize OK` | regexp `firmId=(?P<firm>[0-9]+)`',
        "firm", start_dt, end_dt)
    out["category_codes"] = bylabel_over_window(
        base, token, sel, '|= `Categorize OK` | regexp `categoryCode=(?P<code>[A-Z]+)`',
        "code", start_dt, end_dt)
    out["category_source"] = bylabel_over_window(
        base, token, sel, '|= `Categorize OK` | regexp `categorySource=(?P<src>[A-Z_]+)`',
        "src", start_dt, end_dt)

    # ---- cost & tokens (unwrap numeric fields off the Categorize OK line) ----
    eprint("Collecting cost & tokens …")
    cost_micro = unwrap_sum(base, token, sel, '|= `Categorize OK`',
                            "costMicroUsd=(?P<cost>[0-9]+)", "cost", start_dt, end_dt)
    in_tok = unwrap_sum(base, token, sel, '|= `Categorize OK`',
                        "inputTokens=(?P<t>[0-9]+)", "t", start_dt, end_dt)
    out_tok = unwrap_sum(base, token, sel, '|= `Categorize OK`',
                         "outputTokens=(?P<t>[0-9]+)", "t", start_dt, end_dt)
    out["cost_tokens"] = {
        "cost_usd": round(cost_micro / 1_000_000, 4) if cost_micro is not None else None,
        "input_tokens": in_tok, "output_tokens": out_tok,
    }

    # ---- firm-enablement gate (which firms are actually opted in + flowing) ----
    eprint("Collecting firm-enablement gate …")
    out["enabled_firms"] = sorted(bylabel_over_window(
        base, token, gate,
        '|= `Categorization extract gate` |= `enabled=true` | regexp `firmId=(?P<firm>[0-9]+)`',
        "firm", start_dt, end_dt).keys(), key=lambda x: int(x) if x.isdigit() else 0)

    # ---- optional DMS/iManage filing health for a tenant slug ----
    if dms_slug:
        eprint(f"Collecting DMS filing health for slug '{dms_slug}' …")
        dsel = '{namespace="%s", service_name="%s"}' % (namespace, DMS_SERVICE)
        base_f = '|= `%s:`' % dms_slug
        dms = {
            "total_lines":         scalar_over_window(base, token, dsel, base_f, start_dt, end_dt),
            "document_profiles":   scalar_over_window(base, token, dsel, base_f + ' |= `Document Profile`', start_dt, end_dt),
            "unrendered_category": scalar_over_window(base, token, dsel, base_f + ' |= `Document Profile` |= `{{category}}`', start_dt, end_dt),
            "imanage_400":         scalar_over_window(base, token, dsel, base_f + ' |~ `BAD REQUEST|NRC_INVALID_PROFILE|ERROR SAVING`', start_dt, end_dt),
            "upload_errors":       scalar_over_window(base, token, dsel, base_f + ' |= `DMSHttpClientUploadError`', start_dt, end_dt),
        }
        dms["subclass_values"] = bylabel_over_window(
            base, token, dsel,
            base_f + ' |= `Document Profile` | regexp `"subclass":"(?P<subclass>[^"]*)"`',
            "subclass", start_dt, end_dt)
        out["dms_filing"] = {"slug": dms_slug, **dms}

    return out


def render_text(r):
    w = r["window"]
    L = []
    L.append(f"ECFX categorization stats — {r['service']} ({r['namespace']})")
    L.append(f"Window: {w['start']} → {w['end']}  ({w['hours']}h)")
    L.append("")
    c = r["counters"]
    ok = c["categorize_ok"]
    fails = c["categorize_fail"]
    denom = ok + fails
    succ = f"{100.0*ok/denom:.1f}%" if denom else "n/a"
    L.append("HEADLINE")
    L.append(f"  Categorize OK ............ {ok}")
    L.append(f"  Categorize failures ...... {fails}   (success rate {succ})")
    L.append(f"  Override INTERNAL ........ {c['override_internal']}   (ECFX-16173 custom-cat FK)")
    L.append(f"  Anthropic HTTP 500 ....... {c['anthropic_500']}")
    L.append(f"  RESOURCE_EXHAUSTED ....... {c['resource_exhausted']}   (capacity backpressure)")
    L.append(f"  ANY ERROR-level lines .... {c['any_error_level']}")
    L.append(f"  Pod boots ................ {c['pod_boots']}   (2 together = a deploy/recycle, benign)")
    L.append(f"  Real crashes (CrashLoop/OOM) {c['real_crash']}")
    L.append("")
    ct = r["cost_tokens"]
    cost = f"${ct['cost_usd']}" if ct.get("cost_usd") is not None else "n/a"
    L.append(f"COST & TOKENS   cost={cost}  input_tokens={ct['input_tokens']}  output_tokens={ct['output_tokens']}")
    L.append("")
    L.append("ENABLED FIRMS (had inbox traffic through the gate in-window): "
             + (", ".join(r["enabled_firms"]) or "none"))
    L.append("")

    def table(title, d, keyw=8):
        L.append(title)
        if not d:
            L.append("  (none)"); L.append(""); return
        for k, v in sorted(d.items(), key=lambda kv: (-kv[1], kv[0])):
            L.append(f"  {str(k):<{keyw}} {v}")
        L.append("")

    table("CATEGORIZE OK BY FIRM", r["ok_by_firm"])
    table("CATEGORY CODES", r["category_codes"])
    table("CATEGORY SOURCE (band)", r["category_source"], keyw=14)

    if "dms_filing" in r:
        f = r["dms_filing"]
        L.append(f"DMS / iMANAGE FILING HEALTH — slug '{f['slug']}'")
        L.append(f"  total DMS lines .......... {f['total_lines']}")
        L.append(f"  document profiles ........ {f['document_profiles']}")
        L.append(f"  UNRENDERED {{{{category}}}} .... {f['unrendered_category']}   (ECFX-16121 — should be 0)")
        L.append(f"  iManage 400s ............. {f['imanage_400']}   (should be 0)")
        L.append(f"  DMSHttpClientUploadError . {f['upload_errors']}")
        table("  subclass values", f["subclass_values"], keyw=12)
    return "\n".join(L)


def parse_dt(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def main():
    ap = argparse.ArgumentParser(description="ECFX cat-svc categorization stats for a time window (prod01 Loki).")
    ap.add_argument("--hours", type=float, help="window = last N hours")
    ap.add_argument("--days", type=float, help="window = last N days")
    ap.add_argument("--start", help="RFC3339 UTC start (overrides --hours/--days)")
    ap.add_argument("--end", help="RFC3339 UTC end (default: now)")
    ap.add_argument("--dms-slug", help="also report iManage DMS filing health for this tenant slug (e.g. bilzin)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of a text report")
    ap.add_argument("--token", help="DuploCloud bearer token (skip duplo-jit)")
    ap.add_argument("--namespace", default=DEFAULT_NAMESPACE)
    ap.add_argument("--service", default=DEFAULT_SERVICE)
    ap.add_argument("--grafana-base", default=DEFAULT_GRAFANA_BASE)
    ap.add_argument("--duplo-host", default=DEFAULT_DUPLO_HOST)
    ap.add_argument("--out", help="write report to this path (default: stdout)")
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    end_dt = parse_dt(args.end) if args.end else now
    if args.start:
        start_dt = parse_dt(args.start)
    elif args.days:
        start_dt = end_dt.fromtimestamp(end_dt.timestamp() - args.days * 86400, tz=timezone.utc)
    else:
        hours = args.hours if args.hours else 24.0
        start_dt = end_dt.fromtimestamp(end_dt.timestamp() - hours * 3600, tz=timezone.utc)
    if start_dt >= end_dt:
        eprint("ERROR: start must be before end"); sys.exit(1)

    token = args.token or get_token(args.duplo_host)
    eprint(f"Window: {start_dt.isoformat()} → {end_dt.isoformat()}  ({args.service} / {args.namespace})")

    result = collect(args.grafana_base, token, args.namespace, args.service,
                     start_dt, end_dt, dms_slug=args.dms_slug)

    text = json.dumps(result, indent=2) if args.json else render_text(result)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
        eprint(f"Wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
