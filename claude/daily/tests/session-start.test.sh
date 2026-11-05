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
export FRICTION_LEDGER_BIN="$SANDBOX/no-such-friction-ledger" FRICTION_WIKI="$SANDBOX/friction"
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
assert_contains "$ctx" "except ~/wiki/work/system/ and ~/wiki/tools/" "the write rules carry the system-page exception"
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

echo "== large or unterminated diary block keeps the run state =="
printf '# run-day 2026-10-08\n- ecfx-2 | class=auto | owner=external:ECFX-2 | needs_you=yes\n' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
{ echo '<!-- start-day:start -->'; for i in $(seq 1 200); do echo "- plan line $i with some padding text to take up room"; done; } > "$WIKI_DIR/diary/2026-10-08.md"
out="$(bash "$HOOK" </dev/null)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "owner=external:ECFX-2" "unterminated start marker: owner survives"
assert_contains "$ctx" "needs_you=yes" "unterminated start marker: needs_you survives"
[ "${#ctx}" -le 6000 ] && pass "unterminated block: within the cap" || fail "unterminated cap" "length ${#ctx}"
{ echo '<!-- start-day:start -->'; for i in $(seq 1 200); do echo "- plan line $i with some padding text to take up room"; done; echo '<!-- start-day:end -->'; } > "$WIKI_DIR/diary/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "owner=external:ECFX-2" "large terminated block: owner survives"
assert_contains "$ctx" "needs_you=yes" "large terminated block: needs_you survives"
assert_contains "$ctx" "plan line 1 " "large terminated block: head of the block kept"
assert_contains "$ctx" "[plan block truncated]" "large terminated block: truncation marked"
[ "${#ctx}" -le 6000 ] && pass "large block: within the cap" || fail "large block cap" "length ${#ctx}"

echo "== size cap =="
{ echo '# run-day 2026-10-08'; for i in $(seq 1 400); do echo "- ecfx-$i | class=auto | agent=a$i | needs_you=no"; done; } > "$RUN_DAY_STATE_DIR/2026-10-08.md"
len="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext | length')"
[ "$len" -le 6000 ] && pass "context is capped at 6000 characters ($len)" || fail "context cap" "length $len"

echo "== another day's state is ignored =="
RUN_DAY_DATE=2026-10-09 out="$(bash "$HOOK" </dev/null)"
assert_eq "" "$out" "yesterday's state file does not activate today"

echo "== standing directions =="
export RUN_DAY_DATE=2026-10-08
LEDGER="$TEST_DIR/../../../bin/friction-ledger"
rm -f "$RUN_DAY_STATE_DIR/2026-10-08.md"
assert_eq "" "$(bash "$HOOK" </dev/null)" "no friction-ledger, no run: still silent"
export FRICTION_LEDGER_BIN="$LEDGER"
assert_eq "" "$(bash "$HOOK" </dev/null)" "ledger but no directions file, no run: silent"
"$LEDGER" directions add --rule "Handle service outages with scripts, never model retries" --scope global >/dev/null
"$LEDGER" directions add --rule "Retired one" >/dev/null; "$LEDGER" directions retire D-002
out="$(bash "$HOOK" </dev/null)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_eq "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "directions alone: valid hook JSON"
assert_contains "$ctx" "## Standing directions" "under the Standing directions heading"
assert_contains "$ctx" "- Handle service outages with scripts, never model retries" "with the active rule"
assert_lacks "$ctx" "Retired one" "retired rules are left out"
assert_lacks "$ctx" "run-day session is active" "and no run context without a run"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "- Handle service outages" "the directions argument injects them (startup)"
printf '# run-day 2026-10-08
- ecfx-1 | class=auto | needs_you=no
' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "run-day session is active" "with a run: run context"
assert_contains "$ctx" "- Handle service outages" "and the directions after it"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_lacks "$ctx" "run-day session is active" "the startup entry never injects run state"
export FRICTION_LEDGER_BIN="$SANDBOX/no-such-friction-ledger"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_lacks "$ctx" "Standing directions" "a missing script injects nothing and does not fail the hook"
printf '#!/bin/sh\nexit 3\n' >"$SANDBOX/broken"; chmod +x "$SANDBOX/broken"; export FRICTION_LEDGER_BIN="$SANDBOX/broken"
bash "$HOOK" </dev/null >/dev/null 2>&1; assert_eq "0" "$?" "a failing script does not fail the hook"
assert_eq "startup|clear" "$(jq -r '.hooks.SessionStart[] | select(.hooks[0].command | endswith("directions")) | .matcher' "$TEST_DIR/../hooks/hooks.json")" "directions are injected on startup and after /clear"

