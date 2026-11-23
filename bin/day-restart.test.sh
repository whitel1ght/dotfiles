#!/bin/bash
# Tests for bin/day-restart. `claude` is a stub: `agents --json` answers from a file the test
# writes, and `respawn` is logged. State and transcripts live in a sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/day-restart"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STATE="$SANDBOX/state"; CFG="$SANDBOX/claude"; T="$(date +%F)"
mkdir -p "$STATE" "$CFG/projects/-x" "$SANDBOX/bin"
LOG="$SANDBOX/claude.log"; AGENTS="$SANDBOX/agents.json"

cat > "$SANDBOX/bin/claude" <<'EOF'
#!/bin/bash
case "$1" in
    agents) cat "$AGENTS" ;;
    respawn) echo "respawn $2" >> "$LOG"; [ -z "${RESPAWN_FAIL:-}" ] || exit 1
             # the respawned session is idle
             jq 'map(.state = "idle")' "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS" ;;
esac
EOF
chmod +x "$SANDBOX/bin/claude"

session() { # sessionId short name kind state
    printf '{"sessionId":"%s","id":"%s","name":"%s","kind":"%s","state":"%s","status":"%s"}' "$1" "$2" "$3" "$4" "$5" \
        "$([ "$5" = working ] && echo busy || echo idle)"
}
transcript() { # sessionId command
    printf '{"type":"user","timestamp":"%s","message":{"content":"<command-name>/%s</command-name>"}}\n' \
        "$(date -u +%FT%T.000Z)" "$2" > "$CFG/projects/-x/$1.jsonl"
}
# The system session quotes the command inside a tool result: that is not starting the day.
printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","content":"<command-name>/start-day</command-name>"}]}}\n' \
    "$(date -u +%FT%T.000Z)" > "$CFG/projects/-x/sys-1.jsonl"
transcript day-1 start-day

printf -- '- ecfx-1 | class=auto | agent=a1 | round=- | worktree=/w | mr=- | retries=0 | needs_you=no | owner=main\n- ecfx-2 | class=auto | agent=- | round=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main\n' > "$STATE/$T.md"

restart() {
    : > "$LOG"
    AGENTS="$AGENTS" LOG="$LOG" RUN_DAY_STATE_DIR="$STATE" CLAUDE_CONFIG_DIR="$CFG" \
        DAY_RESTART_CLAUDE="$SANDBOX/bin/claude" DAY_RESTART_POLL=0 DAY_RESTART_WAIT=0 "$SCRIPT" "$@" 2>&1
}

echo "day-restart — finding the day session"
echo "[$(session sys-1 s1 system background working),$(session day-1 d1 main background idle)]" > "$AGENTS"
out="$(restart -n)"
assert_contains "$out" "would restart main (day-1): respawn" "no owner: the session that ran /start-day today, not one that quoted it"
assert_contains "$out" "its agents on ecfx-1 would stop" "names the agents the respawn stops"
[ -e "$STATE/$T.restart" ] && fail "-n writes nothing" "marker written" || pass "-n writes nothing"

echo "day-restart — a background session is respawned"
out="$(restart)"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_eq "respawn d1" "$(cat "$LOG")" "respawns it by its short id"
assert_eq "day-1" "$(cat "$STATE/$T.owner")" "records it as the day's owner"
assert_eq "day-1" "$(cat "$STATE/$T.restart")" "and leaves the marker the mod resumes from"
assert_contains "$out" "agents on ecfx-1 are re-dispatched" "says what happens to its agents"

echo "day-restart — waits for the turn to end"
rm -f "$STATE/$T.restart"
echo "[$(session day-1 d1 main background working)]" > "$AGENTS"
out="$(restart)"; rc=$?
assert_eq 1 "$rc" "a session still working past the wait is refused"
assert_contains "$out" "--now restarts it mid-turn" "and says how to force it"
assert_eq "" "$(cat "$LOG")" "nothing is respawned"
[ -e "$STATE/$T.restart" ] && fail "and no marker is left" "written" || pass "and no marker is left"
restart --now >/dev/null
assert_eq "respawn d1" "$(cat "$LOG")" "--now respawns it mid-turn"

echo "day-restart — in place"
rm -f "$STATE/$T.restart"
echo "[$(session day-1 d1 main background working)]" > "$AGENTS"
out="$(restart --in-place)"
assert_eq "" "$(cat "$LOG")" "--in-place respawns nothing"
assert_eq "day-1" "$(cat "$STATE/$T.restart")" "it only leaves the marker"
assert_contains "$out" "in place within 30 s" "and says the session resumes by itself"
rm -f "$STATE/$T.restart"
echo "[$(session int-1 i1 desk interactive idle)]" > "$AGENTS"
out="$(restart int-1)"
assert_eq "" "$(cat "$LOG")" "an interactive session is never respawned"
assert_contains "$out" "cannot be respawned" "and the reply says why"

echo "day-restart — the owner wins, a name works"
echo "[$(session day-1 d1 main background idle),$(session day-2 d2 other background idle)]" > "$AGENTS"
echo day-2 > "$STATE/$T.owner"
assert_contains "$(restart -n)" "would restart other (day-2)" "the recorded owner is the default"
assert_contains "$(restart main -n)" "would restart main (day-1)" "a session named on the command line wins"
assert_contains "$(restart nope -n)" "no running session nope" "an unknown session is refused"

echo "day-restart — refusals"
echo "[]" > "$AGENTS"; rm -f "$STATE/$T.owner"
out="$(restart -n)"; rc=$?
assert_eq 2 "$rc" "no day session running: exit 2"
assert_contains "$out" "name one" "and it asks for one"
mv "$STATE/$T.md" "$STATE/off.md"
out="$(restart -n)"; rc=$?
assert_eq 1 "$rc" "no day running: refused"
mv "$STATE/off.md" "$STATE/$T.md"
echo "[$(session day-1 d1 main background idle)]" > "$AGENTS"
out="$(RESPAWN_FAIL=1 restart)"; rc=$?
assert_eq 1 "$rc" "a failed respawn fails"
assert_contains "$out" "resume in that session picks it up" "and says the marker still works"

echo "day-restart — detached"
out="$(restart --detach --now)"
assert_contains "$out" "queued" "--detach returns at once"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$LOG" ] && break; sleep 0.2; done
assert_eq "respawn d1" "$(cat "$LOG")" "and the background run respawns it"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
