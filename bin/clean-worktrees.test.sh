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
worktree closedlocal u/closedlocal closed

# Gradle worktrees kept for their open MR: build/ next to a build.gradle is output; a build/
# without one (a scripts folder) or holding tracked files is not.
gradle() {
    worktree "$1" "u/$1" opened
    local w="$WT/repo/$1"
    printf 'build/\n' > "$w/.gitignore"
    mkdir -p "$w/sub" "$w/scripts/build" "$w/tracked/build"
    touch "$w/build.gradle" "$w/sub/build.gradle" "$w/tracked/build.gradle"
    echo run > "$w/scripts/build/run.sh"; echo keep > "$w/tracked/build/keep.txt"
    git -C "$w" add -A && git -C "$w" add -f tracked/build/keep.txt && git -C "$w" commit -q -m gradle
    mkdir -p "$w/build/libs" "$w/sub/build/classes"
    echo jar > "$w/build/libs/a.jar"; echo class > "$w/sub/build/classes/A.class"
}
gradle idlegradle
gradle activegradle
find "$WT/repo/idlegradle" -name .git -prune -o -exec touch -t 202501010000 {} +
worktree generated   u/generated   merged
worktree nomr        u/nomr        none
git -C "$REPO" worktree add -q --detach "$WT/repo/detached" master
mkdir -p "$WT/repo/orphan/.vite" "$WT/repo/orphan2/.vite"
echo keep > "$WT/repo/orphan2/notes.md"

# review worktrees: detached at the MR head; the MR is looked up by the iid in the name
review() {
    git -C "$REPO" worktree add -q --detach "$WT/repo/$1" master
    printf '{"iid":%s,"state":"%s"}' "$2" "$3" > "$MRS/iid-$2"
}
review review-71     71 merged
review X-1-review-72 72 closed
review review-73     73 opened
review review-74     74 merged
echo "local edit" > "$WT/repo/review-74/file"

echo "local edit" > "$WT/repo/dirty/file"
git -C "$WT/repo/ahead" commit -q --allow-empty -m "local only, never pushed"
git -C "$WT/repo/closedlocal" commit -q --allow-empty -m "local only, never pushed"
# tracked files the tools rewrite on their own, and pi's session folder
git -C "$WT/repo/generated" checkout -q -b tmp && mkdir -p "$WT/repo/generated/src" \
    && echo a > "$WT/repo/generated/src/components.d.ts" && git -C "$WT/repo/generated" add src \
    && git -C "$WT/repo/generated" commit -q -m gen && git -C "$WT/repo/generated" checkout -q u/generated \
    && git -C "$WT/repo/generated" merge -q --ff-only tmp && git -C "$WT/repo/generated" branch -q -D tmp \
    && git -C "$WT/repo/generated" push -q origin u/generated 2>/dev/null
printf '[{"iid":9,"state":"merged","sha":"%s","updated_at":"2026-01-01"}]' "$(git -C "$WT/repo/generated" rev-parse HEAD)" > "$MRS/u_generated"
echo b > "$WT/repo/generated/src/components.d.ts"
mkdir -p "$WT/repo/generated/.pi" && echo s > "$WT/repo/generated/.pi/session"

# a repo on GitHub (dotfiles): merged means merged into the local default branch
git init -q --bare -b main "$SANDBOX/gh.git"
git clone -q "$SANDBOX/gh.git" "$SANDBOX/gh" 2>/dev/null
GH="$SANDBOX/gh"
git -C "$GH" commit -q --allow-empty -m init && git -C "$GH" push -q origin main
mkdir -p "$WT/gh"
git -C "$GH" worktree add -q -b landed "$WT/gh/landed" main
git -C "$WT/gh/landed" commit -q --allow-empty -m landed
git -C "$GH" merge -q --ff-only landed
git -C "$GH" worktree add -q -b wip "$WT/gh/wip" main
git -C "$WT/gh/wip" commit -q --allow-empty -m wip
git -C "$GH" remote set-url origin git@github.com:someone/gh.git
# Remote branch deleted after the squash merge: HEAD is on no remote, but it is
# exactly the commit the MR merged.
git -C "$REPO" push -q origin --delete u/squashed 2>/dev/null
git -C "$REPO" fetch -q --prune

# The script derives the GitLab project from origin, so make it look like one.
git -C "$REPO" remote set-url origin git@gitlab.com:grp/repo.git

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
iid=$(echo "$*" | sed -nE 's#.*merge_requests/([0-9]+)$#\1#p')
[ -n "$iid" ] && { cat "$MRS/iid-$iid"; exit; }
b=$(echo "$*" | sed -nE 's/.*source_branch=([^&]*).*/\1/p' | sed 's/%2F/_/g')
cat "$MRS/$b"
EOF
chmod +x "$STUBS/glab"

