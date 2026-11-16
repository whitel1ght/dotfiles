#!/bin/bash
# Tests for bin/plan-pick. fzf, jt and open are stubs that record their argv; the diary is a sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/plan-pick"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
DIARY="$SANDBOX/diary"; STUBS="$SANDBOX/stubs"; LOG="$SANDBOX/log"
mkdir -p "$DIARY/.agent" "$STUBS"

# fzf stub: logs its argv, then prints the row whose label holds $FZF_PICK, or exits $FZF_EXIT
cat > "$STUBS/fzf" <<'STUB'
#!/bin/bash
echo "fzf $*" >> "$LOG"
rows=$(cat)
[ -z "${FZF_EXIT:-}" ] || exit "$FZF_EXIT"
printf '%s\n' "$rows" | grep -F -- "$FZF_PICK" | head -1
STUB
printf '#!/bin/bash\necho "jt $*" >> "$LOG"\n' > "$STUBS/jt"
printf '#!/bin/bash\necho "open $*" >> "$LOG"\n' > "$STUBS/open"
# glab stub: `api graphql -f query=… -f iid=N|key=K` answers $STUBS/gl-<iid=N|key=K>.json
cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
last="${!#}"
echo "glab $last" >> "$LOG"
[ -z "${GLAB_FAIL:-}" ] || exit 1
cat "$(dirname "$0")/gl-$last.json" 2>/dev/null || echo '{"data":{"group":{"mergeRequests":{"nodes":[]}}}}'
STUB
# jira-api stub: `POST search/jql BODY` answers jira-in.json for a `key in (…)` JQL, else jira-main.json
cat > "$STUBS/jira" <<'STUB'
#!/bin/bash
jql=$(jq -r .jql <<<"$3")
echo "jira $jql" >> "$LOG"
[ -z "${JIRA_FAIL:-}" ] || { echo '{"errorMessages":["boom"]}'; exit 0; }
case "$jql" in "key in ("*) f=jira-in ;; *) f=jira-main ;; esac
cat "$(dirname "$0")/$f.json"
STUB
chmod +x "$STUBS"/*

export DIARY_DIR="$DIARY" LOG PLAN_PICK_FZF="$STUBS/fzf" PLAN_PICK_JT="$STUBS/jt" PLAN_PICK_OPEN="$STUBS/open"
export PLAN_PICK_GLAB="$STUBS/glab" PLAN_PICK_JIRA="$STUBS/jira" PLAN_PICK_DEBOUNCE=0
FZF_ARGS="fzf --height=100% --with-nth=3 --delimiter=\\t --disabled --prompt=plan>  --header=type a ticket or MR number to search Jira and GitLab too --bind=change:reload:$SCRIPT --search {q}"
T=$'\t'

# new-format day: agent file exists, plan lines carry no links
cat > "$DIARY/2026-11-05.md" <<'EOF'
# 2026-11-05
<!-- start-day:start -->
**Now**
- [ ] ecfx-17482 retrieve picker: merge after its pipeline
  - [ ] child ecfx-99999 never listed
- [ ] reply to Levi about the rollout <!-- p3 -->
- [ ] just a plain line without a key
- [/] ecfx-18000 second ticket
<!-- start-day:end -->
EOF
cat > "$DIARY/.agent/2026-11-05.md" <<'EOF'
# agent notes 2026-11-05
## ecfx-18000
- mr: backend!6000 https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6000
## ecfx-17482
- mr: dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289
- mr: dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289
## p3
- mr: admin!77 https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/77
## ecfx-55555
- mr: backend!1 https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/1
EOF

export DAY_AGENT_DATE=2026-11-05
out=$("$SCRIPT" --list 2>&1)
exp="ticket${T}ecfx-17482${T}ecfx-17482 retrieve picker: merge after its pipeline${T}ECFX-17482
mr${T}dashboard!2289${T}dashboard!2289 (ecfx-17482)${T}https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289
mr${T}admin!77${T}admin!77 (p3)${T}https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/77
ticket${T}ecfx-18000${T}ecfx-18000 second ticket${T}ECFX-18000
mr${T}backend!6000${T}backend!6000 (ecfx-18000)${T}https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6000"
assert_eq "$exp" "$out" "new format --list rows in plan order, MRs after their line, deduped"

# old-format day: definitions in the block
cat > "$DIARY/2026-11-04.md" <<'EOF'
# 2026-11-04
<!-- start-day:start -->
- [ ] ecfx-20005 review observability!80 · waiting  [↗][observability!80]
- [ ] reply to someone  [↗][backend!5]
- [ ] ecfx-20006 re-review categorization!207  [↗][categorization!207] [↗][observability!80]

[observability!80]: https://gitlab.com/ecfx/observability/-/merge_requests/80
[categorization!207]: https://gitlab.com/ecfx/ecfx-categorization/-/merge_requests/207
[backend!5]: https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/5
[backend!9]: https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/9
<!-- start-day:end -->
EOF
export DAY_AGENT_DATE=2026-11-04
out=$("$SCRIPT" --list 2>&1)
exp="ticket${T}ecfx-20005${T}ecfx-20005 review observability!80${T}ECFX-20005
mr${T}observability!80${T}observability!80 (ecfx-20005)${T}https://gitlab.com/ecfx/observability/-/merge_requests/80
mr${T}backend!5${T}backend!5${T}https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/5
ticket${T}ecfx-20006${T}ecfx-20006 re-review categorization!207${T}ECFX-20006
mr${T}categorization!207${T}categorization!207 (ecfx-20006)${T}https://gitlab.com/ecfx/ecfx-categorization/-/merge_requests/207
mr${T}backend!9${T}backend!9${T}https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/9"
assert_eq "$exp" "$out" "old format --list: MRs from the line's refs, unreferenced definitions last"

# picking
export DAY_AGENT_DATE=2026-11-05
: > "$LOG"; FZF_PICK="ecfx-17482 retrieve" "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "ticket pick exits 0"
assert_eq "$FZF_ARGS
jt ECFX-17482" "$(cat "$LOG")" "ticket row execs jt with the key (fzf gets the reload-on-change search)"

: > "$LOG"; FZF_PICK="dashboard!2289" "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "mr pick exits 0"
assert_eq "$FZF_ARGS
open https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289" "$(cat "$LOG")" "mr row opens its url"

: > "$LOG"; FZF_EXIT=130 "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "fzf cancel exits 0"
assert_eq "$FZF_ARGS" "$(cat "$LOG")" "fzf cancel runs nothing"

# empty plan: --list says so, the picker still opens for searching
export DAY_AGENT_DATE=2026-01-01
: > "$LOG"; err=$("$SCRIPT" --list 2>&1 >/dev/null); rc=$?
assert_eq "0" "$rc" "no diary --list exits 0"
assert_eq "plan-pick: nothing to pick" "$err" "no diary --list says nothing to pick"
: > "$LOG"; "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "no diary picker exits 0"
assert_eq "$FZF_ARGS" "$(cat "$LOG")" "no diary still opens the picker"

printf '# x\n<!-- start-day:start -->\n- [ ] just words\n<!-- start-day:end -->\n' > "$DIARY/2026-01-02.md"
export DAY_AGENT_DATE=2026-01-02
err=$("$SCRIPT" --list 2>&1 >/dev/null); rc=$?
assert_eq "0" "$rc" "no rows exits 0"
assert_eq "plan-pick: nothing to pick" "$err" "no rows says nothing to pick"

# a <!-- pN --> followed by text does not key the line
printf '# x\n<!-- start-day:start -->\n- [ ] call back <!-- p5 --> after lunch\n<!-- start-day:end -->\n' > "$DIARY/2026-01-03.md"
printf '# agent notes 2026-01-03\n## p5\n- mr: admin!77 https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/77\n' > "$DIARY/.agent/2026-01-03.md"
export DAY_AGENT_DATE=2026-01-03
err=$("$SCRIPT" --list 2>&1 >/dev/null); rc=$?
assert_eq "plan-pick: nothing to pick" "$err" "mid-line <!-- p5 --> is not a key: no MR row"

# --search: the plan rows the query matches, then Jira and GitLab for its number
gl() { # gl NAME ref|title|state … : a GraphQL answer with those MRs
  local name="$1" nodes="" ref title state; shift
  while [ $# -gt 0 ]; do
    ref="$1" title="$2" state="$3"; shift 3
    repo="${ref%!*}"; iid="${ref##*!}"
    nodes="$nodes${nodes:+,}{\"reference\":\"$ref\",\"title\":\"$title\",\"state\":\"$state\",\"webUrl\":\"https://gitlab.com/$repo/-/merge_requests/$iid\"}"
  done
  echo "{\"data\":{\"group\":{\"mergeRequests\":{\"nodes\":[$nodes]}}}}" > "$STUBS/gl-$name.json"
}
jira_json() { # jira_json FILE KEY|STATUS|SUMMARY …
  local f="$1" issues=""; shift
  while [ $# -gt 0 ]; do
    issues="$issues${issues:+,}{\"key\":\"$1\",\"fields\":{\"status\":{\"name\":\"$2\"},\"summary\":\"$3\"}}"; shift 3
  done
  echo "{\"issues\":[$issues]}" > "$STUBS/$f.json"
}
gl iid=6000 "ecfx/ecfx-backend!6000" "ECFX-18000: plan MR" merged \
  "ecfx/ecfx-admin!6000" "ECFX-18000 and ecfx-31: two keys, UTF-8 too" opened
gl key=ECFX-6000 "ecfx/infrastructure/camoufox!7" "ECFX-6000: in a subgroup" opened
jira_json jira-main ECFX-555 To-Do "mentions ECFX-6000" ECFX-6000 Done "six thousand"
jira_json jira-in ECFX-18000 Done "eighteen" ECFX-31 To-Do "thirty-one"

export DAY_AGENT_DATE=2026-11-05
: > "$LOG"; out=$("$SCRIPT" --search 6000 2>&1)
exp="mr${T}backend!6000${T}backend!6000 (ecfx-18000)${T}https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6000
ticket${T}ecfx-6000${T}ECFX-6000 · Done · six thousand${T}ECFX-6000
mr${T}admin!6000${T}admin!6000 · opened · ECFX-18000 and ecfx-31: two keys, UTF-8 too${T}https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/6000
ticket${T}ecfx-18000${T}ECFX-18000 · Done · eighteen${T}ECFX-18000
ticket${T}ecfx-31${T}ECFX-31 · To-Do · thirty-one${T}ECFX-31
mr${T}infrastructure/camoufox!7${T}infrastructure/camoufox!7 · opened · ECFX-6000: in a subgroup${T}https://gitlab.com/ecfx/infrastructure/camoufox/-/merge_requests/7
ticket${T}ecfx-555${T}ECFX-555 · To-Do · mentions ECFX-6000${T}ECFX-555"
assert_eq "$exp" "$out" "--search 6000: plan match, exact ticket, MRs !6000, their tickets, titled MRs, mentions; deduped"
assert_eq "jira key in (ECFX-18000,ECFX-31)" "$(grep 'key in' "$LOG")" "the tickets the !6000 MRs name are looked up once, ECFX keys only"
assert_eq "jira key = ECFX-6000 OR (project = ECFX AND text ~ \"ECFX-6000\") ORDER BY updated DESC" \
  "$(grep 'jira key =' "$LOG")" "Jira gets the key and its mentions"
assert_eq "glab iid=6000
glab key=ECFX-6000" "$(grep glab "$LOG" | sort)" "GitLab gets iid and title searches"

out2=$("$SCRIPT" --search 'backend!6000' 2>&1)
assert_eq "$out" "$out2" "repo!iid searches the same number"

out=$("$SCRIPT" --search 'ECFX-18000' | head -1 | cut -f3)
assert_eq "ecfx-18000 second ticket" "$out" "an upper-case key still matches its plan row first"

: > "$LOG"; out=$("$SCRIPT" --search 'ecfx-6000' 2>&1)
assert_eq "jira key = ECFX-6000 OR (project = ECFX AND text ~ \"ECFX-6000\") ORDER BY updated DESC" \
  "$(grep 'jira key =' "$LOG")" "a typed key searches that key"

: > "$LOG"; out=$("$SCRIPT" --search retrieve 2>&1)
assert_eq "ticket${T}ecfx-17482${T}ecfx-17482 retrieve picker: merge after its pipeline${T}ECFX-17482" "$out" "words filter the plan only"
assert_eq "" "$(cat "$LOG")" "words never search Jira or GitLab"
: > "$LOG"; "$SCRIPT" --search 7 >/dev/null
assert_eq "" "$(cat "$LOG")" "one digit never searches"
out=$("$SCRIPT" --search '' | wc -l | tr -d ' ')
assert_eq "5" "$out" "empty query lists the whole plan"

CACHE="$SANDBOX/cache"; mkdir -p "$CACHE"
: > "$LOG"; a=$(PLAN_PICK_CACHE="$CACHE" "$SCRIPT" --search 6000); b=$(PLAN_PICK_CACHE="$CACHE" "$SCRIPT" --search 6000)
assert_eq "$a" "$b" "a cached answer prints the same rows"
assert_eq "4" "$(wc -l < "$LOG" | tr -d ' ')" "the second search is served from the cache"

: > "$LOG"; out=$(GLAB_FAIL=1 PLAN_PICK_CACHE="$CACHE" "$SCRIPT" --search 18000)
assert_eq "info${T}${T}gitlab: search failed${T}gitlab" "$(grep '^info' <<<"$out")" "a GitLab failure shows as an info row"
assert_eq "ECFX-555" "$(grep -o 'ECFX-555$' <<<"$out")" "Jira rows still come when GitLab fails"
[ ! -e "$CACHE/ECFX-18000.18000" ] && pass "a failed search is not cached" || fail "a failed search is not cached" "cache file written"
out=$(JIRA_FAIL=1 "$SCRIPT" --search 18000)
assert_eq "info${T}${T}jira: search failed${T}jira" "$(grep '^info' <<<"$out")" "a Jira error answer shows as an info row"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
