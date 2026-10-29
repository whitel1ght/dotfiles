#!/bin/bash
# Tests for bin/start-day collect's "Ready to merge" section. glab is stubbed
# on PATH, so nothing here reaches GitLab; carry-over and Jira are pointed at
# an empty sandbox / disabled so only Ready to merge is under test.
set -uo pipefail
# Never fall back to the real secrets file (scripts read Jira credentials from it).
export SECRETS_FILE=/nonexistent/secrets.env

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/start-day"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"; STATE="$SANDBOX/state"; DIARY="$SANDBOX/diary"
# The outage marker (glab-gate) lives in the friction dir: keep it out of the real one.
export FRICTION_DIR="$SANDBOX/friction-state"
mkdir -p "$STUBS" "$FIX" "$STATE" "$DIARY"
# Never run the real repos-sync: it would fetch and fast-forward the repos in ~/projects.
printf '#!/bin/bash\n[ -z "${REPOS_SYNC_SILENT:-}" ] || exit 0\necho "- ecfx-dashboard: main fast-forwarded 2 commit(s)"\necho "9 GitLab repos: 1 updated, 8 up to date, 0 left alone, 0 failed"\n' >"$STUBS/repos-sync"
chmod +x "$STUBS/repos-sync"
export START_DAY_REPOS_SYNC="$STUBS/repos-sync"
# Nor the real team-plugins-sync: it would update the installed Claude plugins and run plink.
printf '#!/bin/bash\necho "- backend: 1.0.5 → 1.0.7"\necho "team plugins: 1 updated, 0 failed; pi skills regenerated; new sessions load them"\n' >"$STUBS/team-plugins-sync"
chmod +x "$STUBS/team-plugins-sync"
export START_DAY_TEAM_PLUGINS_SYNC="$STUBS/team-plugins-sync"
# A dummy, older diary entry: collect_carryover pipes ls through grep, and an
# empty DIARY_DIR (grep matches nothing) trips set -o pipefail and aborts the
# whole run. Real usage never hits this since ~/wiki/diary is never empty.
echo '### ECFX' > "$DIARY/2020-01-01.md"

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
FIX="${FIX:?}"
echo "$*" >> "$FIX/glab.log"
[ -n "${GLAB_DOWN:-}" ] && exit 1
case "$*" in
    "api user") echo '{"username":"me"}' ;;
    *todos*) cat "$FIX/todos.json" 2>/dev/null || echo '[]' ;;
    *merge_requests\?scope=created_by_me\&state=opened*) cat "$FIX/mrs.json" 2>/dev/null || echo '[]' ;;
    *merge_requests/*/approvals)
        echo "$*" >> "$FIX/approvals.log"
        [ -n "${APPROVALS_FAIL:-}" ] && exit 1
        id=$(echo "$*" | sed -E 's#.*projects/([^/]+)/merge_requests/([0-9]+)/approvals.*#\1-\2#')
        cat "$FIX/approvals-$id.json" 2>/dev/null || echo '{"approved_by":[]}' ;;
    *merge_requests/*/blocks)
        id=$(echo "$*" | sed -E 's#.*merge_requests/([0-9]+)/blocks.*#\1#')
        cat "$FIX/blocks-$id.json" 2>/dev/null || echo '[]' ;;
    *merge_requests/*)
        id=$(echo "$*" | sed -E 's#.*merge_requests/([0-9]+).*#\1#')
        n_file="$FIX/polls-$id"
        n=$(($(cat "$n_file" 2>/dev/null || echo 0) + 1)); echo "$n" > "$n_file"
        if [ -f "$FIX/polling-$id.json" ]; then
            i=$((n > $(jq length < "$FIX/polling-$id.json") ? $(jq length < "$FIX/polling-$id.json") : n))
            jq ".[$((i - 1))]" "$FIX/polling-$id.json"
        else
            cat "$FIX/detail-$id.json" 2>/dev/null || echo '{}'
        fi ;;
    *) echo '{}' ;;
esac
EOF
chmod +x "$STUBS/glab"

reset() { rm -rf "$FIX" "$STATE" "$FRICTION_DIR"; mkdir -p "$FIX" "$STATE"; }

# MRs deliberately carry no updated_at, so "My open MRs" treats them all as
# idle and never touches the notes endpoint our stub doesn't model.
mr() { # project_id iid ref title source_branch target_branch draft web_url
    printf '{"project_id":%s,"iid":%s,"references":{"full":"%s"},"title":"%s","source_branch":"%s","target_branch":"%s","draft":%s,"web_url":"%s"}' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}
detail() { printf '{"detailed_merge_status":"%s"}\n' "$1" > "$FIX/detail-$2.json"; }
blocks() { printf '%s\n' "$2" > "$FIX/blocks-$1.json"; }

run() {
    (unset JIRA_EMAIL JIRA_API_TOKEN
     PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" START_DAY_STATE="$STATE" START_DAY_POLL_DELAY=0 \
     START_DAY_REPO_ORDER="${TEST_REPO_ORDER:-}" "$SCRIPT" "$@" 2>&1)
}
ready() { printf '%s\n' "$1" | awk '/^## Ready to merge/{f=1;next} /^## /{if(f)exit} f'; }

echo "start-day — Ready to merge: merge now"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 2 700 "ecfx/ecfx-dashboard!700" "isolated fix" "dmitry/iso" "master" false "u700")]
EOF
detail mergeable 700
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "Merge now:" "has a Merge now heading"
assert_contains "$out" "- ecfx/ecfx-dashboard!700 isolated fix — u700" "lists the mergeable MR with ref, title, url"
assert_lacks "$out" "Merge in order:" "no chains, so that heading is skipped"
assert_lacks "$out" "Waiting on dependencies:" "no blocked MRs, so that heading is skipped"

echo "start-day — Ready to merge: stacked chain ordering"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 6419 "ecfx/ecfx-backend!6419" "base" "dmitry/ECFX-1_a" "master" false "u6419"),
 $(mr 1 6455 "ecfx/ecfx-backend!6455" "stacked on base" "dmitry/ECFX-1_b" "dmitry/ECFX-1_a" false "u6455")]
EOF
detail mergeable 6419
detail not_approved 6455
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-backend!6419 [mergeable] → ecfx/ecfx-backend!6455 [not_approved]" "orders the base before the MR stacked on it"
assert_lacks "$out" "Merge now:" "the chain head isn't also double-listed under Merge now"

echo "start-day — Ready to merge: same-ticket cross-repo ordering (admin waits on backend, not dashboard)"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 6390 "ecfx/ecfx-backend!6390" "ECFX-14576 backend" "dmitry/ECFX-14576_a" "master" false "u6390"),
 $(mr 2 2183 "ecfx/ecfx-dashboard!2183" "ECFX-14576 dashboard" "dmitry/ECFX-14576_d" "master" false "u2183"),
 $(mr 3 273 "ecfx/ecfx-admin!273" "ECFX-14576 admin" "dmitry/ECFX-14576_c" "master" false "u273")]
EOF
detail conflict 6390
detail conflict 2183
detail mergeable 273
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-admin!273 waits on ecfx/ecfx-backend!6390 (conflict)" "admin waits on the upstream backend MR"
assert_lacks "$out" "waits on ecfx/ecfx-dashboard!2183" "same-rank dashboard MR doesn't block admin"
assert_lacks "$out" "ecfx/ecfx-dashboard!2183 waits on" "dashboard has no dependency of its own either"

echo "start-day — Ready to merge: declared /blocks dependency"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 9000 "ecfx/ecfx-backend!9000" "blocker" "dmitry/blocker" "master" false "u9000"),
 $(mr 1 9001 "ecfx/ecfx-backend!9001" "blocked" "dmitry/blocked" "master" false "u9001")]
EOF
detail not_approved 9000
detail mergeable 9001
blocks 9001 '[{"blocking_merge_request":{"project_id":1,"iid":9000,"state":"opened"}}]'
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-backend!9001 waits on ecfx/ecfx-backend!9000 (not_approved)" "a declared /blocks dependency is honored"

echo "start-day — Ready to merge: declared /blocks dependency, blocker authored by someone else"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 2 9002 "ecfx/ecfx-dashboard!9002" "blocked by someone else" "dmitry/theirs" "master" false "u9002"),
 $(mr 2 9003 "ecfx/ecfx-dashboard!9003" "merged blocker ignored" "dmitry/ok" "master" false "u9003")]
EOF
detail mergeable 9002
detail mergeable 9003
blocks 9002 '[{"blocking_merge_request":{"project_id":9,"iid":555,"state":"opened","references":{"full":"other/repo!555"},"title":"not mine","draft":false}}]'
blocks 9003 '[{"blocking_merge_request":{"project_id":9,"iid":556,"state":"merged","references":{"full":"other/repo!556"},"title":"already landed","draft":false}}]'
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-dashboard!9002 waits on other/repo!555 (someone else's MR, opened)" "an open blocker owned by someone else still counts, with a distinct label"
merge_now_part=$(printf '%s\n' "$out" | awk '/^Merge now:/{f=1;next} /^$/{f=0} f')
assert_lacks "$merge_now_part" "!9002" "and it's excluded from Merge now while blocked"
assert_contains "$out" "Merge now:" "the MR with a merged (ignored) blocker has no open dependency left"
assert_contains "$out" "- ecfx/ecfx-dashboard!9003 merged blocker ignored — u9003" "so it's listed as merge now"

echo "start-day — Ready to merge: draft upstream blocking"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 8000 "ecfx/ecfx-backend!8000" "draft base" "dmitry/draftbase" "master" true "u8000"),
 $(mr 1 8001 "ecfx/ecfx-backend!8001" "stacked on draft" "dmitry/dep" "dmitry/draftbase" false "u8001")]
EOF
detail mergeable 8001
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-backend!8001 waits on ecfx/ecfx-backend!8000 (draft)" "a draft upstream still blocks its dependant, shown as (draft)"
assert_lacks "$out" "- ecfx/ecfx-backend!8000 " "the draft MR itself is never listed as its own line"
assert_lacks "$out" "u8000" "the draft MR's own line never appears"

echo "start-day — Ready to merge: checking is re-polled then resolved"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 500 "ecfx/ecfx-backend!500" "polling case" "dmitry/poll" "master" false "u500")]
EOF
echo '[{"detailed_merge_status":"checking"},{"detailed_merge_status":"checking"},{"detailed_merge_status":"mergeable"}]' > "$FIX/polling-500.json"
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-backend!500 polling case — u500" "re-polls past checking and lands on mergeable"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 1 600 "ecfx/ecfx-backend!600" "stuck" "dmitry/stuck" "master" false "u600")]
EOF
echo '[{"detailed_merge_status":"unchecked"},{"detailed_merge_status":"unchecked"},{"detailed_merge_status":"unchecked"},{"detailed_merge_status":"unchecked"}]' > "$FIX/polling-600.json"
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_lacks "$out" "!600" "gives up after 3 tries instead of treating it as mergeable"
polls=$(cat "$FIX/polls-600")
assert_eq 3 "$polls" "polls at most 3 times before reporting status pending"

echo "start-day — Ready to merge: START_DAY_REPO_ORDER override"
reset
cat > "$FIX/mrs.json" <<EOF
[$(mr 2 700 "ecfx/ecfx-dashboard!700" "ECFX-8000 dash" "dmitry/ECFX-8000_d" "master" false "u700"),
 $(mr 3 800 "ecfx/ecfx-admin!800" "ECFX-8000 adm" "dmitry/ECFX-8000_a" "master" false "u800")]
EOF
detail mergeable 700
detail conflict 800
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "Merge now:" "same-rank repos: dashboard has no dependency by default"
assert_contains "$out" "!700" "and it's listed as merge now"
TEST_REPO_ORDER="ecfx-protobufs ecfx-admin ecfx-backend"
out=$(ready "$(run collect --since 2026-09-20T00:00:00Z)")
assert_contains "$out" "ecfx/ecfx-dashboard!700 waits on ecfx/ecfx-admin!800 (conflict)" "override makes admin upstream of dashboard"
TEST_REPO_ORDER=

echo "start-day — GitLab failure doesn't abort collect"
reset
out=$(GLAB_DOWN=1 START_DAY_TRIAGE=/nonexistent run collect --since 2026-09-20T00:00:00Z)
assert_contains "$out" "## Ready to merge" "the section heading still prints"
assert_contains "$(ready "$out")" "(GitLab unavailable)" "Ready to merge reports GitLab unavailable"
assert_contains "$out" "## Review queue" "collect keeps running the rest of the digest"
assert_contains "$out" "## Team plugins" "including the final section"
# The best-effort merged-since lookup is not gated; the review-queue triage is a plugin script, switched off here.
gated() { grep -vc 'state=merged' "$FIX/glab.log"; }
assert_eq "1" "$(gated)" "the failing probe is tried once, no gated call behind it (the outage is held)"
out=$(START_DAY_TRIAGE=/nonexistent run collect --since 2026-09-20T00:00:00Z)
assert_contains "$(ready "$out")" "(GitLab unavailable)" "a run inside the 15-minute window prints GitLab unavailable"
assert_eq "1" "$(gated)" "and makes no probe, MR-list or to-dos call"
assert_eq "" "$(cat "$FRICTION_DIR"/*.jsonl 2>/dev/null | sed -n '2,$p')" "and logs no second service_down"
printf '%s\n' "$(($(date +%s) - 901))" > "$FRICTION_DIR/gitlab-down"
out=$(START_DAY_TRIAGE=/nonexistent run collect --since 2026-09-20T00:00:00Z)
[ "$(gated)" -gt 1 ] && pass "after the window GitLab is probed again" || fail "after the window GitLab is probed again" "$(gated) calls"
unset -f gated


echo "start-day — repos"
reset
out=$(run collect --since 2026-09-20T00:00:00Z)
repos=$(awk '/^## Repos/{f=1;next} /^## /{if(f)exit} f' <<<"$out" | sed '/./,$!d')
plugins=$(awk '/^## Team plugins/{f=1;next} /^## /{if(f)exit} f' <<<"$out" | sed '/./,$!d')
assert_eq "## Repos (fetched from GitLab)|## Team plugins" "$(grep '^## ' <<<"$out" | tail -2 | paste -sd '|' -)" "Repos, then Team plugins, printed last"
assert_contains "$repos" "- ecfx-dashboard: main fast-forwarded 2 commit(s)" "with what repos-sync printed"
assert_contains "$repos" "9 GitLab repos:" "and its summary"
assert_contains "$plugins" "- backend: 1.0.5 → 1.0.7" "and what team-plugins-sync printed"
assert_contains "$plugins" "team plugins: 1 updated" "with its summary"
cat >"$STUBS/order-repos" <<EOF
#!/bin/bash
sleep 1; echo repos >>"$SANDBOX/order"
EOF
printf '#!/bin/bash\necho plugins >>"%s/order"\n' "$SANDBOX" >"$STUBS/order-plugins"
chmod +x "$STUBS/order-repos" "$STUBS/order-plugins"; rm -f "$SANDBOX/order"
START_DAY_REPOS_SYNC="$STUBS/order-repos" START_DAY_TEAM_PLUGINS_SYNC="$STUBS/order-plugins" run collect --since 2026-09-20T00:00:00Z >/dev/null
assert_eq "repos plugins" "$(paste -sd ' ' - <"$SANDBOX/order")" "team plugins update only after repos-sync has moved the clone"
out=$(REPOS_SYNC_SILENT=1 run collect --since 2026-09-20T00:00:00Z)
assert_contains "$out" "(repos-sync printed nothing)" "an empty run says so"
out=$(START_DAY_REPOS_SYNC=/nonexistent/repos-sync START_DAY_TEAM_PLUGINS_SYNC=/nonexistent/team-plugins-sync run collect --since 2026-09-20T00:00:00Z)
assert_contains "$out" "## Jira" "a missing repos-sync or team-plugins-sync does not stop the digest"
assert_contains "$out" "## Team plugins" "and both sections still print"

todos() { awk '/^## GitLab to-dos/{f=1;next} /^## /{if(f)exit} f' <<<"$1" | sed '/./,$!d'; }

echo "start-day — GitLab to-dos"
reset
cat > "$FIX/todos.json" <<'JSON'
[{"id":2,"project":{"id":2,"path_with_namespace":"ecfx/ecfx-dashboard"},"author":{"username":"smtsuchi"},"action_name":"mentioned","target_type":"MergeRequest","target":{"iid":2227,"title":"Notice case number","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2227"},"target_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2227#note_2","body":"@dmitry thoughts?","created_at":"2026-10-08T07:40:00.000Z"},
 {"id":1,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"bkeeling"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6610,"title":"Delete Retrieve request","web_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6610"},"target_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6610","body":"Delete Retrieve request","created_at":"2026-10-08T06:00:00.000Z"},
 {"id":3,"project":{"id":9,"path_with_namespace":"epicmax/site"},"author":{"username":"x"},"action_name":"assigned","target_type":"Issue","target":{"iid":3,"title":"Site copy","web_url":"https://gitlab.com/epicmax/site/-/issues/3"},"target_url":"https://gitlab.com/epicmax/site/-/issues/3","body":"Site copy","created_at":"2026-10-08T08:00:00.000Z"}]
JSON
out=$(todos "$(run collect --since 2026-09-20T00:00:00Z)")
assert_eq "- [review requested] ecfx/ecfx-backend!6610 Delete Retrieve request — @bkeeling — https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6610
- [mentioned] ecfx/ecfx-dashboard!2227 Notice case number — @smtsuchi — https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2227#note_2
- [assigned] epicmax/site#3 Site copy — @x — https://gitlab.com/epicmax/site/-/issues/3" "$out" "one line per pending to-do, oldest first, MR as path!iid and issue as path#iid, with its url"
echo '[]' > "$FIX/todos.json"
assert_eq "(none)" "$(todos "$(run collect --since 2026-09-20T00:00:00Z)")" "no to-dos prints (none)"
out=$(GLAB_DOWN=1 run collect --since 2026-09-20T00:00:00Z)
assert_eq "(GitLab unavailable)" "$(todos "$out")" "GitLab down is noted, and the digest keeps going"
assert_contains "$out" "## Team plugins" "including the final section"
reset
echo '{"message":"401 Unauthorized"}' > "$FIX/todos.json"
assert_eq "(none)" "$(todos "$(run collect --since 2026-09-20T00:00:00Z)")" "an unexpected non-array body is treated as none, not a crash"

echo "start-day — GitLab to-dos on MRs I already approved (D-011)"
reset
cat > "$FIX/todos.json" <<'JSON'
[{"id":1,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"bkeeling"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6610,"project_id":3,"title":"Delete Retrieve request","author":{"username":"bkeeling"},"web_url":"w6610"},"target_url":"w6610","body":"b","created_at":"2026-10-08T06:00:00.000Z"},
 {"id":2,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"bkeeling"},"action_name":"mentioned","target_type":"MergeRequest","target":{"iid":6610,"project_id":3,"title":"Delete Retrieve request","author":{"username":"bkeeling"},"web_url":"w6610"},"target_url":"w6610#n","body":"b","created_at":"2026-10-08T06:10:00.000Z"},
 {"id":3,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"carol"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6611,"project_id":3,"title":"Other","author":{"username":"carol"},"web_url":"w6611"},"target_url":"w6611","body":"b","created_at":"2026-10-08T06:20:00.000Z"},
 {"id":4,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"carol"},"action_name":"mentioned","target_type":"MergeRequest","target":{"iid":6612,"project_id":3,"title":"Mine","author":{"username":"me"},"web_url":"w6612"},"target_url":"w6612","body":"b","created_at":"2026-10-08T06:30:00.000Z"}]
JSON
echo '{"approved_by":[{"user":{"username":"bkeeling"}},{"user":{"username":"me"}}]}' > "$FIX/approvals-3-6610.json"
echo '{"approved_by":[{"user":{"username":"someone"}}]}' > "$FIX/approvals-3-6611.json"
out=$(todos "$(run collect --since 2026-09-20T00:00:00Z)")
assert_eq "- [review requested] ecfx/ecfx-backend!6610 Delete Retrieve request (approved by you — no review) — @bkeeling — w6610
- [mentioned] ecfx/ecfx-backend!6610 Delete Retrieve request (approved by you — no review) — @bkeeling — w6610#n
- [review requested] ecfx/ecfx-backend!6611 Other — @carol — w6611
- [mentioned] ecfx/ecfx-backend!6612 Mine — @carol — w6612" "$out" "to-dos on an MR I approved are marked; others and my own MR are not"
assert_eq "1" "$(grep -c 'merge_requests/6610/approvals' "$FIX/approvals.log")" "one approvals call per MR, though two to-dos point at it"
assert_eq "0" "$(grep -c 'merge_requests/6612/approvals' "$FIX/approvals.log")" "no approvals call for my own MR"
out=$(APPROVALS_FAIL=1 run collect --since 2026-09-20T00:00:00Z)
assert_eq "- [review requested] ecfx/ecfx-backend!6610 Delete Retrieve request — @bkeeling — w6610" "$(todos "$out" | head -1)" "a failed approvals lookup leaves the to-do listed, unmarked"
assert_contains "$out" "## Jira" "and the digest keeps going"

echo "start-day — GitLab to-dos on MRs whose last review from me is unaddressed (F-050)"
reset
cat > "$STUBS/triage.py" <<'EOF'
import os, sys
sys.stdout.write(open(os.environ["FIX"] + "/triage.json").read())
EOF
cat > "$FIX/todos.json" <<'JSON'
[{"id":1,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"carol"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6611,"project_id":3,"title":"Other","author":{"username":"carol"},"web_url":"w6611"},"target_url":"w6611","body":"b","created_at":"2026-10-08T06:20:00.000Z"},
 {"id":2,"project":{"id":3,"path_with_namespace":"ecfx/ecfx-backend"},"author":{"username":"dan"},"action_name":"review_requested","target_type":"MergeRequest","target":{"iid":6620,"project_id":3,"title":"Fresh","author":{"username":"dan"},"web_url":"w6620"},"target_url":"w6620","body":"b","created_at":"2026-10-08T06:40:00.000Z"}]
JSON
echo '{"buckets":{"review_now":[{"ref":"ecfx/ecfx-backend!6620","title":"Fresh","author":"dan","context":"first time at you"}],"waiting_on_author":[{"ref":"ecfx/ecfx-backend!6611","title":"Other","author":"carol","context":"no activity since your last review"}]}}' > "$FIX/triage.json"
out=$(START_DAY_TRIAGE="$STUBS/triage.py" run collect --since 2026-09-20T00:00:00Z)
assert_eq "- [review requested] ecfx/ecfx-backend!6611 Other (waiting on author — my last review is unaddressed, leave out) — @carol — w6611
- [review requested] ecfx/ecfx-backend!6620 Fresh — @dan — w6620" "$(todos "$out")" "a to-do on an MR waiting on its author is marked; a fresh one is not"
assert_contains "$out" "- [waiting_on_author] ecfx/ecfx-backend!6611 Other — @carol: no activity since your last review" "the review queue still lists it, from the same triage run"
out=$(START_DAY_TRIAGE=/nonexistent/triage.py run collect --since 2026-09-20T00:00:00Z)
assert_eq "- [review requested] ecfx/ecfx-backend!6611 Other — @carol — w6611" "$(todos "$out" | head -1)" "without triage the to-do is listed, unmarked"

echo "start-day — QA candidates (Ready for QA, not mine)"
reset
# curl answers only the Ready for QA search; the ledger stub answers per key.
cat > "$STUBS/curl" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in jql=*) jql="${a#jql=}" ;; esac; done
echo "${jql:-}" >> "$FIX/jql.log"
case "${jql:-}" in
  *"Ready for QA"*) [ -n "${QA_JIRA_DOWN:-}" ] && exit 22; cat "$FIX/qa.json" ;;
  *) echo '{"issues":[]}' ;;
esac
EOF
cat > "$STUBS/qa-ledger.py" <<'EOF'
import json, sys
stages = {
    "ECFX-1": {},
    "ECFX-2": {"review": {"state": "done", "holder": None}},
    "ECFX-3": {"review": {"state": "live", "holder": {"holder": "Ann@mac/qa-review", "stage": "review"}}},
}
key = sys.argv[-1]
if key not in stages:
    sys.exit(3)
print(json.dumps({"key": key, "stages": stages[key]}))
EOF
chmod +x "$STUBS/curl"
qa_issue() { printf '{"key":"%s","fields":{"summary":"%s","priority":{"name":"%s"},"issuetype":{"name":"%s"},"assignee":%s}}' "$1" "$2" "$3" "$4" "$5"; }
cat > "$FIX/qa.json" <<EOF
{"issues":[$(qa_issue ECFX-1 "Roles page read-only" Highest Bug '{"displayName":"Bill"}'),
$(qa_issue ECFX-2 "Paging parameter" High Task '{"displayName":"Adam"}'),
$(qa_issue ECFX-3 "Decrypt stream" Medium Task null),
$(qa_issue ECFX-4 "Title provider refactor" Low Task '{"displayName":"EJ"}')]}
EOF
run_qa() {
    (PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" START_DAY_STATE="$STATE" START_DAY_POLL_DELAY=0 \
     JIRA_EMAIL=me@x JIRA_API_TOKEN=t START_DAY_QA_LEDGER="${QA_LEDGER:-$STUBS/qa-ledger.py}" START_DAY_TRIAGE=/nonexistent \
     REPOS_SYNC_SILENT=1 "$SCRIPT" collect --since 2026-09-20T00:00:00Z 2>&1)
}
qa() { printf '%s\n' "$1" | awk '/^## QA candidates/{f=1;next} /^## /{if(f)exit} f'; }
out=$(qa "$(run_qa)")
assert_contains "$(cat "$FIX/jql.log")" 'status = "Ready for QA" AND (assignee != currentUser() OR assignee is EMPTY)' "searches Ready for QA tickets that are not mine"
assert_contains "$out" "- ECFX-1 [Highest] Bug, Bill: Roles page read-only — QA: unclaimed" "an untouched ticket reads unclaimed"
assert_contains "$out" "- ECFX-2 [High] Task, Adam: Paging parameter — QA: review done" "a reviewed ticket shows its stages"
assert_contains "$out" "- ECFX-3 [Medium] Task, unassigned: Decrypt stream — QA: review live (Ann@mac/qa-review)" "a live claim names who holds it"
assert_contains "$out" "- ECFX-4 [Low] Task, EJ: Title provider refactor — QA: ledger unavailable" "a ledger failure is shown, not read as unclaimed"
out=$(qa "$(QA_LEDGER=/nonexistent/qa_ledger.py run_qa)")
assert_contains "$out" "QA: ledger unknown (no claude-components checkout)" "without the ledger tool each ticket says so"
cat > "$FIX/qa.json" <<<'{"issues":[]}'
assert_eq "(none)" "$(qa "$(run_qa)" | sed '/^$/d')" "no Ready for QA tickets prints (none)"
out=$(qa "$(QA_JIRA_DOWN=1 run_qa)")
assert_contains "$out" "(Jira unavailable)" "a failed search says so"
out=$(run collect --since 2026-09-20T00:00:00Z)
assert_contains "$(qa "$out")" "(Jira credentials missing" "without credentials the section says so"
rm -f "$STUBS/curl" "$STUBS/qa-ledger.py"

echo "start-day save — trailing diary refs"
reset
printf '%s\n' '- [ ] ECFX-1 thing [dashboard!1](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/1)' \
  | (PATH="$STUBS:$PATH" DIARY_DIR="$DIARY" START_DAY_STATE="$STATE" "$SCRIPT" save >/dev/null)
saved=$(sed -n '/start-day:start/,/start-day:end/p' "$DIARY/$(date +%F).md" | sed '1d;$d')
assert_eq "- [ ] ECFX-1 thing dashboard!1  [↗][dashboard!1]

[dashboard!1]: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/1" "$saved" "save files the plan with trailing refs"
rm -f "$DIARY/$(date +%F).md"

echo "start-day save — one line per ticket"
save() { (PATH="$STUBS:$PATH" DIARY_DIR="$DIARY" START_DAY_STATE="$STATE" "$SCRIPT" save 2>&1 >/dev/null); }
reset
err=$(printf '%s\n' '**Merge**' '- [ ] merge backend!6718 (ecfx-14260)' '**First**' '- [ ] ECFX-14260 reply to @bob on backend!6718' | save); rc=$?
assert_eq 1 "$rc" "a ticket on two lines is refused"
assert_contains "$err" "ecfx-14260" "the refusal names the ticket"
[ ! -e "$DIARY/$(date +%F).md" ] && pass "nothing is filed when refused" || fail "nothing is filed when refused" "diary was written"
err=$(printf '%s\n' '- [ ] ecfx-14260 backend!6718: reply to @bob, then merge' '  - [ ] reply to @bob (ecfx-14260)' '  - [ ] merge' \
  '- [ ] ecfx-17419 dashboard half waits on ecfx-17418' '- [ ] ecfx-17418 offer Retry only for recoverable failures' \
  '- [ ] reply to @anna in DM' '- [ ] review @carol'"'"'s dashboard!9' | save); rc=$?
assert_eq 0 "$rc" "children, later mentions and keyless lines are not duplicates ($err)"
rm -f "$DIARY/$(date +%F).md"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
