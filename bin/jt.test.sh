#!/bin/bash
# Tests for bin/jt. jira, fzf, wt and pbcopy are stubs that log their arguments;
# git repos are throwaways in a sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/jt"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; LOG="$SANDBOX/log"; PROJ="$SANDBOX/projects"
mkdir -p "$STUBS" "$PROJ"

# jira: logs (`issue view`, `open`). curl: Jira's search API, serving $JIRA_ROWS
# (key<TAB>status<TAB>summary lines) or $JIRA_TOTAL generated rows, 100 a page
# with the next offset as the page token; JIRA_ROWS=error answers 400.
printf '#!/bin/bash\necho "jira $*" >> "$LOG"\n' > "$STUBS/jira"
cat > "$STUBS/curl" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do [ "$1" = -d ] && body="$2"; shift; done
echo "search $(jq -r .jql <<<"$body")" >> "$LOG"
if [ "${JIRA_ROWS:-}" = error ]; then
  printf '{"errorMessages":["Field sprnt does not exist"]}\n400'; exit 0
fi
from="$(jq -r '.nextPageToken // 0' <<<"$body")"
if [ -n "${JIRA_TOTAL:-}" ]; then
  rows="$(for ((i = from; i < from + 100 && i < JIRA_TOTAL; i++)); do printf 'ECFX-%s\tTo-Do\tT%s\n' "$i" "$i"; done)"
  next=$((from + 100)); [ "$next" -lt "$JIRA_TOTAL" ] || next=""
else
  rows="$(printf '%b' "${JIRA_ROWS:-}")"; next=""
fi
jq -Rn --arg next "$next" '{issues: [inputs | select(length > 0) | split("\t")
  | {key: .[0], fields: {status: {name: .[1]}, summary: .[2]}}]}
  + (if $next == "" then {} else {nextPageToken: $next} end)' <<<"$rows"
