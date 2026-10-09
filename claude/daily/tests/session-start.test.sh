#!/usr/bin/env bash
# Tests for hooks/session-start.sh. No network, no real HOME.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$TEST_DIR/../hooks/session-start.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not found in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly found" ;; *) pass "$3" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export RUN_DAY_STATE_DIR="$SANDBOX/state" WIKI_DIR="$SANDBOX/wiki" RUN_DAY_DATE=2026-10-08
mkdir -p "$RUN_DAY_STATE_DIR" "$WIKI_DIR/diary"
cat > "$WIKI_DIR/diary/2026-10-08.md" <<'D'
## habits tracking
- [ ] drawing
<!-- start-day:start -->
#### Plan
**Today**
- [/] ecfx-18169 fix the 3 majors
<!-- start-day:end -->
<!-- daily-report:start -->
- report line
<!-- daily-report:end -->
D

echo "== no run active =="
out="$(bash "$HOOK" </dev/null)"; rc=$?
assert_eq "0" "$rc" "exits 0 without a run-state file"
assert_eq "" "$out" "prints nothing without a run-state file"

echo "== run active =="
printf '# run-day 2026-10-08\n- ecfx-18169 | class=auto | agent=a1 | needs_you=yes\n' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
out="$(CLAUDE_PLUGIN_ROOT=/plug bash "$HOOK" </dev/null)"
assert_eq "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "valid hook JSON with the event name"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "ecfx-18169 fix the 3 majors" "includes the plan block"
assert_contains "$ctx" "needs_you=yes" "includes the run-state file"
assert_contains "$ctx" "/plug/commands/run-day.md" "names the playbook"
assert_contains "$ctx" "subagents never write ~/wiki" "includes the write-rules reminder"
assert_contains "$ctx" "owner=external:KEY" "explains the external owner"
assert_lacks "$ctx" "drawing" "leaves out diary lines outside the start-day block"
assert_lacks "$ctx" "report line" "leaves out the daily-report block"

echo "== inbox =="
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_lacks "$ctx" "pending inbox" "no inbox line when the inbox is empty"
mkdir -p "$RUN_DAY_STATE_DIR/inbox/done" "$RUN_DAY_STATE_DIR/inbox/bad"
touch "$RUN_DAY_STATE_DIR/inbox/20261008T154200-ECFX-18169-ab12.md" "$RUN_DAY_STATE_DIR/inbox/20261008T154300-offplan-cd34.md" \
  "$RUN_DAY_STATE_DIR/inbox/20261008T154400-offplan-ef56.md.tmp" "$RUN_DAY_STATE_DIR/inbox/bad/x.md" "$RUN_DAY_STATE_DIR/inbox/done/y.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "2 pending inbox message(s)" "counts waiting messages, not .tmp files or the done/ and bad/ folders"

echo "== missing diary =="
mv "$WIKI_DIR/diary/2026-10-08.md" "$WIKI_DIR/diary/gone.md"
out="$(bash "$HOOK" </dev/null)"
assert_contains "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" "needs_you=yes" "still injects run state without a diary"
mv "$WIKI_DIR/diary/gone.md" "$WIKI_DIR/diary/2026-10-08.md"

echo "== size cap =="
{ echo '# run-day 2026-10-08'; for i in $(seq 1 400); do echo "- ecfx-$i | class=auto | agent=a$i | needs_you=no"; done; } > "$RUN_DAY_STATE_DIR/2026-10-08.md"
len="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext | length')"
[ "$len" -le 6000 ] && pass "context is capped at 6000 characters ($len)" || fail "context cap" "length $len"

echo "== another day's state is ignored =="
RUN_DAY_DATE=2026-10-09 out="$(bash "$HOOK" </dev/null)"
assert_eq "" "$out" "yesterday's state file does not activate today"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
