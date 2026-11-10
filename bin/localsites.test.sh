#!/bin/bash
# Tests for bin/localsites and localsites/Caddyfile. launchctl is a stub that logs; install runs as
# the current user with LOCALSITES_UID=0 and the owner set to the user, paths under a sandbox. The
# routing test runs the real Caddyfile through caddy on spare ports with stub upstreams.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$TEST_DIR/localsites"
CADDYFILE="$TEST_DIR/../localsites/Caddyfile"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
PIDS=()
trap 'for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; [ "$FAIL" -gt 0 ] && tail -5 "$SANDBOX/caddy.log"; rm -rf "${SANDBOX:?}"' EXIT
printf '#!/bin/sh\necho "$*" >>"%s/launchctl.log"\n' "$SANDBOX" >"$SANDBOX/launchctl"
chmod +x "$SANDBOX/launchctl"

ls_env() {
    LOCALSITES_ETC="$SANDBOX/etc" LOCALSITES_LIBEXEC="$SANDBOX/libexec" LOCALSITES_DAEMON="$SANDBOX/local.localsites.plist" \
    LOCALSITES_LOG="$SANDBOX/localsites.log" LOCALSITES_LAUNCHCTL="$SANDBOX/launchctl" \
    LOCALSITES_OWNER="$(id -un)" LOCALSITES_GROUP="$(id -gn)" "$@"
}

echo "localsites"
OUT="$(LOCALSITES_UID=501 ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "1" "$RC" "install without root refuses"
assert_has "needs root: sudo" "$OUT" "and says how to run it"
assert_eq "no" "$([ -e "$SANDBOX/local.localsites.plist" ] && echo yes || echo no)" "and writes nothing"

assert_has "is valid" "$(ls_env "$CMD" check)" "the committed Caddyfile validates"

OUT="$(LOCALSITES_UID=0 ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "0" "$RC" "install as root succeeds"
cmp -s "$CADDYFILE" "$SANDBOX/etc/Caddyfile" && pass "the Caddyfile is copied to the root-owned path" || fail "the Caddyfile is copied" "$(ls -l "$SANDBOX/etc" 2>&1)"
PL="$(cat "$SANDBOX/local.localsites.plist")"
assert_has "<string>$SANDBOX/etc/Caddyfile</string>" "$PL" "the daemon reads the copy, not dotfiles"
assert_has "<string>$SANDBOX/libexec/caddy</string>" "$PL" "and runs a copied caddy, not the user-owned Homebrew one"
cmp -s "$(readlink -f "$(command -v caddy)")" "$SANDBOX/libexec/caddy" && pass "the copy is the installed caddy" || fail "caddy is copied" "$(ls -l "$SANDBOX/libexec" 2>&1)"
assert_has "<string>local.localsites</string>" "$PL" "with its label"
assert_has "$SANDBOX/localsites.log" "$PL" "and its log"
assert_has "bootstrap system $SANDBOX/local.localsites.plist" "$(cat "$SANDBOX/launchctl.log")" "and loads it into the system domain"
assert_has "http://articles.localhost" "$OUT" "install names the sites"

printf "http://x.localhost {\n\tno_such_directive\n}\n" >"$SANDBOX/bad.Caddyfile"
OUT="$(LOCALSITES_UID=0 LOCALSITES_SRC="$SANDBOX/bad.Caddyfile" ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "1" "$RC" "an invalid Caddyfile is not installed"
cmp -s "$CADDYFILE" "$SANDBOX/etc/Caddyfile" && pass "and the running copy stays" || fail "the running copy stays" "changed"

LOCALSITES_UID=0 ls_env "$CMD" uninstall >/dev/null 2>&1
assert_eq "none" "$(ls "$SANDBOX/etc" "$SANDBOX/libexec" "$SANDBOX/local.localsites.plist" 2>/dev/null | tr -d '\n' || true)none" "uninstall removes the daemon, config and binary"

echo "Caddyfile routing (real caddy, spare ports)"
free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
P80="$(free_port)"; PA="$(free_port)"; PC="$(free_port)"
stub() { python3 -I -c '
import http.server, sys
name = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = ("%s host=%s" % (name, self.headers.get("Host"))).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()' "$1" "$2" & PIDS+=($!); }
stub "$PA" articles; stub "$PC" chat
sed -e "s/http_port 80/http_port $P80/" -e "s/127.0.0.1:8765/127.0.0.1:$PA/" -e "s/127.0.0.1:8080/127.0.0.1:$PC/" \
    "$CADDYFILE" >"$SANDBOX/test.Caddyfile"
HOME="$SANDBOX" XDG_DATA_HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX" \
    caddy run --adapter caddyfile --config "$SANDBOX/test.Caddyfile" >"$SANDBOX/caddy.log" 2>&1 & PIDS+=($!)
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$P80/" && break; sleep 0.1; done
get() { curl -s --max-time 3 -H "Host: $1:$P80" "http://127.0.0.1:$P80/"; }
assert_eq "articles host=articles.localhost:$P80" "$(get articles.localhost)" "articles.localhost reaches articles with its Host kept"
assert_eq "chat host=chat.localhost:$P80" "$(get chat.localhost)" "chat.localhost reaches Open WebUI"
assert_eq "No local site with that name." "$(get evil.example)" "any other host gets the 404 page"
assert_eq "404" "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: x.localhost:$P80" "http://127.0.0.1:$P80/")" "with status 404"
OTHER_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [ -n "$OTHER_IP" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -H "Host: articles.localhost" "http://$OTHER_IP:$P80/")"
    assert_eq "000" "$code" "nothing answers on the network address ($OTHER_IP)"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
