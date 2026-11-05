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
[ -z "${GLAB_LOG:-}" ] || echo "$*" >> "$GLAB_LOG"
first_try() { local f; f="$FLAKY_DIR/$(printf '%s' "$*" | tr -c 'A-Za-z0-9' _)"; [ -e "$f" ] && return 1; : > "$f"; }
case "$*" in
    *merge_requests/7002/approvals) if first_try "$@"; then exit 1; fi; echo '{"approved_by":[{}]}' ;;
    *merge_requests/7002/discussions*) if first_try "$@"; then printf '[{"notes":[{"resolvable":true,"resolved":false}]}]\n'; exit 1; fi; echo '[{"notes":[{"resolvable":true,"resolved":false}]}]' ;;
    *merge_requests/7002) if first_try "$@"; then exit 1; fi; echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *merge_requests/6716/approvals) echo '{"approved_by":[{"user":{"username":"adam"}}]}' ;;
    *merge_requests/6716/discussions*) echo '[{"notes":[{"resolvable":true,"resolved":false}]},{"notes":[{"resolvable":true,"resolved":true}]},{"notes":[{"resolvable":false,"resolved":false}]}]' ;;
    *merge_requests/6716) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"failed"},"blocking_discussions_resolved":true}' ;;
    *merge_requests/6717/approvals) echo '{"approved_by":[]}' ;;
    *merge_requests/6717/discussions*) exit 1 ;;
    *merge_requests/6717) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"},"blocking_discussions_resolved":true}' ;;
    *merge_requests/6800/approvals) echo '{"approved_by":[]}' ;;
    *merge_requests/6800/discussions*) echo '[]' ;;
    *merge_requests/6800) sleep 1; echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *merge_requests/6801/approvals) echo '{"approved_by":[]}' ;;
    *merge_requests/6801/discussions*) echo '[]' ;;
    *merge_requests/6801) echo '{"state":"opened","draft":true,"head_pipeline":{"status":"running"}}' ;;
    *merge_requests/7001/approvals) echo '{"approved_by":[]}' ;;
    *merge_requests/7001/discussions*) echo '[]' ;;
    *merge_requests/7001) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *ecfx%2Fecfx-observability/merge_requests/80/approvals) echo '{"approved_by":[]}' ;;
    *ecfx%2Fecfx-observability/merge_requests/80/discussions*) echo '[]' ;;
    *ecfx%2Fecfx-observability/merge_requests/80) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *ecfx%2FECFX-Categorization/merge_requests/207/approvals) echo '{"approved_by":[]}' ;;
    *ecfx%2FECFX-Categorization/merge_requests/207/discussions*) echo '[]' ;;
    *ecfx%2FECFX-Categorization/merge_requests/207) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *ecfx%2Fecfx-observability/merge_requests/81/approvals) echo '{"approved_by":[]}' ;;
    *ecfx%2Fecfx-observability/merge_requests/81/discussions*) echo '[]' ;;
    *ecfx%2Fecfx-observability/merge_requests/81) echo '{"state":"opened","draft":false,"head_pipeline":{"status":"success"}}' ;;
    *merge_requests/9999*) exit 1 ;;
    *"merge_requests?scope=created_by_me"*)
        if [ -n "${GLAB_MINE_FLAKY:-}" ] && first_try "$@"; then exit 1; fi
        if [ -n "${GLAB_MINE:-}" ]; then echo "$GLAB_MINE"; else echo '[]'; fi ;;
    *) exit 1 ;;
esac
STUB
cat > "$STUBS/jira-api" <<'STUB'
#!/bin/bash
case "$*" in
    *ECFX-17100*) f="$FLAKY_DIR/jira"; if [ ! -e "$f" ]; then : > "$f"; exit 1; fi; echo '{"fields":{"status":{"name":"Flaky Ok"}}}' ;;
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
- [ ] ecfx-18400 backend!6717: threads call fails

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
assert_contains "$l1" "1 unresolved threads" "unresolved discussion counted although blocking flag is true"
l6=$(grep 'ECFX-18400' <<<"$out")
assert_contains "$l6" "threads unknown" "failing discussions call: threads unknown"
assert_contains "$l6" "pipeline success" "failing discussions call: rest of MR still shown"
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
assert_eq 6 "$(jq length <<<"$js")" "json: one entry per top-level item"
assert_eq failed "$(jq -r '.[0].mrs[0].pipeline' <<<"$js")" "json: pipeline"
assert_eq 1 "$(jq -r '.[0].mrs[0].approvals' <<<"$js")" "json: approvals"
assert_eq "In Code Review" "$(jq -r '.[0].jira' <<<"$js")" "json: jira"
assert_eq agent123 "$(jq -r '.[0].agent' <<<"$js")" "json: agent"
assert_eq 1 "$(jq -r '.[0].mrs[0].unresolved' <<<"$js")" "json: unresolved count"
assert_eq unknown "$(jq -r '.[4].mrs[0].unresolved' <<<"$js")" "json: unresolved unknown"
assert_eq unknown "$(jq -r '.[3].jira' <<<"$js")" "json: unknown jira"
assert_eq 0 "$(jq -r '.[1].mrs | length' <<<"$js")" "json: no MR is an empty list"
assert_eq in-progress "$(jq -r '.[0].state' <<<"$js")" "json: marker state"

