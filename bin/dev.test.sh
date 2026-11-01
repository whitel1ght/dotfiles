#!/bin/bash
# Tests for bin/dev. A sandbox repo stands in for the dashboard: its `npm run dev`
# is a Python HTTP server on a spare port, run in a throwaway tmux session, so
# the real dashboard and its port are never touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/dev"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

command -v tmux >/dev/null || { echo "skip: no tmux"; exit 0; }

# Worktrees must live under ~/projects to be offered, so the sandbox goes there.
SANDBOX="$(mktemp -d "$HOME/projects/.dev-test.XXXXXX")"
export DEV_REPO="$SANDBOX/repo" DEV_PORT=4799 DEV_SESSION="devtest-$$" DEV_MATCH=http.server DEV_WAIT=20
# DEV_WINDOW stays at its default, "dashboard dev": a name with a space in it.
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cleanup() {
    "$SCRIPT" stop >/dev/null 2>&1
    tmux kill-session -t "=$DEV_SESSION" 2>/dev/null
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

git init -q -b master "$DEV_REPO"
cat > "$DEV_REPO/package.json" <<EOF
{"name":"t","version":"1.0.0","scripts":{"dev":"exec python3 -m http.server $DEV_PORT --bind 127.0.0.1"}}
EOF
echo '{}' > "$DEV_REPO/package-lock.json"
printf '/node_modules/\n/certs/\n' > "$DEV_REPO/.gitignore"
git -C "$DEV_REPO" add -A && git -C "$DEV_REPO" commit -q -m init
mkdir -p "$DEV_REPO/certs" && echo cert > "$DEV_REPO/certs/localhost.pem"
for b in alpha beta; do
    git -C "$DEV_REPO" worktree add -q -b "feat/$b" "$SANDBOX/$b"
    mkdir -p "$SANDBOX/$b/node_modules" && echo '{}' > "$SANDBOX/$b/node_modules/.package-lock.json"
done

served() {
    local pid; pid=$(lsof -nP -tiTCP:$DEV_PORT -sTCP:LISTEN | head -1)
    [ -n "$pid" ] && lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
}

echo "dev — switching"
out="$("$SCRIPT" alpha 2>&1)"
assert_contains "$out" "up: " "starts the matching worktree"
[ "$(served)" = "$SANDBOX/alpha" ] && pass "alpha holds the port" || fail "alpha holds the port" "served: $(served)"
[ -f "$SANDBOX/alpha/certs/localhost.pem" ] && pass "copies certs into a worktree lacking them" || fail "copies certs into a worktree lacking them" "missing"
[ -z "$(git -C "$SANDBOX/alpha" status --porcelain)" ] && pass "leaves the worktree clean for /clean-worktrees" \
    || fail "leaves the worktree clean for /clean-worktrees" "$(git -C "$SANDBOX/alpha" status --porcelain)"

out="$("$SCRIPT" beta 2>&1)"
assert_contains "$out" "stopping $SANDBOX/alpha" "stops the previous worktree"
[ "$(served)" = "$SANDBOX/beta" ] && pass "beta now holds the port" || fail "beta now holds the port" "served: $(served)"
[ "$(tmux list-windows -t "=$DEV_SESSION" | wc -l | tr -d ' ')" = 1 ] && pass "reuses one tmux window" || fail "reuses one tmux window" "$(tmux list-windows -t "=$DEV_SESSION")"

echo "dev — status and stop"
assert_contains "$("$SCRIPT" status)" "$SANDBOX/beta (feat/beta)" "status names the served worktree and branch"
"$SCRIPT" stop >/dev/null
[ -z "$(lsof -nP -tiTCP:$DEV_PORT -sTCP:LISTEN)" ] && pass "stop frees the port" || fail "stop frees the port" "still listening"
assert_contains "$("$SCRIPT" status)" "nothing on port" "status after stop"
tmux list-windows -t "=$DEV_SESSION" -F '#W' | grep -qx 'dashboard dev' && pass "stop keeps the window, with its shell" \
    || fail "stop keeps the window, with its shell" "window gone"

echo "dev — completion"
out="$("$SCRIPT" --complete)"
assert_contains "$out" "status:" "offers subcommands"
assert_contains "$out" "feat/alpha:$SANDBOX/alpha" "offers worktrees by branch"

echo "dev — guards"
out="$("$SCRIPT" nosuchbranch 2>&1)"; rc=$?
assert_contains "$out" "no worktree matches" "reports an unknown query"
[ "$rc" -ne 0 ] && pass "exits non-zero on no match" || fail "exits non-zero on no match" "rc=0"
python3 -m http.server "$DEV_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
other=$!; sleep 1
out="$(DEV_MATCH=vite "$SCRIPT" alpha 2>&1)"
assert_contains "$out" "held by something else" "won't kill a process that isn't the dev server"
kill -0 "$other" 2>/dev/null && pass "the foreign process survives" || fail "the foreign process survives" "killed"
kill "$other" 2>/dev/null

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
