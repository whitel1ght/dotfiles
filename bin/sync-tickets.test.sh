#!/bin/bash
# Tests for bin/sync-tickets. glab and curl are stubbed on PATH, so nothing
# here reaches GitLab or Jira; the curl stub logs every write it receives.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/sync-tickets"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_contains() {
    case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac
}
assert_lacks() {
    case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"
mkdir -p "$STUBS" "$FIX/issue"

mr() { # key-in-branch state draft repo iid
    printf '{"id":%s,"iid":%s,"state":"%s","draft":%s,"source_branch":"dmitry/%s_x","title":"t %s","web_url":"https://gitlab.com/ecfx/%s/-/merge_requests/%s","references":{"full":"ecfx/%s!%s"}}' \
        "$5$RANDOM" "$5" "$2" "$3" "$1" "$1" "$4" "$5" "$4" "$5"
}
issue() { # key status assignee
    printf '{"fields":{"status":{"name":"%s"},"assignee":%s}}' "$2" \
        "$([ -n "$3" ] && printf '{"accountId":"%s","displayName":"%s"}' "$3" "$3" || echo null)" > "$FIX/issue/$1"
}

# Recent window: a ticket to move (draft+ready → In MR), one whose MRs all
# merged (→ In QA), one already ahead (In QA but a draft reopened), one not
# mine, one in a status we never touch, and a To-Do that needs two steps.
cat > "$FIX/recent.json" <<EOF
[$(mr ECFX-1 opened true backend 10),$(mr ECFX-1 opened false dashboard 20),
 $(mr ECFX-2 merged false backend 11),
 $(mr ECFX-3 opened true backend 12),
 $(mr ECFX-4 opened false backend 13),
 $(mr ECFX-5 opened false backend 14),
 $(mr ECFX-6 opened false backend 15),
 $(mr ECFX-7 merged false backend 16),
 {"id":98,"iid":98,"state":"merged","draft":false,"source_branch":"dmitry/ECFX-8_x","title":"ECFX-8: \"Retrieve again\" row action","web_url":"https://gitlab.com/ecfx/backend/-/merge_requests/17","references":{"full":"ecfx/backend!17"}},
 {"id":99,"iid":99,"state":"opened","draft":false,"source_branch":"no-key","title":"chore","web_url":"u","references":{"full":"ecfx/backend!99"}}]
EOF
# ECFX-8's MR title carries quotes, tabs and a backslash: ECFX-17417's real title was
# 'ECFX-17417: "Retrieve again" row action in the Retrieve list', which is what made the
# plan's tab-separated encoding corrupt that row. A title must survive the plan -> loop
# -> link-title round trip verbatim, or the ticket is silently skipped or mislabelled.
# ECFX-7 merged in the window but still has an older open MR: stays In MR.
echo "[$(mr ECFX-7 opened false dashboard 30)]" > "$FIX/open.json"

issue ECFX-1 "In Progress" me
issue ECFX-2 "In MR" me
issue ECFX-3 "In QA" me
issue ECFX-4 "In Progress" someone
issue ECFX-5 "Rejected Incomplete" me
issue ECFX-6 "To-Do" me
issue ECFX-7 "In Progress" me
issue ECFX-8 "In Progress" me

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
case "$*" in
    *state=all*) cat "$FIX/recent.json" ;;
    *state=opened*) cat "$FIX/open.json" ;;
esac
EOF

# Minimal Jira: status lives in a file per issue so transitions stick.
cat > "$STUBS/curl" <<'EOF'
#!/bin/bash
method=GET data="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -X) method="$2"; shift ;;
        --data) data="$2"; shift ;;
        -u|-H|-w) shift ;;
        http*) url="$1" ;;
    esac
    shift
done
path="${url#*atlassian.net}"
[ "$method" = GET ] || echo "$method $path $data" >> "$FIX/writes.log"
[ -n "${JIRA_FAIL:-}" ] && { printf '{}\n401'; exit 0; }
key=$(echo "$path" | sed -nE 's#.*/issue/([A-Z]+-[0-9]+).*#\1#p')
case "$method $path" in
    "GET /rest/api/3/myself") printf '{"accountId":"me"}' ;;
    "GET "*/transitions)
        case "$(jq -r .fields.status.name "$FIX/issue/$key")" in
            To-Do) printf '{"transitions":[{"id":"11","to":{"name":"In Progress"}},{"id":"31","to":{"name":"In QA"}}]}' ;;
            *) printf '{"transitions":[{"id":"11","to":{"name":"In Progress"}},{"id":"21","to":{"name":"In MR"}},{"id":"31","to":{"name":"In QA"}}]}' ;;
        esac ;;
    "POST "*/transitions)
        to=$(echo "$data" | jq -r '{"11":"In Progress","21":"In MR","31":"In QA"}[.transition.id]')
        jq --arg s "$to" '.fields.status.name = $s' "$FIX/issue/$key" > "$FIX/tmp" && mv "$FIX/tmp" "$FIX/issue/$key"
        printf '' ;;
    "GET "*/remotelink)
        [ "$key" = ECFX-1 ] && printf '[{"object":{"url":"https://gitlab.com/ecfx/dashboard/-/merge_requests/20"}}]' || printf '[]' ;;
    "POST "*/remotelink) printf '{"id":1}' ;;
    "GET "*) cat "$FIX/issue/$key" ;;