echo "my open MRs list is fetched once"
cat > "$DIARY/2026-10-28.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-20001 first keyed item, no MR ref
- [ ] ecfx-20002 second keyed item, no MR ref
<!-- start-day:end -->
FIXTURE
LOG="$SANDBOX/glab.log"; : > "$LOG"
mine='[{"project_id":5,"iid":7001,"title":"x","source_branch":"ecfx-20001-feature","references":{"full":"ecfx/ecfx-backend!7001"}}]'
out=$(GLAB_LOG="$LOG" GLAB_MINE="$mine" run --date 2026-10-28)
assert_contains "$(grep 'ECFX-20001' <<<"$out")" "backend!7001 opened" "key search finds the MR by branch"
assert_contains "$(grep 'ECFX-20002' <<<"$out")" "no MR" "key search: other item has no MR"
assert_eq 1 "$(grep -c 'scope=created_by_me' "$LOG")" "list endpoint called exactly once"

echo "a repo outside the known names resolves through the block's link definitions"
cat > "$DIARY/2026-11-01.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-20005 review observability!80  [↗][observability!80]

[observability!80]: https://gitlab.com/ecfx/ecfx-observability/-/merge_requests/80
<!-- start-day:end -->
FIXTURE
: > "$LOG"
out=$(GLAB_LOG="$LOG" run --date 2026-11-01)
assert_contains "$out" "observability!80 opened" "observability!80 shows its MR state"
assert_lacks "$out" "MR unknown" "observability!80 is not unknown"
assert_contains "$(cat "$LOG")" "projects/ecfx%2Fecfx-observability/merge_requests/80" "glab got the project path from the definition"

echo "definitions match case-insensitively, and refs may be written in capitals"
cat > "$DIARY/2026-11-02.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-20006 re-review categorization!207  [↗][categorization!207]

[categorization!207]: https://gitlab.com/ecfx/ECFX-Categorization/-/merge_requests/207
<!-- start-day:end -->
FIXTURE
: > "$LOG"
out=$(GLAB_LOG="$LOG" run --date 2026-11-02)
assert_contains "$out" "categorization!207 opened" "mixed-case definition: MR state shown"
assert_lacks "$out" "MR unknown" "mixed-case definition: not unknown"
assert_contains "$(cat "$LOG")" "projects/ecfx%2FECFX-Categorization/merge_requests/207" "glab got the definition's exact path"
cat > "$DIARY/2026-11-03.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-20007 re-review ECFX-Categorization!207  [↗][categorization!207]

[categorization!207]: https://gitlab.com/ecfx/ECFX-Categorization/-/merge_requests/207
<!-- start-day:end -->
FIXTURE
: > "$LOG"
out=$(GLAB_LOG="$LOG" run --date 2026-11-03)
assert_contains "$out" "categorization!207 opened" "capitalised ref resolves through the definition"
assert_lacks "$out" "MR unknown" "capitalised ref: not unknown"
assert_lacks "$out" " ategorization!207" "capitalised ref: display ref not truncated"
assert_contains "$(cat "$LOG")" "projects/ecfx%2FECFX-Categorization/merge_requests/207" "capitalised ref: glab got the definition's path"

echo "a run-state mr= with a full path is used as is"
cat > "$DIARY/2026-11-04.md" <<'FIXTURE'
<!-- start-day:start -->
- [/] ecfx-123 add the alert
<!-- start-day:end -->
FIXTURE
cat > "$STATE/2026-11-04.md" <<'FIXTURE'
# run-day 2026-11-04
max_agents: 3
- ecfx-123 | class=auto | agent=a1 | round=- | worktree=- | mr=ecfx/ecfx-observability!81 | retries=0 | needs_you=no | owner=main
FIXTURE
: > "$LOG"
out=$(GLAB_LOG="$LOG" run --date 2026-11-04)
assert_contains "$out" "observability!81 opened" "run-state full path: MR state shown"
assert_lacks "$out" "MR unknown" "run-state full path: not unknown"
assert_contains "$out" "a1" "run-state full path: agent shown"
assert_contains "$(cat "$LOG")" "projects/ecfx%2Fecfx-observability/merge_requests/81" "glab got the run-state path"

