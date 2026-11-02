#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if DECISIONS_BIN="$TMP/missing" "$HERE/frictions" list >"$TMP/out" 2>&1; then
  echo 'missing executable unexpectedly succeeded' >&2; exit 1
fi
grep -q 'decisions binary is not built' "$TMP/out"
cat > "$TMP/decisions" <<'STUB'
#!/usr/bin/env bash
printf 'dir=%s\ntitle=%s\nstrip=%s\ntelegram=%s\nargs=%s\n' "$DECISIONS_DIR" "$DECISIONS_TITLE" "$DECISIONS_MR_STRIP" "${DECISIONS_TELEGRAM_TOKEN_CMD:-}" "$*"
STUB
chmod +x "$TMP/decisions"
OUT="$(DECISIONS_BIN="$TMP/decisions" COACH_STATE_DIR="$TMP/state" "$HERE/frictions" list)"
grep -q "dir=$TMP/state/cards" <<<"$OUT"
grep -q 'title=frictions' <<<"$OUT"
grep -q 'strip=' <<<"$OUT"
grep -q 'telegram=$' <<<"$OUT"
grep -q 'args=list' <<<"$OUT"
echo 'passed: frictions wrapper missing-runtime failure and no-telegram/queue contract'
