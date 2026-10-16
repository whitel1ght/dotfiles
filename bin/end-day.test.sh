#!/bin/bash
# Tests for bin/end-day save. Works on a sandbox DIARY_DIR; collect talks to
# GitLab and Jira and is exercised by running it, not here.
set -uo pipefail
# Never fall back to the real secrets file (scripts read Jira credentials from it).
export SECRETS_FILE=/nonexistent/secrets.env

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/end-day"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export DIARY_DIR="$SANDBOX"
printf '## habits\n\n- [ ] x\n\n## Work\n\n### ECFX\n' > "$SANDBOX/template.md"

save() { printf '%s\n' "$2" | "$SCRIPT" save "$1" >/dev/null; }
block() { sed -n '/daily-report:start/,/daily-report:end/p' "$SANDBOX/$1.md" | sed '1d;$d'; }

echo "end-day save — existing entry"
cat > "$SANDBOX/2026-01-05.md" <<'EOF'
# Mon Jan  5 09:00:00 +03 2026

## Work

### ECFX

- [X] my own line

### Personal

- [ ] groceries
EOF
save 2026-01-05 "- first"
assert_eq "- first" "$(block 2026-01-05)" "writes the block"
save 2026-01-05 "- second"
assert_eq "- second" "$(block 2026-01-05)" "a re-run replaces the block"
assert_eq 1 "$(grep -c 'daily-report:start' "$SANDBOX/2026-01-05.md")" "never duplicates the block"
grep -qxF -- '- [X] my own line' "$SANDBOX/2026-01-05.md" && pass "keeps my own lines" || fail "keeps my own lines" "line lost"
awk '/### ECFX/{e=1} /daily-report:start/{if(e && !p) ok=1} /### Personal/{p=1} END{exit !ok}' "$SANDBOX/2026-01-05.md" \
    && pass "lands inside ### ECFX, before the next section" || fail "lands inside ### ECFX, before the next section" "$(cat "$SANDBOX/2026-01-05.md")"
grep -qx -- '- \[ \] groceries' "$SANDBOX/2026-01-05.md" && pass "leaves later sections alone" || fail "leaves later sections alone" "lost"

echo "end-day save — new entry"
save 2026-01-06 "- fresh"
head -1 "$SANDBOX/2026-01-06.md" | grep -q '^# ' && pass "creates the entry with a date heading" || fail "creates the entry with a date heading" "$(head -1 "$SANDBOX/2026-01-06.md")"
grep -qx '## habits' "$SANDBOX/2026-01-06.md" && pass "fills it from template.md" || fail "fills it from template.md" "no template"
assert_eq "- fresh" "$(block 2026-01-06)" "writes the block into it"

echo "end-day save --plan"
save_plan() { printf '%s\n' "$2" | "$SCRIPT" save "$1" --plan >/dev/null; }
plan() { sed -n '/start-day:start/,/start-day:end/p' "$SANDBOX/$1.md" | sed '1d;$d'; }
save_plan 2026-01-05 "- [ ] plan one"
assert_eq "- [ ] plan one" "$(plan 2026-01-05)" "writes the plan block"
first=$(awk '/^### ECFX/{getline; while ($0 == "") getline; print; exit}' "$SANDBOX/2026-01-05.md")
assert_eq "<!-- start-day:start -->" "$first" "puts the plan first in ### ECFX"
save_plan 2026-01-05 "- [ ] plan two"
assert_eq "- [ ] plan two" "$(plan 2026-01-05)" "a re-run replaces the plan"
assert_eq "- second" "$(block 2026-01-05)" "leaves the report block alone"
grep -qxF -- '- [X] my own line' "$SANDBOX/2026-01-05.md" && pass "keeps my own lines beside the plan" || fail "keeps my own lines beside the plan" "lost"

echo "end-day save — trailing diary refs"
D=https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests
save 2026-01-09 "- [x] fix [dashboard!1]($D/1)"
assert_eq "- [x] fix dashboard!1  [↗][dashboard!1]

[dashboard!1]: $D/1" "$(block 2026-01-09)" "save moves inline links to trailing refs"
printf '%s\n' "- [ ] plan [dashboard!2]($D/2)" | "$SCRIPT" save 2026-01-09 --plan >/dev/null
assert_eq "- [ ] plan dashboard!2  [↗][dashboard!2]

