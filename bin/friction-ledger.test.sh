#!/bin/bash
# Tests for bin/friction-ledger. FRICTION_WIKI points into a sandbox and the miner output
# is a fixture file, so nothing touches ~/wiki or ~/.local/state.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/friction-ledger"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export FRICTION_WIKI="$SANDBOX/friction"
LED="$FRICTION_WIKI/ledger.md"
A="auth-src:auth:outlook not connected"
B="run-state:blocked:item needs you: class=-"
C="claude:tool_error:bash: command not found: jq"
COR="claude:correction:no, not that"

# mine FILE DATE then groups as "sig|kind|conf|count|sample"
mine() {
  local file="$1" d="$2"; shift 2
  printf '%s\n' "$@" | jq -Rn --arg d "$d" '{date: $d, groups: [inputs | split("|") | {sig: .[0], source: "x", kind: .[1], count: (.[3] | tonumber), keys: [], confidence: .[2],
    samples: [.[4]], evidence: ["/p/a.jsonl:1", "/p/b.jsonl:2"], known: null, ledger_status: null}]}' >"$file"
}
apply() { "$SCRIPT" apply --date "$1" --mine-json "$2" 2>"$SANDBOX/stderr"; }
fld() { grep -m1 "^$2:" "$FRICTION_WIKI/$1.md" | sed "s/^$2: *//"; }
snap() { (cd "$FRICTION_WIKI" && find . -type f | sort | xargs cat | cksum); }

# --- apply: new ---------------------------------------------------------------
echo "apply — new groups"
mine "$SANDBOX/d1.json" 2026-10-13 "$A|auth|high|2|Outlook not connected" "$C|tool_error|high|1|jq missing" "$COR|correction|low|3|no, not that"
OUT="$(apply 2026-10-13 "$SANDBOX/d1.json")"
assert_eq "F-001 F-002" "$(jq -r '[.new[].id] | join(" ")' <<<"$OUT")" "two high-confidence groups become F-001, F-002"
assert_eq "$A" "$(jq -r '.new[0].sig' <<<"$OUT")" "new item carries the signature"
assert_eq "Outlook not connected" "$(jq -r '.new[0].samples[0]' <<<"$OUT")" "new item carries samples"
assert_eq "/p/a.jsonl:1" "$(jq -r '.new[0].evidence[0]' <<<"$OUT")" "new item carries evidence"
assert_eq "open||2026-10-13|2026-10-13|1" "$(fld F-001 status)|$(fld F-001 class)|$(fld F-001 first)|$(fld F-001 last)|$(fld F-001 days)" "F-001 starts open, no class, one day"
assert_eq "3" "$(jq -r '.corrections[0].count' <<<"$OUT")" "corrections reported with count"
assert_eq "0" "$(grep -c 'no, not that' "$LED")" "corrections are not in the ledger"
assert_eq "2" "$(grep -c '^| F-' "$LED")" "ledger has two rows"
assert_eq "[]" "$(jq -c .needs_proposal <<<"$OUT")" "one-day non-blocked groups need no proposal"
grep -q '^| id | signature | class | first | last | days | status | fix |$' "$LED" && pass "ledger header per spec" || fail "ledger header per spec" "$(head -3 "$LED")"
assert_eq "$(printf '"%s"' "$A")" "$(fld F-001 signature)" "signature stored as a JSON string"
grep -q '^- 2026-10-13 (2×): Outlook not connected — /p/a.jsonl:1, /p/b.jsonl:2$' "$FRICTION_WIKI/F-001.md" && pass "evidence bullet is dated with count, sample and path:line" || fail "evidence bullet" "$(cat "$FRICTION_WIKI/F-001.md")"
grep -q '^- 2026-10-13: opened$' "$FRICTION_WIKI/F-001.md" && pass "History starts with opened" || fail "History starts with opened" ""

