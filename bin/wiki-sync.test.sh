#!/bin/bash
# Tests for bin/wiki-sync. A bare repo in a sandbox stands in for the VPS and
# two clones for this Mac and "another machine", so ~/wiki is never touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/wiki-sync"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REMOTE="$SANDBOX/wiki.git"
git init -q --bare -b main "$REMOTE"
git clone -q "$REMOTE" "$SANDBOX/seed" 2>/dev/null
echo "# index" > "$SANDBOX/seed/index.md"
git -C "$SANDBOX/seed" add -A && git -C "$SANDBOX/seed" commit -qm init && git -C "$SANDBOX/seed" push -q origin main
git clone -q "$REMOTE" "$SANDBOX/wiki"
git clone -q "$REMOTE" "$SANDBOX/other"

export WIKI_DIR="$SANDBOX/wiki" WIKI_SYNC_STATE="$SANDBOX/state"
run() { "$SCRIPT" "$@" 2>&1; }
remote_log() { git -C "$REMOTE" log --format=%s main; }
other_pull() { git -C "$SANDBOX/other" pull -q --rebase; }

echo "sync"
echo "habit: read" > "$WIKI_DIR/diary.md"
run >/dev/null; check "exit 0 after committing and pushing" "0" "$?"
check "remote has the change" "habit: read" "$(git -C "$REMOTE" show main:diary.md)"
case "$(remote_log | head -1)" in autosync*) pass "commit says it is an autosync" ;; *) fail "commit says it is an autosync" "$(remote_log | head -1)" ;; esac
check "working tree is clean" "" "$(git -C "$WIKI_DIR" status --porcelain)"

before="$(remote_log | wc -l)"
run >/dev/null; check "nothing to do still exits 0" "0" "$?"
check "nothing to do makes no commit" "$before" "$(remote_log | wc -l)"
[ -f "$WIKI_SYNC_STATE/last-ok" ] && pass "records the last good sync" || fail "records the last good sync" "no last-ok"

other_pull; echo "from the other machine" > "$SANDBOX/other/other.md"
git -C "$SANDBOX/other" add -A && git -C "$SANDBOX/other" commit -qm other && git -C "$SANDBOX/other" push -q
echo "local note" > "$WIKI_DIR/local.md"
run >/dev/null; check "pulls and pushes when both sides changed" "0" "$?"
[ -f "$WIKI_DIR/other.md" ] && pass "brings the remote change down" || fail "brings the remote change down" "other.md missing"
check "remote has the local change too" "local note" "$(git -C "$REMOTE" show main:local.md)"
check "history stays linear" "" "$(git -C "$WIKI_DIR" log --merges --format=%h)"

echo "conflict"
other_pull; echo "theirs" > "$SANDBOX/other/index.md"
git -C "$SANDBOX/other" commit -qam theirs && git -C "$SANDBOX/other" push -q
echo "mine" > "$WIKI_DIR/index.md"
out="$(run)"; code=$?
check "a conflict exits 1" "1" "$code"
[ -d "$WIKI_DIR/.git/rebase-merge" ] || [ -d "$WIKI_DIR/.git/rebase-apply" ] \
    && fail "never leaves a rebase half done" "rebase in progress" || pass "never leaves a rebase half done"
check "keeps the local edit" "mine" "$(cat "$WIKI_DIR/index.md")"
[ -s "$WIKI_SYNC_STATE/failed" ] && pass "records why it failed" || fail "records why it failed" "no failed file"
case "$(run check)" in *wiki*) pass "check warns after a failure" ;; *) fail "check warns after a failure" "silent" ;; esac

git -C "$WIKI_DIR" pull -q --rebase -X theirs 2>/dev/null || { git -C "$WIKI_DIR" checkout -q --theirs index.md 2>/dev/null; git -C "$WIKI_DIR" add index.md; GIT_EDITOR=true git -C "$WIKI_DIR" rebase --continue >/dev/null 2>&1; }
run >/dev/null; check "syncs again once resolved" "0" "$?"
[ -f "$WIKI_SYNC_STATE/failed" ] && fail "a good sync clears the failure" "failed still there" || pass "a good sync clears the failure"
check "check is silent when all is well" "" "$(run check)"

echo "check"
touch -t 202001010000 "$WIKI_SYNC_STATE/last-ok"
case "$(run check)" in *wiki*) pass "warns when the last good sync is over a day old" ;; *) fail "warns when stale" "silent" ;; esac
run >/dev/null

echo "guards"
mkdir -p "$WIKI_SYNC_STATE/lock"
echo "x" > "$WIKI_DIR/locked.md"
run >/dev/null; check "another run in progress: skip quietly" "0" "$?"
check "and commit nothing" "?? locked.md" "$(git -C "$WIKI_DIR" status --porcelain)"
rmdir "$WIKI_SYNC_STATE/lock"
run >/dev/null

git -C "$WIKI_DIR" remote remove origin
echo "y" > "$WIKI_DIR/noremote.md"
out="$(run)"; check "no remote exits 1" "1" "$?"
case "$out" in *remote*) pass "says the remote is missing" ;; *) fail "says the remote is missing" "$out" ;; esac

echo "status"
out="$(run status)"
case "$out" in *"last good sync"*) pass "status shows the last good sync" ;; *) fail "status shows the last good sync" "$out" ;; esac

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
