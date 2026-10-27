#!/bin/bash
# Tests for bin/jira-issue. jira-api is a fake binary on PATH that answers from a
# fixture file, so nothing here reaches Jira.
set -uo pipefail
# Never fall back to the real secrets file (scripts read Jira credentials from it).
export SECRETS_FILE=/nonexistent/secrets.env

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/jira-issue"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] found in [$1]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"
mkdir -p "$STUBS" "$FIX"
export FIX PATH="$STUBS:$PATH"

# jira-api <METHOD> <path>: logs its arguments, then answers from $FIX/issue.json.
# JIRA_STUB_FAIL=<msg> exits 1 with that message; JIRA_STUB_RAW=<text> answers non-JSON.
cat > "$STUBS/jira-api" <<'STUB'
#!/bin/bash
echo "$*" >> "${FIX:?}/jira.log"
[ -n "${JIRA_STUB_FAIL:-}" ] && { echo "$JIRA_STUB_FAIL" >&2; exit 1; }
[ -n "${JIRA_STUB_RAW:-}" ] && { echo "$JIRA_STUB_RAW"; exit 0; }
cat "$FIX/issue.json"
STUB
chmod +x "$STUBS/jira-api"

cat > "$FIX/issue.json" <<'JSON'
{"key":"ECFX-1","fields":{
 "summary":"Fix the thing",
 "status":{"name":"In Progress","id":"3"},
 "assignee":{"displayName":"Dmitry M","accountId":"abc"},
 "reporter":{"displayName":"Rita R"},
 "issuetype":{"name":"Bug"},
 "priority":{"name":"High"},
 "labels":["a","b"],
 "components":[{"name":"dashboard"},{"name":"backend"}],
 "parent":{"key":"ECFX-9","fields":{"summary":"Big epic"}},
 "issuelinks":[{"type":{"outward":"blocks","inward":"is blocked by"},"outwardIssue":{"key":"ECFX-2","fields":{"summary":"Other"}}}],
 "comment":{"comments":[{"author":{"displayName":"Rita R"},"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Please check"}]}]}}]},
 "customfield_1":{"x":1},
 "description":{"type":"doc","version":1,"content":[
  {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Context"}]},
  {"type":"paragraph","content":[{"type":"text","text":"First line"},{"type":"hardBreak"},{"type":"text","text":"second line"}]},
  {"type":"bulletList","content":[
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"item one"}]}]},
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"item two"}]}]}]}]}}}
JSON

echo "jira-issue — default fields"
: > "$FIX/jira.log"
out=$("$SCRIPT" ECFX-1 2>"$SANDBOX/err"); rc=$?
assert_eq "0" "$rc" "exit 0"
assert_contains "$out" "Summary: Fix the thing" "summary prints"
assert_contains "$out" "Status: In Progress" "status prints its name"
assert_contains "$out" "Assignee: Dmitry M" "assignee prints its display name"
assert_lacks "$out" "Reporter" "a field that was not requested does not print"
assert_lacks "$out" "Bug" "issuetype does not print by default"
assert_lacks "$out" "accountId" "no raw JSON leaks"
assert_eq "GET issue/ECFX-1?fields=summary,status,assignee,description" "$(cat "$FIX/jira.log")" "asks jira-api for only the default fields"

echo "jira-issue — ADF description as plain text"
assert_contains "$out" "Description:" "description label"
assert_contains "$out" "Context" "heading text"
assert_contains "$out" "First line"$'\n'"second line" "hardBreak is a line break"
assert_contains "$out" "- item one"$'\n'"- item two" "list items on their own lines"
assert_lacks "$out" '"type"' "no ADF nodes in the output"

echo "jira-issue — missing description"
jq '.fields.description = null' "$FIX/issue.json" > "$FIX/null.json"
cp "$FIX/issue.json" "$FIX/full.json"; cp "$FIX/null.json" "$FIX/issue.json"
out=$("$SCRIPT" ECFX-1 2>&1)
assert_contains "$out" "Description: (none)" "null description prints (none)"
jq 'del(.fields.description)' "$FIX/full.json" > "$FIX/issue.json"
out=$("$SCRIPT" ECFX-1 2>&1)
assert_contains "$out" "Description: (none)" "absent description prints (none)"
jq '.fields.assignee = null' "$FIX/full.json" > "$FIX/issue.json"
out=$("$SCRIPT" ECFX-1 2>&1)
assert_contains "$out" "Assignee: (unassigned)" "null assignee prints (unassigned)"
cp "$FIX/full.json" "$FIX/issue.json"

echo "jira-issue — --fields"
: > "$FIX/jira.log"
out=$("$SCRIPT" ECFX-1 --fields issuetype,priority,labels,components,parent,issuelinks,comment,customfield_1 2>&1)
assert_eq "GET issue/ECFX-1?fields=issuetype,priority,labels,components,parent,issuelinks,comment,customfield_1" "$(cat "$FIX/jira.log")" "passes the custom list through"
assert_contains "$out" "Issuetype: Bug" "issuetype name"
assert_contains "$out" "Priority: High" "priority name"
assert_contains "$out" "Labels: a, b" "labels list"
assert_contains "$out" "Components: dashboard, backend" "components list"
assert_contains "$out" "Parent: ECFX-9 Big epic" "parent key and summary"
assert_contains "$out" "blocks ECFX-2 Other" "issue link line"
assert_contains "$out" "Rita R: Please check" "comment author and text"
assert_contains "$out" 'Customfield_1: {"x":1}' "unknown field prints raw and compact"
assert_lacks "$out" "Fix the thing" "summary not requested, not printed"

echo "jira-issue — failures"
out=$(JIRA_STUB_FAIL="curl: (6) Could not resolve host" "$SCRIPT" ECFX-1 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && pass "jira-api failing exits non-zero" || fail "jira-api failing exits non-zero" "rc=$rc"
assert_contains "$out" "Could not resolve host" "jira-api's message reaches stderr"
echo '{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}' > "$FIX/issue.json"
out=$("$SCRIPT" ECFX-404 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && pass "an errorMessages body exits non-zero" || fail "an errorMessages body exits non-zero" "rc=$rc"
assert_contains "$out" "Issue does not exist or you do not have permission" "Jira's message reaches stderr"
stdout=$("$SCRIPT" ECFX-404 2>/dev/null)
assert_eq "" "$stdout" "nothing on stdout for an error"
out=$(JIRA_STUB_RAW="<html>Bad gateway</html>" "$SCRIPT" ECFX-1 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && pass "a non-JSON answer exits non-zero" || fail "a non-JSON answer exits non-zero" "rc=$rc"
assert_contains "$out" "Bad gateway" "the raw answer reaches stderr"

echo "jira-issue — usage"
out=$("$SCRIPT" 2>&1); rc=$?
assert_eq "2" "$rc" "no key exits 2"
assert_contains "$out" "usage: jira-issue KEY [--fields a,b,...]" "usage line"
"$SCRIPT" ECFX-1 --bogus >/dev/null 2>&1; assert_eq "2" "$?" "unknown option exits 2"
assert_contains "$("$SCRIPT" --help 2>&1)" "usage: jira-issue" "--help prints usage"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