# --- apply: known update + promotion -------------------------------------------
echo "apply — known groups and promotion"
mine "$SANDBOX/d2.json" 2026-10-14 "$A|auth|high|4|Outlook not connected" "$B|blocked|high|1|item needs you"
OUT="$(apply 2026-10-14 "$SANDBOX/d2.json")"
assert_eq "2|2026-10-14|2026-10-13" "$(fld F-001 days)|$(fld F-001 last)|$(fld F-001 first)" "known: last and days updated, first kept"
assert_eq "F-003" "$(jq -r '[.new[].id] | join(" ")' <<<"$OUT")" "unseen group gets the next id"
assert_eq "F-001 F-003" "$(jq -r '[.needs_proposal[].id] | join(" ")' <<<"$OUT")" "seen on 2 days, or blocked, needs a proposal"
assert_eq "open open" "$(fld F-001 status) $(fld F-003 status)" "nothing is set to proposed by apply"
assert_eq "2" "$(jq -r '.needs_proposal[0].days' <<<"$OUT")" "needs_proposal item carries days"
assert_eq "1" "$(sed -n '/^## Evidence/,/^## Diagnosis/p' "$FRICTION_WIKI/F-003.md" | grep -c '^- 2026')" "one evidence bullet for the new group"

# --- idempotence --------------------------------------------------------------
echo "apply — idempotence"
before="$(snap)"
OUT2="$(apply 2026-10-14 "$SANDBOX/d2.json")"
assert_eq "$before" "$(snap)" "a second run for the same date changes nothing"
assert_eq "F-003" "$(jq -r '[.new[].id] | join(" ")' <<<"$OUT2")" "an item still without a class is reported again"
assert_eq "F-001 F-003" "$(jq -r '[.needs_proposal[].id] | join(" ")' <<<"$OUT2")" "an unproposed candidate is reported again"
assert_eq "2" "$(sed -n '/^## Evidence/,/^## Diagnosis/p' "$FRICTION_WIKI/F-001.md" | grep -c '^- 2026')" "evidence deduped by date"

# --- set ----------------------------------------------------------------------
echo "set"
printf 'rung: script\nwhy lower rungs do not fit: none\ntarget: bin/x\ntest: bin/x.test.sh\n' >"$SANDBOX/p.md"
"$SCRIPT" set F-001 --class env --rung config --diagnosis "Outlook MCP needs re-auth
every few days" --proposal-file "$SANDBOX/p.md" --status proposed --date 2026-10-14
assert_eq "env|config|proposed" "$(fld F-001 class)|$(fld F-001 rung)|$(fld F-001 status)" "set writes class, rung, status"
assert_eq "Outlook MCP needs re-auth every few days" "$(sed -n '/^## Diagnosis/,/^## Proposal/p' "$FRICTION_WIKI/F-001.md" | sed -n 3p)" "diagnosis is one line"
grep -q '^test: bin/x.test.sh$' "$FRICTION_WIKI/F-001.md" && pass "proposal file lands in ## Proposal" || fail "proposal file lands in ## Proposal" ""
grep -q '^- 2026-10-14: open → proposed$' "$FRICTION_WIKI/F-001.md" && pass "status change adds a dated History line" || fail "History line" "$(tail -4 "$FRICTION_WIKI/F-001.md")"
grep -q '^| F-001 | .* | env | 2026-10-13 | 2026-10-14 | 2 | proposed |' "$LED" && pass "ledger row follows the F-file" || fail "ledger row" "$(cat "$LED")"
before="$(snap)"; "$SCRIPT" set F-001 --status proposed --date 2026-10-15; assert_eq "$before" "$(snap)" "same status again writes no History line"
"$SCRIPT" set F-001 --class bogus 2>/dev/null; assert_eq "1" "$?" "bad class is refused"
"$SCRIPT" set F-099 --class env 2>/dev/null; assert_eq "1" "$?" "unknown id is refused"
"$SCRIPT" set F-003 --class external --status wontfix --date 2026-10-14
OUT="$(apply 2026-10-14 "$SANDBOX/d2.json")"
assert_eq "[]" "$(jq -c '[.new[].id]' <<<"$OUT")" "classified items leave new"
assert_eq "[]" "$(jq -c '[.needs_proposal[].id]' <<<"$OUT")" "proposed and wontfix items leave needs_proposal"

