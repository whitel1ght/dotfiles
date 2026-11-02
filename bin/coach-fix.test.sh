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
trap 'stop_stubs; rm -rf "${SANDBOX:?}"' EXIT
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

# stub harness (as claude and as pi): logs its arguments; with $SANDBOX/job.sh it runs that as
# the job and exits, else it stays up like a job at work until end_job stops it
mkdir -p "$SANDBOX/hbin"
cat >"$COACH_HARNESS" <<EOF
#!/bin/bash
echo \$\$ >>"$SANDBOX/pids"
printf '%s\n' "\$*" >>"$SANDBOX/harness.log"
f="\$(sed -E 's#^/(daily:)?fix-friction (F-[0-9]+) --auto\$#\\2#' <<<"\${@: -1}")"
if [ -f "$SANDBOX/job.sh" ]; then bash "$SANDBOX/job.sh" "\$f"; else sleep 600; fi
EOF
chmod +x "$COACH_HARNESS"
cp "$COACH_HARNESS" "$SANDBOX/hbin/pi"

cf() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
qget() { jq -r "if .$2 == null then \"\" else .$2 | tostring end" "$Q/$1.json" 2>/dev/null; }
fld() { grep -m1 "^$2:" "$FRICTION_WIKI/$1.md" | sed "s/^$2: *//"; }
ncalls() { [ -f "$COACH_STATE_DIR/logs/jobs.log" ] && wc -l <"$COACH_STATE_DIR/logs/jobs.log" | tr -d ' ' || echo 0; }
yes_now() { "$FRICTION_LEDGER" coach-answer "$1" yes --date "$TODAY" >/dev/null; } # the user's yes in /start-day
wait_job() { # id: until its process has exited (10 s at most)
  local p i=0; p="$(qget "$1" pid)"; [ -n "$p" ] || return 0
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}
end_job() { local p; p="$(qget "$1" pid)"; [ -z "$p" ] || kill -TERM -- "-$p" 2>/dev/null || true; wait_job "$1"; }
stop_stubs() { local s; [ ! -f "$SANDBOX/pids" ] || while read -r s; do kill -TERM -- "-$s" "$s" 2>/dev/null; done <"$SANDBOX/pids"; rm -f "$SANDBOX/pids"; }

