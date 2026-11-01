#!/usr/bin/env bash
# Tests for review-extract.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RE="$TEST_DIR/review-extract"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

V="$(mktemp -d)"
trap 'rm -rf "$V"' EXIT
mkdir -p "$V/_templates" "$V/diary" "$V/projects/ecfx/log" "$V/projects/ecfx/decisions" "$V/projects/epicmax/log"
printf -- '---\nproject: all\ntype: review\ndate: {{date}}\nperiod: {{period}}\n---\n# {{period}} review\n' > "$V/_templates/review-week.md"
touch "$V/diary/2026-09-27.md" "$V/diary/2026-09-28.md" "$V/diary/2026-10-04.md" "$V/diary/2026-10-05.md" "$V/diary/notes.md"
printf -- '---\nproject: ecfx\n---\n\n## 2026-09-27 out\nbefore\n\n## 2026-09-30 in\ninside\n\n## 2026-10-05 out\nafter\n' > "$V/projects/ecfx/log/2026-Q3.md"
printf '## 2026-10-02 only\nx\n' > "$V/projects/epicmax/log/2026-Q4.md"
printf -- '---\ndate: 2026-10-01\n---\nin\n' > "$V/projects/ecfx/decisions/0001-a.md"
printf -- '---\ndate: 2026-10-09\n---\nout\n' > "$V/projects/ecfx/decisions/0002-b.md"

echo "== frontmatter =="
assert_eq $'---\nproject: all\ntype: review\ndate: 2026-10-04\nperiod: 2026-W40\n---' \
  "$("$RE" frontmatter "$V/_templates/review-week.md" 2026-10-04 2026-W40)" "copies the frontmatter and fills the tokens"
printf 'no frontmatter\n' > "$V/plain.md"
assert_eq "" "$("$RE" frontmatter "$V/plain.md" a b)" "a template without frontmatter yields nothing"

echo "== diary =="
assert_eq "$V/diary/2026-09-28.md"$'\n'"$V/diary/2026-10-04.md" "$("$RE" diary "$V" 2026-09-28 2026-10-04)" "diary files in range, bounds included"
assert_eq "" "$("$RE" diary "$V" 2025-01-01 2025-01-05)" "empty range prints nothing"
rm -rf "$V/diary"
"$RE" diary "$V" 2026-09-28 2026-10-04 >/dev/null 2>&1; assert_eq "0" "$?" "no diary directory is not an error"
mkdir "$V/diary"

echo "== logs =="
out="$("$RE" logs "$V" 2026-09-28 2026-10-04)"
assert_eq "# log entries dated 2026-09-28 to 2026-10-04 under $V/projects/*/log/" "$(echo "$out" | head -1)" "header names the date range and paths"
echo "$out" | grep -qF -- "--- $V/projects/ecfx/log/2026-Q3.md" && pass "file marker" || fail "file marker" "$out"
echo "$out" | grep -q '^inside$' && pass "entry in range kept" || fail "entry in range kept" "$out"
echo "$out" | grep -qE '^(before|after)$' && fail "entries outside range dropped" "$out" || pass "entries outside range dropped"
echo "$out" | grep -qF -- "--- $V/projects/epicmax/log/2026-Q4.md" && pass "second project" || fail "second project" "$out"

echo "== decisions =="
assert_eq "$V/projects/ecfx/decisions/0001-a.md" "$("$RE" decisions "$V" 2026-09-28 2026-10-04)" "decision files dated in range"

echo "== usage =="
"$RE" bogus >/dev/null 2>&1; assert_eq "2" "$?" "unknown subcommand exits 2"

echo; echo "passed: $PASS  failed: $FAIL"; [ "$FAIL" -eq 0 ]
