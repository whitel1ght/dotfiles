#!/bin/bash
# Tests for bin/clean-worktrees. Real git repos in a sandbox; glab is stubbed on
# PATH and answers from a per-branch fixture, so nothing reaches GitLab.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/clean-worktrees"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_contains() {
    case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac
}
gone()    { [ ! -e "$1" ] && pass "$2" || fail "$2" "$1 still exists"; }
present() { [ -e "$1" ] && pass "$2" || fail "$2" "$1 is missing"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
WT="$SANDBOX/worktrees"; MRS="$SANDBOX/mrs"; STUBS="$SANDBOX/stubs"
mkdir -p "$WT/repo" "$MRS" "$STUBS"

git init -q --bare -b master "$SANDBOX/origin.git"
git clone -q "$SANDBOX/origin.git" "$SANDBOX/repo" 2>/dev/null
REPO="$SANDBOX/repo"
git -C "$REPO" commit -q --allow-empty -m init && git -C "$REPO" push -q origin master

# worktree <name> <branch> <mr-state|none>: branch with one commit, pushed, MR at that commit.
worktree() {
    git -C "$REPO" worktree add -q -b "$2" "$WT/repo/$1" master
    git -C "$WT/repo/$1" commit -q --allow-empty -m "$1"
    git -C "$WT/repo/$1" push -q origin "$2" 2>/dev/null
    [ "$3" = none ] && { echo '[]' > "$MRS/$(echo "$2" | tr / _)"; return; }
    printf '[{"iid":%s,"state":"%s","sha":"%s","updated_at":"2026-01-01"}]' \
        "$RANDOM" "$3" "$(git -C "$WT/repo/$1" rev-parse HEAD)" > "$MRS/$(echo "$2" | tr / _)"
}

worktree merged      u/merged      merged
worktree dirty       u/dirty       merged
worktree ahead       u/ahead       merged
worktree squashed    u/squashed    merged
worktree open        u/open        opened
worktree closed      u/closed      closed
worktree nomr        u/nomr        none
git -C "$REPO" worktree add -q --detach "$WT/repo/detached" master
mkdir -p "$WT/repo/orphan/.vite"

echo "local edit" > "$WT/repo/dirty/file"
git -C "$WT/repo/ahead" commit -q --allow-empty -m "local only, never pushed"
# Remote branch deleted after the squash merge: HEAD is on no remote, but it is
# exactly the commit the MR merged.
git -C "$REPO" push -q origin --delete u/squashed 2>/dev/null
git -C "$REPO" fetch -q --prune

# The script derives the GitLab project from origin, so make it look like one.
git -C "$REPO" remote set-url origin git@gitlab.com:grp/repo.git

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
b=$(echo "$*" | sed -nE 's/.*source_branch=([^&]*).*/\1/p' | sed 's/%2F/_/g')
cat "$MRS/$b"
EOF
chmod +x "$STUBS/glab"

run() { PATH="$STUBS:$PATH" MRS="$MRS" WORKTREES_DIR="$WT" "$SCRIPT" "$@" 2>&1; }

echo "clean-worktrees — dry run"
out="$(run -n)"
assert_contains "$out" "would   remove repo/merged" "a clean merged worktree would go"
present "$WT/repo/merged" "dry run removes nothing"

echo "clean-worktrees — apply"
out="$(run)"
gone "$WT/repo/merged" "removes a clean merged worktree"
[ -z "$(git -C "$REPO" branch --list u/merged)" ] && pass "deletes its local branch" || fail "deletes its local branch" "u/merged remains"
gone "$WT/repo/squashed" "removes a merged worktree whose remote branch is gone"
present "$WT/repo/dirty" "keeps a merged worktree with uncommitted changes"
assert_contains "$out" "repo/dirty — !" "says why the dirty one stayed"
present "$WT/repo/ahead" "keeps a merged worktree with unpushed commits"
assert_contains "$out" "exist nowhere else" "says why the ahead one stayed"
present "$WT/repo/open" "keeps an open MR"
present "$WT/repo/closed" "keeps a closed, unmerged MR"
present "$WT/repo/nomr" "keeps a branch with no MR"
present "$WT/repo/detached" "keeps a detached HEAD"
present "$WT/repo/orphan" "keeps a directory git doesn't know"
assert_contains "$out" "repo/orphan — not a git worktree" "reports the orphan directory"
[ -z "$(git -C "$REPO" worktree list | grep "$WT/repo/merged")" ] && pass "git no longer lists the removed worktree" \
    || fail "git no longer lists the removed worktree" "still listed"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
