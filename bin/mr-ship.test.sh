#!/bin/bash
# Tests for bin/mr-ship. glab is a stub on PATH: `api user` and `mr view` answer
# from MR_STATE / MR_AUTHOR, every other call is appended to a log.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/mr-ship"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; LOG="$SANDBOX/glab.log"
mkdir -p "$STUBS"
cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
case "$1 $2" in
    "api user") echo '{"username":"whitel1ght"}' ;;
    "mr view") printf '{"state":"%s","draft":true,"author":{"username":"%s"}}\n' "${MR_STATE:-opened}" "${MR_AUTHOR:-whitel1ght}" ;;
    *) printf '%s\n' "$*" >> "$MR_LOG" ;;
esac
STUB
chmod +x "$STUBS/glab"
export MR_LOG="$LOG"
ship() { : > "$LOG"; PATH="$STUBS:$PATH" "$SCRIPT" "$@" 2>"$SANDBOX/err"; }
EXPECT="mr update 7 -R ecfx/ecfx-dashboard --ready --assignee +whitel1ght --reviewer +adam.warbington,+bkeeling,+smtsuchi,+ejjung,+levisiebensecfx"

echo "mr-ship"
ship ecfx/ecfx-dashboard 7; assert_eq 0 "$?" "an open draft of the user's: exits 0"
assert_eq "$EXPECT" "$(cat "$LOG")" "marks ready, assigns the user, requests the D-008 reviewers"
ship ecfx/ecfx-dashboard 7
call="$(cat "$LOG")"
for n in adam.warbington bkeeling smtsuchi ejjung levisiebensecfx; do
    case ",${call##*--reviewer }," in *",+$n,"*) pass "reviewer $n is added with +" ;; *) fail "reviewer $n is added with +" "$call" ;; esac
done
case "$call" in *"--assignee +whitel1ght "*) pass "the assignee is added with +" ;; *) fail "the assignee is added with +" "$call" ;; esac
ship dashboard 7; assert_eq "$EXPECT" "$(cat "$LOG")" "a short name maps to ecfx/ecfx-<name>"
ship ecfx-dashboard 7; assert_eq "$EXPECT" "$(cat "$LOG")" "so does ecfx-<name>"
for s in merged closed; do
    MR_STATE=$s ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "a $s MR is refused"
    assert_eq 0 "$(wc -c < "$LOG" | tr -d ' ')" "and no update call is made"
done
MR_AUTHOR=someone.else ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "another author's MR is refused"
assert_eq 0 "$(wc -c < "$LOG" | tr -d ' ')" "and no update call is made"
grep -q someone.else "$SANDBOX/err" && pass "and the refusal names the author" || fail "and the refusal names the author" "$(cat "$SANDBOX/err")"
out="$(ship ecfx/ecfx-dashboard 7 -n)"; assert_eq 0 "$?" "-n exits 0"
assert_eq 0 "$(wc -c < "$LOG" | tr -d ' ')" "-n makes no update call"
case "$out" in *"--ready"*"--assignee +whitel1ght"*"--reviewer +adam.warbington,"*) pass "-n prints the calls" ;; *) fail "-n prints the calls" "$out" ;; esac
MR_STATE=merged ship ecfx/ecfx-dashboard 7 -n; assert_eq 1 "$?" "-n still refuses a merged MR"
ship ecfx/ecfx-dashboard; assert_eq 2 "$?" "a missing MR number is a usage error"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