echo "== system map =="
export FRICTION_LEDGER_BIN="$SANDBOX/no-such-friction-ledger"
rm -f "$RUN_DAY_STATE_DIR/2026-10-08.md"
unset SYSTEM_MAP
assert_eq "" "$(bash "$HOOK" </dev/null)" "default map path missing, no run: silent"
export SYSTEM_MAP="$SANDBOX/map.md"
assert_eq "" "$(bash "$HOOK" </dev/null)" "map file missing, no run: silent"
: > "$SYSTEM_MAP"
assert_eq "" "$(bash "$HOOK" </dev/null)" "empty map, no run: silent"
printf -- '- run-day: the daily plan\n' > "$SYSTEM_MAP"
out="$(bash "$HOOK" </dev/null)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_eq "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "map alone: valid hook JSON"
assert_contains "$ctx" "## System map" "map under its heading"
assert_contains "$ctx" "- run-day:" "map text present"
assert_lacks "$ctx" "run-day session is active" "no run context without a run"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "- run-day:" "the directions argument injects the map too"
printf -- '# System map\nPages: here\n- run-day: the daily plan\n' > "$SYSTEM_MAP"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_eq "1" "$(printf '%s\n' "$ctx" | grep -c 'System map')" "the map's own # title is dropped under ## System map"
assert_contains "$ctx" "## System map
Pages: here" "the map body follows the heading"
printf -- '- run-day: the daily plan\n' > "$SYSTEM_MAP"
printf '# run-day 2026-10-08\n- ecfx-1 | class=auto | needs_you=no\n' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "run-day session is active" "with a run: run context"
assert_contains "$ctx" "- run-day:" "with a run: map too"
{ for i in $(seq 1 400); do echo "- part $i: some description of it padding"; done; } > "$SYSTEM_MAP"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
bytes="$(printf '%s' "${ctx#*## System map}" | wc -c | tr -d ' ')"
[ "$bytes" -gt 100 ] && [ "$bytes" -le 3073 ] && pass "over-budget map is cut to 3072 bytes ($bytes)" || fail "map cut" "bytes $bytes"
unset SYSTEM_MAP; export SYSTEM_MAP="$SANDBOX/dir-not-file"; mkdir "$SYSTEM_MAP"
bash "$HOOK" </dev/null >/dev/null 2>&1; assert_eq "0" "$?" "an unreadable map does not fail the hook"
unset SYSTEM_MAP

echo "== total cap (9000 characters) =="
export SYSTEM_MAP="$SANDBOX/big-map.md"
{ for i in $(seq 1 400); do echo "- part $i: some description of it padding"; done; } > "$SYSTEM_MAP"
printf '#!/bin/sh\ni=1; while [ $i -le 300 ]; do echo "- direction $i: always follow this standing rule"; i=$((i+1)); done\n' > "$SANDBOX/big-ledger"
chmod +x "$SANDBOX/big-ledger"; export FRICTION_LEDGER_BIN="$SANDBOX/big-ledger"
rm -f "$RUN_DAY_STATE_DIR/2026-10-08.md"
ctx="$(bash "$HOOK" directions </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
[ "${#ctx}" -le 9000 ] && pass "no run: directions and map within 9000 (${#ctx})" || fail "no run: total cap" "length ${#ctx}"
assert_contains "$ctx" "- part 70:" "no run: the map is kept whole before the directions"
assert_contains "$ctx" "(cut)" "no run: the cut is marked"
assert_contains "$ctx" "- direction 1:" "no run: the head of the directions is kept"
{ echo '# run-day 2026-10-08'; for i in $(seq 1 400); do echo "- ecfx-$i | class=auto | agent=a$i | needs_you=no"; done; } > "$RUN_DAY_STATE_DIR/2026-10-08.md"
alone="$(FRICTION_LEDGER_BIN="$SANDBOX/no-such-friction-ledger" SYSTEM_MAP="$SANDBOX/no-map" bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
[ "${#ctx}" -le 9000 ] && pass "large run state, map and directions within 9000 (${#ctx})" || fail "run: total cap" "length ${#ctx}"
case "$ctx" in "$alone"*) pass "the run context is kept whole first" ;; *) fail "the run context is kept whole first" "${ctx:0:200}" ;; esac
assert_contains "$ctx" "## System map" "the map comes before the directions in priority"
assert_lacks "$ctx" "- direction 1:" "the directions are cut first"
assert_contains "$ctx" "(cut)" "the cut is marked"
rm -f "$RUN_DAY_STATE_DIR/2026-10-08.md"
export FRICTION_LEDGER_BIN="$SANDBOX/no-such-friction-ledger"
unset SYSTEM_MAP

