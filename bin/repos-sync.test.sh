#!/bin/bash
# Tests for bin/repos-sync. Every repo lives in a sandbox: "gitlab.com" remotes are bare repos the
# sandbox git config maps git@gitlab.com: to, so nothing reaches the network or ~/projects.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/repos-sync"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }
assert_lacks() { case "$2" in *"$1"*) fail "$3" "[$1] found in [$2]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
REMOTES="$SANDBOX/remotes"; P="$SANDBOX/projects"; WT="$SANDBOX/worktrees"
mkdir -p "$REMOTES" "$P" "$WT"
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global url."$REMOTES/".insteadOf git@gitlab.com:
git config --global url."$REMOTES/gh/".insteadOf git@github.com:
git config --global user.name t; git config --global user.email t@t
git config --global init.defaultBranch main
git config --global advice.detachedHead false
git config --global protocol.file.allow always

# remote NAME [host]: a bare remote with one commit on main, cloned to $P/NAME
remote() {
  local host="${2:-gitlab}" bare src
  if [ "$host" = github ]; then bare="$REMOTES/gh/ecfx/$1.git"; else bare="$REMOTES/ecfx/$1.git"; fi
  mkdir -p "$(dirname "$bare")"; git init -q --bare "$bare"
  src="$SANDBOX/src-$1"; git init -q "$src"
  echo one >"$src/f.txt"; git -C "$src" add -A; git -C "$src" commit -qm one
  git -C "$src" push -q "$bare" main
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git clone -q "git@$host.com:ecfx/$1.git" "$P/$1"
}
# upstream NAME N: N new commits on the remote's main
upstream() {
  local src="$SANDBOX/src-$1" i
  for i in $(seq 1 "$2"); do echo "up $i" >>"$src/f.txt"; git -C "$src" commit -qam "up $i"; done
  git -C "$src" push -q "$(git -C "$P/$1" remote get-url origin | sed "s#git@gitlab.com:#$REMOTES/#; s#git@github.com:#$REMOTES/gh/#")" main
}
run() { OUT="$(REPOS_DIR="$P" "$SCRIPT" 2>&1)"; RC=$?; }
head_of() { git -C "$P/$1" rev-parse "$2"; }

echo "repos-sync"
remote clean; upstream clean 2
remote dirty; upstream dirty 1; echo "mine" >>"$P/dirty/f.txt"
remote feature; git -C "$P/feature" checkout -q -b ECFX-1; upstream feature 3
remote ahead; echo local >>"$P/ahead/f.txt"; git -C "$P/ahead" commit -qam local; upstream ahead 1
remote current
remote hub github; upstream hub 1
remote gone; rm -rf "$REMOTES/ecfx/gone.git"
remote wtmain; git -C "$P/wtmain" checkout -q -b other; git -C "$P/wtmain" worktree add -q "$WT/wtmain" main; upstream wtmain 1
mkdir -p "$P/plain"; echo x >"$P/plain/notes.txt"
HUB_BEFORE="$(git -C "$P/hub" rev-parse refs/remotes/origin/main)"

run
assert_eq "0" "$RC" "exits 0 even with a failed repo"
assert_eq "$(head_of clean origin/main)" "$(head_of clean main)" "a clean checked-out main is fast-forwarded"
assert_has "clean: main fast-forwarded 2 commit(s)" "$OUT" "and says by how many"
assert_eq "mine" "$(tail -1 "$P/dirty/f.txt")" "uncommitted changes are left as they were"
assert_eq "1" "$(git -C "$P/dirty" rev-list --count main..origin/main)" "a dirty checkout's main is not moved"
assert_has "dirty: main is 1 behind origin, not moved: uncommitted changes in $P/dirty" "$OUT" "and says why"
assert_eq "$(head_of feature origin/main)" "$(head_of feature main)" "main not checked out anywhere: its ref moves"
assert_eq "ECFX-1" "$(git -C "$P/feature" branch --show-current)" "the checked-out branch stays"
assert_has "feature: main fast-forwarded 3 commit(s)" "$OUT" "and is reported"
assert_eq "1|1" "$(git -C "$P/ahead" rev-list --count main..origin/main)|$(git -C "$P/ahead" rev-list --count origin/main..main)" "local commits on main: not moved"
assert_has "ahead: main is 1 behind origin and has 1 local commit(s) not on it, not moved" "$OUT" "and says why"
assert_lacks "current:" "$OUT" "an up-to-date repo gets no line of its own"
assert_eq "$HUB_BEFORE" "$(git -C "$P/hub" rev-parse refs/remotes/origin/main)" "a GitHub repo is not fetched"
assert_lacks "hub" "$OUT" "nor reported"
assert_has "gone: fetch failed:" "$OUT" "a failed fetch is reported"
assert_eq "$(head_of wtmain origin/main)" "$(head_of wtmain main)" "main checked out in another worktree, clean: fast-forwarded there"
assert_eq "$(git -C "$P/wtmain" rev-parse main)" "$(git -C "$WT/wtmain" rev-parse HEAD)" "that worktree's files moved with it"
assert_eq "other" "$(git -C "$P/wtmain" branch --show-current)" "the main checkout's own branch stays"
assert_has "7 GitLab repos: 3 updated, 1 up to date, 2 left alone, 1 failed" "$OUT" "a summary line"

