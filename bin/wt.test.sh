#!/bin/bash
# Tests for bin/wt. Every repo, remote and worktree is a throwaway in a sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/wt"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_ok() { local l="$1"; shift; "$@" >/dev/null 2>&1 && pass "$l" || fail "$l" "failed: $*"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
PROJ="$SANDBOX/projects"; WT="$PROJ/worktrees"; HIST="$SANDBOX/claude-projects"
mkdir -p "$PROJ" "$HIST"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
g() { git -c user.name=t -c user.email=t@t "$@"; }

# A remote with a submodule and a pushed feature branch, and a clone of it.
g init -q -b main "$SANDBOX/sub" && g -C "$SANDBOX/sub" commit -q --allow-empty -m sub
g init -q -b main "$SANDBOX/seed"
g -C "$SANDBOX/seed" submodule add -q "$SANDBOX/sub" lib/sub 2>/dev/null
g -C "$SANDBOX/seed" commit -q -m init
g -C "$SANDBOX/seed" checkout -q -b dmitry/ABC-2_pushed && g -C "$SANDBOX/seed" commit -q --allow-empty -m pushed
g -C "$SANDBOX/seed" checkout -q main
g clone -q --bare "$SANDBOX/seed" "$SANDBOX/remote.git"
g clone -q "$SANDBOX/remote.git" "$PROJ/app" 2>/dev/null
g -C "$PROJ/app" remote set-head origin -a >/dev/null

run() { PROJECTS_DIR="$PROJ" WORKTREES_DIR="$WT" CLAUDE_PROJECTS="$HIST" "$SCRIPT" "$@" 2>&1; }

echo "wt add"
out="$(run add app ABC-1 dmitry/ABC-1_new)"
assert_eq "$WT/app/ABC-1" "$out" "prints the new worktree's path"
assert_eq "dmitry/ABC-1_new" "$(git -C "$WT/app/ABC-1" branch --show-current)" "creates a new branch"
assert_eq "$(git -C "$PROJ/app" rev-parse origin/main)" "$(git -C "$WT/app/ABC-1" rev-parse HEAD)" "branches from origin's default branch"
assert_ok "initialises submodules" test -f "$WT/app/ABC-1/lib/sub/.git"
run add app ABC-2 dmitry/ABC-2_pushed >/dev/null
assert_eq "$(git -C "$PROJ/app" rev-parse origin/dmitry/ABC-2_pushed)" "$(git -C "$WT/app/ABC-2" rev-parse HEAD)" "checks out a branch that exists on origin"
out="$(run add app ABC-1)"
assert_contains "$out" "already exists" "refuses to overwrite a worktree"

echo "wt move"
g -C "$PROJ/app" worktree add -q -b dmitry/ABC-3_stray "$PROJ/app-3" origin/main 2>/dev/null
g -C "$PROJ/app-3" submodule update -q --init 2>/dev/null
echo change > "$PROJ/app-3/README"
mkdir -p "$HIST/$(printf '%s' "$PROJ/app-3" | sed 's/[^A-Za-z0-9]/-/g')"
out="$(run move "$PROJ/app-3")"
assert_contains "$out" "-> $WT/app/ABC-3" "names the destination after the branch's ticket"
assert_eq "dmitry/ABC-3_stray" "$(git -C "$WT/app/ABC-3" branch --show-current)" "the moved worktree still works"
assert_eq "?? README" "$(git -C "$WT/app/ABC-3" status --porcelain)" "keeps uncommitted changes"
assert_eq "$WT/app/ABC-3/lib/sub" "$(git -C "$WT/app/ABC-3/lib/sub" rev-parse --show-toplevel)" "re-points the submodule"
assert_contains "$(git -C "$PROJ/app" worktree list)" "$WT/app/ABC-3" "the clone knows the new path"
assert_ok "carries the Claude session history over" test -d "$HIST/$(printf '%s' "$WT/app/ABC-3" | sed 's/[^A-Za-z0-9]/-/g')"
g -C "$PROJ/app" worktree add -q -b other "$PROJ/app-lk" origin/main 2>/dev/null
g -C "$PROJ/app" worktree lock --reason "claude session x" "$PROJ/app-lk"
out="$(run move "$PROJ/app-lk" LK)"
assert_contains "$out" "is locked: claude session x" "refuses a locked worktree"
assert_ok "leaves a locked worktree where it is" test -d "$PROJ/app-lk"

echo "wt ls"
out="$(run ls)"
assert_contains "$out" "!!  $PROJ/app-lk" "marks an out-of-place worktree"
assert_contains "$out" "    $WT/app/ABC-1" "lists in-place worktrees unmarked"

echo "wt hooks"
out="$(printf '{"name":"swift-oak","cwd":"%s"}' "$PROJ/app/lib" | run hook-create)"
assert_eq "$WT/app/swift-oak" "$(tail -1 <<<"$out")" "hook-create ends with the path"
assert_eq "worktree-swift-oak" "$(git -C "$WT/app/swift-oak" branch --show-current)" "uses Claude's usual branch name"
out="$(printf '{"name":"swift-oak","cwd":"%s"}' "$PROJ/app" | run hook-create)"
assert_eq "$WT/app/swift-oak" "$(tail -1 <<<"$out")" "reuses an existing worktree of that name"
g -C "$PROJ/app" branch -q ABC-9 origin/main
out="$(printf '{"name":"ABC-9","cwd":"%s"}' "$PROJ/app" | run hook-create)"
assert_eq "ABC-9" "$(git -C "$WT/app/ABC-9" branch --show-current)" "checks out a branch named like the worktree"

printf '{"worktree_path":"%s"}' "$WT/app/swift-oak" | run hook-remove >/dev/null
assert_ok "hook-remove removes the worktree" test ! -e "$WT/app/swift-oak"
git -C "$PROJ/app" show-ref -q --verify refs/heads/worktree-swift-oak \
    && fail "drops a branch with nothing unpushed" "branch kept" || pass "drops a branch with nothing unpushed"
printf '{"name":"kept","cwd":"%s"}' "$PROJ/app" | run hook-create >/dev/null
g -C "$WT/app/kept" commit -q --allow-empty -m local-only
printf '{"worktree_path":"%s"}' "$WT/app/kept" | run hook-remove >/dev/null
git -C "$PROJ/app" show-ref -q --verify refs/heads/worktree-kept \
    && pass "keeps a branch with local-only commits" || fail "keeps a branch with local-only commits" "branch dropped"
echo x > "$WT/app/ABC-9/dirty"
printf '{"worktree_path":"%s"}' "$WT/app/ABC-9" | run hook-remove >/dev/null; rc=$?
assert_eq 1 "$rc" "hook-remove fails on uncommitted changes"
assert_ok "and leaves them on disk" test -f "$WT/app/ABC-9/dirty"
printf '{"worktree_path":"%s"}' "$WT/app/gone" | run hook-remove >/dev/null; rc=$?
assert_eq 0 "$rc" "hook-remove is fine when the directory is already gone"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