esac
printf '\n%s' "$([ "$method" = POST ] && [ "${path##*/}" = transitions ] && echo 204 || echo 200)"
EOF
chmod +x "$STUBS/glab" "$STUBS/curl"

run() {
    PATH="$STUBS:$PATH" FIX="$FIX" JIRA_EMAIL=e JIRA_API_TOKEN=t \
    SYNC_TICKETS_STATE="$SANDBOX/state/last-run" "$SCRIPT" "$@" 2>&1
}
status_of() { jq -r .fields.status.name "$FIX/issue/$1"; }

echo "sync-tickets — dry run"
out="$(run -n -v --since 1d)"
assert_contains "$out" "would  ECFX-1 In Progress → In MR" "ready MR beside a draft means In MR"
assert_contains "$out" "would  ECFX-2 In MR → In QA" "all merged means In QA"
assert_contains "$out" "behind ECFX-3 is In QA, MRs say In Progress" "reports a ticket ahead of its MRs"
assert_contains "$out" "skip   ECFX-4 — assigned to someone" "skips tickets not assigned to me"
assert_contains "$out" "skip   ECFX-5 — Rejected Incomplete is left alone" "skips unmanaged statuses"
assert_lacks "$out" "ECFX-7 In Progress → In QA" "an older open MR keeps the ticket out of QA"
assert_contains "$out" "would  ECFX-7 In Progress → In MR" "judges a ticket on MRs outside the window too"
# The regression this file exists for: a title with quotes/tabs/backslash must not corrupt
# the row it travels in. Before the fix this row died with "jq: parse error: Invalid numeric
# literal", which aborted the whole run partway and left Jira half-written.
assert_contains "$out" "would  ECFX-8 In Progress → In QA" "an MR title with quotes and tabs still moves its ticket"
assert_contains "$out" "backend!17" "the awkward title still yields its ref"
assert_lacks "$out" "link ECFX-1 ← dashboard!20" "does not re-link an MR already on the ticket"
assert_contains "$out" "would  link ECFX-1 ← backend!10" "links an MR missing from the ticket"
[ -e "$FIX/writes.log" ] && fail "dry run writes nothing" "$(cat "$FIX/writes.log")" || pass "dry run writes nothing"
[ -e "$SANDBOX/state/last-run" ] && fail "dry run leaves the state file alone" "written" \
    || pass "dry run leaves the state file alone"

echo "sync-tickets — apply"
out="$(run --since 1d)"
[ "$(status_of ECFX-1)" = "In MR" ] && pass "moves ECFX-1 to In MR" || fail "moves ECFX-1 to In MR" "$(status_of ECFX-1)"
[ "$(status_of ECFX-6)" = "In MR" ] && pass "takes To-Do to In MR via In Progress" \
    || fail "takes To-Do to In MR via In Progress" "$(status_of ECFX-6)"
[ "$(status_of ECFX-3)" = "In QA" ] && pass "never moves a ticket backwards" || fail "never moves a ticket backwards" "$(status_of ECFX-3)"
[ "$(status_of ECFX-8)" = "In QA" ] && pass "an awkward MR title does not abort the run" || fail "an awkward MR title does not abort the run" "$(status_of ECFX-8)"
# The link title goes to Jira verbatim, so it has to come back out of the plan unmangled.
# Asserted on the title alone: the payload is JSON, so the quotes arrive escaped there and
# matching on the escaped form is what actually proves nothing was mangled in transit.
assert_contains "$(cat "$FIX/writes.log")" 'backend!17 — ECFX-8: \"Retrieve again\" row action' \
    "a link title carrying quotes and tabs reaches Jira intact"
[ "$(status_of ECFX-4)" = "In Progress" ] && pass "leaves others' tickets alone" || fail "leaves others' tickets alone" "$(status_of ECFX-4)"
links="$(grep -c 'remotelink' "$FIX/writes.log")"
[ "$links" -gt 0 ] && pass "posts remote links" || fail "posts remote links" "none"
assert_contains "$(cat "$FIX/writes.log")" '"globalId":"gitlab-mr-backend-10"' "uses GitLab's globalId so links upsert"
[ -s "$SANDBOX/state/last-run" ] && pass "records the run for next time" || fail "records the run for next time" "no state file"

echo "sync-tickets — expired token"
out="$(JIRA_FAIL=1 run --since 1d)"; rc=$?
assert_contains "$out" "JIRA_API_TOKEN has likely expired" "names the likely cause of a 401"
[ "$rc" -ne 0 ] && pass "exits non-zero" || fail "exits non-zero" "rc=0"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
