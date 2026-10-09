#!/bin/bash
# Tests for bin/changes-since. jira-api and glab are fake binaries on PATH that
# answer from fixture files, so nothing here reaches Jira or GitLab. TZ is
# pinned to UTC; the cursor is written by hand, so no test depends on the clock.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/changes-since"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"; STATE="$SANDBOX/state"
mkdir -p "$STUBS"

# jira-api <METHOD> <path> [body]: picks the fixture by what the JQL asks for.
cat > "$STUBS/jira-api" <<'STUB'
#!/bin/bash
echo "$*" >> "${FIX:?}/jira.log"
[ -n "${JIRA_DOWN:-}" ] && { echo '{"errorMessages":["Unauthorized"]}'; exit 0; }
case "$3" in
    *"CHANGED TO currentUser()"*) cat "$FIX/jira-assigned.json" ;;
    *) cat "$FIX/jira-updated.json" ;;
esac
STUB
chmod +x "$STUBS/jira-api"

reset() {
  rm -rf "$FIX" "$STATE"; mkdir -p "$FIX" "$STATE"
  echo '{"issues":[],"isLast":true}' > "$FIX/jira-assigned.json"
  echo '{"issues":[],"isLast":true}' > "$FIX/jira-updated.json"
}
cursor() { printf '%s\n' "$1" > "$STATE/${2:-default}"; }
run() { (TZ=UTC PATH="$STUBS:$PATH" FIX="$FIX" CHANGES_SINCE_STATE="$STATE" "$SCRIPT" "$@" 2>"$SANDBOX/stderr"); }
errs() { cat "$SANDBOX/stderr"; }

# search/jql issue: only the requested fields come back; updated is in the
# Jira user's offset with a "+0300" style zone.
issue() { # key summary status updated
  printf '{"id":"1","key":"%s","fields":{"summary":"%s","status":{"name":"%s"},"updated":"%s"}}' "$1" "$2" "$3" "$4"
}
issues() { printf '{"issues":[%s],"isLast":true}\n' "$1"; }

echo "changes-since — Jira"
reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-9190 "Retry button" "In Progress" "2026-10-08T10:12:33.123+0300"),$(issue ECFX-1 "Old news" "To-Do" "2026-10-08T09:30:00.000+0300")" > "$FIX/jira-updated.json"
issues "$(issue ECFX-18200 "Layout" "To-Do" "2026-10-08T10:20:00.000+0300")" > "$FIX/jira-assigned.json"
out=$(run); rc=$?
assert_eq "0" "$rc" "exit 0"
assert_eq "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "two events: the one updated before the cursor is dropped even though the minute-granular JQL returned it"
assert_eq '{"kind":"ticket_updated","project":"ecfx","ticket":"ECFX-9190","mr":null,"repo":null,"summary":"Retry button [In Progress]","url":"https://ecfxdev.atlassian.net/browse/ECFX-9190","at":"2026-10-08T07:12:33Z"}' "$(sed -n 1p <<<"$out")" "ticket_updated line: keys in contract order, +0300 converted to UTC, fraction dropped"
assert_eq '{"kind":"assigned","project":"ecfx","ticket":"ECFX-18200","mr":null,"repo":null,"summary":"Layout [To-Do]","url":"https://ecfxdev.atlassian.net/browse/ECFX-18200","at":"2026-10-08T07:20:00Z"}' "$(sed -n 2p <<<"$out")" "assigned line"
assert_contains "$(cat "$FIX/jira.log")" "assignee CHANGED TO currentUser() AFTER \\\"2026/10/08 07:00\\\"" "assigned query uses the cursor, minute granularity"
assert_contains "$(cat "$FIX/jira.log")" "watcher = currentUser()" "updated query covers assignee, reporter and watcher"
assert_contains "$(cat "$FIX/jira.log")" "POST search/jql" "goes through jira-api POST search/jql"

reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-18200 "Layout" "To-Do" "2026-10-08T10:20:00.000+0300")" > "$FIX/jira-assigned.json"
issues "$(issue ECFX-18200 "Layout" "To-Do" "2026-10-08T10:20:00.000+0300")" > "$FIX/jira-updated.json"
out=$(run)
assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "a newly assigned ticket that also shows as updated is one event"
assert_eq "assigned" "$(jq -r .kind <<<"$out")" "and it is the assigned one"

