#!/usr/bin/env bash
# Tests for bin/session-picker — verifies process matching, busy detection,
# and title generation for claude, pi, opencode, and codex sessions.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/session-picker"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1"; }

# Extract BUSY_RE from the script
BUSY_RE=$(grep '^BUSY_RE=' "$SCRIPT" | sed "s/^BUSY_RE='//;s/'$//")
[ -n "$BUSY_RE" ] || { echo 'FAIL: could not extract BUSY_RE' >&2; exit 1; }

# Test 1: claude busy pattern (esc to interrupt)
if echo "esc to interrupt" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "claude 'esc to interrupt' not matched"
fi

# Test 2: claude busy pattern (timer + tokens)
if echo "(37s · ↓ 2.0k tokens)" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "claude '(37s · ↓ 2.0k tokens)' not matched"
fi

# Test 3: pi busy pattern (ponytail ●)
if echo "LSP Inactive ● 🐴 ponytail: ⚡ FULL" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "pi '●' not matched"
fi

# Test 4: pi busy pattern (spinner + Working)
if echo "── ⠼ Working ───" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "pi '⠼ Working' not matched"
fi

# Test 5: opencode busy pattern (esc interrupt)
if echo "⬝⬝⬝⬝⬝⬝⬝⬝ esc interrupt" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "opencode 'esc interrupt' not matched"
fi

# Test 6: codex busy pattern (spinner + Working + timer)
if echo "⠋ Working (0s • esc to interrupt)" | grep -qiE "$BUSY_RE"; then
    pass
else
    fail "codex '⠋ Working (0s • esc to interrupt)' not matched"
fi

# Test 7: codex idle (no match)
if echo "GPT-6.1-Sol default · ~" | grep -qiE "$BUSY_RE"; then
    fail "codex idle falsely matched"
else
    pass
fi

# Test 8: pi idle (no match)
if echo "LSP Inactive ○ 🐴 ponytail: ⚡ FULL" | grep -qiE "$BUSY_RE"; then
    fail "pi idle '○' falsely matched"
else
    pass
fi

# Test 9: process matching — verify the awk regex matches all four agents
AWK_REGEX=$(grep 'c ~ /\^' "$SCRIPT" | sed 's/.*c ~ \/\^//;s/\$\/.*//')
[ -n "$AWK_REGEX" ] || { echo 'FAIL: could not extract process regex' >&2; exit 1; }
for agent in claude pi opencode codex; do
    if echo "$agent" | grep -qE "^(${AWK_REGEX})$"; then
        pass
    else
        fail "process '$agent' not matched by awk regex"
    fi
done

# Test 10: process matching — verify non-agents are rejected
for agent in nvim zsh bash node python; do
    if echo "$agent" | grep -qE "^(${AWK_REGEX})$"; then
        fail "non-agent '$agent' falsely matched"
    else
        pass
    fi
done

# Test 11: title generation
TITLE_BUSY=$(grep 'title="Busy' "$SCRIPT" | sed 's/.*title="//;s/".*//')
if [ "$TITLE_BUSY" = "Busy agent sessions" ]; then
    pass
else
    fail "busy title is '$TITLE_BUSY', expected 'Busy agent sessions'"
fi

TITLE_ALL=$(grep 'SCOPE.*all.*title=' "$SCRIPT" | sed 's/.*title="//;s/".*//')
if [ "$TITLE_ALL" = "Agent sessions" ]; then
    pass
else
    fail "all title is '$TITLE_ALL', expected 'Agent sessions'"
fi

# Test 12: script is executable
if [ -x "$SCRIPT" ]; then
    pass
else
    fail "session-picker is not executable"
fi

echo "passed: $PASSED failed: $FAILED"
[ "$FAILED" -eq 0 ]
