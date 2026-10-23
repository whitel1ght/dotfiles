#!/bin/bash
# Tests for bin/dashboard-check, the PostToolUse hook that lints an edited
# ecfx-dashboard file. A sandbox HOME holds a fake repo and worktree; a stub
# `npx` on PATH stands in for eslint and records every call.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/dashboard-check"
PY="$(command -v python3)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
ERR="$WORK/err"
CALLS="$WORK/calls"
MAIN="$H/projects/ecfx-dashboard"
WT="$H/projects/worktrees/ecfx-dashboard/ECFX-1"
BARE="$H/projects/worktrees/ecfx-dashboard/no-modules"
OTHER="$H/projects/ecfx-admin"
for r in "$MAIN" "$WT" "$OTHER"; do mkdir -p "$r/node_modules/.bin" "$r/src"; : > "$r/node_modules/.bin/eslint"; done
mkdir -p "$BARE/src" "$WORK/bin"
for r in "$MAIN" "$WT" "$BARE" "$OTHER"; do
    for f in a.ts b.vue c.js d.md; do echo x > "$r/src/$f"; done
done
# The stub: logs "<cwd> <args>", then behaves as STUB says (clean|errors|crash|hang).
cat > "$WORK/bin/npx" <<EOF
#!/bin/bash
echo "\$PWD \$*" >> "$CALLS"
case "\${STUB:-clean}" in
    errors) echo "/x/src/a.ts"; echo "  3:7  error  'y' is assigned a value but never used  no-unused-vars"; exit 1 ;;
    crash) echo "Oops! Something went wrong"; exit 2 ;;
    hang) sleep 10 & echo \$! > "$WORK/child"; wait; exit 1 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/npx"

run() { # run <tool> <file> [stub] -> exit code of the hook
    : > "$CALLS"
    jq -n --arg t "$1" --arg f "$2" '{hook_event_name:"PostToolUse", tool_name:$t, tool_input:{file_path:$f}, tool_response:{}}' \
        | env HOME="$H" PATH="$WORK/bin:/usr/bin:/bin" STUB="${3:-clean}" DASHBOARD_CHECK_TIMEOUT="${TIMEOUT:-30}" \
            "$PY" "$SCRIPT" >/dev/null 2>"$ERR"
}
expect() { # expect <name> <code> <tool> <file> [stub]
    run "$3" "$4" "${5:-clean}"; local code=$?
    [ "$code" -eq "$2" ] && pass "$1" || fail "$1" "exit $code, want $2 ($(cat "$ERR"))"
}
skips() { # exit 0, eslint never called
    run "$2" "$3" "${4:-errors}"; local code=$?
    if [ "$code" -ne 0 ]; then fail "$1" "exit $code"
    elif [ -s "$CALLS" ]; then fail "$1" "eslint ran: $(cat "$CALLS")"
    else pass "$1"; fi
}

echo "lints the edited file"
expect "clean .ts is silent" 0 Edit "$MAIN/src/a.ts"
[ -s "$ERR" ] && fail "clean prints nothing" "$(cat "$ERR")" || pass "clean prints nothing"
[ "$(cat "$CALLS")" = "$MAIN --no eslint --quiet --no-color src/a.ts" ] && pass "runs repo eslint on the one file, from the root" \
    || fail "runs repo eslint on the one file, from the root" "$(cat "$CALLS")"
expect "errors in .ts go back to Claude" 2 Edit "$MAIN/src/a.ts" errors
case "$(cat "$ERR")" in *"eslint errors in src/a.ts"*"no-unused-vars"*) pass "the report names the file and the error" ;;
    *) fail "the report names the file and the error" "$(cat "$ERR")" ;; esac
expect "errors in .vue" 2 Write "$MAIN/src/b.vue" errors
expect "MultiEdit counts" 2 MultiEdit "$MAIN/src/a.ts" errors
expect "in a worktree" 2 Edit "$WT/src/a.ts" errors
[ "$(cut -d' ' -f1 "$CALLS")" = "$WT" ] && pass "worktree runs from its own root" || fail "worktree runs from its own root" "$(cat "$CALLS")"
expect "eslint crash stays silent" 0 Edit "$MAIN/src/a.ts" crash

echo "time limit"
start=$(date +%s)
TIMEOUT=1 expect "a hung eslint passes" 0 Edit "$MAIN/src/a.ts" hang
[ $(( $(date +%s) - start )) -le 4 ] && pass "gives up after the limit" || fail "gives up after the limit" "took $(( $(date +%s) - start )) s"
kill -0 "$(cat "$WORK/child" 2>/dev/null || echo 999999)" 2>/dev/null && fail "kills eslint's children" "still running" || pass "kills eslint's children"

echo "leaves everything else alone"
skips "other repo" Edit "$OTHER/src/a.ts"
skips ".js file" Edit "$MAIN/src/c.js"
skips ".md file" Write "$MAIN/src/d.md"
skips "worktree without node_modules" Edit "$BARE/src/a.ts"
skips "missing file" Edit "$MAIN/src/gone.ts"
skips "Read tool" Read "$MAIN/src/a.ts"
skips "lookalike path" Edit "$H/projects/ecfx-dashboard-old/src/a.ts"
printf 'not json' | env HOME="$H" PATH="$WORK/bin:/usr/bin:/bin" "$PY" "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "bad input never blocks" || fail "bad input never blocks" "blocked"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
