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
trap '[ -f "$SANDBOX/sleep.pid" ] && kill -9 "$(cat "$SANDBOX/sleep.pid")" 2>/dev/null; rm -rf "${SANDBOX:?}"' EXIT

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
echo x >>"$SANDBOX/duplo.calls"
case "\$STUB_DUPLO" in
  hang) sleep 300 & echo \$! >"$SANDBOX/sleep.pid"; wait ;;
  fail) echo "connection refused" >&2; exit 1 ;;
  *) printf '{"status":{"token":"%s","expirationTimestamp":"%s"}}\n' "\${STUB_TOKEN:-t}" "\$STUB_EXP" ;;
esac
EOF2
cat >"$SANDBOX/decide" <<EOF2
#!/bin/sh
echo "\$*" >>"$SANDBOX/decide.calls"
[ "\$1" = add ] && cat >>"$SANDBOX/decide.calls"
if [ "\$1" = list ]; then
  cat "$SANDBOX/open.json"
  if [ -f "$SANDBOX/big" ]; then head -c 300000 /dev/zero | tr '\\0' 'x'; fi
fi
EOF2
CACHE="$SANDBOX/cache"; mkdir -p "$CACHE"
# cache fixtures: portal token and k8s credential expiry, as offsets in seconds from now
iso() { date -u -r "$(( $(date -u +%s) + $1 ))" +%Y-%m-%dT%H:%M:%S+00:00; }
setcache() {
  rm -f "$CACHE"/*
  [ -n "${1:-}" ] && printf '{"Version":"v1","DuploToken":"x","Expiration":"%s"}\n' "$(iso "$1")" >"$CACHE/duplo.example,duplo-creds.json"
  [ -n "${2:-}" ] && printf '{"status":{"token":"x","expirationTimestamp":"%s"}}\n' "$(iso "$2")" >"$CACHE/duplo.example,plan,prod01,k8s-creds.json"
  return 0
}
# unsigned JWT with exp = now + $1 seconds, base64url payload without padding
jwt() {
  local p; p="$(printf '{"exp":%s,"sub":"u"}' "$(( $(date -u +%s) + $1 ))" | base64 | tr -d '=\n' | tr '+/' '-_')"
  echo "eyJhbGciOiJub25lIn0.$p.sig"
}
# portal expiry offset (empty: no file), k8s JWT offset, k8s stamp offset: stamp mislabelled like duploctl's
setjwtcache() {
  rm -f "$CACHE"/*
  [ -n "${1:-}" ] && printf '{"Version":"v1","DuploToken":"x","Expiration":"%s"}\n' "$(iso "$1")" >"$CACHE/duplo.example,duplo-creds.json"
  printf '{"status":{"token":"%s","expirationTimestamp":"%s"}}\n' "$(jwt "$2")" "$(iso "$3")" >"$CACHE/duplo.example,plan,prod01,k8s-creds.json"
  return 0
}
K8S_FILE="$CACHE/duplo.example,plan,prod01,k8s-creds.json"
chmod +x "$SANDBOX/kubectl" "$SANDBOX/duploctl" "$SANDBOX/decide"

# mode, expiry, limit → runs the script; sets RC, OUT, CALLS (decide add calls), SECS
run() {
  : >"$SANDBOX/decide.calls"; rm -f "$SANDBOX/duplo.pid" "$SANDBOX/duplo.calls" "$SANDBOX/sleep.pid"
  [ -f "$SANDBOX/open.json" ] || echo '[]' >"$SANDBOX/open.json"
  local start=$SECONDS
  OUT="$(STUB_DUPLO="$1" STUB_EXP="$2" STUB_TOKEN="${STUB_TOKEN:-t}" PROD_KUBE_PREFLIGHT_LIMIT="$3" DECIDE_BIN="$SANDBOX/decide" PROD_KUBE_PREFLIGHT_CACHE="$CACHE" \
    PATH="$SANDBOX:$PATH" bash "$SCRIPT" 2>&1 </dev/null)"
  RC=$?
  SECS=$((SECONDS - start))
  CALLS="$(grep -c '^add ' "$SANDBOX/decide.calls" || true)"
}

echo "hung duploctl (cache says valid)"
setcache 3600 3600
run hang "" 2
assert_eq "3" "$RC" "exits 3"
[ "$SECS" -le 6 ] && pass "within the limit (${SECS}s)" || fail "within the limit" "took ${SECS}s"
assert_has "duploctl jit k8s --host https://duplo.example --tenant prod01 --interactive" "$OUT" "prints the login line"
assert_eq "1" "$CALLS" "files one card"
assert_has "You run" "$(cat "$SANDBOX/decide.calls")" "the option names who acts"
pid="$(cat "$SANDBOX/duplo.pid" 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "hung stub is killed" "pid $pid alive"; else pass "hung stub is killed"; fi
spid="$(cat "$SANDBOX/sleep.pid" 2>/dev/null)"
if [ -n "$spid" ] && ! kill -0 "$spid" 2>/dev/null; then pass "no orphan: the stub's child is dead"; else fail "no orphan" "child pid [$spid] alive or not recorded"; fi

echo "open card already there"
echo '[{"question":"Duplo sign-in expired for kubectl prod01: sign in again?"}]' >"$SANDBOX/open.json"
run hang "" 2
assert_eq "3" "$RC" "still exits 3"
assert_eq "0" "$CALLS" "files no second card"
echo '[]' >"$SANDBOX/open.json"

echo "open card with a large open queue"
echo '[{"question":"Duplo sign-in expired for kubectl prod01: sign in again?"}]' >"$SANDBOX/open.json"
: >"$SANDBOX/big"
run hang "" 2
assert_eq "0" "$CALLS" "files no second card when decide list output exceeds the pipe buffer"
rm -f "$SANDBOX/big"; echo '[]' >"$SANDBOX/open.json"

echo "expired cache"
for c in "-60 -60" "-60 " " " ; do
  # shellcheck disable=SC2086
  setcache $c
  run ok "2099-01-01T00:00:00Z" 2
  assert_eq "3" "$RC" "exits 3 (cache '$c')"
  [ ! -f "$SANDBOX/duplo.calls" ] && pass "duploctl never started" || fail "duploctl never started" "it ran"
  assert_has "Run in a terminal" "$OUT" "prints the login line"
  assert_eq "1" "$CALLS" "files one card"
done

echo "valid k8s credential, expired portal token"
setcache -60 3600
run ok "2099-01-01T00:00:00Z" 2
assert_eq "0" "$RC" "exits 0"

echo "valid session"
setcache 3600 3600
run ok "2099-01-01T00:00:00Z" 2
assert_eq "0" "$RC" "exits 0"
assert_eq "0" "$CALLS" "files no card"

echo "expired session"
run ok "2020-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3"
assert_has "Run in a terminal" "$OUT" "prints the login line"
assert_eq "1" "$CALLS" "files one card"

echo "stale k8s JWT under a stamp that looks valid (local time labelled UTC), portal expired"
setjwtcache -60 -1020 10800
run ok "2099-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3"
[ ! -f "$SANDBOX/duplo.calls" ] && pass "duploctl never started" || fail "duploctl never started" "it ran"
assert_has "$K8S_FILE" "$OUT" "names the k8s cache file to remove"
assert_has "keeps serving" "$OUT" "says duploctl serves the stale cache"
assert_eq "1" "$CALLS" "files one card"
assert_has "remove $K8S_FILE" "$(cat "$SANDBOX/decide.calls")" "the card names the file too"
[ -f "$K8S_FILE" ] && pass "the cache file is left in place" || fail "the cache file is left in place" "it is gone"

echo "stale k8s JWT, portal valid, duploctl serves the stale token with a future stamp"
setjwtcache 3600 -1020 10800
STUB_TOKEN="$(jwt -1020)" run ok "$(date -u -r "$(( $(date -u +%s) + 10800 ))" +%Y-%m-%dT%H:%M:%SZ)" 2
assert_eq "3" "$RC" "exits 3"
assert_has "$K8S_FILE" "$OUT" "names the k8s cache file to remove"
assert_eq "1" "$CALLS" "files one card"

echo "k8s JWT in the future"
setjwtcache -60 3600 3600
STUB_TOKEN="$(jwt 3600)" run ok "2099-01-01T00:00:00Z" 2
assert_eq "0" "$RC" "exits 0"
assert_eq "0" "$CALLS" "files no card"

echo "k8s JWT in the future, stamp wrongly in the past, portal expired"
setjwtcache -60 3600 -3600
STUB_TOKEN="$(jwt 3600)" run ok "2020-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3 (duploctl would not serve the cache and would open the login)"
[ ! -f "$SANDBOX/duplo.calls" ] && pass "duploctl never started" || fail "duploctl never started" "it ran"

echo "k8s JWT in the future, stamp wrongly in the past, portal valid"
setjwtcache 3600 3600 -3600
STUB_TOKEN="$(jwt 3600)" run ok "2099-01-01T00:00:00Z" 2
assert_eq "0" "$RC" "exits 0"
assert_eq "0" "$CALLS" "files no card"

echo "k8s cache with an expired JWT and no expirationTimestamp"
rm -f "$CACHE"/*
printf '{"status":{"token":"%s"}}\n' "$(jwt -60)" >"$K8S_FILE"
run ok "2099-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3"
case "$OUT" in *"integer expression expected"*|*"integer expected"*) fail "no integer expression error" "$OUT" ;; *) pass "no integer expression error" ;; esac

echo "k8s cache with a valid JWT and no expirationTimestamp, portal expired"
rm -f "$CACHE"/*
printf '{"Version":"v1","DuploToken":"x","Expiration":"%s"}\n' "$(iso -60)" >"$CACHE/duplo.example,duplo-creds.json"
printf '{"status":{"token":"%s"}}\n' "$(jwt 3600)" >"$K8S_FILE"
run ok "2099-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "exits 3 (duploctl treats a missing stamp as expired and would open the login)"
[ ! -f "$SANDBOX/duplo.calls" ] && pass "duploctl never started" || fail "duploctl never started" "it ran"

echo "non-JWT token keeps using the stamp"
setcache -60 -60
run ok "2099-01-01T00:00:00Z" 2
assert_eq "3" "$RC" "expired stamp: exits 3"
assert_has "Run in a terminal" "$OUT" "prints the login line"
case "$OUT" in *"keeps serving"*) fail "no stale note" "note printed" ;; *) pass "no stale note" ;; esac

echo "other failure"
setcache 3600 3600
run fail "" 2
assert_eq "2" "$RC" "exits 2"
assert_has "connection refused" "$OUT" "shows the error"
assert_eq "0" "$CALLS" "files no card"

echo "kubectl missing"
OUT="$(PATH="/usr/bin:/bin" HOME="$SANDBOX/nohome" bash "$SCRIPT" 2>&1 </dev/null)"; RC=$?
assert_eq "2" "$RC" "exits 2"
assert_has "kubectl not found" "$OUT" "says kubectl not found"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
