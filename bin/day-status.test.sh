#!/bin/bash
# Tests for bin/day-status. glab and jira-api are stubs (DAY_STATUS_GLAB / DAY_STATUS_JIRA),
# the diary and run state live in a sandbox, so nothing here reaches GitLab or Jira.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/day-status"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; DIARY="$SANDBOX/diary"; STATE="$SANDBOX/state"
mkdir -p "$STUBS" "$DIARY" "$STATE"

cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
case "$*" in
    *merge_requests/6716/approvals) echo '{"approved_by":[{"user":{"username":"adam"}}]}' ;;
    *merge_requests/6716) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"failed"},"blocking_discussions_resolved":true}' ;;
    *merge_requests/9999*) exit 1 ;;
    *"merge_requests?scope=created_by_me"*) echo '[]' ;;
    *) exit 1 ;;
esac
STUB
cat > "$STUBS/jira-api" <<'STUB'
#!/bin/bash
case "$*" in
    *ECFX-18312*) echo '{"fields":{"status":{"name":"In Code Review"}}}' ;;
    *ECFX-18384*) echo '{"fields":{"status":{"name":"In Progress"}}}' ;;
    *ECFX-17001*) echo '{"fields":{"status":{"name":"Ready for QA"}}}' ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$STUBS/glab" "$STUBS/jira-api"

cat > "$DIARY/2026-10-27.md" <<'FIXTURE'
## Work

### ECFX

<!-- start-day:start -->
#### Plan

**First**
- [/] ecfx-18312 backend!6716: answer the re-reviews · progress: round pushed  [↗][backend!6716]
- [ ] ecfx-18384 Subtype Mapping: build the mapping tab
  - [ ] nested line is not an item
- [X] ecfx-17001 backend!9999: merged long ago
- [!] ecfx-17002 Jira breaks for this one

**Today**
- [>] write the retro with no ticket
<!-- start-day:end -->
FIXTURE
cat > "$STATE/2026-10-27.md" <<'FIXTURE'
# run-day 2026-10-27
max_agents: 3
- ecfx-18312 | class=auto | agent=agent123 | round=- | worktree=- | mr=ecfx/ecfx-backend!6716 | retries=0 | needs_you=no | owner=main
FIXTURE

run() { DIARY_DIR="$DIARY" RUN_DAY_STATE_DIR="$STATE" DAY_STATUS_GLAB="$STUBS/glab" DAY_STATUS_JIRA="$STUBS/jira-api" "$SCRIPT" "$@" 2>&1; }

echo "text output"
out=$(run --date 2026-10-27); rc=$?
assert_eq 0 "$rc" "exit 0 although some calls fail"
l1=$(grep 'ECFX-18312' <<<"$out")
assert_contains "$l1" "In Code Review" "approved item: Jira status"
assert_contains "$l1" "approvals 1" "approved item: approval shown"
assert_contains "$l1" "pipeline failed" "approved item: failed pipeline shown"
assert_contains "$l1" "agent123" "approved item: run-day agent shown"
l2=$(grep 'ECFX-18384' <<<"$out")
assert_contains "$l2" "In Progress" "no-MR item: Jira status"
assert_contains "$l2" "no MR" "no-MR item: says no MR"
assert_lacks "$out" "nested line" "nested lines are not items"
l3=$(grep 'ECFX-17001' <<<"$out")
assert_contains "$l3" "MR unknown" "failing glab: MR unknown"
assert_contains "$l3" "Ready for QA" "failing glab: Jira still shown"
l4=$(grep 'ECFX-17002' <<<"$out")
assert_contains "$l4" "Jira unknown" "failing jira: Jira unknown"
assert_contains "$out" "retro with no ticket" "item without a key still prints"

echo "json output"
js=$(run --date 2026-10-27 --json)
assert_eq 5 "$(jq length <<<"$js")" "json: one entry per top-level item"
assert_eq failed "$(jq -r '.[0].mrs[0].pipeline' <<<"$js")" "json: pipeline"
assert_eq 1 "$(jq -r '.[0].mrs[0].approvals' <<<"$js")" "json: approvals"
assert_eq "In Code Review" "$(jq -r '.[0].jira' <<<"$js")" "json: jira"
assert_eq agent123 "$(jq -r '.[0].agent' <<<"$js")" "json: agent"
assert_eq unknown "$(jq -r '.[3].jira' <<<"$js")" "json: unknown jira"
assert_eq 0 "$(jq -r '.[1].mrs | length' <<<"$js")" "json: no MR is an empty list"
assert_eq in-progress "$(jq -r '.[0].state' <<<"$js")" "json: marker state"

echo "errors"
out=$(run --date 2020-01-01); rc=$?
[ "$rc" -ne 0 ] && pass "missing diary: non-zero" || fail "missing diary: non-zero" "rc=$rc"
assert_contains "$out" "no diary" "missing diary: clear message"
echo '## Work' > "$DIARY/2020-01-02.md"
out=$(run --date 2020-01-02); rc=$?
[ "$rc" -ne 0 ] && pass "no plan block: non-zero" || fail "no plan block: non-zero" "rc=$rc"
assert_contains "$out" "no plan block" "no plan block: clear message"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
