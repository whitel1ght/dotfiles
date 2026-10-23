#!/bin/bash
# Tests for bin/coach-fix. Everything lives in a sandbox: HOME, the repos (plain local git
# repos, no remote), the friction wiki, the state dirs, a fake tmux on PATH and a stub
# harness. No real harness, tmux server or repo is ever touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/coach-fix"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }
assert_lacks() { case "$2" in *"$1"*) fail "$3" "[$1] unexpectedly in [$2]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export HOME="$SANDBOX/home"
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name "Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export FRICTION_WIKI="$SANDBOX/friction"
export FRICTION_LEDGER="$TEST_DIR/friction-ledger"
export COACH_STATE_DIR="$SANDBOX/state/coach"
export COACH_REPOS_DIR="$SANDBOX/projects"
export RUN_DAY_STATE="$SANDBOX/state/run-day"
export DIARY_DIR="$SANDBOX/diary"
export COACH_HARNESS="$SANDBOX/hbin/claude"
export SUITE_LOG="$SANDBOX/suite.log"
export FAKE_TMUX_DIR="$SANDBOX/tmux"
export COACH_STALE_GRACE=0
export PATH="$SANDBOX/fakebin:$PATH"
WT="$SANDBOX/worktrees"
Q="$COACH_STATE_DIR/queue"
TODAY="$(date +%F)"
DOT="$COACH_REPOS_DIR/dotfiles"

mkdir -p "$SANDBOX/fakebin"
cat >"$SANDBOX/fakebin/tmux" <<'EOF'
#!/bin/bash
# fake tmux: a server exists unless $FAKE_TMUX_DIR/noserver; windows are lines in windows;
# new-window is logged and, with $FAKE_TMUX_DIR/run, runs its command synchronously.
d="$FAKE_TMUX_DIR"; mkdir -p "$d"
[ ! -e "$d/noserver" ] || { echo "no server running on /tmp/fake" >&2; exit 1; }
case "$1" in
  list-sessions) echo "main: 1 windows" ;;
  list-windows) cat "$d/windows" 2>/dev/null ;;
  new-window)
    printf '%s\n' "$*" >>"$d/log"; shift
    name="" dir=""
    while [ $# -gt 0 ]; do
      case "$1" in -d) ;; -n) name="$2"; shift ;; -c) dir="$2"; shift ;; *) break ;; esac
      shift
    done
    echo "$name" >>"$d/windows"
    printf '%s\n' "$*" >>"$d/cmds"
    if [ -e "$d/run" ]; then (cd "$dir" && bash -c "$*"); fi ;;
  *) echo "fake tmux: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SANDBOX/fakebin/tmux"

# stub harness (as claude and as pi): logs its argument; with $SANDBOX/job.sh it runs that as the job
mkdir -p "$SANDBOX/hbin"
cat >"$COACH_HARNESS" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$SANDBOX/harness.log"
f="\$(sed -E 's#^/(daily:)?fix-friction (F-[0-9]+) --auto\$#\\2#' <<<"\$1")"
[ ! -f "$SANDBOX/job.sh" ] || bash "$SANDBOX/job.sh" "\$f"
EOF
chmod +x "$COACH_HARNESS"
cp "$COACH_HARNESS" "$SANDBOX/hbin/pi"

cf() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
qget() { jq -r "if .$2 == null then \"\" else .$2 | tostring end" "$Q/$1.json" 2>/dev/null; }
fld() { grep -m1 "^$2:" "$FRICTION_WIKI/$1.md" | sed "s/^$2: *//"; }
ncalls() { [ -f "$FAKE_TMUX_DIR/log" ] && wc -l <"$FAKE_TMUX_DIR/log" | tr -d ' ' || echo 0; }
close_window() { grep -vx "coach-$1" "$FAKE_TMUX_DIR/windows" >"$SANDBOX/w.tmp" || true; mv "$SANDBOX/w.tmp" "$FAKE_TMUX_DIR/windows"; }

mkentry() { # id signature safety [status]
  cat >"$FRICTION_WIKI/$1.md" <<EOT
---
id: $1
signature: "$2"
class: script
status: ${4:-landing}
first: 2026-10-01
last: 2026-10-20
days: 2
fix:
rung: script
safety: $3
---

# $1

## Evidence
- 2026-10-20 (3×): sample — /p/a.jsonl:1

## Diagnosis

## Proposal
Do the thing.

## History
- 2026-10-01: opened
EOT
}

