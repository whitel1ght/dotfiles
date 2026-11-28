#!/bin/bash
# Tests for bin/qbit-tunnel: which host it picks and what it forwards. nc and ssh are stubs that
# record their arguments, so nothing touches the network.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$TEST_DIR/qbit-tunnel"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
# nc succeeds only while $SANDBOX/lan-up exists (the laptop answers on the LAN); ssh logs its args.
cat >"$SANDBOX/nc" <<'STUB'
#!/bin/sh
[ -e "$(dirname "$0")/lan-up" ] && exit 0
exit 1
STUB
cat >"$SANDBOX/ssh" <<'STUB'
#!/bin/sh
echo "$*" >"$(dirname "$0")/ssh.log"
STUB
chmod +x "$SANDBOX/nc" "$SANDBOX/ssh"

run() {
    rm -f "$SANDBOX/ssh.log"
    ( PATH="$SANDBOX:$PATH" env "$@" "$CMD" ) >/dev/null 2>&1
    cat "$SANDBOX/ssh.log" 2>/dev/null
}
OPTS="-N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3"

echo "qbit-tunnel"
touch "$SANDBOX/lan-up"
assert_eq "$OPTS -L 127.0.0.1:8090:127.0.0.1:8080 thinkpad" "$(run)" \
    "on the LAN it tunnels straight to the laptop"
assert_eq "$OPTS -L 127.0.0.1:9999:127.0.0.1:8080 thinkpad" "$(run QBIT_TUNNEL_PORT=9999)" \
    "QBIT_TUNNEL_PORT picks the local port"
rm -f "$SANDBOX/lan-up"
assert_eq "$OPTS -L 127.0.0.1:8090:127.0.0.1:8080 thinkpad-away" "$(run)" \
    "away from the LAN it goes out through the VPS home link"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
