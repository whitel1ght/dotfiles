#!/usr/bin/env bash
# Tests for jira-write against a stub jira-api. No network.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JW="$TEST_DIR/jira-write"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not found in [$1]" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export STUB_LOG="$SANDBOX/calls.log"
export JIRA_API="$SANDBOX/jira-api"
cat > "$JIRA_API" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "GET issue/ECFX-1/transitions")
    echo '{"transitions":[{"id":"31","name":"In Progress"},{"id":"41","name":"In QA"}]}' ;;
  "POST issue/ECFX-2/transitions") echo '{"errorMessages":["Transition is not valid"],"errors":{}}' ;;
  "GET issue/ECFX-2/transitions") echo '{"transitions":[{"id":"41","name":"In QA"}]}' ;;
  *) echo '{}' ;;
esac
S
chmod +x "$JIRA_API"
reset_log() { : > "$STUB_LOG"; }

echo "== transition =="
reset_log
out="$("$JW" transition ECFX-1 "in qa" 2>&1)"; rc=$?
assert_eq "0" "$rc" "transition by name exits 0"
assert_contains "$(cat "$STUB_LOG")" 'POST issue/ECFX-1/transitions {"transition":{"id":"41"}}' "posts the resolved id"
assert_contains "$out" "ECFX-1 -> in qa" "reports the move"

reset_log
out="$("$JW" transition ecfx-1 "In Progress" 2>&1)"
assert_contains "$(cat "$STUB_LOG")" "GET issue/ECFX-1/transitions" "lowercase key is upper-cased"

reset_log
out="$("$JW" transition ECFX-1 "Done" 2>&1)"; rc=$?
assert_eq "3" "$rc" "unknown status exits 3"
assert_contains "$out" "- In QA" "lists the available transitions"
assert_eq "1" "$(wc -l < "$STUB_LOG" | tr -d ' ')" "nothing is posted for an unknown status"

reset_log
out="$("$JW" --dry-run transition ECFX-1 "In QA" 2>&1)"; rc=$?
assert_eq "0" "$rc" "dry run exits 0"
assert_contains "$out" 'would move ECFX-1 to "In QA" (transition id 41)' "dry run says what it would do"
assert_eq "1" "$(wc -l < "$STUB_LOG" | tr -d ' ')" "dry run only reads"

out="$("$JW" transition ECFX-2 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a Jira error body fails the command"
assert_contains "$out" "Transition is not valid" "and shows Jira's message"

echo "== comment =="
printf 'First paragraph.\n\nSecond one,\nsame paragraph.\n' > "$SANDBOX/c.md"
reset_log
"$JW" comment ECFX-1 "$SANDBOX/c.md" >/dev/null 2>&1; rc=$?
assert_eq "0" "$rc" "comment exits 0"
body="$(sed -n 's/^POST issue\/ECFX-1\/comment //p' "$STUB_LOG")"
assert_eq "doc" "$(printf '%s' "$body" | jq -r '.body.type')" "sends an ADF document"
assert_eq "2" "$(printf '%s' "$body" | jq '.body.content | length')" "one ADF paragraph per blank-line block"
assert_eq "Second one,
same paragraph." "$(printf '%s' "$body" | jq -r '.body.content[1].content[0].text')" "keeps line breaks inside a paragraph"

reset_log
out="$("$JW" --dry-run comment ECFX-1 "$SANDBOX/c.md" 2>&1)"
assert_contains "$out" "would comment on ECFX-1 (2 paragraph(s))" "dry run counts paragraphs"
assert_eq "0" "$(wc -l < "$STUB_LOG" | tr -d ' ')" "dry run comment sends nothing"

: > "$SANDBOX/empty.md"
"$JW" comment ECFX-1 "$SANDBOX/empty.md" >/dev/null 2>&1; assert_eq "2" "$?" "empty file exits 2"
"$JW" comment ECFX-1 "$SANDBOX/missing.md" >/dev/null 2>&1; assert_eq "2" "$?" "missing file exits 2"

echo "== arguments =="
"$JW" transition "bad key" "In QA" >/dev/null 2>&1; assert_eq "2" "$?" "bad key exits 2"
"$JW" transition ECFX-1 >/dev/null 2>&1; assert_eq "2" "$?" "missing argument exits 2"
"$JW" frobnicate ECFX-1 x >/dev/null 2>&1; assert_eq "2" "$?" "unknown command exits 2"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
