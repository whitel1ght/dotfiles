#!/bin/bash
# Tests for bin/harvest-log. A stub Harvest API runs on localhost (HARVEST_API points at it)
# and the diary is a sandbox, so nothing reaches Harvest or ~/wiki.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/harvest-log"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
STUB_PID=""
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "${SANDBOX:?}"' EXIT
D=2026-11-13
export HARVEST_DIARY_DIR="$SANDBOX/diary"
export HARVEST_TOKEN=tok HARVEST_ACCOUNT_ID=acc
mkdir -p "$HARVEST_DIARY_DIR"

cat >"$SANDBOX/stub.py" <<'PY'
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

state_path, log_path, port_path = sys.argv[1:4]

def load():
    with open(state_path) as f:
        return json.load(f)

def save(s):
    with open(state_path, "w") as f:
        json.dump(s, f)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self, method):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        with open(log_path, "a") as f:
            f.write(json.dumps({"method": method, "path": u.path, "query": q, "body": json.loads(raw) if raw else None}) + "\n")
        if self.headers.get("Authorization") != "Bearer tok" or self.headers.get("Harvest-Account-Id") != "acc":
            return self.reply(401, {"error": "invalid_token"})
        if not self.headers.get("User-Agent"):
            return self.reply(400, {"error": "user agent required"})
        s = load()
        if method == "GET" and u.path == "/v2/users/me":
            return self.reply(200, {"id": 42})
        if method == "GET" and u.path == "/v2/company":
            return self.reply(200, s["company"])
        if method == "GET" and u.path == "/v2/users/me/project_assignments":
            return self.reply(200, {"project_assignments": s["assignments"], "next_page": None})
        if method == "GET" and u.path == "/v2/time_entries":
            es = [e for e in s["entries"] if q.get("from", "") <= e["spent_date"] <= q.get("to", "9999")
                  and str(e["user"]["id"]) == q.get("user_id", "42")
                  and ("project_id" not in q or str(e["project"]["id"]) == q["project_id"])]
            return self.reply(200, {"time_entries": es, "next_page": None})
        if method == "POST" and u.path == "/v2/time_entries":
            b = json.loads(raw)
            e = {"id": 900 + len(s["entries"]), "spent_date": b["spent_date"], "hours": b.get("hours", 8.0),
                 "notes": b.get("notes"), "user": {"id": 42}, "project": {"id": b["project_id"]},
                 "task": {"id": b["task_id"]}, "is_running": False}
            s["entries"].append(e)
            save(s)
            return self.reply(201, e)
        if method == "PATCH" and u.path.startswith("/v2/time_entries/"):
            i = int(u.path.rsplit("/", 1)[1])
            for e in s["entries"]:
                if e["id"] == i:
                    e.update(json.loads(raw))
                    save(s)
                    return self.reply(200, e)
            return self.reply(404, {"error": "not found"})
        return self.reply(404, {"error": "no route"})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")

srv = HTTPServer(("127.0.0.1", 0), H)
with open(port_path, "w") as f:
    f.write(str(srv.server_port))
srv.serve_forever()
PY

ASSIGN='[{"project":{"id":7,"name":"ECFX","code":""},"task_assignments":[{"task":{"id":70,"name":"Programming"}},{"task":{"id":71,"name":"Meetings"}}]},{"project":{"id":8,"name":"Internal","code":"INT"},"task_assignments":[{"task":{"id":80,"name":"Programming"}}]}]'
state() { # company-json entries-json
    printf '{"company":%s,"assignments":%s,"entries":%s}\n' "$1" "$ASSIGN" "$2" >"$SANDBOX/state.json"
    : >"$SANDBOX/requests.log"
}
state '{"wants_timestamp_timers":false}' '[]'
python3 -I "$SANDBOX/stub.py" "$SANDBOX/state.json" "$SANDBOX/requests.log" "$SANDBOX/port" &
STUB_PID=$!
for _ in $(seq 50); do [ -s "$SANDBOX/port" ] && break; sleep 0.1; done
export HARVEST_API="http://127.0.0.1:$(cat "$SANDBOX/port")"

diary() { # date body-of-report-block
    printf '# %s\n\n## Work\n\n### ECFX\n\n<!-- daily-report:start -->\n%s\n<!-- daily-report:end -->\n\n## Personal\n- [X] walk\n' "$1" "$2" >"$HARVEST_DIARY_DIR/$1.md"
}
REPORT=$'**Standup**\nMerged backend!6974.\n\n**Done**\n- ECFX-7538 alert: backend!6974 merged  [↗][backend!6974]\n\n[backend!6974]: https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6974'
WANT=$'**Standup**\nMerged backend!6974.\n\n**Done**\n- ECFX-7538 alert: backend!6974 merged'
writes() { jq -c 'select(.method != "GET")' "$SANDBOX/requests.log"; }
run() { OUT="$("$SCRIPT" "$@" 2>&1)"; RC=$?; }

