#!/bin/bash
# Tests for bin/wiki-commit. A sandbox git repo stands in for ~/wiki.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/wiki-commit"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { # check <label> <got> <want>
    [ "$2" = "$3" ] && pass "$1" || fail "$1" "got '$2', want '$3'"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export WIKI_DIR="$SANDBOX/wiki"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$WIKI_DIR/work/system" "$WIKI_DIR/tools" "$WIKI_DIR/diary" "$WIKI_DIR/cards" "$WIKI_DIR/work/friction"
git -C "$WIKI_DIR" init -q -b main
echo a > "$WIKI_DIR/work/system/a.md"
echo t > "$WIKI_DIR/tools/t.md"
echo d > "$WIKI_DIR/diary/x.md"
git -C "$WIKI_DIR" add -A && git -C "$WIKI_DIR" commit -q -m init

trailer() { git -C "$WIKI_DIR" log -1 --format='%(trailers:key=Agent-edit,valueonly)' | tr -d '\n'; }
head_sha() { git -C "$WIKI_DIR" rev-parse HEAD; }

# commits only the named path, with the trailer
echo a2 > "$WIKI_DIR/work/system/a.md"
echo d2 > "$WIKI_DIR/diary/x.md"
out="$("$SCRIPT" --by claude --session abc -m "edit a" -- "$WIKI_DIR/work/system/a.md" 2>&1)"; rc=$?
check "commit exits 0" "$rc" 0
check "trailer has by and session" "$(trailer)" "claude abc"
check "commit subject" "$(git -C "$WIKI_DIR" log -1 --format=%s)" "edit a"
check "other dirty file stays uncommitted" "$(git -C "$WIKI_DIR" status --porcelain)" " M diary/x.md"

# relative path, new untracked file, no session
echo n > "$WIKI_DIR/tools/new.md"
"$SCRIPT" --by pi -m "add new" -- tools/new.md >/dev/null 2>&1; rc=$?
check "relative new file exits 0" "$rc" 0
check "trailer without session" "$(trailer)" "pi unknown"
check "new file is tracked" "$(git -C "$WIKI_DIR" ls-files tools/new.md)" "tools/new.md"

# deleted file
rm "$WIKI_DIR/tools/t.md"
"$SCRIPT" --by claude --session s1 -m "drop t" -- tools/t.md >/dev/null 2>&1; rc=$?
check "deleted file exits 0" "$rc" 0
check "deleted file committed" "$(git -C "$WIKI_DIR" ls-files tools/t.md)" ""
check "deletion commit has trailer" "$(trailer)" "claude s1"

# already committed (wiki-sync got there first)
before="$(head_sha)"
out="$("$SCRIPT" --by claude --session s2 -m "again" -- tools/new.md 2>&1)"; rc=$?
check "nothing to commit exits 0" "$rc" 0
case "$out" in *"nothing to commit"*) pass "prints nothing to commit" ;; *) fail "prints nothing to commit" "$out" ;; esac
check "no new commit" "$(head_sha)" "$before"

# cards and friction entries are allowed
echo c > "$WIKI_DIR/cards/x.md"
"$SCRIPT" --by claude -m "card" -- cards/x.md >/dev/null 2>&1; check "cards path exits 0" "$?" 0
echo f > "$WIKI_DIR/work/friction/F-001.md"
"$SCRIPT" --by claude -m "friction" -- work/friction/F-001.md >/dev/null 2>&1; check "work/friction path exits 0" "$?" 0
check "friction file tracked" "$(git -C "$WIKI_DIR" ls-files work/friction/F-001.md)" "work/friction/F-001.md"

# usage errors and out-of-scope paths
"$SCRIPT" --by claude -m "x" -- diary/x.md >/dev/null 2>&1; check "diary path exits 2" "$?" 2
"$SCRIPT" --by claude -m "x" -- "$WIKI_DIR/work/system/../../diary/x.md" >/dev/null 2>&1; check "dotdot escape exits 2" "$?" 2
"$SCRIPT" --by claude -m "x" -- "$SANDBOX/outside.md" >/dev/null 2>&1; check "outside wiki exits 2" "$?" 2
"$SCRIPT" --by claude -m "x" -- tools/new.md diary/x.md >/dev/null 2>&1; check "one bad path exits 2" "$?" 2
"$SCRIPT" --by bob -m "x" -- tools/new.md >/dev/null 2>&1; check "bad --by exits 2" "$?" 2
"$SCRIPT" -m "x" -- tools/new.md >/dev/null 2>&1; check "missing --by exits 2" "$?" 2
"$SCRIPT" --by claude -- tools/new.md >/dev/null 2>&1; check "missing -m exits 2" "$?" 2
"$SCRIPT" --by claude -m "x" -- >/dev/null 2>&1; check "no paths exits 2" "$?" 2
check "diary still uncommitted after errors" "$(git -C "$WIKI_DIR" status --porcelain)" " M diary/x.md"

echo "passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
