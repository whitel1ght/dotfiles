#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if DECISIONS_BIN="$TMP/missing" "$HERE/decisions" list >"$TMP/out" 2>&1; then
  echo 'missing executable unexpectedly succeeded' >&2; exit 1
fi
grep -q 'decisions binary is not built' "$TMP/out"
cat > "$TMP/decisions" <<'STUB'
#!/usr/bin/env bash
printf 'dir=%s\nstrip=%s\nargs=%s\n' "$DECISIONS_DIR" "$DECISIONS_MR_STRIP" "$*"
STUB
chmod +x "$TMP/decisions"
OUT="$(DECISIONS_BIN="$TMP/decisions" RUN_DAY_STATE_DIR="$TMP/state" "$HERE/decisions" telegram run)"
grep -q "dir=$TMP/state/decisions" <<<"$OUT"
grep -q 'strip=ecfx-' <<<"$OUT"
grep -q 'args=telegram run' <<<"$OUT"

# A fake standalone runtime exercises the wrapper's exported callback without
# starting the real decisions process. Spaces in both repo and state paths test
# that DECISIONS_ON_ANSWER remains a valid shell command.
REPO="$TMP/dot files/bin"
mkdir -p "$REPO"
cp "$HERE/decisions" "$REPO/decisions"
cp "$HERE/run-day-inbox-answer" "$REPO/run-day-inbox-answer"
cat > "$TMP/event-runtime" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$EVENT" | bash -c "$DECISIONS_ON_ANSWER"
printf 'callback=%s\n' "$DECISIONS_ON_ANSWER"
STUB
chmod +x "$TMP/event-runtime"
EVENT="$(jq -cn --arg text 'answer with spaces and "quotes"' '{event:"answered",id:"D-7",key:"ECFX-1",source:"",option:2,note:null,text:$text,at:"2026-10-20T11:20:00+03:00"}')"
STATE="$TMP/state with spaces"
OUT="$(HOME="$TMP/home" RUN_DAY_STATE_DIR="$STATE" DECISIONS_BIN="$TMP/event-runtime" EVENT="$EVENT" "$REPO/decisions" answer)"
EXPECTED_CALLBACK="$(printf %q "$REPO/run-day-inbox-answer")"
grep -Fq "callback=$EXPECTED_CALLBACK" <<<"$OUT"
FILES=("$STATE/inbox"/*.md)
[ "${#FILES[@]}" -eq 1 ]
grep -Fxq 'key: ECFX-1' "${FILES[0]}"
grep -Fxq 'kind: decision' "${FILES[0]}"
grep -Fxq 'decision: D-7' "${FILES[0]}"
grep -Fxq 'answer with spaces and "quotes"' "${FILES[0]}"
echo 'passed: decisions wrapper missing-runtime, environment, arguments, and answer callback contract'