echo "== create when the day has no ecfx/programming entry =="
diary "$D" "$REPORT"
state '{"wants_timestamp_timers":false}' '[{"id":1,"spent_date":"2026-11-13","hours":2.0,"notes":"standup","user":{"id":42},"project":{"id":7},"task":{"id":71},"is_running":false}]'
run "$D"
assert_eq 0 "$RC" "exit 0"
assert_has "created" "$OUT" "says it created the entry"
assert_has "8" "$OUT" "names the 8 hours"
assert_eq 1 "$(writes | wc -l | tr -d ' ')" "one write: a meetings entry the same day is not ours"
assert_eq '{"project_id":7,"task_id":70,"spent_date":"2026-11-13","hours":8}' "$(writes | jq -c '.body | {project_id, task_id, spent_date, hours}')" "POSTs ecfx/programming, 8h, that day"
assert_eq "$WANT" "$(writes | jq -r '.body.notes')" "notes are the daily-report block, markers and link refs dropped"
assert_eq "" "$(writes | jq -r '.body.notes' | rg 'Personal|walk|daily-report')" "nothing outside the block"

echo "== update notes only when the entry exists =="
state '{"wants_timestamp_timers":false}' '[{"id":5,"spent_date":"2026-11-13","hours":3.5,"notes":"old","user":{"id":42},"project":{"id":7},"task":{"id":70},"is_running":true}]'
run "$D"
assert_eq 0 "$RC" "exit 0"
assert_has "updated" "$OUT" "says it updated"
assert_eq 'PATCH /v2/time_entries/5' "$(writes | jq -r '"\(.method) \(.path)"')" "PATCHes the existing entry"
assert_eq '["notes"]' "$(writes | jq -c '.body | keys')" "sends notes only: the hours stay the user's"
assert_eq "$WANT" "$(writes | jq -r '.body.notes')" "with the report"

echo "== a re-run with the same text writes nothing =="
state '{"wants_timestamp_timers":false}' "$(jq -cn --arg n "$WANT" '[{"id":5,"spent_date":"2026-11-13","hours":3.5,"notes":$n,"user":{"id":42},"project":{"id":7},"task":{"id":70},"is_running":false}]')"
run "$D"
assert_eq 0 "$RC" "exit 0"
assert_has "up to date" "$OUT" "says it is up to date"
assert_eq "" "$(writes)" "no write"

echo "== timestamp accounts get start and end times =="
state '{"wants_timestamp_timers":true}' '[]'
run "$D"
assert_eq 0 "$RC" "exit 0"
assert_eq '{"started_time":"9:00am","ended_time":"5:00pm","hours":null}' "$(writes | jq -c '.body | {started_time, ended_time, hours}')" "9:00am-5:00pm, no hours field"

echo "== dry run =="
state '{"wants_timestamp_timers":false}' '[]'
run --dry-run "$D"
assert_eq 0 "$RC" "exit 0"
assert_has "would create" "$OUT" "says what it would do"
assert_eq "" "$(writes)" "and writes nothing"

echo "== HARVEST_HOURS, HARVEST_PROJECT and HARVEST_TASK override the defaults =="
state '{"wants_timestamp_timers":false}' '[]'
HARVEST_HOURS=6 HARVEST_PROJECT=int HARVEST_TASK=programming run "$D"
assert_eq '{"project_id":8,"task_id":80,"hours":6}' "$(writes | jq -c '.body | {project_id, task_id, hours}')" "project matched by code, case-insensitive"

echo "== skips =="
state '{"wants_timestamp_timers":false}' '[]'
run 2026-11-01
assert_eq 2 "$RC" "no diary: exit 2"
assert_has "no daily-report block" "$OUT" "says why"
printf '# x\n\nnothing\n' >"$HARVEST_DIARY_DIR/2026-11-02.md"
run 2026-11-02
assert_eq 2 "$RC" "no block: exit 2"
assert_eq "" "$(cat "$SANDBOX/requests.log")" "no request at all"
printf '#!/bin/sh\nexit 1\n' >"$SANDBOX/secret"; chmod +x "$SANDBOX/secret"
OUT="$(env -u HARVEST_TOKEN HARVEST_SECRET_BIN="$SANDBOX/secret" "$SCRIPT" "$D" 2>&1)"; RC=$?
assert_eq 2 "$RC" "no token: exit 2"
assert_has "HARVEST_TOKEN" "$OUT" "names the missing secret"
assert_has "secrets" "$OUT" "and how to add it"
printf '#!/bin/sh\n[ "$1" = HARVEST_TOKEN ] && printf tok\n[ "$1" = HARVEST_ACCOUNT_ID ] && printf acc\n' >"$SANDBOX/secret"
state '{"wants_timestamp_timers":false}' '[]'
OUT="$(env -u HARVEST_TOKEN -u HARVEST_ACCOUNT_ID HARVEST_SECRET_BIN="$SANDBOX/secret" "$SCRIPT" "$D" 2>&1)"; RC=$?
assert_eq 0 "$RC" "credentials come from secret when the env has none"

echo "== errors =="
state '{"wants_timestamp_timers":false}' '[]'
HARVEST_PROJECT=nope run "$D"
assert_eq 1 "$RC" "unknown project: exit 1"
assert_has "ECFX" "$OUT" "lists the projects it has"
HARVEST_TOKEN=bad run "$D"
assert_eq 1 "$RC" "rejected token: exit 1"
assert_has "401" "$OUT" "shows the status"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
