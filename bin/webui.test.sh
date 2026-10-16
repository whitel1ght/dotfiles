#!/bin/bash
# Tests for bin/webui. A stub `open-webui` serves a static /health with Python's
# http.server on a spare port, so the real install, its data and port 8080 are
# never touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/webui"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(mktemp -d)"
export WEBUI_HOME="$SANDBOX/home" WEBUI_PORT=4797 WEBUI_WAIT=10 WEBUI_NO_BROWSER=1
export WEBUI_BIN="$SANDBOX/open-webui"
cleanup() {
    "$SCRIPT" stop >/dev/null 2>&1
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

mkdir -p "$SANDBOX/www"
echo '{"status":true}' >"$SANDBOX/www/health"
# Records the env it was started with, then serves; `serve --port N` like the real one.
cat >"$WEBUI_BIN" <<EOF
#!/bin/bash
env >"$SANDBOX/env.txt"
exec python3 -m http.server "\$5" --bind 127.0.0.1 --directory "$SANDBOX/www"
EOF
chmod +x "$WEBUI_BIN"

echo "webui"

out="$("$SCRIPT" status)"
assert_contains "$out" "not running" "status before start"

out="$("$SCRIPT" start 2>&1)"
assert_contains "$out" "up at http://127.0.0.1:4797" "start waits for /health"

out="$("$SCRIPT" status)"
assert_contains "$out" "running at http://127.0.0.1:4797" "status after start"

env_out="$(cat "$SANDBOX/env.txt")"
assert_contains "$env_out" "OPENAI_API_BASE_URL=http://127.0.0.1:1234/v1" "points at LM Studio"
assert_contains "$env_out" "DATA_DIR=$WEBUI_HOME/data" "data dir under WEBUI_HOME"
assert_contains "$env_out" "ANONYMIZED_TELEMETRY=false" "telemetry off"
assert_contains "$env_out" "WHISPER_MODEL=base" "Whisper base (English)"
assert_contains "$env_out" "AUDIO_TTS_ENGINE=browser-kokoro" "Kokoro voice (in the browser)"
assert_contains "$env_out" "WEB_SEARCH_ENGINE=duckduckgo" "web search via DuckDuckGo"

out="$("$SCRIPT" 2>&1)"
assert_contains "$out" "already running" "default command reuses a running instance"

pid="$(cat "$WEBUI_HOME/webui.pid")"
out="$("$SCRIPT" stop)"
assert_contains "$out" "stopped" "stop"
if kill -0 "$pid" 2>/dev/null; then fail "process gone after stop" "pid $pid alive"; else pass "process gone after stop"; fi

out="$("$SCRIPT" stop)"
assert_contains "$out" "not running" "stop when already stopped"

# A server that dies on startup must fail fast with its log, not wait out WEBUI_WAIT.
printf '#!/bin/bash\necho boom >&2\nexit 1\n' >"$WEBUI_BIN"
out="$("$SCRIPT" start 2>&1)"; code=$?
assert_contains "$out" "exited during startup" "startup crash reported"
assert_contains "$out" "boom" "startup crash shows the log"
[ "$code" -ne 0 ] && pass "startup crash exits non-zero" || fail "startup crash exits non-zero" "exit $code"

rm -f "$WEBUI_BIN"
out="$("$SCRIPT" start 2>&1)"
assert_contains "$out" "not installed" "missing install is reported"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
