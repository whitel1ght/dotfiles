#!/bin/bash
# Tests for bin/day-plan. tmux and nvim are PATH stubs that write their argv to a
# log; DIARY_DIR points into a sandbox, so no popup opens and ~/wiki is not read.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/day-plan"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
BIN="$SANDBOX/bin"; DIARY="$SANDBOX/diary"; LOG="$SANDBOX/tmux.log"
mkdir -p "$BIN" "$DIARY"
cat > "$BIN/tmux" <<'STUB'
#!/bin/bash
{ echo "--- tmux"; printf '%s\n' "$@"; } >> "$TMUX_LOG"
STUB
chmod +x "$BIN/tmux"

[ "$(PATH="$BIN:$PATH" command -v tmux)" = "$BIN/tmux" ] || { echo "refusing to run: the tmux stub is not first on PATH"; exit 1; }
TODAY=$(date +%F)
printf '# %s\n\n<!-- start-day:start -->\n- [ ] ecfx-1 x\n<!-- start-day:end -->\n' "$TODAY" > "$DIARY/$TODAY.md"

run() { : > "$LOG"; (PATH="$BIN:$PATH" TMUX_LOG="$LOG" DIARY_DIR="$DIARY" TMUX=/tmp/tmux-1/default,1,0 TMUX_PANE= "$SCRIPT" "$@" 2>"$SANDBOX/stderr"); }
errs() { cat "$SANDBOX/stderr"; }
log() { sed 's/^/|/' "$LOG" | tr '\n' ' '; }

echo "day-plan — popup (--wait)"
run --wait; rc=$?
assert_eq "0" "$rc" "exit 0"
L=$(log)
assert_contains "$L" "|--- tmux |display-popup |-E |-w |85% |-h |85% |-b |rounded " "display-popup, closes on exit, 85% x 85%, rounded border"
assert_contains "$L" "|-T | plan · $(date '+%a %F')  |" "title carries weekday and date"
assert_contains "$L" "|nvim " "runs nvim"
assert_contains "$L" "|+/\\V<!-- start-day:start --> |-c |normal! zt " "searches for the plan block then zt"
assert_contains "$L" "|-c |set autoread |-c |autocmd FocusGained,BufEnter,CursorHold * checktime " "autoread and checktime"
assert_contains "$L" "|-- |$DIARY/$TODAY.md " "opens today's diary from DIARY_DIR"
assert_eq "no" "$(grep -q '^run-shell$' "$LOG" && echo yes || echo no)" "does not go through run-shell"

echo "day-plan — non-blocking"
run; rc=$?
assert_eq "0" "$rc" "exit 0"
L=$(log)
assert_contains "$L" "|--- tmux |run-shell |-b " "default path is tmux run-shell -b"
assert_eq "no" "$(grep -q '^display-popup$' "$LOG" && echo yes || echo no)" "and does not open the popup itself"
assert_contains "$L" "DIARY_DIR=$DIARY" "the background job keeps DIARY_DIR"
assert_contains "$L" "--wait" "and re-enters with --wait"
(PATH="$BIN:$PATH" TMUX_LOG="$LOG" DIARY_DIR="$DIARY" TMUX=x TMUX_PANE=%7 "$SCRIPT" >/dev/null 2>&1)
assert_contains "$(log)" "|-b |-t |%7 " "targets the calling pane when TMUX_PANE is set"

echo "day-plan — plan block and file"
printf '# today\nno block\n' > "$DIARY/$TODAY.md"
run --wait; rc=$?
assert_eq "0" "$rc" "a diary without the block still opens"
L=$(log)
assert_eq "no" "$([[ "$L" == *'+/'* ]] && echo yes || echo no)" "and without a search argument"
assert_contains "$L" "|-- |$DIARY/$TODAY.md " "on the file"
rm -f "$DIARY/$TODAY.md"
run --wait; rc=$?
assert_eq "1" "$rc" "a missing diary exits 1"
assert_contains "$(errs)" "day-plan: no diary at $DIARY/$TODAY.md" "and says where it looked"
assert_eq "" "$(cat "$LOG")" "without calling tmux"
run; assert_eq "1" "$?" "the non-blocking path reports a missing diary too, before launching"

echo "day-plan — environment and arguments"
: > "$LOG"; (PATH="$BIN:$PATH" TMUX_LOG="$LOG" DIARY_DIR="$DIARY" TMUX= "$SCRIPT" 2>"$SANDBOX/stderr"); rc=$?
assert_eq "2" "$rc" "outside tmux exits 2"
assert_eq "day-plan: needs tmux" "$(errs)" "with a one-line message"
assert_eq "" "$(cat "$LOG")" "and does not call tmux"
run --bogus; assert_eq "1" "$?" "an unknown option is an error"
assert_contains "$("$SCRIPT" -h)" "day-plan [--wait]" "-h prints the usage"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