echo "new-format day: MRs come from the agent file, not from the plan line or glab's list"
mkdir -p "$DIARY/.agent"
cat > "$DIARY/2026-11-05.md" <<'FIXTURE'
<!-- start-day:start -->
- [/] ecfx-20010 few words
- [ ] reply to Levi <!-- p3 -->
<!-- start-day:end -->
FIXTURE
cat > "$DIARY/.agent/2026-11-05.md" <<'FIXTURE'
# agent notes 2026-11-05
## ecfx-20010
- mr: backend!7001 https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/7001
- 09:12 progress: pushed
## p3
- mr: observability!80 https://gitlab.com/ecfx/ecfx-observability/-/merge_requests/80
FIXTURE
: > "$LOG"
js=$(GLAB_LOG="$LOG" GLAB_MINE="$mine" run --date 2026-11-05 --json)
assert_eq "backend!7001" "$(jq -r '.[0].mrs[0].ref' <<<"$js")" "agent-file MR for a ticket line"
assert_eq "opened" "$(jq -r '.[0].mrs[0].state' <<<"$js")" "agent-file MR: state from glab"
assert_eq "observability!80" "$(jq -r '.[1].mrs[0].ref' <<<"$js")" "agent-file MR for a keyless <!-- p3 --> line"
assert_eq 0 "$(grep -c 'scope=created_by_me' "$LOG")" "no glab lookup of my open MRs"
assert_contains "$(cat "$LOG")" "projects/ecfx%2Fecfx-backend/merge_requests/7001" "project path taken from the agent-file url"
echo "new-format day: an item without an agent-file MR keeps the key search"
cat > "$DIARY/2026-11-06.md" <<'FIXTURE'
<!-- start-day:start -->
- [/] ecfx-20001 few words
<!-- start-day:end -->
FIXTURE
printf '# agent notes 2026-11-06\n## ecfx-20001\n- 09:12 progress: started\n' > "$DIARY/.agent/2026-11-06.md"
: > "$LOG"
out=$(GLAB_LOG="$LOG" GLAB_MINE="$mine" run --date 2026-11-06)
assert_contains "$(grep 'ECFX-20001' <<<"$out")" "backend!7001 opened" "no agent-file MR: key search still finds it"
assert_eq 1 "$(grep -c 'scope=created_by_me' "$LOG")" "no agent-file MR: list endpoint called once"

echo "plan order is kept when an earlier item is slower"
cat > "$DIARY/2026-10-29.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-30001 backend!6800: slow one
- [ ] ecfx-30002 backend!6801: fast one
<!-- start-day:end -->
FIXTURE
out=$(run --date 2026-10-29)
assert_eq "ECFX-30001 ECFX-30002" "$(grep -oE 'ECFX-3000[12]' <<<"$out" | tr '\n' ' ' | sed 's/ $//')" "text: plan order"
assert_eq "ECFX-30001 ECFX-30002" "$(run --date 2026-10-29 --json | jq -r '[.[].key] | join(" ")')" "json: plan order"

echo "a failed call is retried once"
cat > "$DIARY/2026-10-30.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-17100 backend!7002: every call fails on its first try
<!-- start-day:end -->
FIXTURE
FLAKY_DIR="$SANDBOX/flaky1"; mkdir -p "$FLAKY_DIR"; export FLAKY_DIR
out=$(DAY_STATUS_RETRY_SLEEP=0 run --date 2026-10-30)
assert_lacks "$out" "unknown" "first-try failures: no field unknown"
assert_contains "$out" "Flaky Ok" "jira-api retried"
assert_contains "$out" "approvals 1" "approvals retried"
assert_contains "$out" "1 unresolved threads" "discussions retried, partial first output dropped"
assert_contains "$out" "backend!7002 opened" "MR detail retried"
cat > "$DIARY/2026-10-31.md" <<'FIXTURE'
<!-- start-day:start -->
- [ ] ecfx-20001 key search while the list call fails once
<!-- start-day:end -->
FIXTURE
FLAKY_DIR="$SANDBOX/flaky2"; mkdir -p "$FLAKY_DIR"
out=$(GLAB_MINE_FLAKY=1 GLAB_MINE="$mine" DAY_STATUS_RETRY_SLEEP=0 run --date 2026-10-31)
assert_contains "$out" "backend!7001 opened" "created_by_me list retried"
unset FLAKY_DIR

echo "errors"
out=$(run --date 2020-01-01); rc=$?
[ "$rc" -ne 0 ] && pass "missing diary: non-zero" || fail "missing diary: non-zero" "rc=$rc"
assert_contains "$out" "no diary" "missing diary: clear message"
echo '## Work' > "$DIARY/2020-01-02.md"
out=$(run --date 2020-01-02); rc=$?
[ "$rc" -ne 0 ] && pass "no plan block: non-zero" || fail "no plan block: non-zero" "rc=$rc"
assert_contains "$out" "no plan block" "no plan block: clear message"

echo "help"
out=$("$SCRIPT" --help); rc=$?
assert_eq 0 "$rc" "--help exits 0"
assert_contains "$out" "DAY_STATUS_RETRY_SLEEP" "--help prints the whole header"
assert_lacks "$out" "set -euo" "--help stops at the end of the header"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