printf '\n200'
EOF
# fzf: prints the key in $FZF_KEY, then the first row matching $FZF_PICK.
cat > "$STUBS/fzf" <<'EOF'
#!/bin/bash
echo "fzf $*" >> "$LOG"
rows="$(cat)"
[ -n "${FZF_PICK:-}" ] || exit 130
echo "${FZF_KEY:-}"
grep -m1 -- "$FZF_PICK" <<<"$rows"
EOF
printf '#!/bin/bash\necho "wt $*" >> "$LOG"\necho "/wt/$2/$3"\n' > "$STUBS/wt"
printf '#!/bin/bash\necho "pbcopy $(cat)" >> "$LOG"\n' > "$STUBS/pbcopy"
chmod +x "$STUBS"/*

ROWS='ECFX-10\tIn MR\tFix the thing\nECFX-17612\tTo-Do\tA 403 on a write: "forbidden" returns null\n'

run() {
  : > "$LOG"
  (cd "${CWD:-$SANDBOX}" && PATH="$STUBS:$PATH" LOG="$LOG" PROJECTS_DIR="$PROJ" JT_BRANCH_PREFIX=me/ \
    JIRA_ROWS="${JIRA_ROWS-$ROWS}" JIRA_TOTAL="${JIRA_TOTAL:-}" JT_MAX_ROWS="${JT_MAX_ROWS:-1000}" "$SCRIPT" "$@" 2>&1)
}

echo "queries"
run >/dev/null
assert_eq "search project = ECFX AND (assignee = currentUser() AND statusCategory != Done) ORDER BY updated DESC" "$(head -1 "$LOG")" "no args: my open tickets, recently updated first"
run 'retry "now" access' >/dev/null
assert_contains "$(cat "$LOG")" 'text ~ "retry \"now\" access"' "text search, quotes escaped"
run -q 'status = "In QA"' >/dev/null
assert_contains "$(cat "$LOG")" 'AND (status = "In QA") ORDER BY updated' "-q passes JQL through"
run -q 'sprint in openSprints() order by rank' >/dev/null
assert_eq "search project = ECFX AND (sprint in openSprints()) order by rank" "$(head -1 "$LOG")" "keeps the query's own ORDER BY"
run -q 'reorder by me' >/dev/null
assert_contains "$(cat "$LOG")" "(reorder by me) ORDER BY updated DESC" "only a whole-word ORDER BY counts"
run -m >/dev/null
assert_eq "search project = ECFX AND (sprint in openSprints() AND assignee = currentUser()) ORDER BY status, updated DESC" "$(head -1 "$LOG")" "-m: mine in the current sprint"
run -u >/dev/null
assert_eq 'search project = ECFX AND (filter = OmniEngineersFilter AND sprint in openSprints() AND assignee is EMPTY AND status = "To-Do") ORDER BY Rank' "$(head -1 "$LOG")" "-u: unassigned To-Do in the team's sprint"
run ecfx-42 >/dev/null
assert_eq "jira issue view ECFX-42 --comments 10" "$(cat "$LOG")" "a key shows that ticket"
run 42 >/dev/null
assert_eq "jira issue view ECFX-42 --comments 10" "$(cat "$LOG")" "a bare number is an ECFX key"

echo "results"
out="$(JIRA_ROWS="" run nothing)"; rc=$?
assert_eq "1 jt: nothing found" "$rc $out" "no result is not an error message"
out="$(JIRA_ROWS=error run)"; rc=$?
assert_contains "$rc $out" "1 Field sprnt does not exist" "a failure shows Jira's error"
FZF_PICK=ECFX-261 JIRA_TOTAL=262 run | cat >/dev/null
assert_eq "3" "$(grep -c '^search' "$LOG")" "pages past 100 rows"
assert_eq "ECFX-261" "$(FZF_PICK=ECFX-261 JIRA_TOTAL=262 run | cat)" "and the last page is pickable"
JIRA_TOTAL=5000 JT_MAX_ROWS=300 run >/dev/null
assert_eq "3" "$(grep -c '^search' "$LOG")" "stops at JT_MAX_ROWS"
run >/dev/null
assert_contains "$(cat "$LOG")" "--preview jira issue view {1} --plain --comments 5" "previews the highlighted ticket"

echo "actions"
out="$(FZF_PICK=17612 run | cat)"
assert_eq "ECFX-17612" "$out" "enter prints the key when piped"
FZF_PICK=17612 FZF_KEY=ctrl-y run >/dev/null
assert_contains "$(cat "$LOG")" "pbcopy ECFX-17612" "ctrl-y copies the key"
out="$(run)"; rc=$?
assert_eq "0" "$rc" "esc exits quietly"

run 17612 >/dev/null
assert_eq "jira issue view ECFX-17612 --comments 10" "$(cat "$LOG")" "no search for a single ticket"

echo "worktree"
g() { git -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main "$PROJ/app" && g -C "$PROJ/app" commit -q --allow-empty -m init
out="$(CWD="$PROJ/app" FZF_PICK=17612 FZF_KEY=ctrl-w run)"
assert_contains "$(cat "$LOG")" "wt add app ECFX-17612 me/ECFX-17612_a-403-on-a-write" "new branch named after the summary"
assert_eq "/wt/app/ECFX-17612" "$out" "prints the worktree path"
g -C "$PROJ/app" branch -q someone/ECFX-17612_existing
CWD="$PROJ/app" FZF_PICK=17612 FZF_KEY=ctrl-w run >/dev/null
assert_contains "$(cat "$LOG")" "wt add app ECFX-17612 someone/ECFX-17612_existing" "reuses a branch with the key"
g -C "$PROJ/app" branch -q me/ECFX-176120_other
g -C "$PROJ/app" branch -D -q someone/ECFX-17612_existing
CWD="$PROJ/app" FZF_PICK=17612 FZF_KEY=ctrl-w run >/dev/null
assert_contains "$(cat "$LOG")" "me/ECFX-17612_a-403" "a longer key is not a match"
CWD="$PROJ/app/.git" FZF_PICK=ECFX-10 FZF_KEY=ctrl-w run >/dev/null
assert_contains "$(cat "$LOG")" "wt add app ECFX-10 me/ECFX-10_fix-the-thing" "works from anywhere inside the repo"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