run() { PATH="$STUBS:$PATH" MRS="$MRS" WORKTREES_DIR="$WT" "$SCRIPT" "$@" 2>&1; }

echo "clean-worktrees — dry run"
out="$(run -n)"
assert_contains "$out" "would   remove repo/merged" "a clean merged worktree would go"
present "$WT/repo/merged" "dry run removes nothing"
assert_contains "$out" "would   trim repo/idlegradle" "a dry run names the build output it would trim"
present "$WT/repo/idlegradle/build/libs/a.jar" "a dry run trims nothing"

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
gone "$WT/repo/closed" "removes a clean closed MR whose commits are on the remote"
[ -z "$(git -C "$REPO" branch --list u/closed)" ] && pass "deletes the closed one's local branch" || fail "deletes the closed one's local branch" "u/closed remains"
present "$WT/repo/closedlocal" "keeps a closed MR with commits that exist nowhere else"
assert_contains "$out" "repo/closedlocal — !" "says why the closed one with local commits stayed"
gone "$WT/repo/generated" "regenerated files and .pi/ do not count as changes"
present "$WT/repo/nomr" "keeps a branch with no MR"
present "$WT/repo/detached" "keeps a detached HEAD not named after a review"
gone "$WT/repo/review-71" "removes the review of a merged MR"
gone "$WT/repo/X-1-review-72" "removes the review of a closed MR (<key>-review-<iid>)"
present "$WT/repo/review-73" "keeps the review of an open MR"
assert_contains "$out" "repo/review-73 — review of !73, which is opened" "says why the open review stayed"
present "$WT/repo/review-74" "keeps a review with real uncommitted changes"
gone "$WT/repo/orphan" "removes a leftover directory holding only .vite"
present "$WT/repo/orphan2" "keeps any other directory git doesn't know"
assert_contains "$out" "repo/orphan2 — not a git worktree" "reports the orphan directory"
gone "$WT/gh/landed" "removes a non-GitLab branch merged into the local default branch"
[ -z "$(git -C "$GH" branch --list landed)" ] && pass "deletes its local branch" || fail "deletes its local branch" "landed remains"
present "$WT/gh/wip" "keeps a non-GitLab branch not merged yet"
assert_contains "$out" "gh/wip — not merged into main" "says why the unmerged one stayed"
[ -z "$(git -C "$REPO" worktree list | grep "$WT/repo/merged")" ] && pass "git no longer lists the removed worktree" \
    || fail "git no longer lists the removed worktree" "still listed"

echo "clean-worktrees — Gradle build output of idle worktrees"
present "$WT/repo/idlegradle/build.gradle" "the idle worktree itself stays (its MR is open)"
gone "$WT/repo/idlegradle/build" "removes build/ next to the root build.gradle"
gone "$WT/repo/idlegradle/sub/build" "removes build/ next to a subproject's build.gradle"
present "$WT/repo/idlegradle/scripts/build/run.sh" "keeps a build/ with no build.gradle beside it"
present "$WT/repo/idlegradle/tracked/build/keep.txt" "keeps a build/ holding tracked files"
assert_contains "$out" "trimmed repo/idlegradle (Gradle build output" "says what it trimmed"
assert_contains "$out" "build output trimmed in 1" "counts it in the summary"
present "$WT/repo/activegradle/build/libs/a.jar" "keeps the build output of a worktree changed recently"

echo "clean-worktrees — worktrees root"
# WORKTREES_DIR defaults to <PROJECTS_DIR>/worktrees, so pointing PROJECTS_DIR at
# another root moves it (the clones themselves may sit one folder deeper; this
# script only ever walks the worktrees tree).
ALT="$SANDBOX/alt-projects"; mkdir -p "$ALT/worktrees/repo/keepme"
out="$(PATH="$STUBS:$PATH" MRS="$MRS" PROJECTS_DIR="$ALT" "$SCRIPT" -n 2>&1)"
assert_contains "$out" "repo/keepme — not a git worktree" "WORKTREES_DIR follows PROJECTS_DIR"
out="$(PATH="$STUBS:$PATH" MRS="$MRS" PROJECTS_DIR="$SANDBOX/none" "$SCRIPT" -n 2>&1)"
assert_contains "$out" "no $SANDBOX/none/worktrees" "and a PROJECTS_DIR with no worktrees is reported"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
