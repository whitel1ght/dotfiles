#!/bin/bash
# Tests for bin/prod-kube-preflight. kubectl, duploctl and decide are stubs first on PATH, so no
# cluster, Duplo portal or real decision queue is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/prod-kube-preflight"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'pkill -f "$SANDBOX/" 2>/dev/null; rm -rf "${SANDBOX:?}"' EXIT

assert_has 'PROD_KUBE_PREFLIGHT_LIMIT:-15' "$(cat "$SCRIPT" 2>/dev/null)" "the default limit is 15 s"

cat >"$SANDBOX/kubectl" <<'EOF2'
#!/bin/sh
cat <<'JSON'
{"contexts":[{"name":"prod01","context":{"user":"prod01"}}],
 "users":[{"name":"prod01","user":{"exec":{"command":"duploctl","args":["jit","k8s","--host","https://duplo.example","--tenant","prod01","--interactive"]}}}]}
JSON
EOF2
cat >"$SANDBOX/duploctl" <<EOF2
#!/bin/sh
echo "\$\$" >"$SANDBOX/duplo.pid"
case "\$STUB_DUPLO" in
  hang) sleep 300 ;;
  fail) echo "connection refused" >&2; exit 1 ;;
  *) printf '{"status":{"token":"t","expirationTimestamp":"%s"}}\n' "\$STUB_EXP" ;;
esac
EOF2
cat >"$SANDBOX/decide" <<EOF2
#!/bin/sh
echo "\$*" >>"$SANDBOX/decide.calls"
if [ "\$1" = list ]; then cat "$SANDBOX/open.json"; fi
EOF2
chmod +x "$SANDBOX/kubectl" "$SANDBOX/duploctl" "$SANDBOX/decide"

# mode, expiry, limit → runs the script; sets RC, OUT, CALLS (decide add calls), SECS
run() {
  : >"$SANDBOX/decide.calls"; rm -f "$SANDBOX/duplo.pid"
  [ -f "$SANDBOX/open.json" ] || echo '[]' >"$SANDBOX/open.json"
  local start=$SECONDS
  OUT="$(STUB_DUPLO="$1" STUB_EXP="$2" PROD_KUBE_PREFLIGHT_LIMIT="$3" DECIDE_BIN="$SANDBOX/decide" \
    PATH="$SANDBOX:$PATH" bash "$SCRIPT" 2>&1 </dev/null)"
  RC=$?
  SECS=$((SECONDS - start))
  CALLS="$(grep -c '^add ' "$SANDBOX/decide.calls" || true)"
}

echo "hung duploctl"
run hang "" 2
assert_eq "3" "$RC" "exits 3"
[ "$SECS" -le 6 ] && pass "within the limit (${SECS}s)" || fail "within the limit" "took ${SECS}s"
assert_has "duploctl jit k8s --host https://duplo.example --tenant prod01 --interactive" "$OUT" "prints the login line"
assert_eq "1" "$CALLS" "files one card"
assert_has "You run" "$(cat "$SANDBOX/decide.calls")" "the option names who acts"
pid="$(cat "$SANDBOX/duplo.pid" 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "hung stub is killed" "pid $pid alive"; else pass "hung stub is killed"; fi
pgrep -f "sleep 300" >/dev/null 2>&1 && pgrep -f "$SANDBOX" >/dev/null 2>&1 && fail "no orphan" "still running" || pass "no orphan process"

echo "open card already there"
echo '[{"question":"Duplo sign-in expired for kubectl prod01: sign in again?"}]' >"$SANDBOX/open.json"
run hang "" 2
assert_eq "3" "$RC" "still exits 3"
assert_eq "0" "$CALLS" "files no second card"
echo '[]' >"$SANDBOX/open.json"

echo "valid session"
run ok "2099-01-01T00:00:00Z" 2
assert_eq "0" "$RC" "exits 0"
assert_eq "0" "$CALLS" "files no card"

echo "expired session"
run ok "2020-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3"
assert_has "Run in a terminal" "$OUT" "prints the login line"
assert_eq "1" "$CALLS" "files one card"

echo "other failure"
run fail "" 2
assert_eq "2" "$RC" "exits 2"
assert_has "connection refused" "$OUT" "shows the error"
assert_eq "0" "$CALLS" "files no card"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