reset; cursor 2026-10-08T07:00:00Z
issues "$(issue OTHER-5 "Elsewhere" "To-Do" "2026-10-08T10:20:00.000+0300")" > "$FIX/jira-updated.json"
assert_eq "null" "$(run | jq -r .project)" "a key outside \$JIRA_PROJECT has project null"

reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-7 "Zulu" "To-Do" "2026-10-08T07:30:00.000Z")" > "$FIX/jira-updated.json"
assert_eq "2026-10-08T07:30:00Z" "$(run | jq -r .at)" "a Z timestamp is accepted as is"

reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-8 "On the dot" "To-Do" "2026-10-08T10:00:00.000+0300")" > "$FIX/jira-updated.json"
assert_eq "ECFX-8" "$(run | jq -r .ticket)" "an event exactly at the cursor is included (>=, so nothing is lost at the boundary)"

echo "changes-since — nothing changed"
reset; cursor 2026-10-08T07:00:00Z
out=$(run); rc=$?
assert_eq "0" "$rc" "exit 0 when nothing changed"
assert_eq "" "$out" "and no output at all"
assert_eq "yes" "$([ "$(cat "$STATE/default")" != 2026-10-08T07:00:00Z ] && echo yes || echo no)" "the cursor still advances"

echo "changes-since — cursor"
reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-9190 "Retry" "To-Do" "2026-10-08T10:12:33.000+0300")" > "$FIX/jira-updated.json"
run >/dev/null
new=$(cat "$STATE/default")
assert_eq "yes" "$([[ "$new" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$new" > 2026-10-08T07:00:00Z ]] && echo yes || echo no)" "advances to this run's start time, a UTC ISO timestamp"
assert_eq "" "$(run)" "the next run does not repeat the event"

reset; cursor 2026-10-08T07:00:00Z
issues "$(issue ECFX-9190 "Retry" "To-Do" "2026-10-08T10:12:33.000+0300")" > "$FIX/jira-updated.json"
out=$(run --peek)
assert_eq "ECFX-9190" "$(jq -r .ticket <<<"$out")" "--peek prints events"
assert_eq "2026-10-08T07:00:00Z" "$(cat "$STATE/default")" "--peek leaves the cursor alone"

reset; cursor 2026-10-08T07:00:00Z; cursor 2026-10-08T09:00:00Z run-day
issues "$(issue ECFX-9190 "Retry" "To-Do" "2026-10-08T10:12:33.000+0300")" > "$FIX/jira-updated.json"
assert_eq "" "$(run --cursor run-day)" "--cursor NAME reads that cursor (event is before 09:00Z)"
assert_eq "ECFX-9190" "$(run | jq -r .ticket)" "the default cursor is separate and still sees it"
assert_eq "yes" "$([ "$(cat "$STATE/default")" != 2026-10-08T07:00:00Z ] && [ -s "$STATE/run-day" ] && echo yes || echo no)" "each cursor file moves on its own"

reset
issues "$(issue ECFX-1 "Today" "To-Do" "$(date -u +%Y-%m-%dT%H:%M:%S).000+0000")" > "$FIX/jira-updated.json"
out=$(run)
assert_eq "ECFX-1" "$(jq -r .ticket <<<"$out")" "no cursor file: starts at local midnight, so today's change shows"
assert_eq "yes" "$([ -s "$STATE/default" ] && echo yes || echo no)" "and the cursor file is created"

reset; echo 'garbage' > "$STATE/default"
run >/dev/null; assert_eq "1" "$?" "a corrupt cursor file is an error"
assert_contains "$(errs)" "not a UTC timestamp" "that says what is wrong"
assert_eq "garbage" "$(cat "$STATE/default")" "and is left for me to look at"

echo "changes-since — errors never move the cursor"
reset; cursor 2026-10-08T07:00:00Z
out=$(JIRA_DOWN=1 run); rc=$?
assert_eq "1" "$rc" "Jira error body: exit 1"
assert_eq "" "$out" "nothing on stdout"
assert_contains "$(errs)" "Jira unavailable" "stderr names the failing source"
assert_eq "2026-10-08T07:00:00Z" "$(cat "$STATE/default")" "cursor unchanged"

echo "changes-since — arguments"
run --bogus >/dev/null; assert_eq "1" "$?" "unknown option is an error"
run --cursor >/dev/null; assert_eq "1" "$?" "--cursor without a name is an error"
run --cursor '../x' >/dev/null; assert_eq "1" "$?" "a cursor name cannot escape the state dir"

# --- gitlab tests ---

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