echo "repos-sync — second run"
run
assert_has "7 GitLab repos: 0 updated, 4 up to date, 2 left alone, 1 failed" "$OUT" "nothing moves twice"

echo "repos-sync — submodules"
rm -rf "${P:?}"/*
remote proto; rm -rf "$P/proto"
SD="$SANDBOX/src-dash"; mkdir -p "$REMOTES/ecfx"; git init -q --bare "$REMOTES/ecfx/dash.git"; git init -q "$SD"
git -C "$SD" submodule -q add git@gitlab.com:ecfx/proto.git sub; git -C "$SD" commit -qm "add sub"
git -C "$SD" push -q "$REMOTES/ecfx/dash.git" main; git -C "$REMOTES/ecfx/dash.git" symbolic-ref HEAD refs/heads/main
git clone -q --recurse-submodules git@gitlab.com:ecfx/dash.git "$P/dash"
bump() { # a new proto commit, recorded by dash on origin
  echo "bump $RANDOM" >>"$SANDBOX/src-proto/f.txt"; git -C "$SANDBOX/src-proto" commit -qam bump
  git -C "$SANDBOX/src-proto" push -q "$REMOTES/ecfx/proto.git" main
  git -C "$SD/sub" pull -q origin main; git -C "$SD" commit -qam "bump sub"; git -C "$SD" push -q "$REMOTES/ecfx/dash.git" main
}
sub_head() { git -C "$P/dash/sub" rev-parse HEAD; }
recorded() { git -C "$P/dash" rev-parse HEAD:sub; }

bump; run
assert_eq "$(head_of dash origin/main)" "$(head_of dash main)" "the parent is fast-forwarded"
assert_eq "$(recorded)" "$(sub_head)" "and its submodule follows to the recorded commit"
assert_has "dash: main fast-forwarded 1 commit(s), submodules updated (sub)" "$OUT" "the line names the submodule"
assert_has "1 GitLab repos: 1 updated" "$OUT" "counted as updated"

git -C "$P/dash/sub" checkout -q HEAD~1; run
assert_eq "$(recorded)" "$(sub_head)" "a submodule left behind on an up-to-date branch is brought forward"
assert_has "dash: submodules updated (sub)" "$OUT" "and reported"

bump; echo "mine" >>"$P/dash/sub/f.txt"; run
assert_eq "$(head_of dash origin/main)" "$(head_of dash main)" "a dirty submodule does not hold the parent back"
assert_eq "mine" "$(tail -1 "$P/dash/sub/f.txt")" "its changes stay"
assert_has "dash: main fast-forwarded 1 commit(s); submodule sub not updated: uncommitted changes in it" "$OUT" "and it is left alone, with the reason"
assert_has "1 left alone" "$OUT" "counted as left alone"

git -C "$P/dash/sub" checkout -q -- f.txt; echo "spike" >"$P/dash/sub/spike.txt"; git -C "$P/dash/sub" add spike.txt; git -C "$P/dash/sub" commit -qm spike
SPIKE="$(sub_head)"; run
assert_eq "$SPIKE" "$(sub_head)" "a submodule moved on purpose (not behind) stays where it is"
assert_has "dash: submodule sub not updated: it is on a commit that is not behind the recorded one" "$OUT" "and says why"

echo "repos-sync — clones one folder deeper"
# As on Ubuntu: clones grouped as ~/projects/ecfx/<repo> instead of flat.
mkdir -p "$P/ecfx"
remote deep; upstream deep 2; mv "$P/deep" "$P/ecfx/deep"
# Two clones of one project (different depths, same basename) must both report.
remote dup; upstream dup 2; mv "$P/dup" "$P/ecfx/dup"; cp -a "$P/ecfx/dup" "$P/dup"
run
assert_has "deep: main fast-forwarded 2 commit(s)" "$OUT" "a clone one folder deeper is synced"
assert_eq "$(head_of ecfx/deep origin/main)" "$(head_of ecfx/deep main)" "its default branch moved"
assert_eq "2" "$(grep -c '^- dup: main fast-forwarded 2 commit(s)$' <<<"$OUT")" \
    "two clones with the same basename each get their own line"
assert_has "GitLab repos:" "$OUT" "and the summary still ends the report"

echo "repos-sync — a projects root that itself sits in a dot directory"
# $HOME/.local/projects style. The dot-directory rule must look below the root
# only: it used to skip every repo when the root path itself had a dot.
D="$SANDBOX/.local/projects"; mkdir -p "$D/ecfx"
remote dotroot; upstream dotroot 2; mv "$P/dotroot" "$D/ecfx/dotroot"
OUT="$(REPOS_DIR="$D" "$SCRIPT" 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 with the root under a dot directory"
assert_has "dotroot: main fast-forwarded 2 commit(s)" "$OUT" "a nested clone under a dot root is synced"
assert_eq "$(git -C "$D/ecfx/dotroot" rev-parse origin/main)" "$(git -C "$D/ecfx/dotroot" rev-parse main)" \
    "and its default branch moved"
assert_lacks "no GitLab repos in" "$OUT" "it does not think the root is empty"

echo "repos-sync — MR worktrees"
rm -rf "${P:?}"/* "${WT:?}"/*; remote mrs
SM="$SANDBOX/src-mrs"; MB="$REMOTES/ecfx/mrs.git"
push_on() { # BRANCH N: N new commits on the remote's BRANCH (created from main when new)
  local i
  git -C "$SM" checkout -q "$1" 2>/dev/null || git -C "$SM" checkout -q -b "$1" main
  for i in $(seq 1 "$2"); do echo "$1 $i $RANDOM" >>"$SM/f.txt"; git -C "$SM" commit -qam "$1 $i"; done
  git -C "$SM" push -q "$MB" "$1"; git -C "$SM" checkout -q main
}
for b in ECFX-2 ECFX-3 ECFX-4 ECFX-5; do push_on "$b" 1; done
git -C "$P/mrs" fetch -q
for b in ECFX-2 ECFX-3 ECFX-4 ECFX-5; do git -C "$P/mrs" worktree add -q "$WT/$b" "$b"; done
git -C "$P/mrs" worktree add -q -b ECFX-6 "$WT/ECFX-6" main
for b in ECFX-2 ECFX-3 ECFX-4; do push_on "$b" 1; done
echo local >>"$WT/ECFX-3/f.txt"; git -C "$WT/ECFX-3" commit -qam local
echo "mine" >>"$WT/ECFX-4/f.txt"
run
assert_eq "$(git -C "$P/mrs" rev-parse origin/ECFX-2)" "$(git -C "$WT/ECFX-2" rev-parse HEAD)" "a clean MR worktree behind its remote branch is fast-forwarded"
assert_has "mrs: worktree ECFX-2 fast-forwarded 1 commit(s)" "$OUT" "and reported"
assert_eq "local" "$(git -C "$WT/ECFX-3" log -1 --format=%s)" "a diverged MR worktree is not moved"
assert_has "worktree ECFX-3 not moved: 1 behind origin and 1 local commit(s) not on it" "$OUT" "and says why"
assert_eq "mine" "$(tail -1 "$WT/ECFX-4/f.txt")" "a dirty MR worktree keeps its changes"
assert_eq "1" "$(git -C "$WT/ECFX-4" rev-list --count HEAD..@{u})" "and is not moved"
assert_has "worktree ECFX-4 not moved: 1 behind origin, uncommitted changes" "$OUT" "and says why"
assert_lacks "ECFX-5" "$OUT" "an up-to-date MR worktree gets no mention"
assert_lacks "ECFX-6" "$OUT" "nor one whose branch has no remote"
assert_has "1 GitLab repos: 0 updated, 0 up to date, 1 left alone" "$OUT" "a repo with a worktree left alone counts as left alone"

echo "repos-sync — a slow fetch"
rm -rf "$P"/*; remote slow
mkdir -p "$SANDBOX/slowbin"; printf '#!/bin/bash\nsleep 30\n' >"$SANDBOX/slowbin/ssh"; chmod +x "$SANDBOX/slowbin/ssh"
git -C "$P/slow" remote set-url origin "ssh://git@gitlab.com/ecfx/slow.git"
git config --global --unset-all url."$REMOTES/".insteadOf
START=$(date +%s)
OUT="$(REPOS_DIR="$P" REPOS_SYNC_TIMEOUT=2 GIT_SSH_COMMAND="$SANDBOX/slowbin/ssh" "$SCRIPT" 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0"
[ $(($(date +%s) - START)) -lt 10 ] && pass "it gives up after the timeout" || fail "timeout" "took $(($(date +%s) - START))s"
assert_has "slow: fetch timed out after 2s" "$OUT" "and says so"
pgrep -f "$SANDBOX/slowbin/ssh" >/dev/null && fail "no leftover" "the slow fetch still runs" || pass "the slow fetch is stopped"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
