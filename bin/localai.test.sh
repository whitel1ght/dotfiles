#!/bin/bash
# Tests for bin/localai. Stub `lms` and `webui` record their calls, and a static
# http.server on a spare port stands in for LM Studio's model API, so the real
# server, models and Open WebUI are never touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/localai"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3" "[$2] found in [$1]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(mktemp -d)"
API_PORT=4798
SERVER_PID=
cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

CALLS="$SANDBOX/calls"
for stub in lms webui articles; do
    printf '#!/bin/bash\necho "%s $*" >>"%s"\n' "$stub" "$CALLS" >"$SANDBOX/$stub"
    chmod +x "$SANDBOX/$stub"
done
export LMS="$SANDBOX/lms" WEBUI="$SANDBOX/webui" ARTICLES="$SANDBOX/articles" LMS_URL="http://127.0.0.1:$API_PORT" LOCALAI_NO_BROWSER=1

echo "localai"

# Nothing serving the API: both models count as not loaded.
: >"$CALLS"
out="$("$SCRIPT" start 2>&1)"
calls="$(cat "$CALLS")"
assert_contains "$calls" "lms server start" "start: starts the LM Studio server"
assert_contains "$calls" "lms load gemma-4-e4b-it-mlx -c 32768 --parallel 1 -y" "start: loads the chat model"
assert_contains "$calls" "lms load qwen2.5-coder-1.5b -c 4096 -y" "start: loads the autocomplete model"
assert_contains "$calls" "webui start" "start: starts Open WebUI"
assert_contains "$calls" "articles start" "start: starts the articles server"
assert_contains "$out" "http://127.0.0.1:8080" "start: prints the link"
assert_contains "$out" "Saved articles: http://127.0.0.1:8765" "start: prints the articles link when it started"
first="$(head -1 "$CALLS")"
assert_contains "$first" "server start" "start: server comes up before any load"

# The API reports the chat model loaded: only the other one is loaded.
mkdir -p "$SANDBOX/www/api/v0/models"
echo '{"id":"gemma-4-e4b-it-mlx","state": "loaded"}' >"$SANDBOX/www/api/v0/models/gemma-4-e4b-it-mlx"
echo '{"id":"qwen2.5-coder-1.5b","state": "not-loaded"}' >"$SANDBOX/www/api/v0/models/qwen2.5-coder-1.5b"
python3 -m http.server "$API_PORT" --bind 127.0.0.1 --directory "$SANDBOX/www" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -sf -m 1 "$LMS_URL/api/v0/models/gemma-4-e4b-it-mlx" >/dev/null && break; sleep 0.1; done

: >"$CALLS"
out="$("$SCRIPT" start 2>&1)"
calls="$(cat "$CALLS")"
assert_not_contains "$calls" "load gemma" "start: skips a model that is already loaded"
assert_contains "$calls" "lms load qwen2.5-coder-1.5b" "start: still loads the missing one"
assert_contains "$out" "gemma-4-e4b-it-mlx already loaded" "start: says what it skipped"

: >"$CALLS"
out="$("$SCRIPT" stop 2>&1)"
calls="$(cat "$CALLS")"
assert_contains "$calls" "webui stop" "stop: stops Open WebUI"
assert_contains "$calls" "articles stop" "stop: stops the articles server"
assert_contains "$calls" "lms unload --all" "stop: unloads all models"
assert_contains "$calls" "lms server stop" "stop: stops the server"

# articles failing to start (linked but not installed) must not fail localai.
printf '#!/bin/bash\necho "articles $*" >>"%s"\n[ "$1" = start ] && { echo "articles: not installed" >&2; exit 1; }\nexit 0\n' "$CALLS" >"$SANDBOX/articles"
: >"$CALLS"
out="$("$SCRIPT" start 2>&1)"; code=$?
[ "$code" -eq 0 ] && pass "start: articles failure does not fail localai" || fail "start: articles failure does not fail localai" "exit $code"
assert_contains "$out" "Ready." "start: still prints Ready after an articles failure"
assert_not_contains "$out" "Saved articles:" "start: no articles link when it did not start"

# A failing load must stop the start, not carry on to Open WebUI.
printf '#!/bin/bash\necho "lms $*" >>"%s"\n[ "$1" = load ] && exit 1\nexit 0\n' "$CALLS" >"$SANDBOX/lms"
: >"$CALLS"
out="$("$SCRIPT" start 2>&1)"; code=$?
assert_contains "$out" "could not load" "start: load failure is reported"
assert_not_contains "$(cat "$CALLS")" "webui" "start: no Open WebUI after a load failure"
[ "$code" -ne 0 ] && pass "start: load failure exits non-zero" || fail "start: load failure exits non-zero" "exit $code"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