# --- regression ---------------------------------------------------------------
echo "apply — regression"
"$SCRIPT" set F-002 --class env --status fixed --fix abc1234 --date 2026-10-14
assert_eq "fixed|abc1234" "$(fld F-002 status)|$(fld F-002 fix)" "fixed carries the sha"
mine "$SANDBOX/d3.json" 2026-10-15 "$C|tool_error|high|2|jq missing again"
OUT="$(apply 2026-10-15 "$SANDBOX/d3.json")"
assert_eq "regressed" "$(fld F-002 status)" "fixed seen again turns regressed"
assert_eq "F-002" "$(jq -r '[.regressed[].id] | join(" ")' <<<"$OUT")" "regressed is reported"
grep -q '^- 2026-10-15: regressed (seen again after fix abc1234)$' "$FRICTION_WIKI/F-002.md" && pass "regression History line" || fail "regression History line" "$(tail -4 "$FRICTION_WIKI/F-002.md")"
before="$(snap)"; OUT2="$(apply 2026-10-15 "$SANDBOX/d3.json")"
assert_eq "$before" "$(snap)" "regression is idempotent too"
assert_eq "F-002" "$(jq -r '[.regressed[].id] | join(" ")' <<<"$OUT2")" "regression is still reported on a re-run"

# --- diary-section ------------------------------------------------------------
echo "diary-section"
"$SCRIPT" set F-002 --diagnosis "jq is not on the PATH of the subagent shell"
"$SCRIPT" set F-001 --diagnosis "Outlook MCP needs re-auth"
mine "$SANDBOX/d4.json" 2026-10-15 "$A|auth|high|1|Outlook not connected" "$C|tool_error|high|2|jq missing again" "$B|blocked|high|1|x" "$COR|correction|low|2|no, that is not what I asked, please stop and do the other thing instead of this" "claude:correction:wrong|correction|low|1|wrong file"
apply 2026-10-15 "$SANDBOX/d4.json" >/dev/null
OUT="$("$SCRIPT" diary-section --date 2026-10-15 --mine-json "$SANDBOX/d4.json")"
assert_eq "## Friction" "$(sed -n 1p <<<"$OUT")" "starts with the heading"
assert_eq "0 new · 2 recurring · 1 regressed" "$(sed -n 3p <<<"$OUT")" "counts: new / recurring / regressed"
grep -q '^- F-002 — jq is not on the PATH of the subagent shell → /fix-friction F-002$' <<<"$OUT" && pass "regressed item line ends with /fix-friction" || fail "regressed item line" "$OUT"
grep -q '^- F-001 — Outlook MCP needs re-auth → /fix-friction F-001$' <<<"$OUT" && pass "proposed item line ends with /fix-friction" || fail "proposed item line" "$OUT"
assert_eq "0" "$(grep -c 'F-003' <<<"$OUT")" "wontfix/open items get no line"
grep -q '^- 3 possible corrections (unverified): "no, that is not what I asked, please stop and do ...' <<<"$OUT" && pass "corrections: one line, count, short samples" || fail "corrections line" "$OUT"
assert_eq "1" "$(grep -c 'possible corrections' <<<"$OUT")" "corrections are a single line"
OUT="$("$SCRIPT" diary-section --date 2026-09-01 --mine-json "$SANDBOX/d4.json")"
assert_eq "## Friction" "$(sed -n 1p <<<"$OUT")" "corrections alone still produce a section"
printf '{"groups":[]}' >"$SANDBOX/empty.json"
assert_eq "" "$("$SCRIPT" diary-section --date 2026-09-01 --mine-json "$SANDBOX/empty.json")" "no friction prints nothing"

# --- misc ---------------------------------------------------------------------
echo "misc"
"$SCRIPT" apply 2>/dev/null; assert_eq "1" "$?" "apply without --date fails"
"$SCRIPT" nope 2>/dev/null; assert_eq "1" "$?" "unknown command fails"
jq -n '{groups: [{sig: "a:other:x | y", kind: "other", count: 1, confidence: "high", samples: ["s"], evidence: []}]}' >"$SANDBOX/d5.json"
apply 2026-10-15 "$SANDBOX/d5.json" >/dev/null; apply 2026-10-15 "$SANDBOX/d5.json" >/dev/null
assert_eq "1" "$(rg -c 'a:other:x' -l "$FRICTION_WIKI"/F-*.md | wc -l | tr -d ' ')" "a signature containing | maps to one entry, not one per run"

echo
echo "friction-ledger: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
