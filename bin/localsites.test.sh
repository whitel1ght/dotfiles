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
# Stub state in $SANDBOX: loaded (job exists), linger (print still reports loaded N times after
# bootout), bootstrap_fails (bootstrap fails N times). Bootstrap while lingering fails like error 5.
cat >"$SANDBOX/launchctl" <<'STUB'
#!/bin/sh
D="$(dirname "$0")"
echo "$*" >>"$D/launchctl.log"
n() { cat "$D/$1" 2>/dev/null || echo 0; }
case "$1" in
    bootout) rm -f "$D/loaded"; echo "$(n linger)" >"$D/pending" ;;
    print)
        [ -e "$D/loaded" ] && exit 0
        p="$(n pending)"; [ "$p" -gt 0 ] && { echo $((p - 1)) >"$D/pending"; exit 0; }
        exit 1 ;;
    bootstrap)
        [ "$(n pending)" -gt 0 ] && exit 5
        f="$(n bootstrap_fails)"; [ "$f" -gt 0 ] && { echo $((f - 1)) >"$D/bootstrap_fails"; exit 5; }
        touch "$D/loaded" ;;
esac
STUB
chmod +x "$SANDBOX/launchctl"

ls_env() {
    LOCALSITES_ETC="$SANDBOX/etc" LOCALSITES_LIBEXEC="$SANDBOX/libexec" LOCALSITES_DAEMON="$SANDBOX/local.localsites.plist" \
    LOCALSITES_POLL_SLEEP=0 LOCALSITES_RETRY_SLEEP=0 LOCALSITES_LOG="$SANDBOX/localsites.log" LOCALSITES_LAUNCHCTL="$SANDBOX/launchctl" \
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

echo 3 >"$SANDBOX/linger"; : >"$SANDBOX/launchctl.log"; rm -f "$SANDBOX/pending"
OUT="$(LOCALSITES_UID=0 ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "0" "$RC" "reinstall succeeds while launchd is still removing the job"
LOG="$(cat "$SANDBOX/launchctl.log")"
assert_eq "4" "$(grep -c '^print' <<<"$LOG" | tr -d ' ')" "install polls print until the job is gone (3 loaded, then gone)"
assert_eq "bootstrap" "$(tail -1 <<<"$LOG" | cut -d' ' -f1)" "and bootstraps only after that"
rm -f "$SANDBOX/linger" "$SANDBOX/pending"

: >"$SANDBOX/launchctl.log"; echo 1 >"$SANDBOX/bootstrap_fails"
OUT="$(LOCALSITES_UID=0 ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "0" "$RC" "a first bootstrap failure is retried"
assert_eq "2" "$(grep -c '^bootstrap' "$SANDBOX/launchctl.log")" "with exactly one retry"

echo 5 >"$SANDBOX/bootstrap_fails"
OUT="$(LOCALSITES_UID=0 ls_env "$CMD" install 2>&1)"; RC=$?
assert_eq "1" "$RC" "two bootstrap failures exit 1"
assert_has "sudo" "$OUT" "and name the command to run"
assert_has "start" "$OUT" "start"
rm -f "$SANDBOX/bootstrap_fails"

touch "$SANDBOX/loaded"; : >"$SANDBOX/launchctl.log"
OUT="$(LOCALSITES_UID=0 ls_env "$CMD" start 2>&1)"; RC=$?
assert_eq "0" "$RC" "start on a loaded job exits 0"
assert_has "already running" "$OUT" "and says already running"
assert_eq "0" "$(grep -c '^bootstrap' "$SANDBOX/launchctl.log" | tr -d ' ')" "without bootstrapping"

LOCALSITES_UID=0 ls_env "$CMD" uninstall >/dev/null 2>&1
assert_eq "none" "$(ls "$SANDBOX/etc" "$SANDBOX/libexec" "$SANDBOX/local.localsites.plist" 2>/dev/null | tr -d '\n' || true)none" "uninstall removes the daemon, config and binary"

echo "Caddyfile routing (real caddy, spare ports)"
free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
P80="$(free_port)"; PA="$(free_port)"; PC="$(free_port)"; PL8="$(free_port)"; PAR="$(free_port)"
stub() { python3 -I -c '
import http.server, sys
name = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = ("%s host=%s" % (name, self.headers.get("Host"))).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()' "$1" "$2" & PIDS+=($!); }
stub "$PA" articles; stub "$PC" chat; stub "$PL8" learn; stub "$PAR" artifacts
sed -e "s/http_port 80/http_port $P80/" -e "s/127.0.0.1:8765/127.0.0.1:$PA/" -e "s/127.0.0.1:8080/127.0.0.1:$PC/" -e "s/127.0.0.1:8767/127.0.0.1:$PL8/" -e "s/127.0.0.1:8768/127.0.0.1:$PAR/" \
    "$CADDYFILE" >"$SANDBOX/test.Caddyfile"
HOME="$SANDBOX" XDG_DATA_HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX" \
    caddy run --adapter caddyfile --config "$SANDBOX/test.Caddyfile" >"$SANDBOX/caddy.log" 2>&1 & PIDS+=($!)
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$P80/" && break; sleep 0.1; done
get() { curl -s --max-time 3 -H "Host: $1:$P80" "http://127.0.0.1:$P80/"; }
assert_eq "articles host=articles.localhost:$P80" "$(get articles.localhost)" "articles.localhost reaches articles with its Host kept"
assert_eq "learn host=learn.localhost:$P80" "$(get learn.localhost)" "learn.localhost reaches learn"
assert_eq "artifacts host=artifacts.localhost:$P80" "$(get artifacts.localhost)" "artifacts.localhost reaches the artifacts site"
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
