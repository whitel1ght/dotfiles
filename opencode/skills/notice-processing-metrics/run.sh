#!/usr/bin/env bash
# Notice-processing metrics over a chosen time window.
# Usage:
#   bash run.sh --days 7
#   bash run.sh --hours 24
#   bash run.sh --start 2026-05-27T00:00:00 --end 2026-05-28T00:00:00
# Any extra flags are passed straight through to pull_and_analyze.py.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$DIR/.venv"
PY="$VENV/bin/python"

# ---- 1. bootstrap an isolated venv (firm pip is pinned to CodeArtifact, so use public PyPI) ----
if [ ! -x "$PY" ]; then
  echo "[setup] creating venv + installing deps from public PyPI ..." >&2
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip >/dev/null
  "$VENV/bin/pip" install --quiet --index-url https://pypi.org/simple/ \
      pandas numpy openpyxl matplotlib boto3 >/dev/null
fi

# ---- 2. verify AWS creds reach the prod log account ----
if ! aws sts get-caller-identity --region "${NPM_REGION:-us-west-2}" >/dev/null 2>&1; then
  echo "[error] AWS credentials not available. Run an AWS login first (the log group lives in account 278643824850, us-west-2)." >&2
  exit 1
fi

# ---- 3. isolated, timestamped run dir so windows don't clobber each other ----
LABEL="$(date -u +%Y%m%dT%H%M%SZ)"
for a in "$@"; do case "$a" in --days|--hours|--start|--end) PREV="$a";; *) [ "${PREV:-}" ] && LABEL="${LABEL}_${PREV#--}${a//[:T-]/}" && PREV="";; esac; done
export NPM_RUN_DIR="$DIR/runs/$LABEL"
mkdir -p "$NPM_RUN_DIR"
echo "[run] output -> $NPM_RUN_DIR" >&2

# ---- 4. pull + analyze, then build both chart decks ----
"$PY" "$DIR/pull_and_analyze.py" all "$@"
"$PY" "$DIR/make_charts.py"                  # full deck (keeps dup/ignored context chart)
"$PY" "$DIR/make_charts.py" --exclude-noise  # clean exec deck (duplicates & ignored removed)

echo "" >&2
echo "[done] results in: $NPM_RUN_DIR" >&2
echo "  report.md ......................... $NPM_RUN_DIR/out/report.md" >&2
echo "  full workbook ..................... $NPM_RUN_DIR/out/notice_processing_metrics.xlsx" >&2
echo "  success-by-processor table ........ $NPM_RUN_DIR/out/success_by_processor.{xlsx,csv,md}" >&2
echo "  exec dashboard (clean) ............ $NPM_RUN_DIR/out/charts_excl_dup_ignored/00_dashboard.png" >&2
echo "  exec PDF deck (clean) ............. $NPM_RUN_DIR/out/charts_excl_dup_ignored/notice_processing_exec_deck.pdf" >&2
