#!/bin/bash
# Tests for bin/dot-land. Every repo is a throwaway: a bare origin, a base-branch checkout
# and a worktree per branch, so nothing here reaches the real dotfiles or its remote.
#
# The base branch is a parameter, not a hardcoded main: dot-land lands onto whatever
# branch the checkout is on, which on this host is `ubuntu`. Most fixtures run on `main`
# to prove that still works; the last section runs the whole flow on `ubuntu`.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/dot-land"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fresh() { # fresh <name> [base]: a new origin and checkout; sets SB, REPO, ORIGIN, BASE_BRANCH
    SB="$SANDBOX/$1"; ORIGIN="$SB/origin.git"; REPO="$SB/dotfiles"; BASE_BRANCH="${2:-main}"
    mkdir -p "$SB"
    git init -q --bare -b "$BASE_BRANCH" "$ORIGIN"
    git init -q -b "$BASE_BRANCH" "$REPO"
    git -C "$REPO" remote add origin "$ORIGIN"
    printf 'one\n' > "$REPO/a.txt"; printf 'pool\n' > "$REPO/settings.json"
    git -C "$REPO" add . && git -C "$REPO" commit -qm base
    git -C "$REPO" push -q origin "$BASE_BRANCH"
    export DOT_LAND_REPO="$REPO"
}

branch() { # branch <name> <file> <content>: a worktree off the base with one commit; sets WT
    WT="$SB/wt-$1"
    git -C "$REPO" worktree add -q -b "$1" "$WT" "$BASE_BRANCH"
    mkdir -p "$(dirname "$WT/$2")"
    printf '%s\n' "$3" > "$WT/$2"
    git -C "$WT" add . && git -C "$WT" commit -qm "change $2"
}

base_commit() { # base_commit <file> <content>: the base branch moves on
    printf '%s\n' "$2" > "$REPO/$1"
    git -C "$REPO" add "$1" && git -C "$REPO" commit -qm "$BASE_BRANCH: $1"
    git -C "$REPO" push -q origin "$BASE_BRANCH"
}

land() { OUT="$(cd "$SB" && bash "$SCRIPT" "$@" 2>&1)"; RC=$?; }
rev() { git -C "$1" rev-parse "$2" 2>/dev/null; }

echo "== lands a finished branch =="
fresh happy; branch feat b.txt two
SHA="$(rev "$REPO" feat)"
land feat
assert_eq 0 "$RC" "exits 0: $OUT"
assert_eq "$SHA" "$(rev "$REPO" "$BASE_BRANCH")" "the base is at the branch's commit"
assert_eq "$SHA" "$(rev "$ORIGIN" "$BASE_BRANCH")" "origin's base branch is pushed"
[ ! -d "$WT" ] && pass "the worktree is removed" || fail "the worktree is removed" "$WT"
git -C "$REPO" show-ref --verify --quiet refs/heads/feat && fail "the branch is deleted" "still there" || pass "the branch is deleted"
assert_contains "$OUT" "landed" "says it landed"
assert_contains "$OUT" "${SHA:0:7}" "names the commit"

echo "== refuses what it cannot land =="
fresh refuse; branch feat b.txt two
land main; assert_eq 1 "$RC" "refuses the base branch itself"
assert_contains "$OUT" "what branches land on" "says why"
land nope; assert_eq 1 "$RC" "refuses an unknown branch"
assert_contains "$OUT" "nope" "names the unknown branch"
land; assert_eq 2 "$RC" "no branch is a usage error"
land --bogus feat; assert_eq 2 "$RC" "an unknown option is a usage error"

git -C "$REPO" checkout -q --detach
land feat; assert_eq 1 "$RC" "refuses a detached HEAD"
assert_contains "$OUT" "detached" "says it is detached"
git -C "$REPO" checkout -q main

printf 'wip\n' >> "$WT/b.txt"
land feat; assert_eq 1 "$RC" "refuses a worktree with uncommitted changes"
assert_contains "$OUT" "uncommitted" "says why"
assert_eq "$(rev "$ORIGIN" "$BASE_BRANCH")" "$(rev "$REPO" "$BASE_BRANCH")" "the base and origin did not move"
git -C "$WT" checkout -q -- b.txt

OUT="$(cd "$WT" && bash "$SCRIPT" feat 2>&1)"; RC=$?
assert_eq 1 "$RC" "refuses from inside the worktree it would remove"
assert_contains "$OUT" "leave" "says to leave it"
[ -d "$WT" ] && pass "the worktree stays" || fail "the worktree stays" "$WT"

echo "== the base moved =="
fresh moved; branch feat b.txt two
OLD="$(rev "$REPO" feat)"
base_commit c.txt three
land feat
assert_eq 3 "$RC" "exit 3: rebased, tests come first"
assert_contains "$OUT" "re-run" "says to re-run the tests"
[ "$(rev "$REPO" feat)" != "$OLD" ] && pass "the branch is rebased" || fail "the branch is rebased" "$OLD"
git -C "$REPO" merge-base --is-ancestor "$BASE_BRANCH" feat && pass "the branch now sits on the base" || fail "the branch now sits on the base" ""
assert_eq "$(rev "$ORIGIN" "$BASE_BRANCH")" "$(rev "$REPO" "$BASE_BRANCH")" "nothing was pushed for the branch"
git -C "$REPO" merge-base --is-ancestor feat "$BASE_BRANCH" && fail "the base stays without the branch" "merged" || pass "the base stays without the branch"
land feat
assert_eq 0 "$RC" "the second run lands: $OUT"
assert_eq "$(rev "$REPO" "$BASE_BRANCH")" "$(rev "$ORIGIN" "$BASE_BRANCH")" "pushed after the second run"

