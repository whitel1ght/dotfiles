#!/bin/bash
# Tests for bin/glab-gate. friction is a stub on PATH that logs its argv; the
# marker lives in a sandbox FRICTION_DIR, never the real one.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/glab-gate"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; LOG="$SANDBOX/friction.log"
mkdir -p "$STUBS"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$LOG" > "$STUBS/friction"
chmod +x "$STUBS/friction"
export FRICTION_DIR="$SANDBOX/state"
MARKER="$FRICTION_DIR/gitlab-down"
gate() { PATH="$STUBS:$PATH" "$SCRIPT" "$@"; }

echo "glab-gate"
gate check; assert_eq 0 "$?" "no marker: GitLab may be called"
gate down --source end-day "GitLab unavailable"; assert_eq 0 "$?" "down exits 0"
assert_eq "--source end-day service_down GitLab unavailable" "$(cat "$LOG")" "the first down logs one service_down"
[ -s "$MARKER" ] && pass "and writes the marker into FRICTION_DIR" || fail "and writes the marker into FRICTION_DIR" "missing"
gate check; assert_eq 1 "$?" "a fresh marker: check fails"
gate down --source mr-watch "GitLab unavailable"; assert_eq 0 "$?" "a second down exits 0"
assert_eq 1 "$(wc -l < "$LOG" | tr -d ' ')" "and logs nothing while the marker is fresh"
printf '%s\n' "$(($(date +%s) - 901))" > "$MARKER"
gate check; assert_eq 0 "$?" "a stale marker: check passes"
gate down --source mr-watch "GitLab unavailable"
assert_eq 1 "$(wc -l < "$LOG" | tr -d ' ')" "a still-down probe after the hold adds no line"
gate check; assert_eq 1 "$?" "and refreshes the marker, so the hold restarts"
gate up; gate down --source mr-watch "GitLab unavailable"
assert_eq 2 "$(wc -l < "$LOG" | tr -d ' ')" "down, up, down logs twice"
printf '%s\n' "$(($(date +%s) - 86401))" > "$MARKER"
gate down --source mr-watch "GitLab unavailable"
assert_eq 3 "$(wc -l < "$LOG" | tr -d ' ')" "a marker older than the 24-hour cap logs again"
gate check; assert_eq 1 "$?" "and is renewed"
printf '%s\n' "$(($(date +%s) - 3600))" > "$MARKER"
GLAB_GATE_RELOG=60 gate down --source mr-watch "GitLab unavailable"
assert_eq 4 "$(wc -l < "$LOG" | tr -d ' ')" "GLAB_GATE_RELOG overrides the cap"
GLAB_GATE_HOLD=0 gate check; assert_eq 0 "$?" "GLAB_GATE_HOLD overrides the window"
gate up; assert_eq 0 "$?" "up exits 0"
[ ! -e "$MARKER" ] && pass "up clears the marker" || fail "up clears the marker" "left"
gate up; assert_eq 0 "$?" "up with no marker exits 0"
echo garbage > "$MARKER"; gate check; assert_eq 0 "$?" "a garbled marker counts as stale"
rm -f "$MARKER"; PATH="/usr/bin:/bin" "$SCRIPT" down --source x "m"; assert_eq 0 "$?" "down without friction on PATH exits 0"
[ -s "$MARKER" ] && pass "and still writes the marker" || fail "and still writes the marker" "missing"
gate bogus 2>/dev/null; assert_eq 2 "$?" "unknown command exits 2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
