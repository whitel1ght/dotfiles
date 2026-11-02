#!/bin/bash
# Tests for bin/ecfx-daily-commits. Every repo is a throwaway in a sandbox, and
# the commits are authored today, so the default --since ("today 00:00") sees
# them. The clones are laid out both ways: flat (the Mac) and grouped one folder
# deeper (Ubuntu's ~/projects/ecfx/<repo>).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/ecfx-daily-commits"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME="Dmitry Mamyrev" GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME="Dmitry Mamyrev" GIT_COMMITTER_EMAIL=t@t
ROOT="$SANDBOX/projects"
mkdir -p "$ROOT"

# A clone with one commit authored by me today.
clone() { # path subject
    git init -q -b main "$1" && git -C "$1" commit -q --allow-empty -m "$2"
}

clone "$ROOT/ecfx-admin" "flat commit"
mkdir -p "$ROOT/ecfx"
clone "$ROOT/ecfx/ecfx-backend" "nested commit"
clone "$ROOT/ecfx/ecfx-backend/src/protobufs" "protobufs commit"
clone "$ROOT/js" "js commit"

echo "ecfx-daily-commits"
out="$(PROJECTS_DIR="$ROOT" "$SCRIPT" 2>&1)"
assert_contains "$out" "flat commit" "lists a clone at the projects root"
assert_contains "$out" "nested commit" "lists a clone one folder deeper (~/projects/ecfx/<repo>)"
assert_contains "$out" "ecfx-backend" "under its own name"
assert_contains "$out" "protobufs (via ecfx/ecfx-backend/src/protobufs)" "still labels a nested checkout by its path"
assert_lacks "$out" "js commit" "leaves repos that are not ecfx projects alone"

out="$(env -u PROJECTS_DIR HOME="$SANDBOX" "$SCRIPT" 2>&1)"
assert_contains "$out" "nested commit" "~/projects is the default root"

out="$(PROJECTS_DIR="$SANDBOX/empty" "$SCRIPT" 2>&1)"
assert_lacks "$out" "commit" "an empty root reports nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]