mkrepo() { # name
  local r="$COACH_REPOS_DIR/$1"
  mkdir -p "$r/bin"
  git -C "$r" init -q
  printf 'readme\n' >"$r/README.md"
  printf 'one\ntwo\nthree\n' >"$r/notes.txt"
  printf '#!/bin/bash\necho old\n' >"$r/bin/old"
  mkdir -p "$r/tests"
  printf 'echo "ran $(pwd -P)" >>"$SUITE_LOG"\n' >"$r/tests/ok.sh"
  printf 'exit 1\n' >"$r/tests/red.sh"
  printf 'sleep 8 &\necho $! >"$SUITE_LOG.child"\nwait\n' >"$r/tests/slow.sh"
  printf 'echo sneaky >sneaky.txt\ngit add sneaky.txt && git commit -qm sneaky\n' >"$r/tests/sneak.sh"
  printf 'sleep 2\necho "ran slow" >>"$SUITE_LOG"\n' >"$r/tests/slow2.sh"
  printf '*.local\n' >"$r/.gitignore"
  cat >"$r/install.sh" <<'EOF'
#!/bin/bash
create_symlink() { ln -s "$1" "$2"; }

# old prints old.
if [ -f "$DOTFILES_DIR/bin/old" ]; then
    create_symlink "$DOTFILES_DIR/bin/old" "$HOME/.local/bin/old"
fi
EOF
  git -C "$r" add -A && git -C "$r" commit -qm "init"
}

setup() {
  rm -rf "$FRICTION_WIKI" "$SANDBOX/state" "$COACH_REPOS_DIR" "$WT" "$DIARY_DIR" "$FAKE_TMUX_DIR" "$HOME" \
    "$SANDBOX/job.sh" "$SANDBOX/harness.log" "$SUITE_LOG"
  mkdir -p "$FRICTION_WIKI" "$COACH_REPOS_DIR" "$WT" "$DIARY_DIR" "$FAKE_TMUX_DIR" "$HOME/.local/bin" "$RUN_DAY_STATE"
  mkentry F-001 "claude:tool_error:jq missing" false offered
  mkentry F-002 "claude:repeat:run the tests" false offered
  mkentry F-003 "settings:permissions:allow rules" true offered
  mkentry F-004 "files:secret:glpat:/p/x" true offered
  mkrepo dotfiles
  mkrepo decisions
  mkrepo other
}

