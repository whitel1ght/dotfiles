#!/bin/bash
# Tests for bin/wait-for. Probes, sleep, clock, day-note and friction are all
# stubbed through env, and WAIT_FOR_DIR points into a sandbox, so nothing here
# touches GitLab, Jira, ~/.local/state or really sleeps.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/wait-for"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
BIN="$SANDBOX/bin"; mkdir -p "$BIN"

cat > "$BIN/fake-sleep" <<'S'
#!/bin/bash
echo "$1" >> "$SANDBOX/sleeps"
echo $(( $(cat "$SANDBOX/clock") + $1 )) > "$SANDBOX/clock"
S
cat > "$BIN/fake-now" <<'S'
#!/bin/bash
cat "$SANDBOX/clock"
S
cat > "$BIN/fake-probe" <<'S'
#!/bin/bash
# fails until the Nth call (FAIL_UNTIL), counting in $SANDBOX/probes
n=$(( $(cat "$SANDBOX/probes" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$SANDBOX/probes"
[ "$n" -ge "$FAIL_UNTIL" ]
S
cat > "$BIN/fake-day-note" <<'S'
#!/bin/bash
echo "$*" >> "$SANDBOX/notes"
S
cat > "$BIN/fake-friction" <<'S'
#!/bin/bash
echo "$*" >> "$SANDBOX/friction"
S
chmod +x "$BIN"/*

reset() { rm -rf "$SANDBOX/state" "$SANDBOX"/{sleeps,probes,notes,friction}; echo 1000 > "$SANDBOX/clock"; }
run() {
  (SANDBOX="$SANDBOX" FAIL_UNTIL="${FAIL_UNTIL:-1}" WAIT_FOR_DIR="$SANDBOX/state" \
    WAIT_FOR_GITLAB_PROBE="$BIN/fake-probe" WAIT_FOR_JIRA_PROBE="$BIN/fake-probe" \
    WAIT_FOR_SLEEP="$BIN/fake-sleep" WAIT_FOR_NOW="$BIN/fake-now" \
    DAY_NOTE="$BIN/fake-day-note" FRICTION="$BIN/fake-friction" "$SCRIPT" "$@" 2>"$SANDBOX/stderr")
}
sleeps() { { tr '\n' ' ' < "$SANDBOX/sleeps"; } 2>/dev/null | sed 's/ $//'; }

echo "wait-for — service back"
reset; FAIL_UNTIL=1 run gitlab; rc=$?
assert_eq "0" "$rc" "exit 0 when the probe works at once"
assert_eq "" "$(sleeps)" "no sleep"
assert_eq "--kind service --session wait-for gitlab is back" "$(cat "$SANDBOX/notes")" "day-note called with kind service and no key"
assert_contains "$(cat "$SANDBOX/friction")" "--source wait-for service_down gitlab was down for 0s" "friction event logged"

echo "wait-for — backoff schedule"
reset; FAIL_UNTIL=9 run jira --key ecfx-18169; rc=$?
assert_eq "0" "$rc" "exit 0 once the probe finally works"
assert_eq "30 60 120 240 480 600 600 600" "$(sleeps)" "30 s doubling to a 10 min cap"
assert_eq "--kind service --session wait-for ECFX-18169 jira is back" "$(cat "$SANDBOX/notes")" "note carries the upper-cased key"
assert_contains "$(cat "$SANDBOX/friction")" "--source wait-for --key ECFX-18169 service_down jira was down for 45m" "friction carries the key and the outage duration"
assert_eq "no" "$([ -e "$SANDBOX/state/jira.lock" ] && echo yes || echo no)" "the lock is released"

echo "wait-for — give up"
reset; FAIL_UNTIL=999 run gitlab --max-hours 0.1; rc=$?   # 360 s
assert_eq "1" "$rc" "exit 1 after max-hours"
assert_eq "30 60 120 150" "$(sleeps)" "the last nap is cut to fit the limit"
assert_eq "--kind service --session wait-for gitlab still down after 0.1h — gave up" "$(cat "$SANDBOX/notes")" "an inbox note says it gave up"
assert_contains "$(cat "$SANDBOX/friction")" "gitlab still down after 6m, gave up" "friction event says it gave up"
assert_contains "$(cat "$SANDBOX/stderr")" "gave up" "and stderr too"

echo "wait-for — lock"
reset; mkdir -p "$SANDBOX/state/gitlab.lock"; sleep 30 & holder=$!; echo "$holder" > "$SANDBOX/state/gitlab.lock/pid"
FAIL_UNTIL=1 run gitlab; rc=$?
assert_eq "0" "$rc" "a second instance exits 0"
assert_eq "no" "$([ -e "$SANDBOX/probes" ] && echo yes || echo no)" "without probing"
assert_eq "" "$(cat "$SANDBOX/stderr")" "and without a word"
assert_eq "yes" "$([ -e "$SANDBOX/state/gitlab.lock/pid" ] && echo yes || echo no)" "the holder's lock is left alone"
FAIL_UNTIL=1 run jira; assert_eq "1" "$(cat "$SANDBOX/probes")" "a lock on gitlab does not block jira"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
reset; mkdir -p "$SANDBOX/state/gitlab.lock"; echo 999999 > "$SANDBOX/state/gitlab.lock/pid"
FAIL_UNTIL=1 run gitlab; assert_eq "1" "$(cat "$SANDBOX/probes")" "a lock left by a dead process is taken over"

echo "wait-for — detach"
reset; FAIL_UNTIL=1 SANDBOX="$SANDBOX" pid=$(run gitlab --detach); rc=$?
assert_eq "0" "$rc" "exit 0"
assert_eq "yes" "$([[ "$pid" =~ ^[0-9]+$ ]] && echo yes || echo no)" "prints a pid"
for _ in $(seq 50); do [ -e "$SANDBOX/notes" ] && break; sleep 0.1; done
assert_eq "--kind service --session wait-for gitlab is back" "$(cat "$SANDBOX/notes" 2>/dev/null)" "the background run did the work"

echo "wait-for — usage"
reset
run >/dev/null; assert_eq "1" "$?" "no service is an error"
run slack >/dev/null; assert_eq "1" "$?" "an unknown service is an error"
run gitlab --key nope >/dev/null; assert_eq "1" "$?" "a bad key is an error"
run gitlab --max-hours soon >/dev/null; assert_eq "1" "$?" "a bad --max-hours is an error"
run gitlab --bogus >/dev/null; assert_eq "1" "$?" "an unknown option is an error"
assert_eq "yes" "$("$SCRIPT" --help | grep -q 'wait-for gitlab|jira' && echo yes || echo no)" "--help prints the usage"
assert_eq "no" "$([ -e "$SANDBOX/probes" ] && echo yes || echo no)" "usage errors probe nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