[dashboard!2]: $D/2" "$(sed -n '/start-day:start/,/start-day:end/p' "$SANDBOX/2026-01-09.md" | sed '1d;$d')" "--plan converts its block too"

echo "end-day save — standup paragraph"
STANDUP='**Standup**
Merged backend!6613 for ECFX-1001. ECFX-1003 is in review. Waiting on product for ECFX-1007. Tomorrow: ECFX-1004 first.'
REPORT="$STANDUP

**Done**
- ECFX-1001 CSV export keeps column order"
save 2026-01-10 "$REPORT"
assert_eq "$REPORT" "$(block 2026-01-10)" "a report with the Standup paragraph round-trips"
save 2026-01-10 "$REPORT"
assert_eq "$REPORT" "$(block 2026-01-10)" "and a re-run leaves it unchanged (diary-links adds no refs)"
assert_eq "**Standup**" "$(block 2026-01-10 | head -1)" "Standup stays first in the block"
WIKI_DIR="$SANDBOX/nowhere" "$SCRIPT" touched 2026-01-10 >/dev/null; assert_eq "0" "$?" "touched is unaffected by a diary with a Standup"
assert_eq "" "$(WIKI_DIR="$SANDBOX/nowhere" "$SCRIPT" entries 2026-01-10 ecfx)" "entries is unaffected by a diary with a Standup"

echo "end-day — input checks"
printf '' | "$SCRIPT" save 2026-01-07 >/dev/null 2>&1 && fail "refuses an empty report" "exit 0" || pass "refuses an empty report"
"$SCRIPT" collect 26-1-1 >/dev/null 2>&1 && fail "rejects a malformed date" "exit 0" || pass "rejects a malformed date"

echo "end-day touched"
WIKI="$SANDBOX/wiki"
mkdir -p "$WIKI/projects/ecfx/log" "$WIKI/projects/ecfx/decisions" "$WIKI/projects/epicmax/log" "$WIKI/projects/epicmax/decisions" "$WIKI/projects/personal/log"
printf -- '---\nproject: ecfx\n---\n\n## 2026-10-07 earlier work\n\ntext\n\n## 2026-10-08 retry button\n\ntext\n' > "$WIKI/projects/ecfx/log/2026-Q4.md"
printf -- '---\nproject: epicmax\ntype: decision\ndate: 2026-10-08\n---\n# 0003 pick x\n' > "$WIKI/projects/epicmax/decisions/0003-pick-x.md"
printf -- '---\nproject: personal\ndate: 2026-10-07\n---\n' > "$WIKI/projects/personal/log/2026-Q4.md"
touched() { WIKI_DIR="$WIKI" "$SCRIPT" touched "$@"; }
assert_eq "ecfx
epicmax" "$(touched 2026-10-08)" "lists projects with a log entry or a decision on that date, one per line"
assert_eq "ecfx" "$(touched 2026-10-07)" "an entry dated the 7th only counts for the 7th (a frontmatter date alone in a log file is not an entry)"
assert_eq "" "$(touched 2026-10-09)" "nothing touched prints nothing"
touched 2026-10-09 >/dev/null; assert_eq "0" "$?" "and exits 0"
assert_eq "" "$(WIKI_DIR="$SANDBOX/nowhere" "$SCRIPT" touched 2026-10-08)" "a missing wiki is empty, not an error"
(cd "$SANDBOX" && WIKI_DIR="$WIKI" "$SCRIPT" touched yesterday >/dev/null 2>&1); assert_eq "0" "$?" "accepts yesterday"
assert_eq "yes" "$("$SCRIPT" --help | grep -q 'touched' && echo yes || echo no)" "--help mentions it"

echo "end-day entries"
assert_eq "## 2026-10-08 retry button

text" "$(WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 ecfx)" "prints only that day's entries, up to the next heading"
assert_eq "" "$(WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 personal)" "a project without an entry prints nothing"
assert_eq "" "$(WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 nope)" "a missing project is empty, not an error"
out=$(WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 ../x 2>&1); assert_eq "1" "$?" "entries rejects .. in the project (exit 1)"
assert_eq "yes" "$(grep -q 'end-day: entries: project must be a plain name' <<<"$out" && echo yes || echo no)" "and says why on stderr"
WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 a/b >/dev/null 2>&1; assert_eq "1" "$?" "entries rejects a slash in the project"
out=$(WIKI_DIR="$WIKI" "$SCRIPT" entries 2026-10-08 2>&1); assert_eq "1" "$?" "entries without a project exits 1"
assert_eq "end-day: entries needs a project" "$out" "with an explicit message"

