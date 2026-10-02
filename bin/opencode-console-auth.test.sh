#!/bin/bash
# Tests for bin/opencode-console-auth against a throwaway database shaped like
# OpenCode's; the real one is never read.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/opencode-console-auth"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
DB="$SANDBOX/opencode.db"

PASSES=0; FAILURES=0
pass() { echo "  ok   - $1"; PASSES=$((PASSES + 1)); }
fail() { echo "  FAIL - $1: $2"; FAILURES=$((FAILURES + 1)); }

run() { OPENCODE_DB="$DB" bash "$SCRIPT" "$@"; }

future=$(( ($(date +%s) + 3600) * 1000 ))
past=$(( ($(date +%s) - 3600) * 1000 ))
cred() { # id integration active time_updated expires access
    printf "insert into credential values ('%s','%s','x','{\"type\":\"oauth\",\"access\":\"%s\",\"refresh\":\"rt_x\",\"expires\":%s,\"metadata\":{\"orgID\":\"org_%s\"}}',null,null,%s,0,%s);\n" \
        "$1" "$2" "$6" "$5" "$1" "$3" "$4"
}

sqlite3 "$DB" "create table credential (id text primary key, integration_id text, label text not null, value text not null, connector_id text, method_id text, active integer, time_created integer not null, time_updated integer not null);"

echo "opencode-console-auth"
out="$(run token 2>&1)"; code=$?
[ "$code" = 1 ] && [[ "$out" == *"opencode auth login opencode"* ]] && pass "not signed in says how to sign in" || fail "not signed in" "exit $code: $out"

sqlite3 "$DB" "$(cred old opencode 1 1 "$future" st_old)$(cred new opencode 1 2 "$future" st_new)$(cred off opencode 0 3 "$future" st_off)$(cred mcp mcp_slack 1 4 "$future" st_mcp)"
[ "$(run token)" = st_new ] && pass "prints the newest active Console token" || fail "token" "got $(run token)"
[ "$(run org)" = org_new ] && pass "prints its workspace id" || fail "org" "got $(run org)"
[ "$(run token | wc -l | tr -d ' ')" = 0 ] && pass "no trailing newline" || fail "newline" "output has a newline"

sqlite3 "$DB" "delete from credential; $(cred exp opencode 1 9 "$past" st_exp)"
out="$(run token 2>&1)"; code=$?
[ "$code" = 1 ] && [[ "$out" == *"expired"* ]] && pass "an expired token is refused" || fail "expired" "exit $code: $out"
[ "$(run org)" = org_exp ] && pass "the workspace id does not expire" || fail "org after expiry" "got $(run org)"

run nope >/dev/null 2>&1; [ $? = 2 ] && pass "unknown argument exits 2" || fail "usage" "wrong exit"
OPENCODE_DB="$SANDBOX/missing.db" bash "$SCRIPT" token >/dev/null 2>&1; [ $? = 1 ] && pass "missing database exits 1" || fail "missing db" "wrong exit"

echo
echo "passed: $PASSES  failed: $FAILURES"
[ "$FAILURES" -eq 0 ]
