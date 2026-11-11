#!/bin/bash
# Tests for bin/nm-clone: a real git repo and worktrees in a sandbox on the
# same APFS volume as the cache, so cp -c really clones.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/nm-clone"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { if eval "$1"; then pass "$2"; else fail "$2" "$1"; fi }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export NM_CLONE_CACHE="$SANDBOX/cache"
run() { "$SCRIPT" "$@" 2>&1; }

# install <dir>: what npm ci leaves behind
install() {
    mkdir -p "$1/node_modules/pkg/.bin" "$1/node_modules/.vite/deps"
    echo "module" > "$1/node_modules/pkg/index.js"
    echo "cache" > "$1/node_modules/.vite/deps/x.js"
    sleep 1; echo '{}' > "$1/node_modules/.package-lock.json"
}

MAIN="$SANDBOX/main"
git init -q -b master "$MAIN"
echo '{"lock":1}' > "$MAIN/package-lock.json"; echo 24.11.1 > "$MAIN/.nvmrc"
git -C "$MAIN" add . && git -C "$MAIN" commit -q -m init
git -C "$MAIN" worktree add -q -b a "$SANDBOX/wt-a"
git -C "$MAIN" worktree add -q -b b "$SANDBOX/wt-b"
git -C "$MAIN" worktree add -q -b c "$SANDBOX/wt-c"
echo '{"lock":2}' > "$SANDBOX/wt-c/package-lock.json"
git -C "$MAIN" worktree add -q -b d "$SANDBOX/wt-d"
echo 22.0.0 > "$SANDBOX/wt-d/.nvmrc"

echo "nm-clone — nothing cached, main checkout not installed"
out=$(run "$SANDBOX/wt-a"); code=$?
check '[ "$code" -eq 3 ]' "exit 3 when no install matches"
check '[ ! -e "$SANDBOX/wt-a/node_modules" ]' "leaves no node_modules behind"
case "$out" in *"run npm ci"*) pass "says to run npm ci" ;; *) fail "says to run npm ci" "$out" ;; esac

echo "nm-clone — the main checkout's install seeds the cache"
install "$MAIN"
run "$SANDBOX/wt-a" >/dev/null; code=$?
check '[ "$code" -eq 0 ]' "exit 0 after cloning"
check '[ "$(cat "$SANDBOX/wt-a/node_modules/pkg/index.js")" = module ]' "the worktree gets the packages"
check '[ ! -e "$SANDBOX/wt-a/node_modules/.vite" ]' "build caches are not cloned"
check '[ ! "$SANDBOX/wt-a/package-lock.json" -nt "$SANDBOX/wt-a/node_modules/.package-lock.json" ]' "the clone counts as current for dev's staleness check"
check '[ "$(ls -A "$SANDBOX/wt-a" | grep -c nm-clone)" -eq 0 ]' "no temporary directory left in the worktree"
echo "changed" > "$SANDBOX/wt-a/node_modules/pkg/index.js"
check '[ "$(cat "$MAIN/node_modules/pkg/index.js")" = module ]' "writing in the clone leaves the source alone"

echo "nm-clone — the next worktree clones from the cache"
run "$SANDBOX/wt-b" >/dev/null
check '[ "$(cat "$SANDBOX/wt-b/node_modules/pkg/index.js")" = module ]' "gets a clean copy, not the edited one"
check '[ "$(run --ls | wc -l | tr -d " ")" -eq 1 ]' "one cached install"

echo "nm-clone — a node_modules already there is left alone"
echo mine > "$SANDBOX/wt-b/node_modules/pkg/index.js"
run "$SANDBOX/wt-b" >/dev/null; code=$?
check '[ "$code" -eq 0 ] && [ "$(cat "$SANDBOX/wt-b/node_modules/pkg/index.js")" = mine ]' "exit 0, untouched"

echo "nm-clone — a different lockfile or Node version never gets these packages"
run "$SANDBOX/wt-c" >/dev/null; code=$?
check '[ "$code" -eq 3 ] && [ ! -e "$SANDBOX/wt-c/node_modules" ]' "another package-lock.json misses"
run "$SANDBOX/wt-d" >/dev/null; code=$?
check '[ "$code" -eq 3 ] && [ ! -e "$SANDBOX/wt-d/node_modules" ]' "another .nvmrc misses"

echo "nm-clone --save"
install "$SANDBOX/wt-c"
run --save "$SANDBOX/wt-c" >/dev/null; code=$?
check '[ "$code" -eq 0 ] && [ "$(run --ls | wc -l | tr -d " ")" -eq 2 ]' "caches a finished install"
git -C "$MAIN" worktree add -q -b e "$SANDBOX/wt-e"
echo '{"lock":2}' > "$SANDBOX/wt-e/package-lock.json"
run "$SANDBOX/wt-e" >/dev/null
check '[ -f "$SANDBOX/wt-e/node_modules/pkg/index.js" ]' "a later worktree on that lockfile clones it"
sleep 1; echo '{"lock":3}' > "$SANDBOX/wt-d/package-lock.json"; mkdir -p "$SANDBOX/wt-d/node_modules"
echo '{}' > "$SANDBOX/wt-d/node_modules/.package-lock.json"; sleep 1; touch "$SANDBOX/wt-d/package-lock.json"
run --save "$SANDBOX/wt-d" >/dev/null; code=$?
check '[ "$code" -ne 0 ]' "refuses an install older than its package-lock.json"

echo "nm-clone — only the newest installs are kept"
for i in 1 2 3; do
    d="$SANDBOX/extra-$i"; mkdir -p "$d"; echo "{\"lock\":\"x$i\"}" > "$d/package-lock.json"; install "$d"
    NM_CLONE_KEEP=3 "$SCRIPT" --save "$d" 2>/dev/null
done
check '[ "$(run --ls | wc -l | tr -d " ")" -eq 3 ]' "prunes to NM_CLONE_KEEP"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