echo "end-day friction"
printf '# Day\n\n## Work\n\n### ECFX\n\n- mine\n' > "$SANDBOX/2026-02-01.md"
save 2026-02-01 "- report"
printf '## Friction\n\n1 new\n' | "$SCRIPT" friction 2026-02-01 >/dev/null
assert_eq "yes" "$(tail -5 "$SANDBOX/2026-02-01.md" | head -1 | grep -qx '<!-- friction:start -->' && echo yes || echo no)" "the section goes at the end, between markers"
printf '## Friction\n\n2 new\n' | "$SCRIPT" friction 2026-02-01 >/dev/null
assert_eq "1" "$(grep -c 'friction:start' "$SANDBOX/2026-02-01.md")" "a re-run replaces the block"
assert_eq "yes" "$(grep -q '^2 new$' "$SANDBOX/2026-02-01.md" && ! grep -q '^1 new$' "$SANDBOX/2026-02-01.md" && echo yes || echo no)" "with the new text"
save 2026-02-01 "- report v2"
assert_eq "yes" "$(grep -q '^2 new$' "$SANDBOX/2026-02-01.md" && grep -q -- '- report v2' "$SANDBOX/2026-02-01.md" && echo yes || echo no)" "re-saving the report leaves the friction block alone"
printf '' | "$SCRIPT" friction 2026-02-01 >/dev/null 2>&1; assert_eq "1" "$?" "empty stdin is refused"
printf 'x\n' | "$SCRIPT" friction 2026-02-02 >/dev/null 2>&1; assert_eq "1" "$?" "no diary for the day is refused"

echo "end-day collect — friction capture"
# A private copy of the script, so HERE holds a failing ecfx-daily-commits; glab and curl fail too.
CBIN="$SANDBOX/cbin"; CSTUBS="$SANDBOX/cstubs"; CLOG="$SANDBOX/friction.log"
mkdir -p "$CBIN" "$CSTUBS" "$SANDBOX/claude"
cp "$SCRIPT" "$CBIN/end-day"
printf '#!/bin/bash\nexit 1\n' > "$CBIN/ecfx-daily-commits"
printf '#!/bin/bash\nexit 1\n' > "$CSTUBS/glab"
printf '#!/bin/bash\nexit 22\n' > "$CSTUBS/curl"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$CLOG"\n[ -n "${FRICTION_FAIL:-}" ] && exit 1\nexit 0\n' > "$CSTUBS/friction"
chmod +x "$CBIN/end-day" "$CBIN/ecfx-daily-commits" "$CSTUBS"/*
collect() { PATH="$CSTUBS:$PATH" CLOG="$CLOG" CLAUDE_DIR="$SANDBOX/claude" JIRA_EMAIL=a JIRA_API_TOKEN=b "$CBIN/end-day" collect 2026-01-05 2>&1; }
mkdir -p "$SANDBOX/cnof"; ln -s "$CSTUBS/glab" "$CSTUBS/curl" "$SANDBOX/cnof/"
baseline=$(PATH="$SANDBOX/cnof:$(dirname "$(command -v jq)"):/usr/bin:/bin" CLAUDE_DIR="$SANDBOX/claude" JIRA_EMAIL=a JIRA_API_TOKEN=b "$CBIN/end-day" collect 2026-01-05 2>&1); brc=$?
assert_eq "0" "$brc" "collect with no friction on PATH still exits 0"
out=$(collect); rc=$?
assert_eq "0" "$rc" "collect with friction present exits 0"
assert_eq "$baseline" "$out" "and prints the same digest as without friction"
assert_eq "--source end-day service_down commits unavailable
--source end-day service_down GitLab unavailable
--source end-day auth Jira unavailable, token may have expired" "$(cat "$CLOG")" "commits, GitLab and Jira failures record service_down/service_down/auth"
rm -f "$CLOG"
out=$(FRICTION_FAIL=1 collect); rc=$?
assert_eq "0" "$rc" "a failing friction leaves exit 0"
assert_eq "$baseline" "$out" "and the same digest"
printf '#!/bin/bash\nexit 0\n' > "$CSTUBS/curl"
rm -f "$CLOG"; collect >/dev/null
assert_eq "--source end-day service_down commits unavailable
--source end-day service_down GitLab unavailable" "$(cat "$CLOG")" "Jira answering with nothing records no auth event"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
