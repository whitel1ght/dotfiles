#!/bin/bash
# Tests for bin/daily-report save. Works on a sandbox DIARY_DIR; collect talks to
# GitLab and Jira and is exercised by running it, not here.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/daily-report"
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

echo "daily-report save — existing entry"
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

echo "daily-report save — new entry"
save 2026-01-06 "- fresh"
head -1 "$SANDBOX/2026-01-06.md" | grep -q '^# ' && pass "creates the entry with a date heading" || fail "creates the entry with a date heading" "$(head -1 "$SANDBOX/2026-01-06.md")"
grep -qx '## habits' "$SANDBOX/2026-01-06.md" && pass "fills it from template.md" || fail "fills it from template.md" "no template"
assert_eq "- fresh" "$(block 2026-01-06)" "writes the block into it"

echo "daily-report — input checks"
printf '' | "$SCRIPT" save 2026-01-07 >/dev/null 2>&1 && fail "refuses an empty report" "exit 0" || pass "refuses an empty report"
"$SCRIPT" collect 26-1-1 >/dev/null 2>&1 && fail "rejects a malformed date" "exit 0" || pass "rejects a malformed date"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
