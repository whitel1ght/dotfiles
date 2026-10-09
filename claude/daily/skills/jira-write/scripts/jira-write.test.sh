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
assert_not_contains() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly found in [$1]" ;; *) pass "$3" ;; esac; }

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
  "POST issue/ECFX-1/transitions") ;;
  "POST issue/ECFX-1/comment") echo '{"id":"10001","self":"https://example.atlassian.net/rest/api/3/issue/10100/comment/10001"}' ;;
  "POST issue/ECFX-2/transitions") echo '{"errorMessages":["Transition is not valid"],"errors":{}}' ;;
  "GET issue/ECFX-2/transitions") echo '{"transitions":[{"id":"41","name":"In QA"}]}' ;;
  "GET issue/ECFX-3/transitions") echo '{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}' ;;
  "GET issue/ECFX-4/transitions") echo '<!DOCTYPE html><html><body>Login</body></html>' ;;
  "GET issue/ECFX-5/transitions") echo 'Unauthorized' ;;
  "GET issue/ECFX-6/transitions") echo 'curl: (6) Could not resolve host' >&2; exit 6 ;;
  "GET issue/ECFX-7/transitions") echo '{"message":"Forbidden"}' ;;
  "GET issue/ECFX-8/transitions"|"GET issue/ECFX-9/transitions"|"GET issue/ECFX-10/transitions"|"GET issue/ECFX-11/transitions"|"GET issue/ECFX-12/transitions")
    echo '{"transitions":[{"id":"41","name":"In QA"}]}' ;;
  "POST issue/ECFX-8/transitions") echo '<html><body>Unauthorized</body></html>' ;;
  "POST issue/ECFX-9/transitions") echo 'Unauthorized' ;;
  "POST issue/ECFX-10/transitions") echo '{"message":"Forbidden"}' ;;
  "POST issue/ECFX-11/transitions") echo '{}' ;;
  "POST issue/ECFX-12/transitions") echo 'curl: (22) The requested URL returned error: 500' >&2; exit 22 ;;
  "POST issue/ECFX-13/comment") echo '<html><body>Login</body></html>' ;;
  "POST issue/ECFX-14/comment") echo 'Unauthorized' ;;
  "POST issue/ECFX-15/comment") echo '{"message":"Forbidden"}' ;;
  "POST issue/ECFX-16/comment") echo '{}' ;;
  "POST issue/ECFX-17/comment") echo 'curl: (22) The requested URL returned error: 500' >&2; exit 22 ;;
  *) echo '{}' ;;
esac
S
chmod +x "$JIRA_API"
reset_log() { : > "$STUB_LOG"; }
log_lines() { wc -l < "$STUB_LOG" | tr -d ' '; }

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
assert_eq "1" "$(log_lines)" "nothing is posted for an unknown status"

reset_log
out="$("$JW" --dry-run transition ECFX-1 "In QA" 2>&1)"; rc=$?
assert_eq "0" "$rc" "dry run exits 0"
assert_contains "$out" 'would move ECFX-1 to "In QA" (transition id 41)' "dry run says what it would do"
assert_eq "1" "$(log_lines)" "dry run only reads"

out="$("$JW" transition ECFX-2 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a Jira error body fails the command"
assert_contains "$out" "Transition is not valid" "and shows Jira's message"

echo "== transition: unrecognized responses fail closed =="
reset_log
out="$("$JW" transition ECFX-3 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "GET transitions 404 error body exits 1, not 3"
assert_contains "$out" "does not exist" "GET error body is shown"
assert_not_contains "$out" "no transition named" "GET error body is not read as an empty transition list"
assert_eq "1" "$(log_lines)" "nothing is posted after a failed GET"

out="$("$JW" transition ECFX-4 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "GET transitions returning HTML exits 1"
assert_contains "$out" "Login" "GET HTML body is shown"

out="$("$JW" transition ECFX-5 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "GET transitions returning plain text exits 1"
assert_contains "$out" "Unauthorized" "GET plain-text body is shown"

out="$("$JW" transition ECFX-7 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "GET transitions returning {message} exits 1"
assert_contains "$out" "Forbidden" "GET {message} body is shown"

out="$("$JW" transition ECFX-6 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "jira-api failing on GET exits 1"
assert_contains "$out" "jira-api failed" "jira-api failure is reported"

out="$("$JW" transition ECFX-8 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "POST transition returning HTML exits 1"
assert_contains "$out" "<html>" "POST HTML body is shown"
assert_not_contains "$out" "ECFX-8 -> In QA" "POST HTML is not reported as a move"

out="$("$JW" transition ECFX-9 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "POST transition returning plain text exits 1"
assert_contains "$out" "Unauthorized" "POST plain-text body is shown"

out="$("$JW" transition ECFX-10 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "POST transition returning {message} exits 1"
assert_contains "$out" "Forbidden" "POST {message} body is shown"

out="$("$JW" transition ECFX-11 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "POST transition with a non-empty JSON body exits 1"
assert_not_contains "$out" "ECFX-11 -> In QA" "non-empty body is not reported as a move"

out="$("$JW" transition ECFX-12 "In QA" 2>&1)"; rc=$?
assert_eq "1" "$rc" "jira-api failing on POST exits 1"
assert_contains "$out" "jira-api failed" "jira-api POST failure is reported"

echo "== comment =="
printf 'First paragraph.\n\nSecond one,\nsame paragraph.\n' > "$SANDBOX/c.md"
reset_log
out="$("$JW" comment ECFX-1 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "0" "$rc" "comment exits 0"
assert_contains "$out" "commented on ECFX-1" "reports the comment when Jira returns an id"
body="$(sed -n 's/^POST issue\/ECFX-1\/comment //p' "$STUB_LOG")"
assert_eq "doc" "$(printf '%s' "$body" | jq -r '.body.type')" "sends an ADF document"
assert_eq "2" "$(printf '%s' "$body" | jq '.body.content | length')" "one ADF paragraph per blank-line block"
assert_eq "Second one,
same paragraph." "$(printf '%s' "$body" | jq -r '.body.content[1].content[0].text')" "keeps line breaks inside a paragraph"

reset_log
out="$("$JW" --dry-run comment ECFX-1 "$SANDBOX/c.md" 2>&1)"
assert_contains "$out" "would comment on ECFX-1 (2 paragraph(s))" "dry run counts paragraphs"
assert_eq "0" "$(log_lines)" "dry run comment sends nothing"

echo "== comment: unrecognized responses fail closed =="
out="$("$JW" comment ECFX-13 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "comment answered with HTML exits 1"
assert_contains "$out" "<html>" "comment HTML body is shown"
assert_not_contains "$out" "commented on" "comment HTML is not reported as written"

out="$("$JW" comment ECFX-14 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "comment answered with plain text exits 1"
assert_contains "$out" "Unauthorized" "comment plain-text body is shown"
assert_not_contains "$out" "commented on" "comment plain text is not reported as written"

out="$("$JW" comment ECFX-15 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "comment answered with {message} exits 1"
assert_contains "$out" "Forbidden" "comment {message} body is shown"
assert_not_contains "$out" "commented on" "comment {message} is not reported as written"

out="$("$JW" comment ECFX-16 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "comment JSON without an id exits 1"
assert_not_contains "$out" "commented on" "comment without an id is not reported as written"

out="$("$JW" comment ECFX-17 "$SANDBOX/c.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "jira-api failing on comment exits 1"
assert_contains "$out" "jira-api failed" "jira-api comment failure is reported"

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
