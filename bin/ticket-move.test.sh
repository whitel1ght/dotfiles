#!/bin/bash
# Tests for bin/ticket-move. glab and curl are stubbed on PATH, so nothing here reaches
# GitLab or Jira; Jira keeps each issue's status in a file so transitions stick.
set -uo pipefail
export SECRETS_FILE=/nonexistent/secrets.env

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/ticket-move"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"
mkdir -p "$STUBS" "$FIX/issue"

mr() { # key state draft iid
    printf '{"id":%s,"iid":%s,"state":"%s","draft":%s,"source_branch":"dmitry/%s_x","title":"t","references":{"full":"ecfx/ecfx-backend!%s"}}' \
        "$4" "$4" "$2" "$3" "$1" "$4"
}
issue() { # key status assignee [type]
    printf '{"fields":{"status":{"name":"%s"},"assignee":%s,"issuetype":{"name":"%s"},"customfield_10604":null}}' "$2" \
        "$([ -n "$3" ] && printf '{"accountId":"%s","displayName":"%s"}' "$3" "$3" || echo null)" "${4:-Task}" > "$FIX/issue/$1"
}

# ECFX-30: a draft and a ready MR open. ECFX-31: all merged. ECFX-32: one merged, one
# draft still open. ECFX-310 shares a prefix with ECFX-31 and must not count for it.
echo "[$(mr ECFX-30 opened true 1),$(mr ECFX-30 opened false 2),$(mr ECFX-32 opened true 5),$(mr ECFX-310 opened false 6)]" > "$FIX/open.json"
echo "[$(mr ECFX-31 merged false 3),$(mr ECFX-32 merged false 4)]" > "$FIX/merged.json"

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
case "$*" in
    *state=opened*) cat "$FIX/open.json" ;;
    *state=merged*) cat "$FIX/merged.json" ;;
esac
EOF

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
key=$(echo "$path" | sed -nE 's#.*/issue/([A-Z]+-[0-9]+).*#\1#p')
case "$method $path" in
    "GET /rest/api/3/myself") printf '{"accountId":"me"}' ;;
    "GET "*/transitions)
        case "$(jq -r .fields.status.name "$FIX/issue/$key")" in
            To-Do) printf '{"transitions":[{"id":"11","to":{"name":"In Progress"}}]}' ;;
            "In Progress") printf '{"transitions":[{"id":"21","to":{"name":"In MR"}}]}' ;;
            "In MR") printf '{"transitions":[{"id":"31","to":{"name":"In QA"}},{"id":"25","to":{"name":"Ready for QA"}}]}' ;;
            *) printf '{"transitions":[]}' ;;
        esac ;;
    "POST "*/transitions)
        to=$(echo "$data" | jq -r '{"11":"In Progress","21":"In MR","25":"Ready for QA","31":"In QA"}[.transition.id]')
        jq --arg s "$to" '.fields.status.name = $s' "$FIX/issue/$key" > "$FIX/tmp" && mv "$FIX/tmp" "$FIX/issue/$key" ;;
    "GET "*) cat "$FIX/issue/$key" ;;
esac
printf '\n%s' "$([ "$method" = POST ] && echo 204 || echo 200)"
EOF
chmod +x "$STUBS/glab" "$STUBS/curl"

LOG="$SANDBOX/moves.log"
move() { PATH="$STUBS:$PATH" FIX="$FIX" JIRA_EMAIL=e JIRA_API_TOKEN=t TICKET_MOVE_LOG="$LOG" "$SCRIPT" "$@" 2>&1; }
status_of() { jq -r .fields.status.name "$FIX/issue/$1"; }