# branch REPO F: branch coach-F from main in a worktree, commit FILE=CONTENT pairs on it
branch() {
  local repo="$1" f="$2" r="$COACH_REPOS_DIR/$1" w="$WT/$1/coach-$2"; shift 2
  git -C "$r" branch "coach-$f" main && git -C "$r" worktree add -q "$w" "coach-$f"
  while [ $# -gt 0 ]; do
    mkdir -p "$(dirname "$w/$1")"; printf '%s' "$2" >"$w/$1"; shift 2
  done
  git -C "$w" add -A && git -C "$w" commit -qm "fix: $f"
}
built() { # repo F [test-cmd]
  cf built "$2" --repo "$1" --branch "coach-$2" --worktree "$WT/$1/coach-$2" --test-cmd "${3:-bash tests/ok.sh}"
}
on_main() { # repo file content message: a commit straight on main
  printf '%s' "$3" >"$COACH_REPOS_DIR/$1/$2"; git -C "$COACH_REPOS_DIR/$1" add -A && git -C "$COACH_REPOS_DIR/$1" commit -qm "$4"
}
snap() { # repo: HEAD, branch, status, every file's bytes
  local r="$COACH_REPOS_DIR/$1"
  { git -C "$r" rev-parse HEAD; git -C "$r" symbolic-ref -q HEAD; git -C "$r" status --porcelain=v1 --untracked-files=all
    (cd "$r" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum); } | cksum
}
STALE_ARGS='-p --print --dangerously-skip-permissions --permission-mode --allow-dangerously-skip-permissions'

echo "help"
OUT="$("$SCRIPT" --help 2>&1)"
assert_has "--force-check" "$OUT" "help names --force-check"
assert_has "window" "$OUT" "help says what --force-check skips"

# --- enqueue ---------------------------------------------------------------------
echo "enqueue"
setup
cf enqueue F-003; RC=$?
assert_eq "3" "$RC" "a safety entry without --approved-safety exits 3"
assert_has "safety" "$(cat "$SANDBOX/stderr")" "the refusal says why"
assert_eq "no" "$([ -e "$Q/F-003.json" ] && echo yes || echo no)" "no queue file for a refused safety entry"
assert_eq "offered" "$(fld F-003 status)" "the ledger is untouched on refusal"
assert_eq "0" "$(ncalls)" "no job started on refusal"

OUT="$(cf enqueue F-004 --approved-safety)"; RC=$?
assert_eq "0" "$RC" "a secret entry exits 0"
assert_has "needs the user: follow the proposal's steps" "$OUT" "a secret entry says it needs the user"
assert_eq "failed" "$(fld F-004 status)" "a secret entry goes failed in the ledger"
assert_eq "needs the user: follow the proposal's steps" "$(fld F-004 reason)" "the ledger keeps the reason"
assert_eq "0" "$(ncalls)" "no job for a secret entry"

cf enqueue F-001 >/dev/null; RC=$?
assert_eq "0" "$RC" "enqueue exits 0"
assert_eq "running" "$(qget F-001 state)" "enqueue starts the job at once"
assert_eq "landing" "$(fld F-001 status)" "enqueue sets the ledger to landing"
assert_eq "false" "$(qget F-001 approved_safety)" "approved_safety recorded"
assert_eq "null" "$(jq -c .repo "$Q/F-001.json")" "repo is null until built"
assert_eq "1" "$(ncalls)" "one tmux window started"
LOG="$(cat "$FAKE_TMUX_DIR/log")"
assert_has "new-window -d -n coach-F-001 -c $COACH_REPOS_DIR" "$LOG" "detached window coach-F-001 in the projects dir"
assert_eq "$COACH_HARNESS '/daily:fix-friction F-001 --auto'" "$(cat "$FAKE_TMUX_DIR/cmds")" "claude gets the namespaced plugin command"
for a in $STALE_ARGS; do assert_lacks " $a" "$(cat "$FAKE_TMUX_DIR/cmds")" "no permission flag $a"; done

OUT="$(cf enqueue F-001)"; RC=$?
assert_eq "0" "$RC" "enqueue of a queued entry exits 0"
assert_eq "1" "$(ncalls)" "enqueue of a queued entry starts nothing"
assert_has "already" "$OUT" "it says the entry is already queued"

cf enqueue F-003 --approved-safety >/dev/null
assert_eq "queued" "$(qget F-003 state)" "a second job waits while one runs"
assert_eq "true" "$(qget F-003 approved_safety)" "the approval is recorded"
assert_eq "1" "$(ncalls)" "only one job at a time"
cf run >/dev/null
assert_eq "1" "$(ncalls)" "run starts nothing while a job runs"

echo "built and fail"
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null; RC=$?
assert_eq "0" "$RC" "built exits 0"
assert_eq "built" "$(qget F-001 state)" "built marks the queue entry"
assert_eq "coach-F-001|$WT/dotfiles/coach-F-001|dotfiles|bash tests/ok.sh" "$(qget F-001 branch)|$(qget F-001 worktree)|$(qget F-001 repo)|$(qget F-001 test_cmd)" "built records branch, worktree, repo, test command"
H="$(git -C "$DOT" rev-parse coach-F-001)"
assert_eq "$H|$H" "$(qget F-001 head)|$(qget F-001 tested)" "built records the reviewed head as tested"
assert_eq "landing" "$(fld F-001 status)" "built leaves the ledger at landing"
assert_eq "running" "$(qget F-003 state)" "built starts the next queued job"
assert_eq "2" "$(ncalls)" "two windows in all"

cf fail F-003 --reason "tests stayed red" >/dev/null; RC=$?
assert_eq "0" "$RC" "fail exits 0"
assert_eq "failed|tests stayed red" "$(qget F-003 state)|$(qget F-003 reason)" "fail marks the queue entry with the reason"
assert_eq "failed|tests stayed red" "$(fld F-003 status)|$(fld F-003 reason)" "fail sets the ledger failed with the reason"

echo "enqueue: answered no"
setup
"$FRICTION_LEDGER" set F-002 --status declined >/dev/null
cf enqueue F-002 >/dev/null; RC=$?
assert_eq "1|no" "$RC|$([ -e "$Q/F-002.json" ] && echo yes || echo no)" "a declined entry is never queued"

echo "built: repos"
setup
cf enqueue F-001 >/dev/null
git -C "$DOT" branch side main
git -C "$DOT" worktree add -q "$WT/dotfiles/side" side
printf 'x\n' >"$WT/dotfiles/side/a"; git -C "$WT/dotfiles/side" add -A; git -C "$WT/dotfiles/side" commit -qm x
cf built F-001 --repo dotfiles --branch side --worktree "$WT/dotfiles/side" --test-cmd true >/dev/null
assert_eq "failed|branch must be coach-F-001, got side" "$(qget F-001 state)|$(qget F-001 reason)" "only the entry's own coach branch is accepted"
cf enqueue F-002 >/dev/null
cf built F-002 --repo dotfiles --branch coach-F-002 --worktree "$DOT" --test-cmd true >/dev/null
assert_eq "failed" "$(qget F-002 state)" "the main checkout is not a worktree to land from"
setup
cf enqueue F-001 >/dev/null
branch other F-001 notes.txt "x"
cf built F-001 --repo other --branch coach-F-001 --worktree "$WT/other/coach-F-001" --test-cmd true >/dev/null
assert_eq "failed|repo not allowed: other" "$(qget F-001 state)|$(qget F-001 reason)" "a repo outside the list fails"
assert_eq "failed|repo not allowed: other" "$(fld F-001 status)|$(fld F-001 reason)" "and the ledger says so"
cf enqueue F-002 >/dev/null
cf built F-002 --repo claude-components --branch coach-F-002 --worktree "$WT/x" --test-cmd true >/dev/null
assert_eq "failed|repo not allowed: claude-components" "$(qget F-002 state)|$(qget F-002 reason)" "claude-components only as an MR"

# --- run ---------------------------------------------------------------------------
echo "run: stale, safety, tmux"
setup
cf enqueue F-001 >/dev/null
cf enqueue F-002 >/dev/null
close_window F-001
cf run >/dev/null
assert_eq "failed|job ended without a result" "$(qget F-001 state)|$(qget F-001 reason)" "a running entry without its window fails"
assert_eq "failed|job ended without a result" "$(fld F-001 status)|$(fld F-001 reason)" "the ledger says the job ended"
assert_eq "running" "$(qget F-002 state)" "and the next job starts"

setup
cf enqueue F-001 >/dev/null
jq -n '{id: "F-003", repo: null, approved_safety: false, queued_at: "2026-01-01T00:00:00Z", state: "queued"}' >"$Q/F-003.json"
close_window F-001; cf fail F-001 --reason x >/dev/null
assert_eq "failed|safety entry queued without approval" "$(qget F-003 state)|$(qget F-003 reason)" "run re-checks the ledger's safety flag"
assert_eq "failed" "$(fld F-003 status)" "the ledger marks it failed"
assert_eq "1" "$(ncalls)" "no job for it"

setup
touch "$FAKE_TMUX_DIR/noserver"
cf enqueue F-001 >/dev/null; RC=$?
assert_eq "0" "$RC" "enqueue without tmux still exits 0"
assert_eq "failed|needs tmux" "$(qget F-001 state)|$(qget F-001 reason)" "no tmux server: the job fails"
assert_eq "failed" "$(fld F-001 status)" "the ledger marks it failed"

setup
COACH_HARNESS="$COACH_HARNESS --dangerously-skip-permissions" cf enqueue F-001 >/dev/null
assert_eq "failed" "$(qget F-001 state)" "a harness command with a permission flag is never started"
assert_eq "0" "$(ncalls)" "nothing reached tmux"

echo "run: end to end with the stub harness"
setup
touch "$FAKE_TMUX_DIR/run"
cat >"$SANDBOX/job.sh" <<EOF
f="\$1"; r="$DOT"; w="$WT/dotfiles/coach-\$f"
git -C "\$r" branch "coach-\$f" main && git -C "\$r" worktree add -q "\$w" "coach-\$f"
echo "\$f" >"\$w/\$f.txt"; git -C "\$w" add -A && git -C "\$w" commit -qm "fix: \$f"
"$SCRIPT" built "\$f" --repo dotfiles --branch "coach-\$f" --worktree "\$w" --test-cmd "bash tests/ok.sh"
EOF
cf enqueue F-001 >/dev/null
assert_eq "/daily:fix-friction F-001 --auto" "$(cat "$SANDBOX/harness.log")" "the harness gets the auto prompt"
assert_eq "built" "$(qget F-001 state)" "the stub job built the branch"
cf land --force-check >/dev/null
assert_eq "landed" "$(qget F-001 state)" "the stub job's branch lands"
assert_eq "F-001" "$(cat "$DOT/F-001.txt")" "its change is in main"

# --- land: window ------------------------------------------------------------------
echo "land: window"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null
touch "$RUN_DAY_STATE/$TODAY.md"
printf '# day\n\n### ECFX\n' >"$DIARY_DIR/$TODAY.md"
BEFORE="$(snap dotfiles)"
OUT="$(cf land)"; RC=$?
assert_eq "0" "$RC" "land in a running day exits 0"
assert_eq "a day session is running; landing waits" "$OUT" "it says landing waits"
assert_eq "built" "$(qget F-001 state)" "nothing lands"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout untouched"
printf '<!-- daily-report:start -->\nreport\n<!-- daily-report:end -->\n' >>"$DIARY_DIR/$TODAY.md"
cf land >/dev/null
assert_eq "landed" "$(qget F-001 state)" "once the report is saved, land goes ahead"

setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
touch "$RUN_DAY_STATE/$TODAY.md"
cf land --force-check >/dev/null
assert_eq "landed" "$(qget F-001 state)" "--force-check skips the window check"

# --- land: fast-forward and install ------------------------------------------------
echo "land: fast-forward"
setup
cf enqueue F-001 >/dev/null
OLD="$(git -C "$DOT" rev-parse --short main)"
branch dotfiles F-001 bin/x $'#!/bin/bash\necho x\n' install.sh "$(cat "$DOT/install.sh")
if [ -f \"\$DOTFILES_DIR/bin/x\" ]; then
    create_symlink \"\$DOTFILES_DIR/bin/x\" \"\$HOME/.local/bin/x\"
fi
" bin/y $'#!/bin/bash\n'
NEW="$(git -C "$DOT" rev-parse --short coach-F-001)"
built dotfiles F-001 >/dev/null
cf land >/dev/null; RC=$?
assert_eq "0" "$RC" "land exits 0"
assert_eq "$NEW" "$(git -C "$DOT" rev-parse --short main)" "main fast-forwarded to the branch"
assert_eq "main" "$(git -C "$DOT" symbolic-ref --short HEAD)" "main checkout still on main"
assert_eq "$DOT/bin/x" "$(readlink "$HOME/.local/bin/x")" "the new linked bin/x is linked into ~/.local/bin"
assert_eq "no" "$([ -e "$HOME/.local/bin/y" ] || [ -L "$HOME/.local/bin/y" ] && echo yes || echo no)" "a new bin file install.sh does not link is not linked"
assert_eq "landed|$OLD..$NEW" "$(fld F-001 status)|$(fld F-001 fix)" "the ledger has landed with the range"
assert_eq "" "$(fld F-001 reason)" "no user step for a link-only install.sh change"
assert_eq "landed|$OLD..$NEW" "$(qget F-001 state)|$(qget F-001 fix)" "the queue entry is landed"
assert_eq "no" "$([ -d "$WT/dotfiles/coach-F-001" ] && echo yes || echo no)" "the worktree is removed"
assert_eq "" "$(git -C "$DOT" branch --list coach-F-001)" "the branch is deleted"

echo "land: install.sh changed elsewhere"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 install.sh "$(cat "$DOT/install.sh")
brew install something
"
built dotfiles F-001 >/dev/null
cf land >/dev/null
assert_eq "landed" "$(fld F-001 status)" "it still lands"
assert_has "user step: run ./install.sh" "$(fld F-001 reason)" "the ledger notes the install.sh user step"

echo "land: main moved"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
OLD="$(git -C "$DOT" rev-parse --short main)"
cf land >/dev/null
assert_eq "landed" "$(qget F-001 state)" "a moved main: the branch is rebased and lands"
assert_eq "ran $WT/dotfiles/coach-F-001" "$(cat "$SUITE_LOG" 2>/dev/null)" "the recorded suite ran once, in the worktree, after the rebase"
assert_eq "readme 2|four" "$(cat "$DOT/README.md")|$(tail -1 "$DOT/notes.txt")" "main has both changes"
assert_has "$OLD.." "$(fld F-001 fix)" "the range starts at the moved main"

echo "land: rebase conflict"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "branch side"
built dotfiles F-001 >/dev/null
on_main dotfiles notes.txt "main side" "chore: notes"
BEFORE="$(snap dotfiles)"
cf land >/dev/null; RC=$?
assert_eq "0" "$RC" "a failed landing still exits 0"
assert_eq "failed" "$(qget F-001 state)" "a conflicting rebase fails"
assert_has "conflict" "$(fld F-001 reason)" "the reason names the conflict"
assert_eq "failed" "$(fld F-001 status)" "the ledger is failed"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical after a conflict"
assert_eq "no" "$(git -C "$WT/dotfiles/coach-F-001" status | grep -q 'rebase in progress' && echo yes || echo no)" "the rebase was aborted"
assert_eq "coach-F-001" "$(git -C "$WT/dotfiles/coach-F-001" symbolic-ref --short HEAD)" "the worktree is back on its branch"
assert_eq "branch side" "$(cat "$WT/dotfiles/coach-F-001/notes.txt")" "the worktree keeps the branch for a look"

echo "land: red tests after rebase"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 "bash tests/red.sh" >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "failed" "$(qget F-001 state)" "red tests after the rebase fail"
assert_has "tests failed" "$(fld F-001 reason)" "the reason names the tests"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical after red tests"

echo "land: uncommitted edits in the main checkout"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n' bin/new "new"
built dotfiles F-001 >/dev/null
printf 'my edit\n' >>"$DOT/notes.txt"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "failed" "$(qget F-001 state)" "an uncommitted edit in a touched file fails"
assert_eq "uncommitted edits in notes.txt" "$(fld F-001 reason)" "the reason names the file"
assert_eq "my edit" "$(tail -1 "$DOT/notes.txt")" "the edit is intact"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x" bin/new "new"
built dotfiles F-001 >/dev/null
printf 'mine\n' >"$DOT/bin/new"
git -C "$DOT" add bin/new 2>/dev/null; git -C "$DOT" reset -q
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "uncommitted edits in bin/new" "$(fld F-001 reason)" "an untracked file the branch adds counts"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
printf 'staged\n' >>"$DOT/README.md"; git -C "$DOT" add README.md
cf land >/dev/null
assert_eq "landed" "$(qget F-001 state)" "an edit in a file the branch does not touch does not block"
assert_eq "M  README.md" "$(git -C "$DOT" status --porcelain)" "that edit is kept as it was"

echo "land: main checkout not on main"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
git -C "$DOT" checkout -q -b side
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "failed|main checkout not on main" "$(qget F-001 state)|$(qget F-001 reason)" "a checkout on another branch fails"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

echo "land: decisions repo"
setup
cf enqueue F-001 >/dev/null
branch decisions F-001 notes.txt "x"
built decisions F-001 >/dev/null
cf land >/dev/null
assert_eq "landed|x" "$(qget F-001 state)|$(cat "$COACH_REPOS_DIR/decisions/notes.txt")" "decisions lands too"

echo "land: MR entries"
setup
cf enqueue F-002 >/dev/null
URL="https://gitlab.com/ecfx/claude-components/-/merge_requests/42"
cf built F-002 --mr "$URL" >/dev/null
assert_eq "built|claude-components|$URL" "$(qget F-002 state)|$(qget F-002 repo)|$(qget F-002 mr)" "an MR entry is built with its link"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "landed|$URL" "$(fld F-002 status)|$(fld F-002 fix)" "an MR entry lands as its link"
assert_eq "landed" "$(qget F-002 state)" "the queue entry is landed"
assert_eq "$BEFORE" "$(snap dotfiles)" "no repo is touched for an MR"

echo "run: harness prompt"
setup
COACH_HARNESS="$SANDBOX/hbin/pi" cf enqueue F-001 >/dev/null
assert_eq "$SANDBOX/hbin/pi '/fix-friction F-001 --auto'" "$(cat "$FAKE_TMUX_DIR/cmds")" "pi gets the bare prompt command"
setup
COACH_PROMPT_CMD=/my:fix cf enqueue F-001 >/dev/null
assert_eq "$COACH_HARNESS '/my:fix F-001 --auto'" "$(cat "$FAKE_TMUX_DIR/cmds")" "COACH_PROMPT_CMD overrides it"
setup
COACH_PROMPT_CMD="/x'; rm -rf ~; '" cf enqueue F-001 >/dev/null
assert_eq "failed|0" "$(qget F-001 state)|$(ncalls)" "a COACH_PROMPT_CMD that is not a plain command is never run"

echo "run: stalled job"
setup
cf enqueue F-001 >/dev/null
cf enqueue F-002 >/dev/null
jq '.started_epoch = 1000' "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
cf run >/dev/null
assert_eq "failed|job stalled in tmux window coach-F-001 (waiting on a prompt?)" "$(qget F-001 state)|$(qget F-001 reason)" "a job running past COACH_JOB_MAX fails as stalled"
assert_eq "failed" "$(fld F-001 status)" "the ledger says so"
assert_eq "yes" "$(grep -qx coach-F-001 "$FAKE_TMUX_DIR/windows" && echo yes || echo no)" "its window is left open"
assert_eq "running" "$(qget F-002 state)" "the next job starts"

echo "enqueue: the queue file cannot be written"
setup
mkdir -p "$Q" && chmod 555 "$Q"
cf enqueue F-001 >/dev/null; RC=$?
chmod 755 "$Q"
assert_eq "1|offered" "$RC|$(fld F-001 status)" "an unwritable queue exits non-zero before the ledger goes landing"
setup
mkdir -p "$SANDBOX/badjq"
printf '#!/bin/bash\n[ "$1" != -n ] || [ "$4" != F-001 ] || exit 5\nexec %q "$@"\n' "$(command -v jq)" >"$SANDBOX/badjq/jq"
chmod +x "$SANDBOX/badjq/jq"
PATH="$SANDBOX/badjq:$PATH" cf enqueue F-001 >/dev/null; RC=$?
assert_eq "1|offered|no" "$RC|$(fld F-001 status)|$([ -e "$Q/F-001.json" ] && echo yes || echo no)" "a failed queue-file write exits non-zero before the ledger goes landing"

echo "built: test command"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
printf 'x\n' >"$WT/dotfiles/coach-F-001/tests/untracked.sh"
for c in "true" "bash tests/ok.sh; rm -rf x" "bash tests/ok.sh | cat" 'bash $(echo tests/ok.sh)' "bash tests/untracked.sh" \
  "bash ../dotfiles/tests/ok.sh" "bash /bin/ls" "bash tests/ok.sh &&  bash tests/ok.sh" "bash tests/ok.sh && rm -rf x" "bash  tests/ok.sh"; do
  cf built F-001 --repo dotfiles --branch coach-F-001 --worktree "$WT/dotfiles/coach-F-001" --test-cmd "$c" >/dev/null; RC=$?
  assert_eq "2|running" "$RC|$(qget F-001 state)" "refused test command: $c"
done
built dotfiles F-001 "bash tests/ok.sh && bash tests/ok.sh" >/dev/null; RC=$?
assert_eq "0|built" "$RC|$(qget F-001 state)" "bash items joined by && are accepted"

echo "land: only the reviewed head"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
printf 'later\n' >"$WT/dotfiles/coach-F-001/later.txt"
git -C "$WT/dotfiles/coach-F-001" add -A && git -C "$WT/dotfiles/coach-F-001" commit -qm "unreviewed"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "failed|branch changed after review" "$(qget F-001 state)|$(qget F-001 reason)" "a commit after built is never landed"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

echo "land: an interrupted re-test runs again"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
git -C "$WT/dotfiles/coach-F-001" rebase -q main
R="$(git -C "$DOT" rev-parse coach-F-001)"
jq --arg r "$R" '.rebased_head = $r | .tested = null' "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
cf land >/dev/null
assert_eq "landed" "$(qget F-001 state)" "the rebased head from an earlier land is accepted"
assert_eq "ran $WT/dotfiles/coach-F-001" "$(cat "$SUITE_LOG" 2>/dev/null)" "and its tests run before it lands"

echo "land: test timeout"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 "bash tests/slow.sh" >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
BEFORE="$(snap dotfiles)"
T0="$(date +%s)"
COACH_TEST_TIMEOUT=1 cf land >/dev/null
T1="$(date +%s)"
assert_has "tests timed out" "$(qget F-001 reason)" "a suite over COACH_TEST_TIMEOUT fails"
assert_eq "yes" "$([ $((T1 - T0)) -lt 7 ] && echo yes || echo no)" "land does not wait for it"
assert_eq "no" "$(kill -0 "$(cat "$SUITE_LOG.child")" 2>/dev/null && echo yes || echo no)" "the suite's children are killed too"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

echo "land: an ignored file in the way"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
printf 'branch\n' >"$WT/dotfiles/coach-F-001/conf.local"
git -C "$WT/dotfiles/coach-F-001" add -f conf.local && git -C "$WT/dotfiles/coach-F-001" commit -qm "conf"
built dotfiles F-001 >/dev/null
printf 'mine\n' >"$DOT/conf.local"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "failed|uncommitted edits in conf.local" "$(qget F-001 state)|$(qget F-001 reason)" "an ignored local file the branch adds blocks the landing"
assert_eq "mine" "$(cat "$DOT/conf.local")" "and is not overwritten"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"

echo "land: a commit during the test run"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 "bash tests/sneak.sh" >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
MAIN_BEFORE="$(git -C "$DOT" rev-parse main)"
cf land >/dev/null
assert_eq "failed|branch changed after review" "$(qget F-001 state)|$(qget F-001 reason)" "a commit made while the tests ran is never landed"
assert_eq "$MAIN_BEFORE" "$(git -C "$DOT" rev-parse main)" "main did not move"
assert_eq "no|" "$([ -e "$DOT/sneaky.txt" ] && echo yes || echo no)|$(git -C "$DOT" status --porcelain)" "main checkout untouched"

echo "land: --detach"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 "bash tests/slow2.sh" >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
T0="$(date +%s)"
OUT="$(cf land --detach)"; RC=$?
T1="$(date +%s)"
LOGF="$COACH_STATE_DIR/logs/land-$TODAY.log"
assert_eq "0|landing in the background; log: $LOGF" "$RC|$OUT" "--detach prints the log path"
assert_eq "yes|built" "$([ $((T1 - T0)) -lt 2 ] && echo yes || echo no)|$(qget F-001 state)" "--detach returns before the 2 s suite ends"
for _ in $(seq 1 25); do [ -s "$Q/.land.lock/pid" ] && break; sleep 0.05; done
OUT2="$(cf land)"
assert_eq "a land is already running" "$OUT2" "a second land while one runs exits with a line"
OUT2="$(cf land --detach)"
assert_eq "a land is already running" "$OUT2" "so does a second --detach"
for _ in $(seq 1 100); do [ "$(qget F-001 state)" = built ] || break; sleep 0.2; done
for _ in $(seq 1 25); do [ -d "$Q/.land.lock" ] || break; sleep 0.2; done
assert_eq "landed" "$(qget F-001 state)" "the background land completes"
assert_has "F-001: landed" "$(cat "$LOGF")" "its output is in the log"
assert_eq "no" "$([ -d "$Q/.land.lock" ] && echo yes || echo no)" "and it releases the lock"

echo "land: stale lock"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
sh -c 'exit 0' & DEAD=$!; wait "$DEAD"
mkdir -p "$Q/.land.lock" && echo "$DEAD" >"$Q/.land.lock/pid"
cf land >/dev/null
assert_eq "landed" "$(qget F-001 state)" "a dead holder's land lock is taken over"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
mkdir -p "$Q/.land.lock" && echo "$$" >"$Q/.land.lock/pid"
OUT="$(cf land)"
assert_eq "a land is already running|built" "$OUT|$(qget F-001 state)" "a live holder's lock is respected"
rm -rf "$Q/.land.lock"

echo "land: then run"
setup
cf enqueue F-001 >/dev/null
cf enqueue F-002 >/dev/null
branch dotfiles F-001 notes.txt "x"
built dotfiles F-001 >/dev/null
cf fail F-002 --reason "no" >/dev/null
cf enqueue F-003 --approved-safety >/dev/null
close_window F-003
jq '.state = "queued"' "$Q/F-003.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-003.json"
cf land >/dev/null
assert_eq "running" "$(qget F-003 state)" "land starts the next queued job"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
