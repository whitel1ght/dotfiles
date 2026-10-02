"""Shared plumbing for the notice-qa skill: environment constants, Jira, dev Loki, run storage.

Reuses the claude-components shared library (plugins/ops/lib): jira_metrics for Jira auth/ADF,
notice_loki for the DuploCloud token + Loki GET. Stdlib only otherwise.
"""
import datetime
import json
import os
import pathlib
import re
import sys
import urllib.parse

for _lib in (pathlib.Path(__file__).resolve().parents[2] / "lib", pathlib.Path.home() / ".claude" / "lib"):
    if (_lib / "jira_metrics.py").exists():
        sys.path.insert(0, str(_lib))
        break
import ecfx_credentials as creds  # noqa: E402  — the ~/.config/ecfx standard (docs/CREDENTIALS.md)
import jira_metrics as jm  # noqa: E402
import notice_loki as nl  # noqa: E402

DEV_ADMIN = "https://admin.development.cloud.ecfxglobal.net/"
NONPROD_DUPLO = "https://duplo.cloud.ecfxglobal.net"
NONPROD_LOKI = "https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/datasources/proxy/uid/duplo-logging"
DEV_NS = "duploservices-dev01"
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Everything a run produces lives here, one folder per ticket, so a later run can tell
# "duplicate of a notice from this ticket" from "duplicate of something processed before".
QA_HOME = pathlib.Path.home() / ".cache" / "notice-qa"


# M9: this cache holds full prod legal notices (parties, attorney addresses, document links).
# Everything a notice-qa script writes is private to the user — the same 700/600 as credentials.
os.umask(0o077)


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path, 0o700)            # tighten directories created before this rule existed
    return path


def ticket_dir(ticket):
    if not re.fullmatch(r"[A-Z][A-Z0-9]+-\d+", ticket or ""):
        raise ValueError(f"not a Jira key: {ticket!r}")
    private_dir(QA_HOME)
    d = private_dir(QA_HOME / ticket)
    private_dir(d / "emls")
    private_dir(d / "runs")
    return d


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc)


def dev_admin_link(inbox_id):
    return DEV_ADMIN + "inbox_item/details/?" + urllib.parse.urlencode({"id": inbox_id})


# ── Jira ─────────────────────────────────────────────────────────────────────

def jira_client():
    # jira_metrics reads ~/.config/ecfx/jira.env itself (its first candidate comes from ecfx_credentials),
    # so nothing is exported into the environment of the subprocesses this skill runs (N4).
    host, user, token = jm.load_credentials()
    return jm.JiraClient(host.replace("https://", "").rstrip("/"), user, token, verbose=False)


# ── dev Loki ─────────────────────────────────────────────────────────────────

_token = None


LOKI_MAX_RANGE = datetime.timedelta(days=30)   # server limit is 30d1h per query (measured 2026-09-28)


def loki_query(logql, since, until=None, limit=None):
    """ALL lines matching `logql` in [since, until], oldest first, ANSI stripped.

    Pages through Loki (lib/notice_loki.paginate_query) instead of taking one capped response —
    a truncated result drops the NEWEST lines, i.e. a child's final attempt or a late forbidden
    line (M6). Ranges longer than the server's 30-day cap are split into 30-day slices.
    `limit` is accepted for backward compatibility and ignored.
    """
    token = loki_token()
    until = until or utcnow()
    vals, lo = [], since
    while lo < until:
        hi = min(lo + LOKI_MAX_RANGE, until)
        vals += list(nl.paginate_query(NONPROD_LOKI, token, logql, int(lo.timestamp() * 1e9), int(hi.timestamp() * 1e9)))
        lo = hi
    return [ANSI.sub("", line) for _, line in sorted(vals, key=lambda v: v[0])]


def loki_token():
    """Shared read-only token from ~/.config/ecfx/duplo.env (or the container's DUPLO_TOKEN);
    without one, the user's own interactive DuploCloud login."""
    global _token
    if _token is None:
        d = creds.load("duplo", ("DUPLO_HOST", "DUPLO_TOKEN"))
        same_host = d.get("DUPLO_HOST", NONPROD_DUPLO).rstrip("/") == NONPROD_DUPLO
        _token = d["DUPLO_TOKEN"] if d.get("DUPLO_TOKEN") and same_host else nl.get_token(NONPROD_DUPLO)
    return _token


def loki_ping():
    """(ok, detail) from one cheap instant query — proves the token works, not just that it exists (N9)."""
    try:
        r = nl.loki_get(NONPROD_LOKI, loki_token(), "/loki/api/v1/query",
                        {"query": 'sum(count_over_time({namespace="%s"}[1m]))' % DEV_NS}, attempts=2)
        return r.get("status") == "success", "query ok"
    except SystemExit as e:
        return False, f"no DuploCloud token ({e})"
    except Exception as e:  # noqa: BLE001 — report any failure as "not ready"
        return False, f"{type(e).__name__}: {str(e)[:120]}"
