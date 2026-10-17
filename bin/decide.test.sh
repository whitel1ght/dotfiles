#!/bin/bash
# Tests for bin/decide. A sandbox state dir stands in for ~/.local/state/run-day.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/decide"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export RUN_DAY_STATE_DIR="$SANDBOX/state"
D="$RUN_DAY_STATE_DIR/decisions"
run() { "$SCRIPT" "$@" 2>&1; }

echo "add"
id="$(printf '@adam: "rename to trackCount" (nit)\nPipeline green.\n' | run add --key ecfx-18313 \
  --mr https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/315 --blocks merge \
  --question 'Fix the nit, or merge now?' --option 'Fix now, then merge' --option 'Merge, follow-up ticket' \
  --option 'Decline: the name stays' --recommend 1)"
check "prints the new id" "D-1" "$id"
f="$D/D-1.md"
[ -f "$f" ] && pass "writes the file" || fail "writes the file" "no $f"
has "frontmatter in field order" "$(sed -n 2,8p "$f" | cut -d: -f1 | tr '\n' ' ')" "id day key mr asked blocks status"
has "key upper-cased" "$(cat "$f")" "key: ECFX-18313"
has "status open" "$(cat "$f")" "status: open"
has "context from stdin" "$(cat "$f")" '@adam: "rename to trackCount" (nit)'
has "options numbered, recommended marked" "$(cat "$f")" "1. Fix now, then merge (recommended)"
[ -z "$(ls -A "$D" | grep -v '^D-1.md$')" ] && pass "no temp file left" || fail "no temp file left" "$(ls -A "$D")"

id2="$(run add --key '' --blocks 'reply: a "quoted" | piped' --question 'Weird: text | "quotes" ✓' --option a --option b </dev/null)"
check "second id" "D-2" "$id2"
has "awkward blocks survive" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .blocks')" 'reply: a "quoted" | piped'
has "awkward question survives" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .question')" 'Weird: text | "quotes" ✓'

echo "refusals"
run add --key X-1 --question q --option only </dev/null >/dev/null; check "one option refused" "1" "$?"
run add --key X-1 --question q --option a --option b --recommend 3 </dev/null >/dev/null; check "recommend out of range refused" "1" "$?"
run add --key 'not a key' --question q --option a --option b </dev/null >/dev/null; check "bad key refused" "1" "$?"
out="$(run add --key ECFX-18313 --question 'Fix the nit, or merge now?' --option a --option b </dev/null)"; code=$?
check "duplicate open question refused" "1" "$code"
has "names the existing one" "$out" "D-1"

echo "list"
out="$(run list)"
check "two open" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
has "first line is the blocking one with its MR" "$(printf '%s\n' "$out" | head -1)" "admin!315"
has "line shows blocks" "$out" "blocks merge"
check "json recommended" "1" "$(run list --json | jq -r '.[] | select(.id=="D-1") | .recommended')"
check "json no recommended" "null" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .recommended')"
printf 'garbage\n' > "$D/D-9.md"
out="$("$SCRIPT" list 2>"$SANDBOX/err")"
check "a bad file is skipped" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
has "and named on stderr" "$(cat "$SANDBOX/err")" "D-9.md"
rm "$D/D-9.md"

echo "show and count"
has "show prints the file" "$(run show D-1)" "## Question"
run show D-77 >/dev/null; check "show of a missing id exits 1" "1" "$?"
check "count" "2" "$(run count)"
check "badge" "✋ 2" "$(run count --badge)"
rm -rf "$D"
check "count is empty when nothing is open" "" "$(run count)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