fresh conflict; branch feat a.txt mine
OLD="$(rev "$REPO" feat)"
base_commit a.txt theirs
land feat
assert_eq 1 "$RC" "a rebase conflict refuses"
assert_contains "$OUT" "conflict" "says conflict"
assert_eq "$OLD" "$(rev "$REPO" feat)" "the branch is back where it was"
[ -z "$(git -C "$WT" status --porcelain)" ] && pass "the rebase is aborted" || fail "the rebase is aborted" "$(git -C "$WT" status --porcelain)"

echo "== uncommitted files in the base checkout =="
fresh dirty; branch feat settings.json new-pool
printf 'pi-wrote-this\n' > "$REPO/settings.json"
land feat
assert_eq 1 "$RC" "a dirty file the branch changes refuses"
assert_contains "$OUT" "settings.json" "names the file"
assert_eq "pi-wrote-this" "$(cat "$REPO/settings.json")" "the uncommitted edit is kept"
assert_eq "$(rev "$ORIGIN" "$BASE_BRANCH")" "$(rev "$REPO" "$BASE_BRANCH")" "the base did not move"

printf 'new-pool\n' > "$REPO/settings.json"
land feat
assert_eq 0 "$RC" "a dirty file identical to the branch's lands: $OUT"
[ -z "$(git -C "$REPO" status --porcelain)" ] && pass "the checkout is clean after it" || fail "the checkout is clean after it" "$(git -C "$REPO" status --porcelain)"

fresh unrelated; branch feat b.txt two
printf 'mine\n' >> "$REPO/a.txt"
land feat
assert_eq 0 "$RC" "an unrelated dirty file does not stop it: $OUT"
assert_contains "$(git -C "$REPO" status --porcelain)" "a.txt" "that file stays dirty"

echo "== a failed push =="
fresh nopush; branch feat b.txt two
SHA="$(rev "$REPO" feat)"
git -C "$REPO" remote set-url origin "$SB/gone.git"
land feat
assert_eq 1 "$RC" "a failed push exits 1"
assert_contains "$OUT" "not pushed" "says it is not pushed"
assert_eq "$SHA" "$(rev "$REPO" "$BASE_BRANCH")" "the base holds the merge"
[ -d "$WT" ] && pass "the worktree is kept" || fail "the worktree is kept" "$WT"

echo "== install =="
fresh hint; branch feat bin/newtool tool
land feat
assert_eq 0 "$RC" "lands a new script: $OUT"
assert_contains "$OUT" "install.sh" "a new bin file says to run install.sh"

fresh nohint; branch feat b.txt two
land feat
assert_lacks "$OUT" "install.sh" "a plain change does not mention install.sh"

fresh inst
printf '#!/bin/bash\ntouch "%s/installed"\n' "$SANDBOX" > "$REPO/install.sh"; chmod +x "$REPO/install.sh"
git -C "$REPO" add . && git -C "$REPO" commit -qm 'add installer' && git -C "$REPO" push -q origin "$BASE_BRANCH"
branch feat b.txt two
land --install feat
assert_eq 0 "$RC" "--install lands: $OUT"
[ -f "$SANDBOX/installed" ] && pass "--install runs install.sh" || fail "--install runs install.sh" "$OUT"

fresh instfail
printf '#!/bin/bash\nexit 7\n' > "$REPO/install.sh"; chmod +x "$REPO/install.sh"
git -C "$REPO" add . && git -C "$REPO" commit -qm 'add installer' && git -C "$REPO" push -q origin "$BASE_BRANCH"
branch feat b.txt two
land --install feat
assert_eq 1 "$RC" "a failed install exits 1"
assert_contains "$OUT" "install.sh failed" "says the installer failed"
assert_eq "$(rev "$REPO" "$BASE_BRANCH")" "$(rev "$ORIGIN" "$BASE_BRANCH")" "the landing itself stands"

echo "== a base branch that is not main =="
# This host's dotfiles clone lives on ubuntu, so the base is the checked-out branch.
fresh onubuntu ubuntu; branch feat b.txt two
SHA="$(rev "$REPO" feat)"
land feat
assert_eq 0 "$RC" "lands onto ubuntu: $OUT"
assert_eq "$SHA" "$(rev "$REPO" ubuntu)" "ubuntu is at the branch's commit"
assert_eq "$SHA" "$(rev "$ORIGIN" ubuntu)" "origin/ubuntu is pushed"
assert_lacks "$OUT" "main" "never mentions main"
git -C "$REPO" show-ref --verify --quiet refs/heads/main && fail "no main branch is created" "main exists" || pass "no main branch is created"

fresh ubuntumoved ubuntu; branch feat b.txt two
base_commit c.txt three
land feat
assert_eq 3 "$RC" "exit 3 when ubuntu moved"
assert_contains "$OUT" "ubuntu moved" "names ubuntu as the base that moved"
land feat
assert_eq 0 "$RC" "the second run lands onto ubuntu: $OUT"
assert_eq "$(rev "$REPO" ubuntu)" "$(rev "$ORIGIN" ubuntu)" "origin/ubuntu is pushed"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