echo "ticket-move — work starts"
issue ECFX-1 To-Do me
out="$(move ecfx-1 "In Progress" -n)"
assert_contains "$out" "would  ECFX-1 To-Do → In Progress" "a dry run names the move (lower-case key accepted)"
assert_eq "To-Do" "$(status_of ECFX-1)" "a dry run moves nothing"
out="$(move ECFX-1 "In Progress" --by wt)"; rc=$?
assert_contains "$out" "moved  ECFX-1 To-Do → In Progress" "To-Do goes In Progress"
assert_eq 0 "$rc" "exits 0 after a move"
assert_contains "$(cat "$LOG")" "ECFX-1	To-Do	In Progress	wt" "the move is logged with who asked"
out="$(move ECFX-1 "In Progress")"
assert_eq "" "$out" "a second call is quiet: already there"
assert_contains "$(move ECFX-1 "In Progress" -v)" "ok     ECFX-1 — already In Progress" "-v says it is in step"

issue ECFX-2 "In MR" me
out="$(move ECFX-2 "In Progress")"
assert_eq "In MR" "$(status_of ECFX-2)" "work starting on an In MR ticket (a review round) moves nothing back"
assert_eq "" "$out" "and says nothing: not behind"

issue ECFX-3 To-Do someone
move ECFX-3 "In Progress" >/dev/null
assert_eq "To-Do" "$(status_of ECFX-3)" "someone else's ticket is left alone"
assert_contains "$(move ECFX-3 "In Progress" -v)" "skip   ECFX-3 — assigned to someone" "-v says why"
issue ECFX-4 To-Do ""
move ECFX-4 "In Progress" >/dev/null
assert_eq "To-Do" "$(status_of ECFX-4)" "an unassigned sprint ticket is left alone until it is taken"
issue ECFX-5 "Awaiting Details" me
move ECFX-5 "In Progress" >/dev/null
assert_eq "Awaiting Details" "$(status_of ECFX-5)" "a status outside the flow is left alone"

echo "ticket-move — MR goes ready"
issue ECFX-6 To-Do me
move ECFX-6 "In MR" >/dev/null
assert_eq "In MR" "$(status_of ECFX-6)" "To-Do reaches In MR through In Progress"

echo "ticket-move — judged on the MRs"
issue ECFX-30 "In Progress" me
assert_contains "$(move ECFX-30 --from-mrs)" "moved  ECFX-30 In Progress → In MR (ecfx-backend!1, ecfx-backend!2)" "an open ready MR means In MR"
issue ECFX-31 "In MR" me
assert_contains "$(move ECFX-31 --from-mrs)" "moved  ECFX-31 In MR → Ready for QA (ecfx-backend!3)" "all merged means Ready for QA; ECFX-310's MR does not count"
issue ECFX-32 "In Progress" me
move ECFX-32 --from-mrs >/dev/null
assert_eq "In Progress" "$(status_of ECFX-32)" "an open draft beside a merged MR keeps it In Progress"
issue ECFX-33 To-Do me
assert_eq "" "$(move ECFX-33 --from-mrs)" "no MR: nothing to judge"
assert_eq "To-Do" "$(status_of ECFX-33)" "and nothing moves"
issue ECFX-31 "In QA" me
assert_eq "" "$(move ECFX-31 --from-mrs)" "merged and already In QA is in step"
issue ECFX-30 "Ready for QA" me
assert_contains "$(move ECFX-30 --from-mrs)" "behind ECFX-30 is Ready for QA, MRs say In MR" "ahead of its MRs is reported, not moved"
assert_eq "Ready for QA" "$(status_of ECFX-30)" "and stays"

echo "ticket-move — a merged Bug without its summary"
issue ECFX-31 "In MR" me Bug
out="$(move ECFX-31 --from-mrs)"; rc=$?
assert_eq 3 "$rc" "exits 3"
assert_contains "$out" "wait   ECFX-31 — Bug needs a Resolution Summary" "says what it waits on"
assert_eq "In MR" "$(status_of ECFX-31)" "and stays"

echo "ticket-move — usage"
move ECFX-1 "In QA" >/dev/null; assert_eq 2 "$?" "In QA is never a target (QA moves it)"
move nonsense "In MR" >/dev/null; assert_eq 2 "$?" "a non-key is refused"
move ECFX-1 >/dev/null; assert_eq 2 "$?" "a target or --from-mrs is required"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
