#!/bin/bash
# Tests for bin/start-day collect's "Ready to merge" section. glab is stubbed
# on PATH, so nothing here reaches GitLab; carry-over and Jira are pointed at
# an empty sandbox / disabled so only Ready to merge is under test.
set -uo pipefail

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
mkdir -p "$STUBS" "$FIX" "$STATE" "$DIARY"
# A dummy, older diary entry: collect_carryover pipes ls through grep, and an
# empty DIARY_DIR (grep matches nothing) trips set -o pipefail and aborts the
# whole run. Real usage never hits this since ~/wiki/diary is never empty.
echo '### ECFX' > "$DIARY/2020-01-01.md"

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
[ -n "${GLAB_DOWN:-}" ] && exit 1
FIX="${FIX:?}"
case "$*" in
    "api user") echo '{"username":"me"}' ;;
    *merge_requests\?scope=created_by_me\&state=opened*) cat "$FIX/mrs.json" ;;
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

reset() { rm -rf "$FIX" "$STATE"; mkdir -p "$FIX" "$STATE"; }

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
out=$(GLAB_DOWN=1 run collect --since 2026-09-20T00:00:00Z)
assert_contains "$out" "## Ready to merge" "the section heading still prints"
assert_contains "$(ready "$out")" "(GitLab unavailable)" "Ready to merge reports GitLab unavailable"
assert_contains "$out" "## Review queue" "collect keeps running the rest of the digest"
assert_contains "$out" "## Jira" "including the final section"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
