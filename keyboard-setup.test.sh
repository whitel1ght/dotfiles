#!/bin/bash
# Tests for keyboard-setup.sh. Never touches the real keyboard or LaunchAgents:
# hidutil and launchctl are stubbed through their seams and every call is
# recorded to a log we assert on, and AGENT_DIR points at a temp directory.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/keyboard-setup.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

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

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

CALL_LOG="$SANDBOX/calls.log"

# Stub hidutil. GET_OUTPUT decides what `property --get` reports back, so a
# test can present the mapped and unmapped states without a real device.
cat > "$SANDBOX/hidutil" <<'STUB'
#!/bin/bash
echo "hidutil $*" >> "$CALL_LOG"
if [ "${1:-}" = "property" ] && [ "${2:-}" = "--get" ]; then
    printf '%s\n' "${GET_OUTPUT:-(null)}"
fi
exit 0
STUB

cat > "$SANDBOX/launchctl" <<'STUB'
#!/bin/bash
echo "launchctl $*" >> "$CALL_LOG"
exit "${LAUNCHCTL_RC:-0}"
STUB

chmod +x "$SANDBOX/hidutil" "$SANDBOX/launchctl"

# The decimal forms hidutil --get prints for Caps Lock and Grave.
MAPPED_OUTPUT='(
        {
        HIDKeyboardModifierMappingDst = 30064771125;
        HIDKeyboardModifierMappingSrc = 30064771129;
    }
)'

run() {
    : > "$CALL_LOG"
    env HIDUTIL="$SANDBOX/hidutil" \
        LAUNCHCTL="$SANDBOX/launchctl" \
        OS_NAME="Darwin" \
        AGENT_DIR="$SANDBOX/agents" \
        CALL_LOG="$CALL_LOG" \
        GET_OUTPUT="${GET_OUTPUT:-(null)}" \
        bash "$SCRIPT" "$@" 2>&1
}

echo "keyboard-setup.sh"

# --- apply -----------------------------------------------------------------
echo "apply"
out="$(run apply)"
calls="$(cat "$CALL_LOG")"

assert_contains "$calls" "0x700000039" "apply maps from Caps Lock"
assert_contains "$calls" "0x700000035" "apply maps to Grave/Tilde"
assert_contains "$calls" "launchctl bootstrap" "apply bootstraps the LaunchAgent"
assert_contains "$calls" "launchctl bootout" "apply boots out first so a re-run reloads"

if [ -f "$SANDBOX/agents/local.keyremap.plist" ]; then
    pass "apply installs the plist into AGENT_DIR"
else
    fail "apply installs the plist into AGENT_DIR" "plist not found"
fi

plist="$(cat "$SANDBOX/agents/local.keyremap.plist" 2>/dev/null)"
assert_contains "$plist" "0x700000039" "installed plist carries the source code"
assert_lacks "$plist" "<key>KeepAlive</key>" "installed plist has no KeepAlive key (one-shot, not a daemon)"

# A re-run must not stack duplicate agents.
out="$(run apply)"
calls="$(cat "$CALL_LOG")"
assert_contains "$calls" "launchctl bootout" "re-apply boots out before bootstrapping again"

# --- status ----------------------------------------------------------------
echo "status"
GET_OUTPUT="$MAPPED_OUTPUT" out="$(GET_OUTPUT="$MAPPED_OUTPUT" run status)"
assert_contains "$out" "active" "status reports an active remap"
assert_contains "$out" "installed" "status reports the installed agent"

GET_OUTPUT="(null)" out="$(GET_OUTPUT="(null)" run status)"
assert_contains "$out" "not active" "status reports a missing remap"

# A mapping for some other key must not read as ours.
OTHER='(
        {
        HIDKeyboardModifierMappingDst = 30064771113;
        HIDKeyboardModifierMappingSrc = 30064771110;
    }
)'
out="$(GET_OUTPUT="$OTHER" run status)"
assert_contains "$out" "not active" "status does not match an unrelated remap"

# --- remove ----------------------------------------------------------------
echo "remove"
out="$(run remove)"
calls="$(cat "$CALL_LOG")"
assert_contains "$calls" 'UserKeyMapping":[]' "remove clears the mapping"
assert_contains "$calls" "launchctl bootout" "remove boots out the agent"

if [ -f "$SANDBOX/agents/local.keyremap.plist" ]; then
    fail "remove deletes the plist" "plist still present"
else
    pass "remove deletes the plist"
fi

# remove on a clean machine must not fail.
out="$(run remove)"
assert_contains "$out" "No LaunchAgent installed" "remove is idempotent"

# --- guards ----------------------------------------------------------------
echo "guards"
out="$(env HIDUTIL="$SANDBOX/hidutil" LAUNCHCTL="$SANDBOX/launchctl" \
        OS_NAME="Linux" AGENT_DIR="$SANDBOX/agents" CALL_LOG="$CALL_LOG" \
        bash "$SCRIPT" apply 2>&1)"
assert_contains "$out" "Not macOS" "non-Darwin is a no-op"

out="$(run bogus)"
assert_contains "$out" "Unknown command" "unknown command is rejected"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
