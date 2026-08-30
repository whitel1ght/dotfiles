#!/bin/bash
# Tests for macos-daemons.sh. Never touches real daemons: launchctl is stubbed
# through the LAUNCHCTL seam and every call is recorded to a log we assert on.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/macos-daemons.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then pass "$label"
    else fail "$label" "expected [$expected] got [$actual]"; fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) pass "$label" ;;
        *) fail "$label" "[$needle] not found in [$haystack]" ;;
    esac
}

assert_lacks() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) fail "$label" "[$needle] unexpectedly found in [$haystack]" ;;
        *) pass "$label" ;;
    esac
}

# assert_fails <expected-exit> <label> -- <cmd...>
assert_fails() {
    local expected="$1" label="$2"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" = "$expected" ]; then pass "$label"
    else fail "$label" "expected exit $expected got $rc; output: $out"; fi
}

UID_NUM="$(id -u)"

# Fresh sandbox with a launchctl stub. The stub logs every invocation and
# replays canned stdout for the two subcommands the script reads back.
new_sandbox() {
    ROOT="$(mktemp -d)"
    CALL_LOG="$ROOT/calls.log"
    : > "$CALL_LOG"
    : > "$ROOT/disabled.txt"
    : > "$ROOT/print.txt"

    cat > "$ROOT/launchctl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALL_LOG"
case "$1" in
    print-disabled) cat "$STUB_DISABLED" ;;
    print)          cat "$STUB_PRINT" ;;
esac
exit 0
STUB
    chmod +x "$ROOT/launchctl"
}

# Run the script with the stub wired in. OS_NAME defaults to Darwin so the
# platform guard passes; individual tests override it.
run() {
    CALL_LOG="$CALL_LOG" \
    STUB_DISABLED="$ROOT/disabled.txt" \
    STUB_PRINT="$ROOT/print.txt" \
    LAUNCHCTL="$ROOT/launchctl" \
    OS_NAME="${OS_NAME_OVERRIDE:-Darwin}" \
        "$SCRIPT" "$@" 2>&1
}

calls() { cat "$CALL_LOG"; }

echo "macos-daemons.sh"

# --- disable -----------------------------------------------------------------
new_sandbox
out="$(run disable)"
assert_contains "$(calls)" "disable gui/$UID_NUM/com.apple.mediaanalysisd" \
    "disable issues launchctl disable for mediaanalysisd"
assert_contains "$(calls)" "disable gui/$UID_NUM/com.apple.photoanalysisd" \
    "disable issues launchctl disable for photoanalysisd"
assert_lacks "$(calls)" "enable gui/" \
    "disable never issues an enable"

# --- default subcommand ------------------------------------------------------
new_sandbox
run >/dev/null
assert_contains "$(calls)" "disable gui/$UID_NUM/com.apple.mediaanalysisd" \
    "no argument defaults to disable"

# --- enable ------------------------------------------------------------------
new_sandbox
run enable >/dev/null
assert_contains "$(calls)" "enable gui/$UID_NUM/com.apple.mediaanalysisd" \
    "enable issues launchctl enable for mediaanalysisd"
assert_contains "$(calls)" "enable gui/$UID_NUM/com.apple.photoanalysisd" \
    "enable issues launchctl enable for photoanalysisd"
assert_lacks "$(calls)" "disable gui/" \
    "enable never issues a disable"

# --- status ------------------------------------------------------------------
new_sandbox
printf '\t\t"com.apple.mediaanalysisd" => disabled\n' > "$ROOT/disabled.txt"
out="$(run status)"
assert_contains "$(calls)" "print-disabled gui/$UID_NUM" \
    "status queries the override database"
assert_contains "$out" "com.apple.mediaanalysisd" \
    "status names each daemon"
assert_contains "$out" "disabled" \
    "status reports a disabled daemon as disabled"
assert_contains "$out" "enabled" \
    "status reports an absent daemon as enabled"
assert_lacks "$(calls)" "disable gui/" \
    "status never mutates state"

# --- reboot warning ----------------------------------------------------------
# SIP blocks bootout, so a still-running instance must be reported rather than
# silently counted as stopped.
new_sandbox
printf '\tstate = running\n' > "$ROOT/print.txt"
out="$(run disable)"
assert_contains "$out" "Reboot to stop the running instance" \
    "disable warns a reboot is needed while an instance is still running"

new_sandbox
printf '\tstate = not running\n' > "$ROOT/print.txt"
out="$(run disable)"
assert_lacks "$out" "Reboot to stop the running instance" \
    "disable stays quiet about reboots when nothing is running"

# --- argument handling -------------------------------------------------------
new_sandbox
assert_fails 2 "unknown subcommand exits 2" -- run bogus
out="$(run bogus)"
assert_contains "$out" "Usage" \
    "unknown subcommand prints usage"

# --- platform guard ----------------------------------------------------------
new_sandbox
OS_NAME_OVERRIDE=Linux
out="$(run disable)"
rc=$?
unset OS_NAME_OVERRIDE
assert_eq "0" "$rc" "non-macOS exits 0 so install.sh is not aborted"
assert_eq "" "$(calls)" "non-macOS makes no launchctl calls"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
