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
    "api projects/"*)
        printf '%s\n' "$2" >> "$MR_COMMITS_LOG"
        [ -z "${MR_COMMITS_FAIL:-}" ] || exit 1
        # --paginate prints one array per page
        for c in $MR_COMMITS; do printf '[{"id":"%s"}]\n' "$c"; done
        ;;
    *) printf '%s\n' "$*" >> "$MR_LOG" ;;
esac
STUB
chmod +x "$STUBS/glab"
SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
FIX=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export MR_LOG="$LOG" MR_COMMITS_LOG="$SANDBOX/commits.log" MR_SHIP_STATE="$SANDBOX/state" MR_COMMITS="$FIX $SHA"
ship() { : > "$LOG"; PATH="$STUBS:$PATH" "$SCRIPT" "$@" 2>"$SANDBOX/err"; }
EXPECT="mr update 7 -R ecfx/ecfx-dashboard --ready --assignee +whitel1ght --reviewer +adam.warbington,+bkeeling,+smtsuchi,+ejjung,+levisiebensecfx"
REVIEW="$SANDBOX/review.md"
printf '# Local review\n\nPanel: security\nHead SHA: %s\n' "$SHA" > "$REVIEW"
errs() { grep -q "$1" "$SANDBOX/err" && pass "$2" || fail "$2" "$(cat "$SANDBOX/err")"; }
no_update() { assert_eq 0 "$(wc -c < "$LOG" | tr -d ' ')" "$1"; }

echo "the review gate"
ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "no review recorded: refused"
no_update "and no update call is made"
errs "no local review recorded for ecfx/ecfx-dashboard!7" "and it names the MR"
errs "/ship-mr" "and it points at /ship-mr"
ship ecfx/ecfx-dashboard 7 -n; assert_eq 0 "$?" "-n exits 0 with no review, /ship-mr runs it before reviewing"
errs "no local review recorded" "and -n says what a real run would refuse"
ship ecfx/ecfx-dashboard 7 --no-review; assert_eq 0 "$?" "--no-review ships without a review"
assert_eq "$EXPECT" "$(cat "$LOG")" "and makes the same update call"

ship --reviewed ecfx/ecfx-dashboard 7 "${SHA:0:12}" "$REVIEW"; assert_eq 2 "$?" "--reviewed refuses a short SHA"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA"; assert_eq 2 "$?" "--reviewed with no file is a usage error"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA" "$SANDBOX/missing.md"; assert_eq 1 "$?" "--reviewed refuses a missing file"
: > "$SANDBOX/empty.md"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA" "$SANDBOX/empty.md"; assert_eq 1 "$?" "--reviewed refuses an empty file"
printf 'Panel: security\nHead SHA: %s\n' "$FIX" > "$SANDBOX/other.md"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA" "$SANDBOX/other.md"; assert_eq 1 "$?" "--reviewed refuses a file naming another SHA"
printf 'looks fine\n%s\n' "$SHA" > "$SANDBOX/nopanel.md"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA" "$SANDBOX/nopanel.md"; assert_eq 1 "$?" "--reviewed refuses a file with no Panel line"
ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "none of those recorded a review"

: > "$MR_COMMITS_LOG"
ship --reviewed ecfx/ecfx-dashboard 7 "$SHA" "$REVIEW"; assert_eq 0 "$?" "--reviewed records a review"
no_update "and calls no GitLab write"
assert_eq 0 "$(wc -c < "$MR_COMMITS_LOG" | tr -d ' ')" "and reads nothing from GitLab"
mv "$REVIEW" "$REVIEW.keep"
ship ecfx/ecfx-dashboard 7; assert_eq 0 "$?" "it ships once the reviewed commit is in the MR, the source file gone"
assert_eq "$EXPECT" "$(cat "$LOG")" "and the update call is made"
case "$(tail -1 "$MR_COMMITS_LOG")" in
    "projects/ecfx%2Fecfx-dashboard/merge_requests/7/commits?per_page=100") pass "it reads the MR's commits" ;;
    *) fail "it reads the MR's commits" "$(cat "$MR_COMMITS_LOG")" ;;
esac
mv "$REVIEW.keep" "$REVIEW"
MR_COMMITS="$FIX" ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "a reviewed commit gone from the MR's history is refused"
no_update "and no update call is made"
errs "no longer in the MR" "and the refusal says why"
MR_COMMITS_FAIL=1 ship ecfx/ecfx-dashboard 7; assert_eq 1 "$?" "unreadable commits: refused, it fails closed"
no_update "and no update call is made"
errs "cannot read the commits" "and the refusal says why"
ship ecfx/ecfx-dashboard 8; assert_eq 1 "$?" "a review of one MR does not count for another"
ship ecfx/ecfx-admin 7; assert_eq 1 "$?" "nor for the same number in another repo"
ship --reviewed dashboard 9 "$SHA" "$REVIEW"; ship ecfx/ecfx-dashboard 9; assert_eq 0 "$?" "a short name records under the full repo"
printf 'Panel: security\nHead SHA: %s\n' "$FIX" > "$SANDBOX/second.md"
ship --reviewed ecfx/ecfx-dashboard 7 "$FIX" "$SANDBOX/second.md"
MR_COMMITS="$FIX" ship ecfx/ecfx-dashboard 7; assert_eq 0 "$?" "a new review replaces the old one"

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