echo "== agent notes =="
printf '# run-day 2026-10-08\n- ecfx-1 | class=auto | needs_you=no\n' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
cat > "$WIKI_DIR/diary/2026-10-08.md" <<'D'
<!-- start-day:start -->
#### Plan
- [/] ecfx-18169 fix the 3 majors
<!-- start-day:end -->
D
before="$(bash "$HOOK" </dev/null)"
assert_lacks "$before" "Agent notes" "no agent file: no agent section"
mkdir -p "$WIKI_DIR/diary/.agent"
printf '# agent notes 2026-10-08\n## ecfx-18169\n- 09:12 progress: N1 fixed, pushed at 811e370a3\n' > "$WIKI_DIR/diary/.agent/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "## Agent notes ($WIKI_DIR/diary/.agent/2026-10-08.md)" "agent notes under their heading with the path"
assert_contains "$ctx" "- 09:12 progress: N1 fixed, pushed at 811e370a3" "agent notes carry the entry"
case "$ctx" in *"fix the 3 majors"*"## Agent notes"*"## Run state"*) pass "agent notes sit between the plan block and the run state" ;; *) fail "agent notes order" "$ctx" ;; esac
assert_lacks "$ctx" "[agent notes truncated]" "a small agent file is not cut"
{ echo '# agent notes 2026-10-08'; for i in $(seq 1 200); do echo "- 10:00 note: agent entry number $i with padding"; done; } > "$WIKI_DIR/diary/.agent/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "fix the 3 majors" "10 KB agent file: plan block whole"
assert_contains "$ctx" "- ecfx-1 | class=auto | needs_you=no" "10 KB agent file: run state whole"
assert_contains "$ctx" "[agent notes truncated]" "10 KB agent file: cut is marked"
assert_contains "$ctx" "- 10:00 note: agent entry number 1 " "10 KB agent file: head kept"
assert_lacks "$ctx" "agent entry number 200" "10 KB agent file: tail dropped"
body="${ctx#*## Agent notes (*)
}"; body="${body%%

## Run state*}"
[ "${#body}" -le 2100 ] && pass "agent notes capped near 2000 (${#body})" || fail "agent cap" "length ${#body}"
last="$(printf '%s\n' "$body" | tail -2 | head -1)"
case "$last" in "- 10:00 note: agent entry number "*" with padding") pass "cut ends on a full entry" ;; *) fail "cut on a full line" "[$last]" ;; esac
[ "${#ctx}" -le 6000 ] && pass "agent notes: within the cap" || fail "agent cap total" "length ${#ctx}"
mv "$WIKI_DIR/diary/.agent/2026-10-08.md" "$SANDBOX/agent.md"
printf '# run-day 2026-10-08\n- ecfx-1 | class=auto | needs_you=no\n' > "$RUN_DAY_STATE_DIR/2026-10-08.md"
base="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext | length')"
{ printf '# run-day 2026-10-08\n- ecfx-1 | class=auto | needs_you=no\n- pad: '; head -c $((5950 - base)) /dev/zero | tr '\0' x; echo; } > "$RUN_DAY_STATE_DIR/2026-10-08.md"
mv "$SANDBOX/agent.md" "$WIKI_DIR/diary/.agent/2026-10-08.md"
ctx="$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "- pad: xxxxxxxxxx" "tight budget: run state whole"
assert_contains "$ctx" "[agent notes truncated]" "tight budget: only the marker is left of the notes"
assert_lacks "$ctx" "agent entry number 1 " "tight budget: no notes body"
[ "${#ctx}" -le 6000 ] && pass "tight budget: within the cap" || fail "tight cap" "length ${#ctx}"
rm -f "$RUN_DAY_STATE_DIR/2026-10-08.md" "$WIKI_DIR/diary/.agent/2026-10-08.md"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
