#!/bin/bash
# Tests for bin/pi-autoupdate and the zsh `pi` function. pi is a stub (PI_BIN, and first on PATH
# for the zsh check) that logs its calls, so nothing is installed or updated.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/pi-autoupdate"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export SANDBOX LOG="$SANDBOX/pi.log" PI_AUTOUPDATE_STATE="$SANDBOX/state"
mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/pi" <<'STUB'
#!/bin/bash
echo "pi $* | stdin=$([ -t 0 ] && echo tty || echo closed)" >>"$LOG"
[ "$1" != update ] && exit 0
[ ! -f "$SANDBOX/slow" ] || sleep 30
[ ! -f "$SANDBOX/fail" ] || { echo "npm ERR! network unreachable"; exit 1; }
echo "Updated packages"; echo "pi is already up to date (v1.4.0)"
STUB
chmod +x "$SANDBOX/bin/pi"
export PI_BIN="$SANDBOX/bin/pi"
run() { : >"$LOG"; ERR="$("$SCRIPT" "$@" 2>&1 >/dev/null)"; RC=$?; }
calls() { grep -c 'update --all' "$LOG" 2>/dev/null || true; }

echo "pi-autoupdate"
run; assert_eq "0|1" "$RC|$(calls)" "an interactive start runs pi update --all"
assert_has "stdin=closed" "$(cat "$LOG")" "with stdin closed"
assert_has "pi: pi and its extensions are up to date" "$ERR" "and says so"
run --model openai/x --models "openai/*"; assert_eq "0" "$(calls)" "within 10 min of the last update: no second wait"
rm -rf "$PI_AUTOUPDATE_STATE"
run --model openai/x; assert_eq "1" "$(calls)" "an alias's flags still update"

echo "pi-autoupdate — not an interactive session"
for args in "update --all" "install npm:x" "list" "config" "-p hello" "--print hi" "--help" "-v" "--mode rpc"; do
  rm -rf "$PI_AUTOUPDATE_STATE"
  # shellcheck disable=SC2086
  run $args; assert_eq "0|0" "$RC|$(calls)" "pi $args: no update"
done

echo "pi-autoupdate — failures never stop pi"
rm -rf "$PI_AUTOUPDATE_STATE"; touch "$SANDBOX/fail"
run; assert_eq "0" "$RC" "a failed update exits 0"
assert_has "update failed (npm ERR! network unreachable), starting anyway" "$ERR" "with its last line"
run; assert_eq "1" "$(calls)" "a failed update is tried again next start"
rm -f "$SANDBOX/fail"; rm -rf "$PI_AUTOUPDATE_STATE"; touch "$SANDBOX/slow"
START=$(date +%s); ERR="$(PI_UPDATE_TIMEOUT=1 "$SCRIPT" 2>&1 >/dev/null)"; RC=$?
assert_eq "0" "$RC" "a slow update exits 0"
[ $(($(date +%s) - START)) -lt 8 ] && pass "after the timeout" || fail "timeout" "took $(($(date +%s) - START))s"
assert_has "timed out after 1s, starting anyway" "$ERR" "and says so"
rm -f "$SANDBOX/slow"

echo "zsh pi function"
if command -v zsh >/dev/null; then
  mkdir -p "$SANDBOX/zbin"; ln -sf "$SCRIPT" "$SANDBOX/zbin/pi-autoupdate"; ln -sf "$SANDBOX/bin/pi" "$SANDBOX/zbin/pi"
  rm -rf "$PI_AUTOUPDATE_STATE"; : >"$LOG"
  fn="$(sed -n '/^pi() {/,/^}/p' "$TEST_DIR/../zsh/.zshrc")"
  PATH="$SANDBOX/zbin:$PATH" PI_BIN="$SANDBOX/zbin/pi" zsh -fc "$fn; pi --model x hello" 2>/dev/null
  assert_eq "pi update --all|pi --model x hello" "$(cut -d'|' -f1 "$LOG" | sed 's/ $//' | paste -sd '|' -)" "the function updates, then starts pi with the same arguments"
  : >"$LOG"; PATH="$SANDBOX/bin:$PATH" zsh -fc "$fn; pi --model y" 2>/dev/null
  assert_eq "pi --model y" "$(cut -d'|' -f1 "$LOG" | sed 's/ $//')" "without pi-autoupdate installed, pi still starts"
  : >"$LOG"; PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX" zsh -fc "$fn; pi --team -c 'a b'" 2>/dev/null
  assert_eq "pi --skill $SANDBOX/.pi/agent/skills-team -c a b" "$(cut -d'|' -f1 "$LOG" | sed 's/ $//')" "--team loads the team skills; other arguments pass through"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
