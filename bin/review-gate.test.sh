#!/bin/bash
# Tests for bin/review-gate. glab is a fake binary on PATH that answers from env vars.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/review-gate"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; mkdir -p "$STUBS"

# glab api user -> {"username":"me"} (USER_FAIL=1 fails it); glab api projects/... ->
# $APPROVALS (APPROVALS_FAIL=1 fails it); the endpoint asked for is logged.
cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
echo "$*" >> "${LOG:?}"
case "$*" in
    "api user") [ -n "${USER_FAIL:-}" ] && exit 1; echo '{"username":"me"}' ;;
    *approvals*) [ -n "${APPROVALS_FAIL:-}" ] && exit 1; echo "${APPROVALS:-{\"approved_by\":[]\}}" ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$STUBS/glab"

run() { LOG="$SANDBOX/glab.log" PATH="$STUBS:$PATH" "$SCRIPT" "$@" 2>&1; }
user() { printf '{"user":{"username":"%s"}}' "$1"; }

echo "review-gate"
export APPROVALS="{\"approved_by\":[$(user other),$(user me)]}"
out=$(run ecfx/ecfx-dashboard 2202); rc=$?
assert_eq "1" "$rc" "approved by me among others: exit 1"
assert_contains "$out" "already approved by you" "approved: says why"
assert_contains "$(cat "$SANDBOX/glab.log")" "api projects/ecfx%2Fecfx-dashboard/merge_requests/2202/approvals" "asks the url-encoded approvals endpoint"

export APPROVALS="{\"approved_by\":[$(user other)]}"
out=$(run ecfx/ecfx-dashboard 2202); rc=$?
assert_eq "0" "$rc" "approved by someone else only: exit 0"

export APPROVALS='{"approved_by":[]}'
run ecfx/ecfx-dashboard 2202 >/dev/null; assert_eq "0" "$?" "no approvals: exit 0"

APPROVALS_FAIL=1 run ecfx/ecfx-dashboard 2202 >/dev/null; assert_eq "3" "$?" "approvals lookup failure: exit 3"
USER_FAIL=1 run ecfx/ecfx-dashboard 2202 >/dev/null; assert_eq "3" "$?" "user lookup failure: exit 3"
APPROVALS='<html>502</html>' run ecfx/ecfx-dashboard 2202 >/dev/null; assert_eq "3" "$?" "unreadable reply: exit 3"
APPROVALS='{"message":"404 Not Found"}' run ecfx/ecfx-dashboard 2202 >/dev/null; assert_eq "3" "$?" "reply without approved_by: exit 3"
run ecfx/ecfx-dashboard >/dev/null; assert_eq "2" "$?" "missing iid: exit 2"
run ecfx/ecfx-dashboard abc >/dev/null; assert_eq "2" "$?" "non-numeric iid: exit 2"

# Ubuntu links bin commands from one name list (link_command "$name") instead of
# one create_symlink call per tool, so look for the name in that list.
sed -n '/^# Portable command links\./,/^done$/p' "$TEST_DIR/../install.sh" | grep -qw review-gate \
    && pass "install.sh links review-gate onto PATH" || fail "install.sh links review-gate onto PATH" "not in the linked-command list"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
