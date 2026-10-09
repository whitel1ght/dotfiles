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

# glab api [--paginate] <endpoint>: one fixture per endpoint, named after
# project id and MR iid; GLAB_FAIL=<substring> makes matching calls fail.
cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
echo "$*" >> "${FIX:?}/glab.log"
[ -n "${GLAB_FAIL:-}" ] && case "$*" in *"$GLAB_FAIL"*) exit 1 ;; esac
case "$*" in
    "api user") echo '{"username":"me"}' ;;
    *todos*) cat "$FIX/todos.json" ;;
    *"merge_requests?scope=created_by_me"*) cat "$FIX/mrs.json" ;;
    *projects/*/merge_requests/*/notes*)
        id=$(sed -E 's#.*projects/([0-9]+)/merge_requests/([0-9]+)/.*#\1-\2#' <<<"$*"); cat "$FIX/notes-$id.json" ;;
    *projects/*/merge_requests/*/pipelines*)
        id=$(sed -E 's#.*projects/([0-9]+)/merge_requests/([0-9]+)/.*#\1-\2#' <<<"$*"); cat "$FIX/pipelines-$id.json" ;;
    *projects/*/merge_requests/*)
        id=$(sed -E 's#.*projects/([0-9]+)/merge_requests/([0-9]+).*#\1-\2#' <<<"$*"); cat "$FIX/detail-$id.json" ;;
    *) echo '{}' ;;
esac
STUB
chmod +x "$STUBS/glab"

reset() {
  rm -rf "$FIX" "$STATE"; mkdir -p "$FIX" "$STATE"
  echo '{"issues":[],"isLast":true}' > "$FIX/jira-assigned.json"
  echo '{"issues":[],"isLast":true}' > "$FIX/jira-updated.json"
  echo '[]' > "$FIX/todos.json"; echo '[]' > "$FIX/mrs.json"
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

echo
echo "changes-since — GitLab to-dos"
reset; cursor 2026-10-08T07:00:00Z
cat > "$FIX/todos.json" <<'JSON'
[{"id":1,"project":{"id":2,"path_with_namespace":"ecfx/ecfx-dashboard"},"author":{"username":"bkeeling"},"action_name":"review_submitted","target_type":"MergeRequest","target":{"iid":2224,"title":"ECFX-9190 retry button","source_branch":"dmitry/ECFX-9190_retry","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2224"},"target_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2224#note_1","body":"four items","state":"pending","created_at":"2026-10-08T07:30:00.500Z"},
 {"id":2,"project":{"id":2,"path_with_namespace":"ecfx/ecfx-dashboard"},"author":{"username":"smtsuchi"},"action_name":"mentioned","target_type":"MergeRequest","target":{"iid":2227,"title":"Notice case number","source_branch":"smtsuchi/ECFX-6659","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2227"},"target_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2227#note_2","body":"@dmitry thoughts?","state":"pending","created_at":"2026-10-08T07:40:00.000Z"},
 {"id":3,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"travisECFX"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6538,"title":"gitleaks","source_branch":"travis/gitleaks","web_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6538"},"target_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6538","body":"gitleaks","state":"pending","created_at":"2026-10-08T07:50:00.000Z"},
 {"id":4,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"me"},"action_name":"build_failed","target_type":"MergeRequest","target":{"iid":6576,"title":"names","source_branch":"dmitry/ECFX-9190_be","web_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576"},"target_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576/pipelines/9","body":"names","state":"pending","created_at":"2026-10-08T06:00:00.000Z"},
 {"id":5,"project":{"id":9,"path_with_namespace":"epicmax/site"},"author":{"username":"x"},"action_name":"marked","target_type":"Issue","target":{"iid":3,"title":"Site copy","web_url":"https://gitlab.com/epicmax/site/-/issues/3"},"target_url":"https://gitlab.com/epicmax/site/-/issues/3","body":"Site copy","state":"pending","created_at":"2026-10-08T08:00:00.000Z"}]
JSON
out=$(run)
assert_eq "4" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "four to-dos at or after the cursor; the 06:00 one is older"
assert_eq '{"kind":"review","project":"ecfx","ticket":"ECFX-9190","mr":2224,"repo":"ecfx-dashboard","summary":"@bkeeling review submitted: ECFX-9190 retry button","url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2224#note_1","at":"2026-10-08T07:30:00Z"}' "$(sed -n 1p <<<"$out")" "review_submitted -> review; ticket from the branch; repo is the last path segment"
assert_eq "mention" "$(sed -n 2p <<<"$out" | jq -r .kind)" "mentioned -> mention"
assert_eq "assigned" "$(sed -n 3p <<<"$out" | jq -r .kind)" "review_requested -> assigned"
assert_eq "null" "$(sed -n 3p <<<"$out" | jq -r .ticket)" "no key in branch or title -> ticket null"
assert_eq '{"kind":"mention","project":null,"ticket":null,"mr":null,"repo":"site","summary":"@x marked: Site copy","url":"https://gitlab.com/epicmax/site/-/issues/3","at":"2026-10-08T08:00:00Z"}' "$(sed -n 4p <<<"$out")" "an issue to-do: other namespace -> project null, mr null, unknown action -> mention"
assert_contains "$(cat "$FIX/glab.log")" "todos?state=pending" "asks for pending to-dos"

echo "changes-since — my MRs"
reset; cursor 2026-10-08T07:00:00Z
echo '[{"id":10,"iid":2231,"project_id":2,"title":"ECFX-18169 majors","state":"opened","updated_at":"2026-10-08T08:00:00.000Z","references":{"full":"ecfx/ecfx-dashboard!2231"}},
 {"id":11,"iid":6576,"project_id":3,"title":"ECFX-9190 names","state":"merged","updated_at":"2026-10-08T08:30:00.000Z","references":{"full":"ecfx/ecfx-backend!6576"}}]' > "$FIX/mrs.json"
echo '{"iid":2231,"title":"ECFX-18169 majors","state":"opened","merged_at":null,"source_branch":"dmitry/ECFX-18169_x","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231","references":{"full":"ecfx/ecfx-dashboard!2231"},"head_pipeline":{"id":51,"status":"failed","updated_at":"2026-10-08T08:05:00.000Z","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/pipelines/51"}}' > "$FIX/detail-2-2231.json"
echo '[{"id":3,"type":"DiffNote","system":false,"body":"nit","author":{"username":"bkeeling"},"created_at":"2026-10-08T07:10:00.000Z"},
 {"id":4,"type":"DiffNote","system":false,"body":"bug","author":{"username":"smtsuchi"},"created_at":"2026-10-08T07:20:00.000Z"},
 {"id":5,"type":null,"system":false,"body":"thanks","author":{"username":"bkeeling"},"created_at":"2026-10-08T07:25:00.000Z"},
 {"id":6,"type":null,"system":false,"body":"my own reply","author":{"username":"me"},"created_at":"2026-10-08T07:30:00.000Z"},
 {"id":7,"type":null,"system":true,"body":"approved this merge request","author":{"username":"smtsuchi"},"created_at":"2026-10-08T07:40:00.000Z"},
 {"id":8,"type":null,"system":true,"body":"added 2 commits","author":{"username":"me"},"created_at":"2026-10-08T07:45:00.000Z"},
 {"id":9,"type":null,"system":false,"body":"before the cursor","author":{"username":"bkeeling"},"created_at":"2026-10-08T06:00:00.000Z"}]' > "$FIX/notes-2-2231.json"
echo '{"iid":6576,"title":"ECFX-9190 names","state":"merged","merged_at":"2026-10-08T08:30:00.000Z","source_branch":"dmitry/ECFX-9190_be","web_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576","references":{"full":"ecfx/ecfx-backend!6576"},"head_pipeline":{"id":40,"status":"success","updated_at":"2026-10-08T07:50:00.000Z"}}' > "$FIX/detail-3-6576.json"
echo '[]' > "$FIX/notes-3-6576.json"
out=$(run)
dash() { jq -c "select(.mr == 2231 and .kind == \"$1\")" <<<"$out"; }
assert_eq "5" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "review, comment, approved, pipeline_failed on !2231 plus merged on !6576 (and no pipeline_fixed: that one was never red)"
assert_eq '{"kind":"review","project":"ecfx","ticket":"ECFX-18169","mr":2231,"repo":"ecfx-dashboard","summary":"@bkeeling, @smtsuchi: 2 inline comment(s) on ECFX-18169 majors","url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231","at":"2026-10-08T07:20:00Z"}' "$(dash review)" "inline diff notes from others collapse into one review event at the latest note"
assert_eq "2026-10-08T07:25:00Z" "$(dash comment | jq -r .at)" "plain notes from others are a comment event; my own note and the pre-cursor one are not counted"
assert_eq "@bkeeling" "$(dash comment | jq -r '.summary | split(" ")[0] | rtrimstr(":")')" "only the other person is named"
assert_eq "2026-10-08T07:40:00Z" "$(dash approved | jq -r .at)" "the system note 'approved this merge request' is an approval; my own 'added commits' note is not"
assert_eq "2026-10-08T08:05:00Z" "$(dash pipeline_failed | jq -r .at)" "failed head pipeline updated after the cursor"
assert_eq "merged" "$(jq -r 'select(.mr == 6576) | .kind' <<<"$out")" "a merged MR is a merged event (its green pipeline is not reported)"
assert_eq "2026-10-08T08:30:00Z" "$(jq -r 'select(.mr == 6576) | .at' <<<"$out")" "at is merged_at"
assert_eq "$(jq -s -r 'map(.at) | sort | join(",")' <<<"$out")" "$(jq -s -r 'map(.at) | join(",")' <<<"$out")" "events are sorted by at"
assert_contains "$(cat "$FIX/glab.log")" "updated_after=2026-10-08T07:00:00Z" "MRs are filtered by the cursor"
assert_contains "$(cat "$FIX/glab.log")" "scope=created_by_me" "only my MRs"

reset; cursor 2026-10-08T07:00:00Z
echo '[{"id":10,"iid":2231,"project_id":2,"title":"t","state":"opened","references":{"full":"ecfx/ecfx-dashboard!2231"}}]' > "$FIX/mrs.json"
echo '{"iid":2231,"title":"ECFX-18169 majors","state":"opened","merged_at":null,"source_branch":"b","web_url":"u","references":{"full":"ecfx/ecfx-dashboard!2231"},"head_pipeline":{"id":52,"status":"success","updated_at":"2026-10-08T09:00:00.000Z"}}' > "$FIX/detail-2-2231.json"
echo "[]" > "$FIX/notes-2-2231.json"
echo '[{"id":52,"status":"success","updated_at":"2026-10-08T09:00:00.000Z"},{"id":51,"status":"failed","updated_at":"2026-10-08T08:05:00.000Z"}]' > "$FIX/pipelines-2-2231.json"
out=$(run)
assert_eq "pipeline_fixed" "$(jq -r .kind <<<"$out")" "green head pipeline right after a red one is pipeline_fixed"
assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "and only that"
echo '[{"id":52,"status":"success","updated_at":"2026-10-08T09:00:00.000Z"},{"id":50,"status":"success","updated_at":"2026-10-08T06:00:00.000Z"}]' > "$FIX/pipelines-2-2231.json"
assert_eq "" "$(run)" "green after green is nothing"

echo "changes-since — merging the feeds"
reset; cursor 2026-10-08T07:00:00Z
echo '[{"id":1,"project":{"path_with_namespace":"ecfx/ecfx-dashboard"},"author":{"username":"bkeeling"},"action_name":"review_submitted","target_type":"MergeRequest","target":{"iid":2231,"title":"ECFX-18169 majors","source_branch":"b","web_url":"u"},"target_url":"u#n","body":"b","created_at":"2026-10-08T07:30:00.000Z"}]' > "$FIX/todos.json"
echo '[{"id":10,"iid":2231,"project_id":2,"references":{"full":"ecfx/ecfx-dashboard!2231"}}]' > "$FIX/mrs.json"
echo '{"iid":2231,"title":"ECFX-18169 majors","state":"opened","source_branch":"b","web_url":"u","references":{"full":"ecfx/ecfx-dashboard!2231"},"head_pipeline":null}' > "$FIX/detail-2-2231.json"
echo '[{"id":3,"type":"DiffNote","system":false,"body":"x","author":{"username":"bkeeling"},"created_at":"2026-10-08T07:35:00.000Z"}]' > "$FIX/notes-2-2231.json"
out=$(run)
assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "a to-do and a note feed describing the same review are one event per kind per MR"
assert_eq "2026-10-08T07:35:00Z" "$(jq -r .at <<<"$out")" "the latest one wins"

echo "changes-since — a GitLab failure never moves the cursor"
reset; cursor 2026-10-08T07:00:00Z
echo '[{"id":10,"iid":2231,"project_id":2,"references":{"full":"ecfx/ecfx-dashboard!2231"}}]' > "$FIX/mrs.json"
issues "$(issue ECFX-9190 "Retry" "To-Do" "2026-10-08T10:12:33.000+0300")" > "$FIX/jira-updated.json"
out=$(GLAB_FAIL='todos' run); rc=$?
assert_eq "1" "$rc" "to-dos endpoint fails: exit 1"
assert_eq "" "$out" "nothing printed, not even the Jira event that did work"
assert_contains "$(errs)" "GitLab to-dos unavailable" "stderr names the source"
assert_eq "2026-10-08T07:00:00Z" "$(cat "$STATE/default")" "cursor unchanged"
out=$(GLAB_FAIL='merge_requests/2/' run); rc=$?
assert_eq "1" "$rc" "a per-MR call fails: exit 1"
assert_eq "" "$out" "nothing printed"
assert_eq "2026-10-08T07:00:00Z" "$(cat "$STATE/default")" "cursor unchanged"
out=$(GLAB_FAIL='merge_requests/2/' run --peek); assert_eq "1" "$?" "--peek fails the same way"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