mkentry() { # id signature safety [status] [proposal]
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
offered_on: 2026-10-20
---

# $1

## Evidence
- 2026-10-20 (3×): sample — /p/a.jsonl:1

## Diagnosis

## Proposal
${5:-Do the thing.}

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
  stop_stubs
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
  git -C "$w" add -A
  # The repository's ignore rules exclude .claude/*; this safety-path fixture
  # intentionally tests a committed settings.local.json change.
  if [ -f "$w/.claude/settings.local.json" ]; then git -C "$w" add -f -- .claude/settings.local.json; fi
  git -C "$w" commit -qm "fix: $f"
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

cf enqueue F-004 --approved-safety >/dev/null; RC=$?
assert_eq "3" "$RC" "a secret entry is refused with exit 3"
assert_has "secret entries are user steps" "$(cat "$SANDBOX/stderr")" "the refusal says secret entries are user steps"
assert_eq "offered|no" "$(fld F-004 status)|$([ -e "$Q/F-004.json" ] && echo yes || echo no)" "nothing is written for a secret entry"
assert_eq "0" "$(ncalls)" "no job for a secret entry"

cf enqueue F-001 >/dev/null; RC=$?
assert_eq "0" "$RC" "enqueue exits 0"
assert_eq "running" "$(qget F-001 state)" "enqueue starts the job at once"
assert_eq "landing" "$(fld F-001 status)" "enqueue sets the ledger to landing"
assert_eq "false" "$(qget F-001 approved_safety)" "approved_safety recorded"
assert_eq "null" "$(jq -c .repo "$Q/F-001.json")" "repo is null until built"
assert_eq "1" "$(ncalls)" "one job started"
assert_eq "" "$(cat "$FAKE_TMUX_DIR/log" 2>/dev/null)" "no tmux window"
P="$(qget F-001 pid)"
assert_eq "yes" "$([ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo yes || echo no)" "its pid is recorded and running"
assert_has ": $COACH_HARNESS -p --permission-prompts none '/daily:fix-friction F-001 --auto'" "$(cat "$COACH_STATE_DIR/logs/jobs.log")" "claude runs headless with the namespaced plugin command, prompts denied"
for a in --print --dangerously-skip-permissions --permission-mode --allow-dangerously-skip-permissions; do
  assert_lacks " $a" "$(cat "$COACH_STATE_DIR/logs/jobs.log")" "no permission flag $a"
done
assert_eq "$(cd "$COACH_REPOS_DIR" && pwd -P)" "$(lsof -a -p "$P" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" "it runs in the projects dir"
assert_eq "$P" "$(ps -o pgid= -p "$P" | tr -d ' ')" "in its own process group"

OUT="$(cf enqueue F-001)"; RC=$?
assert_eq "0" "$RC" "enqueue of a queued entry exits 0"
assert_eq "1" "$(ncalls)" "enqueue of a queued entry starts nothing"
assert_has "already" "$OUT" "it says the entry is already queued"

yes_now F-003
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
end_job F-001
cf run >/dev/null
assert_eq "failed|job ended without a result (log: $COACH_STATE_DIR/logs/F-001.job.log)" "$(qget F-001 state)|$(qget F-001 reason)" "a running entry whose process is gone fails, naming its log"
assert_has "job ended without a result" "$(fld F-001 status)|$(fld F-001 reason)" "the ledger says the job ended"
assert_eq "running" "$(qget F-002 state)" "and the next job starts"

setup
cf enqueue F-001 >/dev/null
end_job F-001
sleep 300 & SL=$!
jq --arg p "$SL" '.pid = ($p | tonumber)' "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
cf run >/dev/null
kill "$SL" 2>/dev/null
assert_eq "failed" "$(qget F-001 state)" "a reused pid running something else is not the job"

echo "run: a job from before headless jobs is checked by its window"
setup
mkdir -p "$Q"; "$FRICTION_LEDGER" set F-001 --status landing >/dev/null
jq -n '{id: "F-001", state: "running", queued_at: "2026-01-01T00:00:00Z", started_epoch: 1}' >"$Q/F-001.json"
echo coach-F-001 >"$FAKE_TMUX_DIR/windows"
COACH_JOB_MAX=999999999999 cf run >/dev/null
assert_eq "running|0" "$(qget F-001 state)|$(ncalls)" "its window is open: still running, nothing new starts"
: >"$FAKE_TMUX_DIR/windows"
cf run >/dev/null
assert_eq "failed" "$(qget F-001 state)" "its window gone: it ended without a result"

setup
cf enqueue F-001 >/dev/null
jq -n '{id: "F-003", repo: null, approved_safety: false, queued_at: "2026-01-01T00:00:00Z", state: "queued"}' >"$Q/F-003.json"
end_job F-001; cf fail F-001 --reason x >/dev/null
assert_eq "held|needs the user: safety entry queued without approval" "$(qget F-003 state)|$(qget F-003 reason)" "run re-checks the ledger's safety flag"
assert_eq "proposed|true|needs the user: safety entry queued without approval" "$(fld F-003 status)|$(fld F-003 safety)|$(fld F-003 reason)" "the ledger puts it back to proposed, a safety item for the user"
assert_eq "1" "$(ncalls)" "no job for it"

setup
touch "$FAKE_TMUX_DIR/noserver"
cf enqueue F-001 >/dev/null; RC=$?
assert_eq "0|running|1" "$RC|$(qget F-001 state)|$(ncalls)" "no tmux server: the job starts all the same"

setup
COACH_HARNESS="$COACH_HARNESS --dangerously-skip-permissions" cf enqueue F-001 >/dev/null
assert_eq "failed" "$(qget F-001 state)" "a harness command with a permission flag is never started"
assert_eq "0" "$(ncalls)" "nothing started"

echo "run: end to end with the stub harness"
setup
cat >"$SANDBOX/job.sh" <<EOF
f="\$1"; r="$DOT"; w="$WT/dotfiles/coach-\$f"
git -C "\$r" branch "coach-\$f" main && git -C "\$r" worktree add -q "\$w" "coach-\$f"
echo "\$f" >"\$w/\$f.txt"; git -C "\$w" add -A && git -C "\$w" commit -qm "fix: \$f"
"$SCRIPT" built "\$f" --repo dotfiles --branch "coach-\$f" --worktree "\$w" --test-cmd "bash tests/ok.sh"
EOF
cf enqueue F-001 >/dev/null
wait_job F-001
assert_eq "-p --permission-prompts none /daily:fix-friction F-001 --auto" "$(cat "$SANDBOX/harness.log")" "the harness gets the auto prompt, headless"
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
yes_now F-001
cf enqueue F-001 --approved-safety >/dev/null
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
yes_now F-001
cf enqueue F-001 --approved-safety >/dev/null
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
assert_has ": $SANDBOX/hbin/pi -p '/fix-friction F-001 --auto'" "$(cat "$COACH_STATE_DIR/logs/jobs.log")" "pi gets the bare prompt command, headless"
setup
COACH_PROMPT_CMD=/my:fix cf enqueue F-001 >/dev/null
assert_has ": $COACH_HARNESS -p --permission-prompts none '/my:fix F-001 --auto'" "$(cat "$COACH_STATE_DIR/logs/jobs.log")" "COACH_PROMPT_CMD overrides it"
setup
COACH_PROMPT_CMD="/x'; rm -rf ~; '" cf enqueue F-001 >/dev/null
assert_eq "failed|0" "$(qget F-001 state)|$(ncalls)" "a COACH_PROMPT_CMD that is not a plain command is never run"

echo "run: stalled job"
setup
cf enqueue F-001 >/dev/null
cf enqueue F-002 >/dev/null
jq '.started_epoch = 1000' "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
P="$(qget F-001 pid)"
cf run >/dev/null
assert_eq "failed|job stalled: still running after 6 h, stopped (log: $COACH_STATE_DIR/logs/F-001.job.log)" "$(qget F-001 state)|$(qget F-001 reason)" "a job running past COACH_JOB_MAX fails as stalled"
assert_eq "failed" "$(fld F-001 status)" "the ledger says so"
wait_job F-001
assert_eq "no" "$(kill -0 "$P" 2>/dev/null && echo yes || echo no)" "its process is stopped"
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
yes_now F-003
cf enqueue F-003 --approved-safety >/dev/null
end_job F-003
jq '.state = "queued"' "$Q/F-003.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-003.json"
cf land >/dev/null
assert_eq "running" "$(qget F-003 state)" "land starts the next queued job"

# --- safety: re-checked at enqueue, run and land; the approval is the user's recorded yes ----
echo "safety: enqueue re-checks the proposal"
setup
mkentry F-006 "claude:repeat:docker builds" false offered "Loosen the docker guard for builds"
cf enqueue F-006 >/dev/null; RC=$?
assert_eq "3|no" "$RC|$([ -e "$Q/F-006.json" ] && echo yes || echo no)" "an entry stored safety: false whose proposal loosens a guard is refused"
assert_eq "true|offered" "$(fld F-006 safety)|$(fld F-006 status)" "the ledger now says safety: true, status untouched"
mkentry F-007 "claude:repeat:perm" "" offered "Add Bash(rg:*) to the settings.json allowlist"
cf enqueue F-007 >/dev/null; RC=$?
assert_eq "3" "$RC" "an entry with no safety field is judged by its proposal"

echo "safety: --approved-safety needs today's recorded yes"
setup
cf enqueue F-003 --approved-safety >/dev/null; RC=$?
assert_eq "3|no" "$RC|$([ -e "$Q/F-003.json" ] && echo yes || echo no)" "no recorded yes: --approved-safety is refused"
assert_has "yes recorded today" "$(cat "$SANDBOX/stderr")" "the refusal names the missing yes"
"$FRICTION_LEDGER" coach-answer F-003 yes --date 2026-10-01 >/dev/null
cf enqueue F-003 --approved-safety >/dev/null; RC=$?
assert_eq "3" "$RC" "a yes from another day is refused"
mkentry F-005 "settings:permissions:deny" true offered
"$FRICTION_LEDGER" coach-answer F-005 no --date "$TODAY" >/dev/null
cf enqueue F-005 --approved-safety >/dev/null; RC=$?
assert_eq "1|no" "$RC|$([ -e "$Q/F-005.json" ] && echo yes || echo no)" "a no today is refused (declined)"
mkentry F-008 "settings:permissions:x" true offered
yes_now F-008
cf enqueue F-008 --approved-safety >/dev/null; RC=$?
assert_eq "0|running|true" "$RC|$(qget F-008 state)|$(qget F-008 approved_safety)" "today's yes: queued with the approval"

echo "safety: run re-checks the proposal"
setup
cf enqueue F-001 >/dev/null
mkentry F-006 "claude:repeat:hooks" false landing "Drop the PreToolUse hook"
jq -n '{id: "F-006", repo: null, approved_safety: false, queued_at: "2026-01-01T00:00:00Z", state: "queued"}' >"$Q/F-006.json"
end_job F-001; cf fail F-001 --reason x >/dev/null
assert_eq "held|needs the user: safety entry queued without approval" "$(qget F-006 state)|$(qget F-006 reason)" "run applies the rule, not only the stored flag"
assert_eq "true|proposed" "$(fld F-006 safety)|$(fld F-006 status)" "and writes safety: true back"

echo "safety: a busy ledger leaves the job queued"
setup
mkdir -p "$Q"
jq -n '{id: "F-001", repo: null, approved_safety: false, queued_at: "2026-01-01T00:00:00Z", state: "queued"}' >"$Q/F-001.json"
sleep 30 & HOLDER=$!
mkdir "$FRICTION_WIKI/.lock"; echo "$HOLDER" >"$FRICTION_WIKI/.lock/pid"
OUT="$(FRICTION_LOCK_WAIT=1 cf run)"; RC=$?
assert_eq "0|queued|0" "$RC|$(qget F-001 state)|$(ncalls)" "run leaves a harmless job queued while the ledger is busy"
assert_eq "1" "$(grep -c . <<<"$OUT")" "and prints one line"
assert_has "busy" "$OUT" "that says the ledger is busy"
assert_eq "offered|" "$(fld F-001 status)|$(fld F-001 reason)" "the ledger is untouched"
FRICTION_LOCK_WAIT=1 cf enqueue F-002 >/dev/null; RC=$?
assert_eq "1|no|offered" "$RC|$([ -e "$Q/F-002.json" ] && echo yes || echo no)|$(fld F-002 status)" "enqueue with a busy ledger queues nothing"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; rm -rf "$FRICTION_WIKI/.lock"
cf run >/dev/null
assert_eq "running|1" "$(qget F-001 state)|$(ncalls)" "the next run starts it"

echo "land: a safety path needs an approved safety suggestion"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 bin/secrets-guard "loosened" pi/settings.json "{}" notes.txt "x"
built dotfiles F-001 >/dev/null
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "held|needs the user: touches a safety control: bin/secrets-guard, pi/settings.json; needs an approved safety suggestion" "$(qget F-001 state)|$(qget F-001 reason)" "a guard and a settings file are refused without approval"
assert_eq "proposed|true" "$(fld F-001 status)|$(fld F-001 safety)" "the ledger puts it back to proposed as a safety item"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"
for p in .githooks/commit-msg claude/settings.json pi/extensions/claude-hooks/index.ts claude/daily/hooks/guard.sh \
  claude/daily/mod/guard.ts pi/extensions/secrets-guard/index.ts bin/docs-check bin/docker-guard install.sh \
  claude/vendor/x/hooks/hooks.json hooks.json claude/daily/.claude-plugin/plugin.json claude/.claude-plugin/marketplace.json \
  claude/CLAUDE.md pi/AGENTS.md bin/secret bin/secrets bin/secrets-sync pi/extensions/mcp-env/index.ts \
  bin/coach-fix bin/friction-ledger bin/wiki-commit bin/pi-parity \
  claude/commands/start-day.md pi/prompts/start-day.md claude/daily/commands/fix-friction.md pi/prompts/fix-friction.md \
  claude/commands/end-day.md pi/prompts/end-day.md .gitattributes .gitmodules git/.gitconfig \
  .claude/commands/x.md .claude/agents/a.md .claude/settings.local.json pi/mcp-servers.json .mcp.json claude/daily/.mcp.json \
  pi/APPEND_SYSTEM.md pi/extensions/herdr-agent-state.ts pi/extensions/daily/index.ts; do
  setup
  cf enqueue F-001 >/dev/null
  if [ "$p" = install.sh ]; then branch dotfiles F-001 install.sh "$(cat "$DOT/install.sh")
# a comment
"; else branch dotfiles F-001 "$p" "x"; fi
  built dotfiles F-001 >/dev/null
  BEFORE="$(snap dotfiles)"
  cf land >/dev/null
  assert_eq "held|needs the user: touches a safety control: $p; needs an approved safety suggestion" "$(qget F-001 state)|$(qget F-001 reason)" "safety path $p"
  [ "$BEFORE" = "$(snap dotfiles)" ] || fail "main untouched for $p" "main changed"
done

echo "land: allowed-tools and hooksPath changes need an approved safety suggestion"
# setup, then a commit on main adding FILE with CONTENT, then the branch rewriting it
md_case() { # file main-content branch-content
  setup
  mkdir -p "$(dirname "$DOT/$1")"; printf '%s' "$2" >"$DOT/$1"
  git -C "$DOT" add -A && git -C "$DOT" commit -qm "add $1"
  cf enqueue F-001 >/dev/null
  branch dotfiles F-001 "$1" "$3"
  built dotfiles F-001 >/dev/null
  cf land >/dev/null
}
FM=$'---\ndescription: x\nallowed-tools: Bash(git:*)\n---\nbody\n'
md_case claude/commands/foo.md $'---\ndescription: x\n---\nbody\n' "$FM"
assert_eq "held|needs the user: touches a safety control: claude/commands/foo.md; needs an approved safety suggestion" "$(qget F-001 state)|$(qget F-001 reason)" "a command that gains allowed-tools is held"
md_case pi/prompts/foo.md "$FM" "${FM/Bash(git:*)/Bash(*)}"
assert_eq "held" "$(qget F-001 state)" "a widened allowed-tools line in pi/ is held"
md_case claude/daily/skills/s/SKILL.md "$FM" $'---\ndescription: x\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a removed allowed-tools line is held"
md_case claude/commands/list.md $'---\nallowed-tools:\n  - Bash(git:*)\n---\nbody\n' $'---\nallowed-tools:\n  - Bash(*)\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a changed allowed-tools list item is held"
md_case claude/commands/foo.md "$FM" "${FM/body/new body}"
assert_eq "landed" "$(qget F-001 state)" "a body edit in a command with allowed-tools lands"
md_case docs/notes.md "x" $'allowed-tools: Bash(*)\n'
assert_eq "landed" "$(qget F-001 state)" "an allowed-tools line outside claude/ and pi/ is not a command"
md_case zsh/git.zsh "alias g=git" $'alias g=git\ngit config core.hooksPath /dev/null\n'
assert_eq "held|needs the user: touches a safety control: zsh/git.zsh; needs an approved safety suggestion" "$(qget F-001 state)|$(qget F-001 reason)" "a file that sets core.hooksPath is held"
PLAIN=$'---\ndescription: x\n---\nbody\n'
md_case claude/commands/h.md "$PLAIN" $'---\ndescription: x\nhooks:\n  PreToolUse: []\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a command that gains a hooks: key is held"
md_case pi/prompts/h.md $'---\nhooks:\n  - a\n---\nbody\n' $'---\nhooks:\n  - b\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a changed hooks list item is held"
md_case claude/daily/agents/a.md "$PLAIN" $'---\ndescription: x\npermissionMode: bypassPermissions\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "an agent that gains permissionMode is held"
md_case pi/prompts/p.md $'---\npermissionMode: default\n---\nbody\n' $'---\npermissionMode: acceptEdits\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a changed permissionMode is held"
md_case pi/agents/r.md $'---\nname: r\ntools: read, grep\n---\nbody\n' $'---\nname: r\ntools: read, grep, bash\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a pi agent's widened tools: line is held"
md_case pi/agents/s.md $'---\nname: s\ntools:\n  - read\n---\nbody\n' $'---\nname: s\ntools:\n  - read\n  - bash\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a pi agent's tools list gaining an item is held"
md_case claude/commands/t.md "$PLAIN" $'---\ndescription: x\ntools: anything\n---\nbody\n'
assert_eq "landed" "$(qget F-001 state)" "a tools: key outside pi/agents is not a tool list"
md_case claude/commands/q.md "$PLAIN" $'---\ndescription: x\n"allowed-tools": Bash(*)\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a quoted allowed-tools key is held"
md_case pi/prompts/q.md "$PLAIN" $'---\ndescription: x\n\'hooks\': {}\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a quoted hooks key is held"
md_case claude/commands/q2.md "$PLAIN" $'---\ndescription: x\n"permissionMode": "bypassPermissions"\n---\nbody\n'
assert_eq "held" "$(qget F-001 state)" "a quoted permissionMode key is held"
md_case zsh/git.zsh "alias g=git" $'alias g=git\nalias gc="git commit --no-verify"\n'
assert_eq "held|needs the user: touches a safety control: zsh/git.zsh; needs an approved safety suggestion" "$(qget F-001 state)|$(qget F-001 reason)" "an added --no-verify line is held"
md_case zsh/git.zsh $'alias g=git\nalias gc="git commit --no-verify"\n' "alias g=git"
assert_eq "landed" "$(qget F-001 state)" "removing a --no-verify line lands"

echo "land: a held safety change comes back, and an approved yes lands the kept branch"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 bin/secrets-guard "loosened"
built dotfiles F-001 >/dev/null
H="$(git -C "$DOT" rev-parse coach-F-001)"
BEFORE="$(snap dotfiles)"
cf land >/dev/null
assert_eq "held|$H" "$(qget F-001 state)|$(git -C "$DOT" rev-parse coach-F-001)" "held, branch kept"
assert_eq "yes" "$([ -d "$WT/dotfiles/coach-F-001" ] && echo yes || echo no)" "its worktree kept"
assert_eq "proposed|true|||" "$(fld F-001 status)|$(fld F-001 safety)|$(fld F-001 offered_on)|$(fld F-001 answer)|$(fld F-001 answered_on)" "the ledger: proposed, safety, offer and answer cleared"
assert_has "needs the user: touches a safety control" "$(fld F-001 reason)" "the ledger reason needs the user"
assert_eq "$BEFORE" "$(snap dotfiles)" "main checkout byte-identical"
cf retry F-001 >/dev/null; RC=$?
assert_eq "1|held" "$RC|$(qget F-001 state)" "a held entry is not retried by hand"
cf enqueue F-001 --approved-safety >/dev/null; RC=$?
assert_eq "3|held" "$RC|$(qget F-001 state)" "the old yes does not approve it"
OFFER="$("$FRICTION_LEDGER" coach-offer --date "$TODAY" --limit 10)"
assert_eq "true" "$(jq -r '.offer[] | select(.id == "F-001") | .safety' <<<"$OFFER")" "it is offered again as a safety item"
yes_now F-001
cf enqueue F-001 >/dev/null; RC=$?
assert_eq "3|held" "$RC|$(qget F-001 state)" "a yes without --approved-safety is refused"
N0="$(ncalls)"
cf enqueue F-001 --approved-safety >/dev/null; RC=$?
assert_eq "0|built|true|landing|$N0" "$RC|$(qget F-001 state)|$(qget F-001 approved_safety)|$(fld F-001 status)|$(ncalls)" "the approved yes takes the kept branch back to built, no new job"
cf land >/dev/null
assert_eq "landed|loosened" "$(qget F-001 state)|$(cat "$DOT/bin/secrets-guard")" "and the next land lands it"

setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 bin/secrets-guard "loosened"
built dotfiles F-001 >/dev/null
cf land >/dev/null
printf 'more\n' >"$WT/dotfiles/coach-F-001/more.txt"
git -C "$WT/dotfiles/coach-F-001" add -A && git -C "$WT/dotfiles/coach-F-001" commit -qm "after the hold"
"$FRICTION_LEDGER" coach-offer --date "$TODAY" --limit 10 >/dev/null; yes_now F-001
N0="$(ncalls)"
cf enqueue F-001 --approved-safety >/dev/null
assert_eq "running|$((N0 + 1))|" "$(qget F-001 state)|$(ncalls)|$(git -C "$DOT" branch --list coach-F-001)" "a kept branch that moved is removed and a fresh job starts"

echo "held: a lost ledger write never lets the old yes approve it"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 bin/secrets-guard "loosened"
built dotfiles F-001 >/dev/null
jq '.state = "held" | .reason = "needs the user: touches a safety control: bin/secrets-guard; needs an approved safety suggestion"' \
  "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
"$FRICTION_LEDGER" set F-001 --status offered >/dev/null; yes_now F-001
assert_eq "landing|false" "$(fld F-001 status)|$(fld F-001 safety)" "the hold never reached the ledger; a yes today"
cf enqueue F-001 --approved-safety >/dev/null; RC=$?
assert_eq "3|held" "$RC|$(qget F-001 state)" "enqueue --approved-safety of a held entry needs safety: true in the ledger"
assert_has "safety: true" "$(cat "$SANDBOX/stderr")" "the refusal says why"

echo "held: mark_held retries a failed ledger write once"
setup
cat >"$SANDBOX/flaky-ledger" <<EOF
#!/bin/bash
if [ "\$1" = set ] && [[ " \$* " == *" --safety true "* ]] && [ ! -e "$SANDBOX/flaky.once" ]; then
  touch "$SANDBOX/flaky.once"; echo "friction-ledger: ledger busy" >&2; exit 1
fi
exec "$TEST_DIR/friction-ledger" "\$@"
EOF
chmod +x "$SANDBOX/flaky-ledger"; rm -f "$SANDBOX/flaky.once"
yes_now F-001 # answered today, so reconcile leaves a lost hold alone: only the retry can write it
cf enqueue F-001 >/dev/null
branch dotfiles F-001 bin/secrets-guard "loosened"
built dotfiles F-001 >/dev/null
FRICTION_LEDGER="$SANDBOX/flaky-ledger" cf land >/dev/null
assert_eq "yes|held|proposed|true" "$([ -e "$SANDBOX/flaky.once" ] && echo yes || echo no)|$(qget F-001 state)|$(fld F-001 status)|$(fld F-001 safety)" "the first write failed, the retry wrote the hold"
setup
yes_now F-003
cf enqueue F-003 --approved-safety >/dev/null
branch dotfiles F-003 bin/secrets-guard "changed as approved"
built dotfiles F-003 >/dev/null
cf land >/dev/null
assert_eq "landed|changed as approved" "$(qget F-003 state)|$(cat "$DOT/bin/secrets-guard")" "an approved safety suggestion lands its guard change"

# --- retry -------------------------------------------------------------------------
echo "retry: a built branch goes back to built"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null
printf 'my edit\n' >>"$DOT/notes.txt"
cf land >/dev/null
assert_eq "failed" "$(qget F-001 state)" "a land blocked by an edit fails"
git -C "$DOT" checkout -q notes.txt
OUT="$(cf retry F-001)"; RC=$?
assert_eq "0|built|landing" "$RC|$(qget F-001 state)|$(fld F-001 status)" "retry: back to built, ledger landing"
assert_has "back to built" "$OUT" "it says so"
assert_eq "" "$(fld F-001 reason)" "the old reason is cleared"
cf land >/dev/null
assert_eq "landed|four" "$(qget F-001 state)|$(tail -1 "$DOT/notes.txt")" "and the next land lands it"

echo "retry: a built branch behind main is rebased first"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt $'one\ntwo\nthree\nfour\n'
built dotfiles F-001 >/dev/null
on_main dotfiles README.md "readme 2" "docs: readme"
jq '.state = "failed" | .reason = "rebase onto main hit a conflict"' "$Q/F-001.json" >"$SANDBOX/q.tmp" && mv "$SANDBOX/q.tmp" "$Q/F-001.json"
OUT="$(cf retry F-001)"; RC=$?
R="$(git -C "$DOT" rev-parse coach-F-001)"
assert_eq "0|built|$R|" "$RC|$(qget F-001 state)|$(qget F-001 rebased_head)|$(qget F-001 tested)" "rebased onto main, back to built, the new head untested"
assert_eq "yes" "$(git -C "$DOT" merge-base --is-ancestor main coach-F-001 && echo yes || echo no)" "the branch sits on top of main"
: >"$SUITE_LOG"
cf land >/dev/null
assert_eq "landed|readme 2|four" "$(qget F-001 state)|$(cat "$DOT/README.md")|$(tail -1 "$DOT/notes.txt")" "the next land tests and lands it"
assert_eq "ran $WT/dotfiles/coach-F-001" "$(cat "$SUITE_LOG" 2>/dev/null)" "the suite ran on the rebased head"

echo "retry: a branch that no longer rebases is built again"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "branch side"
built dotfiles F-001 >/dev/null
on_main dotfiles notes.txt "main side" "chore: notes"
cf land >/dev/null
assert_eq "failed" "$(qget F-001 state)" "the land hit the conflict"
N0="$(ncalls)"
OUT="$(cf retry F-001)"; RC=$?
assert_eq "0|running|$((N0 + 1))" "$RC|$(qget F-001 state)|$(ncalls)" "a fresh job starts instead of a land that would fail again"
assert_has "no longer rebases" "$OUT" "it says why"
assert_eq "no|" "$([ -d "$WT/dotfiles/coach-F-001" ] && echo yes || echo no)|$(qget F-001 head)" "the old branch and worktree are gone, its fields cleared"
assert_eq "main side" "$(cat "$DOT/notes.txt")" "main is untouched"

echo "retry: no built branch, leftovers removed, queued again"
setup
cf enqueue F-001 >/dev/null
branch dotfiles F-001 notes.txt "half done"
git -C "$COACH_REPOS_DIR/decisions" branch coach-F-002 main
git -C "$DOT" branch coach-F-0010 main
end_job F-001; cf fail F-001 --reason "tests stayed red" >/dev/null
N0="$(ncalls)"
OUT="$(cf retry F-001)"; RC=$?
assert_eq "0" "$RC" "retry exits 0"
assert_eq "no|" "$([ -d "$WT/dotfiles/coach-F-001" ] && echo yes || echo no)|$(git -C "$DOT" branch --list coach-F-001)" "the leftover worktree and branch are removed"
assert_eq "coach-F-0010|coach-F-002" "$(git -C "$DOT" branch --list coach-F-0010 | tr -d ' *')|$(git -C "$COACH_REPOS_DIR/decisions" branch --list coach-F-002 | tr -d ' *')" "other coach branches are kept"
assert_eq "running|landing|$((N0 + 1))" "$(qget F-001 state)|$(fld F-001 status)|$(ncalls)" "queued again and started"
assert_eq "||" "$(qget F-001 repo)|$(qget F-001 head)|$(qget F-001 reason)" "the old attempt's fields are cleared"

echo "retry: refusals"
setup
cf enqueue F-001 >/dev/null
cf retry F-001 >/dev/null; RC=$?
assert_eq "1|running" "$RC|$(qget F-001 state)" "a running entry is not retried"
cf retry F-002 >/dev/null; RC=$?
assert_eq "1" "$RC" "an entry never queued is not retried"
end_job F-001; cf fail F-001 --reason "needs the user: rotate it" >/dev/null
cf retry F-001 >/dev/null; RC=$?
assert_eq "1|failed" "$RC|$(qget F-001 state)" "a failure that needs the user is not retried"
jq -n '{id: "F-003", repo: null, approved_safety: false, queued_at: "2026-01-01T00:00:00Z", state: "failed", reason: "x"}' >"$Q/F-003.json"
cf retry F-003 >/dev/null; RC=$?
assert_eq "3|failed" "$RC|$(qget F-003 state)" "an unapproved safety entry is not retried"

# --- reconcile -----------------------------------------------------------------------
echo "run and land reconcile the ledger with the queue"
setup
for i in 001 002; do "$FRICTION_LEDGER" set F-$i --status landing >/dev/null; done
mkdir -p "$Q"
jq -n '{id: "F-001", state: "landed", fix: "a1..b2", reason: "user step: run ./install.sh", queued_at: "2026-01-01T00:00:00Z"}' >"$Q/F-001.json"
jq -n '{id: "F-002", state: "failed", reason: "tests failed", queued_at: "2026-01-01T00:00:00Z"}' >"$Q/F-002.json"
cf run >/dev/null
assert_eq "landed|a1..b2|user step: run ./install.sh" "$(fld F-001 status)|$(fld F-001 fix)|$(fld F-001 reason)" "a landed queue entry sets the ledger landed with its range and note"
assert_eq "failed|tests failed" "$(fld F-002 status)|$(fld F-002 reason)" "a failed queue entry sets the ledger failed with its reason"
"$FRICTION_LEDGER" set F-002 --status landing >/dev/null
cf land --force-check >/dev/null
assert_eq "failed" "$(fld F-002 status)" "land reconciles too"
"$FRICTION_LEDGER" set F-001 --status declined >/dev/null
cf run >/dev/null
assert_eq "declined" "$(fld F-001 status)" "a ledger status other than landing is left alone"
setup
mkdir -p "$Q"
for i in 001 002; do
  jq -n --arg i "F-$i" '{id: $i, state: "held", reason: "needs the user: touches a safety control: bin/x", queued_at: "2026-01-01T00:00:00Z"}' >"$Q/F-$i.json"
done
"$FRICTION_LEDGER" coach-answer F-001 yes --date 2026-10-01 >/dev/null
yes_now F-002
cf run >/dev/null
assert_eq "proposed|true|needs the user: touches a safety control: bin/x" "$(fld F-001 status)|$(fld F-001 safety)|$(fld F-001 reason)" "a held entry whose hold never reached the ledger is put back to proposed"
assert_eq "landing" "$(fld F-002 status)" "a held entry answered yes today is left for its enqueue"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
