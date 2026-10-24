#!/bin/bash
# Tests for bin/agent-report, against fixture subagent transcripts in a sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/agent-report"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

WITH_TEXT="$SANDBOX/with-text.jsonl"
cat > "$WITH_TEXT" <<'JSONL'
{"type":"user","message":{"role":"user","content":"do the task"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"early text"},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"first part"},{"type":"text","text":"second part"}]}}
JSONL

NO_TEXT="$SANDBOX/no-text.jsonl"
cat > "$NO_TEXT" <<'JSONL'
{"type":"user","message":{"role":"user","content":"do the task"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
JSONL

# Long transcript: the final reply sits after many tool-call lines.
LONG="$SANDBOX/long.jsonl"
: > "$LONG"
i=0
while [ "$i" -lt 500 ]; do
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Bash","input":{}}]}}' >> "$LONG"
    i=$((i + 1))
done
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"final answer"}]}}' >> "$LONG"

echo "agent-report"

out="$("$SCRIPT" "$WITH_TEXT" 2>"$SANDBOX/err")"; rc=$?
expected="$(printf 'first part\n\nsecond part')"
if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
    pass "prints the last assistant message's text blocks joined by a blank line"
else
    fail "last assistant message" "rc=$rc out=[$out]"
fi

out="$("$SCRIPT" "$NO_TEXT" 2>"$SANDBOX/err")"; rc=$?
err="$(cat "$SANDBOX/err")"
if [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$err" = "agent-report: no assistant text in $NO_TEXT" ]; then
    pass "exit 1 with message when no assistant text"
else
    fail "no assistant text" "rc=$rc out=[$out] err=[$err]"
fi

out="$("$SCRIPT" "$LONG" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "final answer" ]; then
    pass "finds the final reply in a long transcript"
else
    fail "long transcript" "rc=$rc out=[$out]"
fi

out="$("$SCRIPT" "$SANDBOX/missing.jsonl" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *"usage:"* ]]; then
    pass "exit 2 with usage when the file is missing"
else
    fail "missing file" "rc=$rc out=[$out]"
fi

out="$("$SCRIPT" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *"usage:"* ]]; then
    pass "exit 2 with usage when no argument"
else
    fail "no argument" "rc=$rc out=[$out]"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
