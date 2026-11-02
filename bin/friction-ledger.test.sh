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
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export FRICTION_WIKI="$SANDBOX/friction" CARDS_DIR="$SANDBOX/cards"
# Isolate the optional card-store dependency: the Ubuntu port does not import that
# unrelated interactive helper, but the ledger's ingest contract is exercised here.
CARDS_CLI="$SANDBOX/cards-cli"; export CARDS_CLI
export CARDS_BIN="$CARDS_CLI"
cat > "$CARDS_BIN" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = add ] || exit 2
shift
front="" back="" tags="" date_="" source_=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --front) front="$2"; shift 2 ;; --back) back="$2"; shift 2 ;;
    --tags) tags="$2"; shift 2 ;; --date) date_="$2"; shift 2 ;;
    --source) source_="$2"; shift 2 ;; *) exit 2 ;;
  esac
done
mkdir -p "$CARDS_DIR"
if grep -lFx "$front" "$CARDS_DIR"/*.md >/dev/null 2>&1; then exit 0; fi
id="$(printf '%s' "$front" | cksum | awk '{print $1}')"
printf '%s\n%s\n%s\n%s\n' "$front" "$back" "$tags" "$source_" > "$CARDS_DIR/$id.md"
STUB
chmod +x "$CARDS_BIN"
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
mine "$SANDBOX/d1.json" 2026-10-13 "$A|auth|high|2|Outlook not connected" "$C|tool_error|high|2|jq missing" "$COR|correction|low|3|no, not that"
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
grep -qF -- '- F-002 — jq is not on the PATH of the subagent shell → in the friction queue (`` ` f ``)' <<<"$OUT" && pass "regressed item line points at the friction queue" || fail "regressed item line" "$OUT"
grep -qF -- '- F-001 — Outlook MCP needs re-auth → in the friction queue (`` ` f ``)' <<<"$OUT" && pass "proposed item line points at the friction queue" || fail "proposed item line" "$OUT"
grep -q 'in the friction queue' <<<"$OUT" && pass "item lines say in the friction queue" || fail "friction queue wording" "$OUT"
grep -q '/daily:fix-friction' <<<"$OUT" && fail "item lines no longer name /daily:fix-friction" "$OUT" || pass "item lines no longer name /daily:fix-friction"
assert_eq "0" "$(grep -c 'F-003' <<<"$OUT")" "wontfix/open items get no line"
grep -q '^- 3 possible corrections (unverified): "no, that is not what I asked, please stop and do ...' <<<"$OUT" && pass "corrections: one line, count, short samples" || fail "corrections line" "$OUT"
assert_eq "1" "$(grep -c 'possible corrections' <<<"$OUT")" "corrections are a single line"
OUT="$("$SCRIPT" diary-section --date 2026-09-01 --mine-json "$SANDBOX/d4.json")"
assert_eq "## Friction" "$(sed -n 1p <<<"$OUT")" "corrections alone still produce a section"
printf '{"groups":[]}' >"$SANDBOX/empty.json"
assert_eq "" "$("$SCRIPT" diary-section --date 2026-09-01 --mine-json "$SANDBOX/empty.json")" "no friction prints nothing"

# --- directions ---------------------------------------------------------------
echo "directions"
DF="$FRICTION_WIKI/directions.md"
id="$("$SCRIPT" directions add --rule "Handle service outages with scripts, never model retries" --scope global --quote "gitlab fails | run a script" --harness claude --date 2026-10-15)"
assert_eq "D-001" "$id" "add allocates D-001"
grep -q '^| D-001 | Handle service outages with scripts, never model retries | global | 2026-10-15 | "gitlab fails ¦ run a script" (claude) | active |$' "$DF" && pass "row format per spec, | in the quote escaped" || fail "row format" "$(cat "$DF")"
assert_eq "D-001" "$("$SCRIPT" directions add --rule "handle service outages with scripts; never model retries!" --date 2026-10-16)" "a rule equal after normalising is not added again"
assert_eq "1" "$(grep -c '^| D-' "$DF")" "still one row"
assert_eq "D-001" "$("$SCRIPT" directions add --rule "Prefer scripts over model retries when services fail" --same-as D-001)" "--same-as keeps the original"
assert_eq "2026-10-15" "$(awk -F'|' '/D-001/ { gsub(/ /, "", $5); print $5 }' "$DF")" "and its since date"
assert_eq "D-002" "$("$SCRIPT" directions add --rule "Reviews cite the commit sha" --scope reviews --date 2026-10-15)" "a new rule gets the next id"
"$SCRIPT" directions add --rule "Reviews never approve with open blockers" --scope reviews --date 2026-10-15 >/dev/null
assert_eq "D-001" "$("$SCRIPT" directions render | head -1 | grep -q 'Handle service outages' && echo D-001)" "render lists active rules"
assert_eq "- Handle service outages with scripts, never model retries
- Reviews cite the commit sha [reviews]
- Reviews never approve with open blockers [reviews]" "$("$SCRIPT" directions render)" "render format: scope shown unless global"
assert_eq "- Handle service outages with scripts, never model retries" "$("$SCRIPT" directions render --scope run-day)" "--scope keeps global plus that scope"
"$SCRIPT" directions retire D-002 --reason "wrong"
"$SCRIPT" directions promote D-003 --fix abc1234
grep -q '^| D-002 | .* | retired — retired: wrong |$' "$DF" || grep -q 'D-002.*retired: wrong | retired |$' "$DF" && pass "retire marks the row and keeps the reason" || fail "retire row" "$(cat "$DF")"
grep -q 'D-003.*fix abc1234 | promoted |$' "$DF" && pass "promote marks the row with the fix" || fail "promote row" "$(cat "$DF")"
assert_eq "- Handle service outages with scripts, never model retries" "$("$SCRIPT" directions render)" "retired and promoted rules are not rendered"
assert_eq "D-004" "$("$SCRIPT" directions add --rule "Reviews cite the commit sha" --scope reviews)" "a retired rule can be learned again under a new id"
"$SCRIPT" directions retire D-099 2>/dev/null; assert_eq "1" "$?" "retire of an unknown id fails"
"$SCRIPT" directions promote D-004 2>/dev/null; assert_eq "1" "$?" "promote needs --fix"
"$SCRIPT" directions add --date 2026-10-15 2>/dev/null; assert_eq "1" "$?" "add needs a rule"
printf '%s\n' "  Never run \$(touch $SANDBOX/pwned) or \`id\`; say \"it\" \\ 	 " "second line ignored" >"$SANDBOX/rule.txt"
id="$("$SCRIPT" directions add --rule-file "$SANDBOX/rule.txt" --scope reviews --date 2026-10-15)"
assert_eq "D-005" "$id" "--rule-file adds the rule"
assert_eq "Never run \$(touch $SANDBOX/pwned) or \`id\`; say \"it\" \\" "$(awk -F' \\| ' '/^\| D-005 /{ print $2 }' "$DF")" "the file's first line, trimmed, kept verbatim"
assert_eq "no" "$([ -e "$SANDBOX/pwned" ] && echo yes || echo no)" "nothing in the rule is run"
"$SCRIPT" directions add --rule x --rule-file "$SANDBOX/rule.txt" 2>/dev/null; assert_eq "1" "$?" "--rule and --rule-file together are refused"
"$SCRIPT" directions add --rule-file "$SANDBOX/nope.txt" 2>/dev/null; assert_eq "1" "$?" "a missing rule file is refused"
printf '   \n' >"$SANDBOX/blank.txt"
"$SCRIPT" directions add --rule-file "$SANDBOX/blank.txt" 2>/dev/null; assert_eq "1" "$?" "a blank rule file is refused"
rows="$(grep -c '^| D-' "$DF")"
for s in '$(touch '"$SANDBOX/pwned2"')' 'two words' '"x"' '-x' "$(printf 'a%.0s' $(seq 1 61))" 'a;b' 'a`b`'; do
  "$SCRIPT" directions add --rule "Scope test rule" --scope "$s" --date 2026-10-15 2>/dev/null; rc=$?
  assert_eq "2|$rows" "$rc|$(grep -c '^| D-' "$DF")" "a bad scope is refused with exit 2, nothing added: ${s:0:30}"
done
assert_eq "no" "$([ -e "$SANDBOX/pwned2" ] && echo yes || echo no)" "nothing in a scope is run"
id="$("$SCRIPT" directions add --rule "Scope test rule" --scope "dotfiles:bin/coach-fix" --date 2026-10-15)"; rc=$?
assert_eq "0|D-006" "$rc|$id" "a repo:path scope is accepted"

export FRICTION_WIKI="$SANDBOX/cap"; DF="$FRICTION_WIKI/directions.md"
assert_eq "" "$("$SCRIPT" directions render)" "no file renders nothing"
long="$(printf 'word%.0s ' $(seq 1 25))"
for i in $(seq 1 30); do "$SCRIPT" directions add --rule "global rule $i $long" --scope global --date "2026-09-$(printf '%02d' "$i")" >/dev/null; done
"$SCRIPT" directions add --rule "Reviews keep one comment" --scope reviews --date 2026-10-01 >/dev/null
out="$("$SCRIPT" directions render)"
[ "$(printf '%s' "$out" | wc -c)" -le 2048 ] && pass "render stays within 2 KB" || fail "render size" "$(printf '%s' "$out" | wc -c)"
assert_eq "yes" "$(grep -q 'Reviews keep one comment \[reviews\]' <<<"$out" && grep -q 'global rule 30 ' <<<"$out" && ! grep -q 'global rule 1 ' <<<"$out" && echo yes || echo no)" "the oldest global rules are folded first"
grep -Eq '^- [0-9]+ more in ~/wiki/work/friction/directions.md$' <<<"$out" && pass "the folded rules are summarised in one line" || fail "summary line" "$out"
export FRICTION_WIKI="$SANDBOX/friction"; DF="$FRICTION_WIKI/directions.md"

# --- frustration ----------------------------------------------------------------
echo "frustration"
out="$("$SCRIPT" frustration --date 2026-10-14 --what "Gitlab outage made the run loop on retries" --class env --sig-hint "gitlab retries loop" --quote "why is it retrying again")"
assert_eq "true|1|false" "$(jq -r '[.new, .days, .needs_proposal] | join("|")' <<<"$out")" "a first frustration is a new ledger entry, no proposal yet"
fid="$(jq -r .id <<<"$out")"
assert_eq "\"user:frustration:gitlab retries loop\"" "$(fld "$fid" signature)" "signature is user:frustration:<hint>"
assert_eq "env" "$(fld "$fid" class)" "class set from the reply"
grep -q 'Gitlab outage made the run loop' "$FRICTION_WIKI/$fid.md" && pass "diagnosis set from what_went_wrong" || fail "diagnosis" ""
out="$("$SCRIPT" frustration --date 2026-10-15 --what "Gitlab outage again" --class env --sig-hint "GitLab retries loop")"
assert_eq "false|2|true" "$(jq -r '[.new, .days, .needs_proposal] | join("|")' <<<"$out")" "the same hint on another day: same entry, 2 days, needs a proposal"
before="$(snap)"; "$SCRIPT" frustration --date 2026-10-15 --what "Gitlab outage again" --class env --sig-hint "gitlab retries loop" >/dev/null
assert_eq "$before" "$(snap)" "recording the same frustration twice changes nothing"

# --- apply passes user_signals --------------------------------------------------
echo '{"groups":[],"user_signals":[{"text":"always use scripts"}]}' >"$SANDBOX/us.json"
assert_eq "always use scripts" "$("$SCRIPT" apply --date 2026-10-15 --mine-json "$SANDBOX/us.json" | jq -r '.user_signals[0].text')" "apply passes user_signals through"
echo '{"groups":[]}' >"$SANDBOX/us.json"
assert_eq "[]" "$("$SCRIPT" apply --date 2026-10-15 --mine-json "$SANDBOX/us.json" | jq -c .user_signals)" "and an empty list when there are none"

# --- diary-section: directions and frustrations ---------------------------------
echo "diary-section — directions"
"$SCRIPT" directions add --rule "Never merge without asking" --scope global --date 2026-10-15 >/dev/null
for r in one two three; do last="$("$SCRIPT" directions add --rule "docs rule $r" --scope docs --date 2026-10-10)"; done
OUT="$("$SCRIPT" diary-section --date 2026-10-15 --mine-json "$SANDBOX/us.json")"
grep -q '^Directions learned today (active from the next session; retire with' <<<"$OUT" && pass "lists the directions learned today" || fail "directions header" "$OUT"
grep -q '^- D-.* — Never merge without asking (global)$' <<<"$OUT" && pass "one D-NNN — rule line per direction" || fail "direction line" "$OUT"
assert_eq "0" "$(grep -c 'docs rule one (' <<<"$OUT")" "older directions are not listed"
grep -q '^3 active directions share the scope "docs" (D-.*, D-.*, D-.*): they can be folded into that prompt or skill' <<<"$OUT" && pass "3 directions on one scope suggest folding them" || fail "scope suggestion" "$OUT"
assert_eq "0" "$(grep -c 'fix-friction' <<<"$OUT")" "and never tell the user to run /fix-friction"
grep -q "^- F-.* — Gitlab outage made the run loop on retries (frustration)$" <<<"$OUT" || grep -q "(frustration)" <<<"$OUT" && pass "a frustration seen today is listed" || fail "frustration line" "$OUT"
"$SCRIPT" directions retire "$last" >/dev/null
OUT="$("$SCRIPT" diary-section --date 2026-10-15 --mine-json "$SANDBOX/us.json")"
assert_eq "0" "$(grep -c 'share the scope' <<<"$OUT")" "retiring one drops the suggestion below 3"

# --- frustration with a proposal ------------------------------------------------
echo "frustration — proposal"
printf 'Script it.\n' >"$SANDBOX/fp.md"
out="$("$SCRIPT" frustration --date 2026-10-14 --what "Slow export" --class script --sig-hint "slow export" --rung script --proposal-file "$SANDBOX/fp.md")"
fid="$(jq -r .id <<<"$out")"
assert_eq "open" "$(fld "$fid" status)" "day 1: proposal stored, status stays open"
grep -q 'Script it.' "$FRICTION_WIKI/$fid.md" && pass "proposal stored on day 1" || fail "proposal stored" ""
out="$("$SCRIPT" frustration --date 2026-10-15 --what "Slow export" --class script --sig-hint "slow export" --rung script --proposal-file "$SANDBOX/fp.md")"
assert_eq "proposed" "$(fld "$fid" status)" "day 2: the script sets proposed"
assert_eq "script" "$(fld "$fid" rung)" "rung stored"
assert_eq "false" "$(jq -r .needs_proposal <<<"$out")" "and nothing is left to propose"

# --- section_edit: headings in text ---------------------------------------------
echo "set — headings in a proposal"
printf '## Evil\nbody\n# Top\n### keep\n' >"$SANDBOX/evil.md"
"$SCRIPT" set "$fid" --proposal-file "$SANDBOX/evil.md" --diagnosis "$(printf 'x\n## Y')"
assert_eq "4" "$(grep -c '^## ' "$FRICTION_WIKI/$fid.md")" "still exactly the four sections"
grep -q '^### Evil$' "$FRICTION_WIKI/$fid.md" && grep -q '^### Top$' "$FRICTION_WIKI/$fid.md" && pass "## and # are demoted to ###" || fail "demote" ""
assert_eq "$(printf '### Evil\nbody\n### Top\n### keep')" "$(awk '/^## Proposal/{f=1;next} /^## /{f=0} f' "$FRICTION_WIKI/$fid.md" | sed '/^$/d')" "the proposal stays in its section"

# --- file modes and temp files ----------------------------------------------------
echo "files"
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
assert_eq "644" "$(file_mode "$FRICTION_WIKI/$fid.md")" "F-file is 0644"
assert_eq "644" "$(file_mode "$LED")" "ledger.md is 0644"
assert_eq "0" "$(ls -A "$FRICTION_WIKI" | grep -c '\.[A-Za-z0-9]\{6\}$' | tr -d ' ')" "no temp files left behind"

# --- tool_error needs 2 occurrences or 2 days ---------------------------------------
echo "apply — tool_error"
TE="claude:tool_error:one-off boom"
mine "$SANDBOX/t1.json" 2026-10-20 "$TE|tool_error|high|1|boom"
OUT="$(apply 2026-10-20 "$SANDBOX/t1.json")"
assert_eq "0" "$(rg -l 'one-off boom' "$FRICTION_WIKI"/F-*.md 2>/dev/null | wc -l | tr -d ' ')" "a single tool_error does not get an entry"
OUT="$(apply 2026-10-20 "$SANDBOX/t1.json")"
assert_eq "0" "$(rg -l 'one-off boom' "$FRICTION_WIKI"/F-*.md 2>/dev/null | wc -l | tr -d ' ')" "the same day again still does not"
mine "$SANDBOX/t2.json" 2026-10-21 "$TE|tool_error|high|1|boom"
OUT="$(apply 2026-10-21 "$SANDBOX/t2.json")"
assert_eq "1" "$(jq '.new | length' <<<"$OUT")" "seen again on a later day: entry created"
mine "$SANDBOX/t3.json" 2026-10-22 "claude:tool_error:twice today|tool_error|high|2|boom"
assert_eq "1" "$(apply 2026-10-22 "$SANDBOX/t3.json" | jq '.new | length')" "2 occurrences in one day: entry created"
mine "$SANDBOX/t4.json" 2026-10-22 "x:auth:one auth|auth|high|1|a"
assert_eq "1" "$(apply 2026-10-22 "$SANDBOX/t4.json" | jq '.new | length')" "other kinds are unchanged"

# --- ingest -------------------------------------------------------------------------
echo "ingest"
rm -rf "$FRICTION_WIKI"
mine "$SANDBOX/i1.json" 2026-10-15 "$A|auth|high|1|Outlook not connected" "$B|blocked|high|1|x"
jq '. + {user_signals: [{text: "always script it", harness: "claude"}]}' "$SANDBOX/i1.json" >"$SANDBOX/i1u.json"
OUT="$(apply 2026-10-15 "$SANDBOX/i1u.json")"
assert_eq "1" "$(jq '.user_signals | length' <<<"$OUT")" "signals are passed before ingest"
cat >"$SANDBOX/r1.json" <<'EOT'
{"items": {"F-001": {"class": "env", "diagnosis": "Outlook auth lapsed", "rung": "config", "proposal": "## Rung\nconfig re-auth"},
           "F-002": {"class": "external", "diagnosis": "waits on approval"}},
 "directions": [{"rule": "Script every outage fix", "scope": "global", "quote": "always script it", "harness": "claude"}],
 "frustrations": [{"what_went_wrong": "Slow retries", "class": "script", "sig_hint": "slow retries", "rung": "script", "proposal": "backoff"}]}
EOT
before="$(snap)"
echo '{"items": {"F-001": {"class": "env", "diagnosis": "ok"}, "F-009": {"class": "env", "diagnosis": "x"}}, "directions": [{"rule": "r", "scope": "g"}]}' >"$SANDBOX/bad1.json"
"$SCRIPT" ingest "$SANDBOX/bad1.json" --date 2026-10-15 2>"$SANDBOX/err"; assert_eq "1" "$?" "unknown id is refused"
grep -q 'F-009: no such entry' "$SANDBOX/err" && pass "error names the id" || fail "error text" "$(cat "$SANDBOX/err")"
assert_eq "$before" "$(snap)" "invalid input applies nothing (valid parts included)"
for bad in '{"items": {"F-001": {"class": "bogus", "diagnosis": "x"}}}' \
           '{"items": {"F-001": {"class": "env", "diagnosis": "x", "rung": "magic", "proposal": "p"}}}' \
           '{"items": {"F-001": {"class": "env", "diagnosis": "x", "rung": "script"}}}' \
           '{"items": {"F-001": {"class": "env", "diagnosis": "x", "extra": 1}}}' \
           '{"frustrations": [{"what_went_wrong": "w", "class": "env", "sig_hint": "h"}]}' \
           '{"directions": [{"rule": "r"}]}' '{"directions": [{"rule": "r", "scope": "$(id)"}]}' \
           '{"directions": [{"rule": "r", "scope": "two words"}]}' 'not json'; do
  printf '%s' "$bad" >"$SANDBOX/bad.json"
  "$SCRIPT" ingest "$SANDBOX/bad.json" --date 2026-10-15 2>/dev/null; rc=$?
  [ "$rc" = 1 ] && [ "$before" = "$(snap)" ] && pass "rejected, nothing applied: ${bad:0:60}" || fail "invalid input" "$bad rc=$rc"
done
OUT="$("$SCRIPT" ingest "$SANDBOX/r1.json" --date 2026-10-15)"
assert_eq "proposed|env|config" "$(fld F-001 status)|$(fld F-001 class)|$(fld F-001 rung)" "item with a proposal becomes proposed"
grep -q '^### Rung$' "$FRICTION_WIKI/F-001.md" && pass "proposal heading demoted" || fail "demote in ingest" ""
assert_eq "wontfix|external" "$(fld F-002 status)|$(fld F-002 class)" "external becomes wontfix"
assert_eq "D-001" "$(jq -r '.directions[0]' <<<"$OUT")" "direction added"
grep -q '(claude)' "$FRICTION_WIKI/directions.md" && pass "direction keeps its harness" || fail "harness" ""
assert_eq "open" "$(fld F-003 status)" "frustration entry created, open on day 1"
assert_eq "[]" "$("$SCRIPT" apply --date 2026-10-15 --mine-json "$SANDBOX/i1u.json" | jq -c .user_signals)" "re-run apply: signals dropped once ingested"
before="$(snap)"
sed -i.bak 's/Script every outage fix/Always script each outage fix/' "$SANDBOX/r1.json"
"$SCRIPT" ingest "$SANDBOX/r1.json" --date 2026-10-15 | jq -e .skipped_signals >/dev/null && pass "re-ingest skips directions and frustrations" || fail "skip" ""
apply 2026-10-15 "$SANDBOX/i1u.json" >/dev/null
assert_eq "$before" "$(snap)" "re-run of apply + ingest creates no new entries"
assert_eq "1" "$(grep -c '^| D-' "$FRICTION_WIKI/directions.md")" "one direction"

# --- coach --------------------------------------------------------------------
echo "coach"
export FRICTION_WIKI="$SANDBOX/coach"
# cg FILE DATE then groups as "sig|kind|count|days"; days may be empty
cg() {
  local file="$1" d="$2"; shift 2
  printf '%s\n' "$@" | jq -Rn --arg d "$d" '{date: $d, groups: [inputs | split("|") | {sig: .[0], source: "x", kind: .[1], count: (.[2] | tonumber), keys: [], confidence: "high",
    samples: ["sample " + .[0]], evidence: []} + (if .[3] != "" then {days: (.[3] | tonumber)} else {} end)]}' >"$file"
}
is_safe() { bash -c 'eval "$(sed -n "/^is_safety()/,/^}/p" "$1")"; is_safety "$2" && echo yes || echo no' _ "$SCRIPT" "$1"; }
hist() { sed -n '/^## History/,$p' "$FRICTION_WIKI/$1.md" | grep -c '^- 2026'; }
offered_ids() { jq -r '[.offer[].id] | sort | join(" ")' <<<"$1"; }
printf 'Do the thing\nsecond line\n' >"$SANDBOX/prop.md"

cg "$SANDBOX/c0.json" 2026-10-01 "t:tool:status probe|tool|1|"
apply 2026-10-01 "$SANDBOX/c0.json" >/dev/null
for st in offered declined landing landed failed; do
  "$SCRIPT" set F-001 --status "$st" --date 2026-10-02 2>/dev/null; assert_eq "$st" "$(fld F-001 status)" "set accepts status $st"
done
"$SCRIPT" set F-001 --status bogus 2>/dev/null; assert_eq "1" "$?" "set still rejects an unknown status"
"$SCRIPT" set F-001 --safety true --queued-by user --date 2026-10-02
assert_eq "true|user" "$(fld F-001 safety)|$(fld F-001 queued_by)" "set writes safety and queued_by"
"$SCRIPT" set F-001 --safety false --date 2026-10-02; assert_eq "false" "$(fld F-001 safety)" "set --safety false is explicit"
"$SCRIPT" set F-001 --safety maybe 2>/dev/null; assert_eq "1" "$?" "bad --safety rejected"
rm -rf "$FRICTION_WIKI"

# window fields from apply
cg "$SANDBOX/c1.json" 2026-10-10 "r:repeat:alpha|repeat|4|3" "r:tool:beta|tool|9|9"
apply 2026-10-10 "$SANDBOX/c1.json" >/dev/null
assert_eq "4|3" "$(fld F-001 window_count)|$(fld F-001 window_days)" "repeat group with days writes window_count/window_days"
assert_eq "|" "$(fld F-002 window_count)|$(fld F-002 window_days)" "tool kind gets no window fields"
cg "$SANDBOX/c1b.json" 2026-10-11 "r:repeat:alpha|repeat|7|5"
apply 2026-10-11 "$SANDBOX/c1b.json" >/dev/null
assert_eq "7|5" "$(fld F-001 window_count)|$(fld F-001 window_days)" "window fields are overwritten on the next run"
assert_eq "2" "$(sed -n '/^## Evidence/,/^## Diagnosis/p' "$FRICTION_WIKI/F-001.md" | grep -c '^- 2026')" "an evidence bullet is still added per date"
rm -rf "$FRICTION_WIKI"

# offer selection: limit, repeat thresholds, later rule
cg "$SANDBOX/c2.json" 2026-10-10 "o:tool:a|tool|2|" "o:tool:b|tool|2|" "o:tool:c|tool|2|" "o:tool:d|tool|2|" "o:repeat:low|repeat|2|5" "o:repeat:short|repeat|5|1" "o:repeat:ok|repeat|3|2"
apply 2026-10-10 "$SANDBOX/c2.json" >/dev/null
cg "$SANDBOX/c2b.json" 2026-10-12 "o:tool:b|tool|1|"
apply 2026-10-12 "$SANDBOX/c2b.json" >/dev/null
for n in 1 2 3 4 5 6 7; do "$SCRIPT" set "F-00$n" --status proposed --proposal-file "$SANDBOX/prop.md" --date 2026-10-12; done
OUT="$("$SCRIPT" coach-offer --date 2026-10-15)"
assert_eq "3" "$(jq '.offer | length' <<<"$OUT")" "default limit is 3"
assert_eq "F-002" "$(jq -r '.offer[0].id' <<<"$OUT")" "newest last comes first"
assert_eq "[]" "$(jq -c .results <<<"$OUT")" "no results yet"
assert_eq "offered|2026-10-15" "$(fld F-002 status)|$(fld F-002 offered_on)" "offered entry is marked offered with offered_on"
assert_eq "Do the thing" "$(jq -r '.offer[0].proposal_summary' <<<"$OUT")" "proposal_summary is the first line"
assert_eq "3|false|tool" "$(jq -r '.offer[0] | "\(.count)|\(.safety)|\(.kind)"' <<<"$OUT")" "count sums evidence, safety false, kind from the signature"
assert_eq "2" "$(jq '.offer[0].evidence | length' <<<"$OUT")" "two evidence samples"
case "$(jq -r '.offer[0].evidence[0]' <<<"$OUT")" in 2026-10-12*) pass "newest evidence first" ;; *) fail "newest evidence first" "$(jq -c '.offer[0].evidence' <<<"$OUT")" ;; esac
snap1="$(snap)"; first_ids="$(offered_ids "$OUT")"
OUT="$("$SCRIPT" coach-offer --date 2026-10-15 --limit 10)"
assert_eq "$first_ids" "$(offered_ids "$OUT")" "a second offer on the same date returns the same ids"
assert_eq "$snap1" "$(snap)" "a second offer on the same date writes nothing"
OUT="$("$SCRIPT" coach-offer --date 2026-10-16 --limit 10)"
assert_eq "F-001 F-003" "$(offered_ids "$OUT")" "next day: the rest are offered; repeat below 3 count or 2 days is not; already offered ones wait"
assert_eq "proposed proposed" "$(fld F-005 status) $(fld F-006 status)" "gated repeat entries stay proposed"
assert_eq "[]" "$(jq -c '.offer' <<<"$("$SCRIPT" coach-offer --date 2026-10-17 --limit 10)")" "offered 1-2 days ago is not re-offered"
OUT="$("$SCRIPT" coach-offer --date 2026-10-18 --limit 10)"
assert_eq "F-002 F-004 F-007" "$(offered_ids "$OUT")" "offered 3 days ago is offered again"

# answers
"$SCRIPT" coach-answer F-001 later --date 2026-10-18
assert_eq "offered|later" "$(fld F-001 status)|$(fld F-001 answer)" "later keeps offered"
assert_eq "1" "$(grep -c 'answered later' "$FRICTION_WIKI/F-001.md")" "later records one History line"
"$SCRIPT" coach-answer F-001 later --date 2026-10-18
assert_eq "1" "$(grep -c 'answered later' "$FRICTION_WIKI/F-001.md")" "same answer twice adds nothing"
"$SCRIPT" coach-answer F-002 yes --date 2026-10-18
assert_eq "landing" "$(fld F-002 status)" "yes -> landing"
before="$(cat "$FRICTION_WIKI/F-002.md")"
"$SCRIPT" coach-answer F-002 yes --date 2026-10-18
assert_eq "$before" "$(cat "$FRICTION_WIKI/F-002.md")" "yes twice leaves the file unchanged"
h0="$(hist F-002)"
"$SCRIPT" coach-answer F-002 no --date 2026-10-18
assert_eq "declined|3" "$(fld F-002 status)|$(fld F-002 declined_count)" "no -> declined with declined_count = current count"
assert_eq "$((h0 + 1))" "$(hist F-002)" "a different answer adds exactly one History line"
"$SCRIPT" coach-answer F-002 no --date 2026-10-18
assert_eq "$((h0 + 1))" "$(hist F-002)" "no twice adds nothing"
"$SCRIPT" coach-answer F-009 yes --date 2026-10-18 2>/dev/null; assert_eq "1" "$?" "answer on a missing entry fails"
"$SCRIPT" coach-answer F-005 yes --date 2026-10-18 2>"$SANDBOX/err"; assert_eq "1" "$?" "answering a never-offered entry exits 1"
assert_eq "proposed|" "$(fld F-005 status)|$(fld F-005 answer)" "a never-offered entry is unchanged"
grep -q 'F-005 is proposed, not waiting for an answer' "$SANDBOX/err" && pass "refusal names the status" || fail "refusal message" "$(cat "$SANDBOX/err")"
"$SCRIPT" coach-answer F-004 yes --date 2026-10-18
"$SCRIPT" set F-004 --status failed --date 2026-10-19
h4="$(hist F-004)"; b4="$(cat "$FRICTION_WIKI/F-004.md")"
"$SCRIPT" coach-answer F-004 yes --date 2026-10-20; assert_eq "0" "$?" "a stale identical answer is a no-op"
assert_eq "failed|$h4" "$(fld F-004 status)|$(hist F-004)" "failed stays failed, no History line"
assert_eq "$b4" "$(cat "$FRICTION_WIKI/F-004.md")" "stale answer writes nothing"
"$SCRIPT" coach-answer F-004 no --date 2026-10-20 2>/dev/null; assert_eq "1" "$?" "a different answer on a failed entry is refused"
assert_eq "failed" "$(fld F-004 status)" "refused answer leaves the status"

# declined doubling (F-002 declined at count 3)
assert_eq "no" "$(jq -r '[.offer[].id] | index("F-002") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" coach-offer --date 2026-10-30 --limit 10)")" "declined is not offered at the same count"
cg "$SANDBOX/c2c.json" 2026-10-31 "o:tool:b|tool|2|"
apply 2026-10-31 "$SANDBOX/c2c.json" >/dev/null
assert_eq "no" "$(jq -r '[.offer[].id] | index("F-002") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" coach-offer --date 2026-10-31 --limit 10)")" "declined at 2x-1 is not offered"
cg "$SANDBOX/c2d.json" 2026-11-01 "o:tool:b|tool|1|"
apply 2026-11-01 "$SANDBOX/c2d.json" >/dev/null
assert_eq "yes" "$(jq -r '[.offer[].id] | index("F-002") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" coach-offer --date 2026-11-01 --limit 10)")" "declined is offered again at 2x the declined count"
rm -rf "$FRICTION_WIKI"

# declined doubling uses window_count when present
cg "$SANDBOX/c3.json" 2026-10-10 "w:restated:x|restated|4|3"
apply 2026-10-10 "$SANDBOX/c3.json" >/dev/null
"$SCRIPT" set F-001 --status proposed --proposal-file "$SANDBOX/prop.md" --date 2026-10-10
"$SCRIPT" coach-offer --date 2026-10-10 >/dev/null
"$SCRIPT" coach-answer F-001 no --date 2026-10-10
assert_eq "4" "$(fld F-001 declined_count)" "declined_count is the window count"
cg "$SANDBOX/c3b.json" 2026-10-20 "w:restated:x|restated|7|3"
apply 2026-10-20 "$SANDBOX/c3b.json" >/dev/null
assert_eq "[]" "$("$SCRIPT" coach-offer --date 2026-10-20 | jq -c '[.offer[].id]')" "window count 7 < 8: still declined"
cg "$SANDBOX/c3c.json" 2026-10-21 "w:restated:x|restated|8|4"
apply 2026-10-21 "$SANDBOX/c3c.json" >/dev/null
OUT="$("$SCRIPT" coach-offer --date 2026-10-21)"
assert_eq "F-001|8|4" "$(jq -r '.offer[0] | "\(.id)|\(.count)|\(.days)"' <<<"$OUT")" "window count 8 = 2x4: offered with window count and days"
rm -rf "$FRICTION_WIKI"

# results
cg "$SANDBOX/c4.json" 2026-10-10 "l:tool:one|tool|2|" "l:tool:two|tool|2|" "l:tool:three|tool|2|"
apply 2026-10-10 "$SANDBOX/c4.json" >/dev/null
"$SCRIPT" set F-001 --status landed --fix abc1234..def5678 --reason "user step: run ./install.sh" --date 2026-10-11
"$SCRIPT" set F-002 --status failed --reason $'rebase onto main\nconflicts' --date 2026-10-11
"$SCRIPT" set F-003 --status landing --date 2026-10-11
OUT="$("$SCRIPT" coach-offer --date 2026-10-12)"
assert_eq "F-001 F-002" "$(jq -r '[.results[].id] | sort | join(" ")' <<<"$OUT")" "results are landed and failed entries"
assert_eq "landed|abc1234..def5678|user step: run ./install.sh" "$(jq -r '.results[] | select(.id == "F-001") | "\(.status)|\(.fix)|\(.reason)"' <<<"$OUT")" "a landed result carries status, range and note"
assert_eq "failed|rebase onto main conflicts" "$(jq -r '.results[] | select(.id == "F-002") | "\(.status)|\(.reason)"' <<<"$OUT")" "a failed result carries its reason on one line"
assert_eq "2026-10-12" "$(fld F-001 result_reported_on)" "result_reported_on is set"
assert_eq "$(jq -r '[.results[].id] | sort | join(" ")' <<<"$OUT")" "$(jq -r '[.results[].id] | sort | join(" ")' <<<"$("$SCRIPT" coach-offer --date 2026-10-12)")" "a second offer on the same date shows the same results"
assert_eq "[]" "$("$SCRIPT" coach-offer --date 2026-10-13 | jq -c .results)" "the next day has no results"
"$SCRIPT" set F-002 --status landing --date 2026-10-13
assert_eq "|" "$(fld F-002 reason)|$(fld F-002 result_reported_on)" "a new landing attempt clears the old reason and report date"
"$SCRIPT" set F-002 --status failed --reason "again" --date 2026-10-14
assert_eq "F-002|again" "$("$SCRIPT" coach-offer --date 2026-10-14 | jq -r '.results[] | "\(.id)|\(.reason)"')" "so its next result is reported"
"$SCRIPT" set F-001 --reason "" --date 2026-10-14
assert_eq "" "$(fld F-001 reason)" "--reason \"\" clears the reason"
rm -rf "$FRICTION_WIKI"

# ingest safety
cg "$SANDBOX/c5.json" 2026-10-10 "s:tool:safe|tool|2|" "s:tool:guard|tool|2|"
apply 2026-10-10 "$SANDBOX/c5.json" >/dev/null
jq -n '{items: {"F-001": {class: "script", diagnosis: "d", rung: "script", proposal: "Edit bin/start-day to print the date"},
  "F-002": {class: "script", diagnosis: "d", rung: "config", proposal: "Loosen secrets-guard for this path"}}}' >"$SANDBOX/c5r.json"
"$SCRIPT" ingest "$SANDBOX/c5r.json" --date 2026-10-10 >/dev/null
assert_eq "" "$(fld F-001 safety)" "a proposal about bin/start-day leaves safety unset"
assert_eq "true" "$(fld F-002 safety)" "a proposal naming secrets-guard sets safety: true"
jq -n '{items: {"F-002": {class: "script", diagnosis: "d2", rung: "script", proposal: "Print the date"}}}' >"$SANDBOX/c5s.json"
"$SCRIPT" ingest "$SANDBOX/c5s.json" --date 2026-10-11 >/dev/null
assert_eq "true" "$(fld F-002 safety)" "a later harmless proposal never resets safety"
jq -n '{frustrations: [{what_went_wrong: "hook blocked me", class: "script", sig_hint: "hook-block", rung: "config", proposal: "Relax the PreToolUse hook"}]}' >"$SANDBOX/c5f.json"
"$SCRIPT" ingest "$SANDBOX/c5f.json" --date 2026-10-12 >/dev/null
assert_eq "true" "$(fld F-003 safety)" "a frustration proposal mentioning PreToolUse sets safety"
for t in "secrets-guard" "docker-guard" "the allow rule" "deny rule" "autoMode" "bypass" ".githooks/pre-commit" "hooks.json" "worktree guard" "mr-description-review" "auto-approve" "automatically approve" "skipDangerous" "permissions"; do
  assert_eq "yes" "$(is_safe "x $t y")" "is_safety matches $t"
done
assert_eq "no" "$(is_safe "edit bin/start-day")" "is_safety ignores bin/start-day"
for t in "add it to the allowlist" "the allow list" "an allow-list entry" "switch on auto mode" "auto-mode" "AutoMode" \
  "allowedTools" "defaultMode: acceptEdits" "the WorktreeCreate hook" "WorktreeRemove" "the wt hook" "the docker guard" \
  "secrets guard" "worktree-guard" "relax the guard" "settings.json allowlist" "disable the docs-check commit hook" \
  "the commit-msg hook" "the MR-description gate" "claude --dangerously-skip-permissions" "a permission prompt" \
  "a deny entry" "PreToolUse" "hook.json" "hooks.json" ".githooks/commit-msg" "bypass it" "skipDangerousModePermissionPrompt" \
  "auto-approve" "autoapprove"; do
  assert_eq "yes" "$(is_safe "x $t y")" "is_safety matches $t"
done
for t in "allowed-tools: Bash(*)" "allowed_tools" "allowed tools" "auto approve" "autoapproval" "git commit --no-verify" \
  "git config core.hooksPath /dev/null" "the commit hook" "commit-hook" "docs check" "docscheck" "plugin.json" \
  ".claude-plugin/marketplace.json" "add a line to CLAUDE.md" "edit claude/CLAUDE.md" "secret-guard" "secrets-guard" \
  "permissionMode: bypassPermissions" "the permission mode" "bypasspermissions"; do
  assert_eq "yes" "$(is_safe "x $t y")" "is_safety matches $t"
done
for t in "Print the date" "Create /run-tests" "Try jira-cli view instead of the curl wrapper." "Do the thing" "safeguarding the cache"; do
  assert_eq "no" "$(is_safe "$t")" "is_safety leaves alone: $t"
done
rm -rf "$FRICTION_WIKI"

# safety backfill: coach-offer and safety-check judge every candidate, not only ingested ones
cg "$SANDBOX/c6.json" 2026-10-10 "b:tool:old|tool|2|" "b:tool:plain|tool|2|" "b:tool:flagged|tool|2|" "b:secret:x|secret|1|" "b:tool:done|tool|2|"
apply 2026-10-10 "$SANDBOX/c6.json" >/dev/null
printf 'Change bin/secrets-guard to allow the wiki path\n' >"$SANDBOX/p6a.md"
printf 'Print the date\n' >"$SANDBOX/p6b.md"
printf 'Add the docker guard bypass\n' >"$SANDBOX/p6e.md"
"$SCRIPT" set F-001 --status proposed --proposal-file "$SANDBOX/p6a.md" --date 2026-10-10
"$SCRIPT" set F-002 --status proposed --proposal-file "$SANDBOX/p6b.md" --date 2026-10-10
"$SCRIPT" set F-003 --status proposed --proposal-file "$SANDBOX/p6b.md" --safety true --date 2026-10-10
"$SCRIPT" set F-004 --status proposed --proposal-file "$SANDBOX/p6b.md" --date 2026-10-10
"$SCRIPT" set F-005 --status fixed --proposal-file "$SANDBOX/p6e.md" --date 2026-10-10
assert_eq "|||" "$(fld F-001 safety)|$(fld F-002 safety)|$(fld F-004 safety)|$(fld F-005 safety)" "pre-existing entries without a safety field"
OUT="$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10)"
assert_eq "true" "$(jq -r '.offer[] | select(.id == "F-001") | .safety' <<<"$OUT")" "coach-offer marks an unflagged secrets-guard proposal as safety"
assert_eq "true|true" "$(fld F-001 safety)|$(fld F-004 safety)" "and writes safety: true back (a secret entry too)"
assert_eq "|true" "$(fld F-002 safety)|$(fld F-003 safety)" "a harmless proposal stays unset; a stored true stays true"
assert_eq "" "$(fld F-005 safety)" "a fixed entry is left alone"
"$SCRIPT" set F-003 --proposal-file "$SANDBOX/p6b.md" --date 2026-10-12
assert_eq "true" "$(jq -r '.offer[] | select(.id == "F-003") | .safety' <<<"$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10)")" "never true -> false"
assert_eq "false" "$("$SCRIPT" safety-check F-002)" "safety-check: a harmless entry is false"
"$SCRIPT" set F-002 --proposal-file "$SANDBOX/p6e.md" --date 2026-10-12
assert_eq "true|true" "$("$SCRIPT" safety-check F-002)|$(fld F-002 safety)" "safety-check re-reads the proposal and writes true back"
"$SCRIPT" safety-check F-099 2>/dev/null; assert_eq "1" "$?" "safety-check of an unknown id fails"
sleep 30 & HOLDER=$!
mkdir "$FRICTION_WIKI/.lock"; echo "$HOLDER" >"$FRICTION_WIKI/.lock/pid"
out="$(FRICTION_LOCK_WAIT=1 "$SCRIPT" safety-check F-002 2>&1)"; rc=$?
assert_eq "75" "$rc" "safety-check exits 75 while the ledger is busy"
assert_has "ledger busy" "$out" "and says so"
FRICTION_LOCK_WAIT=1 "$SCRIPT" set F-002 --reason x --date 2026-10-12 2>/dev/null; assert_eq "1" "$?" "other writers still exit 1 when busy"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; rm -rf "$FRICTION_WIKI/.lock"
# a held safety change goes back to proposed: it waits to be offered afresh, its old answer gone
"$SCRIPT" coach-offer --date 2026-10-12 --limit 10 >/dev/null
"$SCRIPT" coach-answer F-002 yes --date 2026-10-12
assert_eq "landing|2026-10-12|yes|2026-10-12" "$(fld F-002 status)|$(fld F-002 offered_on)|$(fld F-002 answer)|$(fld F-002 answered_on)" "an answered entry before the hold"
"$SCRIPT" set F-002 --status proposed --safety true --reason "needs the user: touches a safety control: bin/x" --date 2026-10-12
assert_eq "proposed|true||||needs the user: touches a safety control: bin/x" \
  "$(fld F-002 status)|$(fld F-002 safety)|$(fld F-002 offered_on)|$(fld F-002 answer)|$(fld F-002 answered_on)|$(fld F-002 reason)" \
  "a change to proposed clears offered_on, answer and answered_on"
assert_eq "true" "$("$SCRIPT" coach-offer --date 2026-10-13 --limit 10 | jq -r '.offer[] | select(.id == "F-002") | .safety')" "and it is offered again, as a safety item"
rm -rf "$FRICTION_WIKI"

# offer items carry rung, the full proposal, the exact change and a restated direction
cg "$SANDBOX/c7.json" 2026-10-10 "i:tool:arrow|tool|2|" "i:tool:block|tool|2|" "i:restated:rule|restated|3|2" "i:tool:none|tool|2||"
apply 2026-10-10 "$SANDBOX/c7.json" >/dev/null
printf 'Allow the wiki path.\nChange: bin/secrets-guard: deny ~/wiki → allow ~/wiki/work\n- settings.json defaultMode: default -> acceptEdits\nWhy: it blocks the sync.\n' >"$SANDBOX/p7a.md"
printf 'Widen the rule.\n\n## Change\n\n- claude/settings.json allow: [] → [Bash(rg:*)]\n- pi/settings.json: same\n\n## Test\nbin/x.test.sh case → green\n' >"$SANDBOX/p7b.md"
printf 'Keep it as a standing direction.\nDirection: Run the linter before every commit\nScope: reviews\n' >"$SANDBOX/p7c.md"
"$SCRIPT" set F-001 --status proposed --rung config --proposal-file "$SANDBOX/p7a.md" --date 2026-10-10
"$SCRIPT" set F-002 --status proposed --rung config --proposal-file "$SANDBOX/p7b.md" --date 2026-10-10
"$SCRIPT" set F-003 --status proposed --rung prompt --proposal-file "$SANDBOX/p7c.md" --date 2026-10-10
"$SCRIPT" set F-004 --status proposed --proposal-file "$SANDBOX/prop.md" --date 2026-10-10
sed -i.bak 's/^days: .*/days:/' "$FRICTION_WIKI/F-004.md" && rm -f "$FRICTION_WIKI/F-004.md.bak"
OUT="$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10)"
it() { jq -c --arg i "$1" ".offer[] | select(.id == \$i) | $2" <<<"$OUT"; }
assert_eq '"config"' "$(it F-001 .rung)" "an offer item carries its rung"
assert_eq '["Change: bin/secrets-guard: deny ~/wiki → allow ~/wiki/work","- settings.json defaultMode: default -> acceptEdits"]' "$(it F-001 .change)" "change: the before → after and -> lines"
assert_eq '["- claude/settings.json allow: [] → [Bash(rg:*)]","- pi/settings.json: same"]' "$(it F-002 .change)" "change: a ## Change block wins over arrows elsewhere"
assert_eq '[]' "$(it F-004 .change)" "change: empty when the proposal states none"
assert_eq "$(cat "$SANDBOX/p7a.md")" "$(it F-001 .proposal | jq -r .)" "the full proposal text"
assert_eq '{"rule":"Run the linter before every commit","scope":"reviews"}' "$(it F-003 .direction)" "a Direction line gives the rule and its scope"
assert_eq 'null' "$(it F-001 .direction)" "no Direction line: null"
assert_eq "0" "$(it F-004 .days)" "an entry with empty days still offers (days 0)"
long="$(printf 'line of the proposal that goes on %.0s\n' $(seq 1 80))"
printf '%s\n' "$long" >"$SANDBOX/p7d.md"
"$SCRIPT" set F-004 --proposal-file "$SANDBOX/p7d.md" --date 2026-10-12
assert_eq "1500" "$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10 | jq '.offer[] | select(.id == "F-004") | .proposal | length')" "the proposal is cut to 1500 chars"
for s in '$(touch /tmp/x)' 'a b' '"; rm -rf ~; "' '`id`'; do
  printf 'Keep it.\nDirection: Keep the rule\nScope: %s\n' "$s" >"$SANDBOX/p7e.md"
  "$SCRIPT" set F-003 --proposal-file "$SANDBOX/p7e.md" --date 2026-10-12
  assert_eq '{"rule":"Keep the rule","scope":"global"}' "$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10 | jq -c '.offer[] | select(.id == "F-003") | .direction')" "an unsafe Scope line becomes global: $s"
done
printf 'Keep it.\nDirection: Keep the rule\nScope: dotfiles:claude/commands/review.md\n' >"$SANDBOX/p7e.md"
"$SCRIPT" set F-003 --proposal-file "$SANDBOX/p7e.md" --date 2026-10-12
assert_eq '"dotfiles:claude/commands/review.md"' "$("$SCRIPT" coach-offer --date 2026-10-12 --limit 10 | jq -c '.offer[] | select(.id == "F-003") | .direction.scope')" "a path-like scope is kept"
rm -rf "$FRICTION_WIKI"

# retryable results, and done for secret entries
cg "$SANDBOX/c8.json" 2026-10-10 "r:tool:a|tool|2|" "r:tool:b|tool|2|" "r:tool:c|tool|2|" "files:secret:glpat:/p/x|secret|1|"
apply 2026-10-10 "$SANDBOX/c8.json" >/dev/null
"$SCRIPT" set F-001 --status failed --reason "uncommitted edits in notes.txt" --date 2026-10-11
"$SCRIPT" set F-002 --status failed --reason "needs the user: rotate it" --date 2026-10-11
"$SCRIPT" set F-003 --status landed --fix a..b --date 2026-10-11
OUT="$("$SCRIPT" coach-offer --date 2026-10-12)"
assert_eq "F-001:true F-002:false F-003:false" "$(jq -r '[.results[] | "\(.id):\(.retryable)"] | sort | join(" ")' <<<"$OUT")" "only a failure that does not need the user is retryable"
"$SCRIPT" set F-004 --status proposed --proposal-file "$SANDBOX/prop.md" --date 2026-10-12
"$SCRIPT" coach-offer --date 2026-10-13 >/dev/null
"$SCRIPT" coach-answer F-004 yes --date 2026-10-13 2>"$SANDBOX/err"; assert_eq "1" "$?" "yes on a secret entry is refused"
assert_eq "offered" "$(fld F-004 status)" "and changes nothing"
"$SCRIPT" coach-answer F-004 done --date 2026-10-13; assert_eq "0" "$?" "done on a secret entry is accepted"
assert_eq "fixed|done|2026-10-13" "$(fld F-004 status)|$(fld F-004 answer)|$(fld F-004 answered_on)" "done -> fixed"
"$SCRIPT" coach-answer F-004 later --date 2026-10-13; assert_eq "offered" "$(fld F-004 status)" "a different answer the same day still wins"
"$SCRIPT" coach-answer F-001 done --date 2026-10-13 2>/dev/null; assert_eq "1" "$?" "done is refused for a non-secret entry"
rm -rf "$FRICTION_WIKI"
export FRICTION_WIKI="$SANDBOX/friction"
# ingest cards and secret
echo "ingest — cards and secret"
rm -rf "$FRICTION_WIKI"
export CARDS_DIR="$SANDBOX/cards"
cg "$SANDBOX/k1.json" 2026-10-20 "claude:secret:aws-key|secret|1|" "claude:repeat:run tests|repeat|3|2"
apply 2026-10-20 "$SANDBOX/k1.json" >/dev/null
jq -n '{items: {"F-001": {class: "model", diagnosis: "key pasted", rung: "prompt", proposal: "Rotate the key, then use $(secret NAME)"},
  "F-002": {class: "model", diagnosis: "repeats", rung: "prompt", proposal: "Create /run-tests"}},
  cards: [{front: "What does a WAL do?", back: "Logs writes first.", tags: ["tech"], source: "claude/s1.jsonl 2026-10-20"},
          {front: "What does a WAL do?", back: "dup", tags: []}]}' >"$SANDBOX/k1r.json"
"$SCRIPT" ingest "$SANDBOX/k1r.json" --date 2026-10-20 >/dev/null
assert_eq "true" "$(fld F-001 safety)" "a secret item ingests with safety: true"
assert_eq "" "$(fld F-002 safety)" "a repeat item stays unsafe"
assert_eq "1" "$(ls "$CARDS_DIR" | wc -l | tr -d ' ')" "cards are created, identical fronts deduped"
grep -q 'Logs writes first' "$CARDS_DIR"/*.md && pass "card body stored" || fail "card body" ""
"$SCRIPT" ingest "$SANDBOX/k1r.json" --date 2026-10-20 >/dev/null
jq -n '{cards: [{front: "Another?", back: "yes"}]}' >"$SANDBOX/k2r.json"
"$SCRIPT" ingest "$SANDBOX/k2r.json" --date 2026-10-20 >/dev/null
assert_eq "1" "$(ls "$CARDS_DIR" | wc -l | tr -d ' ')" "cards are skipped on a re-run of an ingested date"
before="$(snap)"; cb="$(ls "$CARDS_DIR" | wc -l | tr -d ' ')"
for bad in '{"cards": [{"front": "q"}]}' '{"cards": [{"front": "q", "back": " "}]}' '{"cards": [{"front": "q", "back": "b", "tags": "x"}]}' \
           '{"cards": [{"front": "q", "back": "b", "tags": [1]}]}' '{"cards": [{"front": "q", "back": "b", "extra": 1}]}' '{"cards": {}}' \
           '{"cards": [{"front": "q9", "back": "b"}, {"front": "q8"}]}'; do
  printf '%s' "$bad" >"$SANDBOX/bad.json"
  "$SCRIPT" ingest "$SANDBOX/bad.json" --date 2026-10-21 2>/dev/null; rc=$?
  [ "$rc" = 1 ] && [ "$before" = "$(snap)" ] && [ "$cb" = "$(ls "$CARDS_DIR" | wc -l | tr -d ' ')" ] && pass "rejected, nothing applied: ${bad:0:60}" || fail "invalid cards" "$bad rc=$rc"
done
before="$(snap)"
CARDS_BIN="$SANDBOX/nocards" "$SCRIPT" ingest "$SANDBOX/k2r.json" --date 2026-10-22 2>"$SANDBOX/err"; rc=$?
[ "$rc" = 1 ] && [ "$before" = "$(snap)" ] && pass "missing cards binary with cards: refused, nothing applied" || fail "missing cards bin" "rc=$rc"
grep -q 'not executable' "$SANDBOX/err" && ! grep -q 'friction-ledger: friction-ledger' "$SANDBOX/err" && pass "clear single-prefix message" || fail "message" "$(cat "$SANDBOX/err")"
printf '#!/bin/bash\ncase "$*" in *"Bad one"*) exit 1 ;; esac\nexec "$CARDS_CLI" "$@"\n' >"$SANDBOX/stubcards"; chmod +x "$SANDBOX/stubcards"
cg "$SANDBOX/k3.json" 2026-10-23 "claude:repeat:another|repeat|3|2"
apply 2026-10-23 "$SANDBOX/k3.json" >/dev/null
jq -n '{items: {"F-003": {class: "model", diagnosis: "d", rung: "prompt", proposal: "Create /x"}},
  cards: [{front: "Bad one", back: "b"}, {front: "Good one", back: "g"}]}' >"$SANDBOX/k3r.json"
CARDS_BIN="$SANDBOX/stubcards" "$SCRIPT" ingest "$SANDBOX/k3r.json" --date 2026-10-23 2>"$SANDBOX/err"; rc=$?
assert_eq "0" "$rc" "one failing cards add does not fail ingest"
grep -q 'cards add failed for "Bad one"' "$SANDBOX/err" && pass "warning names the card" || fail "warning" "$(cat "$SANDBOX/err")"
assert_eq "2" "$(ls "$CARDS_DIR" | wc -l | tr -d ' ')" "the other card was added"
assert_eq "proposed" "$(fld F-003 status)" "items were applied"
[ -f "$FRICTION_WIKI/.ingested/2026-10-23" ] && pass "date marked ingested" || fail "ingested mark" ""
rm -rf "$FRICTION_WIKI" "$CARDS_DIR"
unset CARDS_DIR
export FRICTION_WIKI="$SANDBOX/friction"

# --- coach-log ----------------------------------------------------------------
echo "coach-log"
rm -rf "$FRICTION_WIKI"
CL="$FRICTION_WIKI/coach-log.md"
"$SCRIPT" coach-log --date 2026-10-20 --offered 3 --answered 2 --landed 1 --failed 0 --cards 5; assert_eq "0" "$?" "coach-log writes a row"
"$SCRIPT" coach-log --date 2026-10-18 --offered 1 --answered 1 --landed 0 --failed 1 --cards 0
assert_eq "2026-10-18 2026-10-20" "$(grep -E '^\| [0-9]{4}-' "$CL" | awk -F'|' '{gsub(/ /,"",$2); printf "%s ", $2}' | sed 's/ $//')" "rows are sorted by date"
"$SCRIPT" coach-log --date 2026-10-20 --offered 3 --answered 3 --landed 2 --failed 0 --cards 4
assert_eq "2" "$(grep -cE '^\| [0-9]{4}-' "$CL")" "a re-run replaces the date's row"
grep -qE '^\| 2026-10-20 \| 3 \| 3 \| 2 \| 0 \| 4 \|$' "$CL" && pass "the replaced row has the new counts" || fail "row content" "$(cat "$CL")"
grep -q '^| date | offered | answered | landed | failed | cards |$' "$CL" && pass "table header present" || fail "header" "$(cat "$CL")"
"$SCRIPT" coach-log --date 2026-10-21 --offered x --answered 0 --landed 0 --failed 0 --cards 0 2>/dev/null; assert_eq "1" "$?" "a non-integer count fails"
"$SCRIPT" coach-log --date 2026-10-21 --offered -1 --answered 0 --landed 0 --failed 0 --cards 0 2>/dev/null; assert_eq "1" "$?" "a negative count fails"
"$SCRIPT" coach-log --date 10-21 --offered 0 --answered 0 --landed 0 --failed 0 --cards 0 2>/dev/null; assert_eq "1" "$?" "a bad date fails"
"$SCRIPT" coach-log --date 2026-10-21 --offered 0 --answered 0 --landed 0 --failed 0 2>/dev/null; assert_eq "1" "$?" "a missing count fails"
assert_eq "2" "$(grep -cE '^\| [0-9]{4}-' "$CL")" "failed calls write nothing"

# --- add-tool -------------------------------------------------------------------
echo "add-tool"
rm -rf "$FRICTION_WIKI"; mkdir -p "$FRICTION_WIKI"
printf 'Try jira-cli view instead of the curl wrapper.\n' >"$SANDBOX/tp.md"
out="$("$SCRIPT" add-tool --sig tool:jira-api --proposal-file "$SANDBOX/tp.md" --date 2026-10-20)"
tid="$(jq -r .id <<<"$out")"
assert_eq "true" "$(jq -r .new <<<"$out")" "add-tool creates a new entry"
assert_eq "\"tool:tool:jira-api\"" "$(fld "$tid" signature)" "signature is tool:tool:<name> (kind tool)"
assert_eq "proposed" "$(fld "$tid" status)" "status is proposed at once"
grep -q "jira-cli view" "$FRICTION_WIKI/$tid.md" && pass "proposal text is stored" || fail "proposal text" ""
assert_eq "" "$(fld "$tid" safety)" "no safety flag for a plain proposal"
out="$("$SCRIPT" coach-offer --date 2026-10-21)"
assert_eq "$tid|tool" "$(jq -r '.offer[0] | [.id, .kind] | join("|")' <<<"$out")" "coach-offer offers the tool entry later"
printf 'Replace it; also add an allow rule for jira.\n' >"$SANDBOX/tp2.md"
rm -rf "$FRICTION_WIKI"; mkdir -p "$FRICTION_WIKI"
"$SCRIPT" add-tool --sig tool:jira-api --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 >/dev/null
out="$("$SCRIPT" add-tool --sig tool:jira-api --proposal-file "$SANDBOX/tp2.md" --date 2026-10-21)"
assert_eq "false|F-001" "$(jq -r '[.new, .id] | join("|")' <<<"$out")" "the same tool again updates the entry"
assert_eq "1" "$(ls "$FRICTION_WIKI"/F-*.md | wc -l | tr -d ' ')" "and creates no second one"
assert_eq "true" "$(fld F-001 safety)" "a proposal touching an allow rule sets safety"
grep -q "allow rule" "$FRICTION_WIKI/F-001.md" && pass "proposal replaced on update" || fail "proposal replaced" ""
"$SCRIPT" add-tool --sig tool:jira-api --proposal-file "$SANDBOX/tp.md" --date 2026-10-22 >/dev/null
assert_eq "true" "$(fld F-001 safety)" "safety is never reset"
"$SCRIPT" add-tool --sig jira-api --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 2>/dev/null; assert_eq "1" "$?" "add-tool needs the tool: prefix"
"$SCRIPT" add-tool --sig "tool:" --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 2>/dev/null; assert_eq "1" "$?" "add-tool needs a name"
"$SCRIPT" add-tool --sig tool:x --proposal-file "$SANDBOX/tp.md" --date 10-20 2>/dev/null; assert_eq "1" "$?" "add-tool validates --date"
"$SCRIPT" add-tool --sig tool:x --proposal-file "$SANDBOX/nope.md" --date 2026-10-20 2>/dev/null; assert_eq "1" "$?" "add-tool needs a readable proposal file"
assert_eq "1" "$(ls "$FRICTION_WIKI"/F-*.md | wc -l | tr -d ' ')" "failed calls write nothing"

# --- add-tool on settled entries --------------------------------------------------
echo "add-tool — settled entries"
rm -rf "$FRICTION_WIKI"; mkdir -p "$FRICTION_WIKI"
"$SCRIPT" add-tool --sig tool:alpha --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 >/dev/null
"$SCRIPT" add-tool --sig tool:beta --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 >/dev/null
"$SCRIPT" add-tool --sig tool:gamma --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 >/dev/null
"$SCRIPT" set F-001 --status fixed --fix abc --date 2026-10-21
"$SCRIPT" set F-002 --status landed --date 2026-10-21
"$SCRIPT" set F-003 --status declined --date 2026-10-21
for n in alpha beta gamma; do "$SCRIPT" add-tool --sig "tool:$n" --proposal-file "$SANDBOX/tp2.md" --date 2026-10-25 >/dev/null; done
assert_eq "fixed|landed|declined" "$(fld F-001 status)|$(fld F-002 status)|$(fld F-003 status)" "fixed, landed and declined keep their status (no regressed flip)"
assert_eq "0" "$(grep -c "allow rule" "$FRICTION_WIKI"/F-00[123].md | awk -F: '{s+=$2} END{print s}')" "the existing proposal is kept"
assert_eq "yes" "$(grep -q '^- 2026-10-25' "$FRICTION_WIKI/F-001.md" && echo yes)" "the date's evidence bullet is added"
assert_eq "2026-10-25|2" "$(fld F-001 last)|$(fld F-001 days)" "last and days follow the evidence"
assert_eq "" "$(fld F-001 safety)" "safety is not taken from the ignored proposal"

# --- lock -------------------------------------------------------------------------
echo "lock"
rm -rf "$FRICTION_WIKI"; mkdir -p "$FRICTION_WIKI"
for i in 1 2 3 4 5 6; do
  jq -n --arg s "x:other:group $i" '{groups: [{sig: $s, kind: "other", count: 1, confidence: "high", samples: ["s"], evidence: []}]}' >"$SANDBOX/lk$i.json"
  "$SCRIPT" apply --date 2026-10-15 --mine-json "$SANDBOX/lk$i.json" >/dev/null 2>"$SANDBOX/lkerr$i" &
done
wait
assert_eq "6" "$(ls "$FRICTION_WIKI"/F-*.md | wc -l | tr -d ' ')" "six concurrent applies on new groups make six distinct entries"
assert_eq "6" "$(cat "$FRICTION_WIKI"/F-*.md | grep -c '^signature:')" "none overwrote another"
[ ! -e "$FRICTION_WIKI/.lock" ] && pass "the lock is released afterwards" || fail "lock released" "still there"
ls "$FRICTION_WIKI"/.lock.stale.* >/dev/null 2>&1 && fail "no stale leftovers" "found" || pass "no stale leftovers"
mkdir "$FRICTION_WIKI/.lock"; echo 999999 >"$FRICTION_WIKI/.lock/pid"
out="$("$SCRIPT" add-tool --sig tool:delta --proposal-file "$SANDBOX/tp.md" --date 2026-10-20 2>&1)"
assert_eq "0" "$?" "a lock with a dead pid is taken over"
[ ! -e "$FRICTION_WIKI/.lock" ] && pass "and released" || fail "released after takeover" ""
sleep 30 & HOLDER=$!
mkdir "$FRICTION_WIKI/.lock"; echo "$HOLDER" >"$FRICTION_WIKI/.lock/pid"
out="$(FRICTION_LOCK_WAIT=1 "$SCRIPT" set F-001 --status wontfix --date 2026-10-20 2>&1)"; rc=$?
assert_eq "1" "$rc" "a live lock times out with exit 1"
grep -q "ledger busy (lock held by pid $HOLDER)" <<<"$out" && pass "and names the holder" || fail "busy message" "$out"
assert_eq "$HOLDER" "$(cat "$FRICTION_WIKI/.lock/pid")" "a timed-out run leaves the holder's lock alone"
"$SCRIPT" diary-section --date 2026-10-15 >/dev/null 2>&1; assert_eq "0" "$?" "read-only diary-section ignores the lock"
"$SCRIPT" directions render >/dev/null 2>&1; assert_eq "0" "$?" "directions render ignores the lock"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; rm -rf "$FRICTION_WIKI/.lock"

# --- cards verbs --------------------------------------------------------------
echo "cards verbs"
rm -rf "$FRICTION_WIKI"
fmset() { bash -c 'eval "$(sed -n "/^fm_set()/,/^}/p" "$1")"; fm_set "$2" "$3" "$4"' _ "$SCRIPT" "$FRICTION_WIKI/$1.md" "$2" "$3"; }
ids() { jq -r "[.$1[].id] | sort | join(\" \")" <<<"$2"; }
hashof() { "$SCRIPT" cards --date 2026-12-31 >/dev/null; bash -c 'eval "$(sed -n "/^fm_get()/,/^}/p;/^section_get()/,/^}/p;/^card_hash()/,/^}/p" "$1")"; card_hash "$2"' _ "$SCRIPT" "$FRICTION_WIKI/$1.md"; }
cfile() { local id="$1"; shift; "$SCRIPT" card-filed "$id" --hash "$(hashof "$id")" "$@"; }
cg "$SANDBOX/k1.json" 2026-10-10 "k:tool:plain|tool|8|" "k:tool:noprop|tool|2|" "k:tool:off|tool|2|" "k:tool:dec|tool|8|" "k:repeat:thin|repeat|3|1" \
  "k:secret:key|secret|2|" "k:restated:rule|restated|2|" "k:tool:guard|tool|2|" "k:tool:landed|tool|2|"
apply 2026-10-10 "$SANDBOX/k1.json" >/dev/null
printf 'Tighten the thing\n\n## Change\n- a → b\n' >"$SANDBOX/kp.md"
printf 'Add a rule\nDirection: Always run the tests first `now` $(id)\nScope: dotfiles\n' >"$SANDBOX/kr.md"
printf 'Loosen the permission guard\n' >"$SANDBOX/kg.md"
# F-001 plain, 002 noprop, 003 off, 004 dec, 005 thin, 006 secret, 007 rule, 008 nochange, 009 landed
for n in 1 3 4 5 6; do "$SCRIPT" set "F-00$n" --status proposed --proposal-file "$SANDBOX/kp.md" --date 2026-10-12; done
"$SCRIPT" set F-007 --status proposed --proposal-file "$SANDBOX/kr.md" --date 2026-10-12
"$SCRIPT" set F-008 --status proposed --proposal-file "$SANDBOX/kg.md" --date 2026-10-12
"$SCRIPT" set F-002 --status proposed --date 2026-10-12
"$SCRIPT" set F-009 --status landed --date 2026-10-12
OUT="$("$SCRIPT" cards --date 2026-10-15)"
assert_eq "F-001 F-003 F-004 F-006 F-007 F-008" "$(ids file "$OUT")" "cards lists proposed entries with a proposal, not one without or a thin repeat"
assert_eq "suggestion|secret|rule|nochange" "$(jq -r '[.file[] | select(.id == "F-006" or .id == "F-007" or .id == "F-008" or .id == "F-001") | {i: .id, c: .card}] | sort_by(.i) | map(.c) | join("|")' <<<"$OUT")" "card kinds: secret, rule, nochange, suggestion"
assert_eq "Always run the tests first \`now\` \$(id)|dotfiles" "$(jq -r '.file[] | select(.id == "F-007") | .direction.rule + "|" + .direction.scope' <<<"$OUT")" "a rule item carries its direction"
assert_eq "F-009" "$(ids results "$OUT")" "results lists a landed entry not yet reported"
assert_eq "landed" "$(jq -r '.results[0].card' <<<"$OUT")" "a result card is landed"
assert_eq "false" "$(jq -r '.results[0].retryable' <<<"$OUT")" "a landed result is not retryable"
"$SCRIPT" card-filed F-009 --result --date 2026-10-15
assert_eq "2026-10-15|landed" "$(fld F-009 result_reported_on)|$(fld F-009 status)" "card-filed --result sets only result_reported_on"
assert_eq "" "$(ids results "$("$SCRIPT" cards --date 2026-10-15)")" "a reported result is not listed again"
# offered 2 days ago is skipped, 3 days listed
cfile F-001 --date 2026-10-13
assert_eq "offered|2026-10-13|" "$(fld F-001 status)|$(fld F-001 offered_on)|$(fld F-001 answer)" "card-filed marks the entry offered"
assert_eq "no" "$(jq -r '[.file[].id] | index("F-001") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-15)")" "offered 2 days ago is skipped"
assert_eq "yes" "$(jq -r '[.file[].id] | index("F-001") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-16)")" "offered 3 days ago is listed"
# declined_count
"$SCRIPT" set F-004 --status declined --date 2026-10-14; fmset F-004 declined_count 4
assert_eq "yes" "$(jq -r '[.file[].id] | index("F-004") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-15)")" "declined at count 8 with declined_count 4 is listed"
fmset F-004 declined_count 5
assert_eq "no" "$(jq -r '[.file[].id] | index("F-004") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-15)")" "declined at count 8 with declined_count 5 is not"
# apply on a suggestion
cfile F-003 --date 2026-10-15
OUT="$("$SCRIPT" card-answer F-003 apply --date 2026-10-15)"
assert_eq '{"enqueue":true,"safety":false}' "$OUT" "apply on a suggestion enqueues"
assert_eq "landing|yes|2026-10-15" "$(fld F-003 status)|$(fld F-003 answer)|$(fld F-003 answered_on)" "apply sets landing, answer yes, answered_on"
cfile F-003 --date 2026-10-16 2>/dev/null; assert_eq "1" "$?" "card-filed on a landing entry exits 1"
assert_eq "landing" "$(fld F-003 status)" "and leaves it landing"
"$SCRIPT" card-answer F-003 apply --date 2026-10-15 2>"$SANDBOX/err"; assert_eq "1" "$?" "answering a landing entry exits 1"
assert_has "F-003 is landing, not on a card" "$(cat "$SANDBOX/err")" "and says why"
# safety suggestion reports safety true
"$SCRIPT" set F-004 --status proposed --proposal-file "$SANDBOX/kg.md" --date 2026-10-16
printf 'Loosen the permission guard\n- a → b\n' >"$SANDBOX/kg2.md"
"$SCRIPT" set F-004 --proposal-file "$SANDBOX/kg2.md" --date 2026-10-16
cfile F-004 --date 2026-10-16
assert_eq '{"enqueue":true,"safety":true}' "$("$SCRIPT" card-answer F-004 apply --date 2026-10-16)" "apply on a safety suggestion reports safety true"
# nochange, secret
cfile F-008 --date 2026-10-15; "$SCRIPT" card-answer F-008 apply --date 2026-10-15 2>"$SANDBOX/err"; assert_eq "1" "$?" "apply on a nochange card exits 1"
assert_has "no exact change to approve" "$(cat "$SANDBOX/err")" "nochange refusal says why"
assert_eq "offered" "$(fld F-008 status)" "a refused apply leaves the entry offered"
cfile F-006 --date 2026-10-15; "$SCRIPT" card-answer F-006 apply --date 2026-10-15 2>/dev/null; assert_eq "1" "$?" "apply on a secret card exits 1"
assert_eq "{}" "$("$SCRIPT" card-answer F-006 done --date 2026-10-15)" "done on a secret card prints {}"
assert_eq "fixed" "$(fld F-006 status)" "and fixes it"
"$SCRIPT" card-answer F-006 done --date 2026-10-15 2>/dev/null; assert_eq "1" "$?" "a second answer on a fixed entry exits 1"
# rule
cfile F-007 --date 2026-10-15
OUT="$("$SCRIPT" card-answer F-007 apply --date 2026-10-15)"
assert_eq '{"rule":"D-001"}' "$OUT" "apply on a rule card prints the direction id"
assert_eq "fixed|D-001" "$(fld F-007 status)|$(fld F-007 fix)" "the rule entry is fixed with the direction as fix"
assert_eq "| D-001 | Always run the tests first \`now\` \$(id) | dotfiles | 2026-10-15 |  | active |" "$(grep '^| D-001' "$FRICTION_WIKI/directions.md")" "the direction row is added literally with its scope"
# a proposal changed after its card was shown is never approved
printf 'Tweak the thing\n\n## Change\n- x → y\n' >"$SANDBOX/cx.md"
printf 'Tweak the thing\n\n## Change\n- x → z\n' >"$SANDBOX/cx2.md"
for n in 1 2 3; do
  jq -n --arg s "user:frustration:chg$n" '{groups: [{sig: $s, source: "user", kind: "frustration", count: 1, confidence: "high", samples: ["s"], evidence: []}]}' >"$SANDBOX/chg$n.json"
  apply 2026-10-23 "$SANDBOX/chg$n.json" >/dev/null
done
CH1="$(grep -l 'chg1' "$FRICTION_WIKI"/F-*.md | head -1 | xargs basename | sed 's/\.md//')"
CH2="$(grep -l 'chg2' "$FRICTION_WIKI"/F-*.md | head -1 | xargs basename | sed 's/\.md//')"
CH3="$(grep -l 'chg3' "$FRICTION_WIKI"/F-*.md | head -1 | xargs basename | sed 's/\.md//')"
for id in "$CH1" "$CH2" "$CH3"; do "$SCRIPT" set "$id" --status proposed --proposal-file "$SANDBOX/cx.md" --date 2026-10-23; cfile "$id" --date 2026-10-23; done
assert_eq "16" "$(fld "$CH1" card_hash | wc -c | tr -d ' ' | awk '{print $1 - 1}')" "card-filed stores a 16-char card_hash"
"$SCRIPT" set "$CH1" --proposal-file "$SANDBOX/cx2.md" --date 2026-10-23
OUT="$("$SCRIPT" card-answer "$CH1" apply --date 2026-10-23 2>/dev/null)"; RC=$?
assert_eq "1|{\"changed\":true}" "$RC|$OUT" "apply after the proposal changed is refused"
assert_eq "proposed|the proposal changed after its card was shown" "$(fld "$CH1" status)|$(fld "$CH1" reason)" "and the entry is proposed with the reason"
assert_eq "0" "$(grep -c landing "$FRICTION_WIKI/$CH1.md" | head -1)" "and never landed"
"$SCRIPT" set "$CH2" --safety true --date 2026-10-23
"$SCRIPT" card-answer "$CH2" apply --date 2026-10-23 >/dev/null 2>&1; assert_eq "1" "$?" "apply after only safety flipped is refused"
assert_eq "proposed" "$(fld "$CH2" status)" "safety flip leaves it proposed"
OUT="$("$SCRIPT" card-answer "$CH3" apply --date 2026-10-23)"
assert_eq '{"enqueue":true,"safety":false}' "$OUT" "an unchanged proposal applies"
# a card's fingerprint is the one the listing showed: card-filed takes it and refuses a stale one
jq -n '{groups: [{sig: "user:frustration:chg4", source: "user", kind: "frustration", count: 1, confidence: "high", samples: ["s"], evidence: []}]}' >"$SANDBOX/chg4.json"
apply 2026-10-23 "$SANDBOX/chg4.json" >/dev/null
CH4="$(grep -l 'chg4' "$FRICTION_WIKI"/F-*.md | head -1 | xargs basename | sed 's/\.md//')"
"$SCRIPT" set "$CH4" --status proposed --proposal-file "$SANDBOX/cx.md" --date 2026-10-23
LIST="$("$SCRIPT" cards --date 2026-10-23)"
H4="$(jq -r --arg i "$CH4" '.file[] | select(.id == $i) | .card_hash' <<<"$LIST")"
assert_eq "16" "${#H4}" "a cards file item carries a 16-char card_hash"
"$SCRIPT" set "$CH4" --proposal-file "$SANDBOX/cx2.md" --date 2026-10-23
"$SCRIPT" card-filed "$CH4" --date 2026-10-23 --hash "$H4" 2>"$SANDBOX/err"; assert_eq "1" "$?" "card-filed with a stale hash exits 1"
assert_eq "proposed|" "$(fld "$CH4" status)|$(fld "$CH4" card_hash)" "and the entry is not offered, no hash stored"
"$SCRIPT" card-filed "$CH4" --date 2026-10-23 2>/dev/null; assert_eq "1" "$?" "card-filed without --hash exits 1"
H4="$(jq -r --arg i "$CH4" '.file[] | select(.id == $i) | .card_hash' <<<"$("$SCRIPT" cards --date 2026-10-23)")"
"$SCRIPT" card-filed "$CH4" --date 2026-10-23 --hash "$H4"; assert_eq "0" "$?" "card-filed with the current hash succeeds"
assert_eq "offered|$H4" "$(fld "$CH4" status)|$(fld "$CH4" card_hash)" "and stores that hash"
printf 'Add a rule\nDirection: Always do A\nScope: dotfiles\n' >"$SANDBOX/cr1.md"
printf 'Add a rule\nDirection: Always do B\nScope: dotfiles\n' >"$SANDBOX/cr2.md"
jq -n '{groups: [{sig: "k:restated:chgrule", source: "mine", kind: "restated", count: 2, confidence: "high", samples: ["s"], evidence: []}]}' >"$SANDBOX/chgr.json"
apply 2026-10-23 "$SANDBOX/chgr.json" >/dev/null
CHR="$(grep -l 'chgrule' "$FRICTION_WIKI"/F-*.md | head -1 | xargs basename | sed 's/\.md//')"
"$SCRIPT" set "$CHR" --status proposed --proposal-file "$SANDBOX/cr1.md" --date 2026-10-23
cfile "$CHR" --date 2026-10-23
"$SCRIPT" set "$CHR" --proposal-file "$SANDBOX/cr2.md" --date 2026-10-23
"$SCRIPT" card-answer "$CHR" apply --date 2026-10-23 >/dev/null 2>&1; assert_eq "1" "$?" "a rule whose Direction changed is refused"
assert_eq "proposed|1" "$(fld "$CHR" status)|$(grep -c "^| D-" "$FRICTION_WIKI/directions.md")" "and no direction was added"
# later / ignore
cfile F-001 --date 2026-10-16
assert_eq "{}" "$("$SCRIPT" card-answer F-001 later --date 2026-10-17)" "later prints {}"
assert_eq "offered|2026-10-17|later" "$(fld F-001 status)|$(fld F-001 offered_on)|$(fld F-001 answer)" "later keeps it offered with offered_on D"
assert_eq "no" "$(jq -r '[.file[].id] | index("F-001") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-19)")" "a later card is skipped until D+3"
assert_eq "yes" "$(jq -r '[.file[].id] | index("F-001") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-20)")" "and listed at D+3"
assert_eq "{}" "$("$SCRIPT" card-answer F-001 ignore --date 2026-10-20)" "ignore prints {}"
assert_eq "declined|8" "$(fld F-001 status)|$(fld F-001 declined_count)" "ignore declines with declined_count"
"$SCRIPT" card-answer F-001 later --date 2026-10-20 2>/dev/null; assert_eq "1" "$?" "answering a declined entry exits 1"
# revise
printf 'Why `rm -rf` and $(id)?\nsecond line\n' >"$SANDBOX/q.md"; printf 'Because `x` $(id) stays literal.\n' >"$SANDBOX/a.md"
printf 'Revised plan\n## Change\n- c → d\n' >"$SANDBOX/rp.md"
"$SCRIPT" set F-002 --status failed --reason "boom" --date 2026-10-20
"$SCRIPT" revise F-002 --question-file "$SANDBOX/q.md" --answer-file "$SANDBOX/a.md" --proposal-file "$SANDBOX/rp.md" --date 2026-10-20
assert_eq '- 2026-10-20: you asked: Why `rm -rf` and $(id)? second line · coach: Because `x` $(id) stays literal.' "$(sed -n '/^## Discussion/,$p' "$FRICTION_WIKI/F-002.md" | grep '^- ')" "revise stores the question literally in ## Discussion"
assert_eq "Revised plan" "$(section_first() { sed -n '/^## Proposal/,/^## /p' "$FRICTION_WIKI/F-002.md" | sed -n 3p; }; section_first)" "revise replaces the proposal"
assert_eq "proposed|" "$(fld F-002 status)|$(fld F-002 reason)" "revise sets proposed and clears reason"
"$SCRIPT" revise F-002 --question-file "$SANDBOX/q.md" --answer-file "$SANDBOX/a.md" --date 2026-10-21
assert_eq "2" "$(grep -c '^- 2026-10-2[01]: you asked' "$FRICTION_WIKI/F-002.md")" "a second revise appends another Discussion entry"
assert_eq "Because \`x\` \$(id) stays literal." "$(jq -r '.file[] | select(.id == "F-002") | .discussion | sub(".*coach: "; "")' <<<"$("$SCRIPT" cards --date 2026-10-21)")" "cards carries the last discussion entry"
cfile F-002 --date 2026-10-21
"$SCRIPT" revise F-006 --question-file "$SANDBOX/q.md" --answer-file "$SANDBOX/a.md" --date 2026-10-21
assert_eq "proposed" "$(fld F-006 status)" "revise makes a fixed entry proposed"
"$SCRIPT" revise F-002 --question-file "$SANDBOX/q.md" --answer-file "$SANDBOX/a.md" --date 2026-10-22
assert_eq "yes" "$(jq -r '[.file[].id] | index("F-002") | if . == null then "no" else "yes" end' <<<"$("$SCRIPT" cards --date 2026-10-22)")" "a revised entry is listed again"
assert_eq "|" "$(fld F-002 offered_on)|$(fld F-002 answer)" "and its offered_on and answer are cleared"
rm -rf "$FRICTION_WIKI"

# --- fixed_at -----------------------------------------------------------------
echo "fixed_at — a sighting before the fix landed is not a regression"
# mine_seen FILE DATE LAST_SEEN: one group of $C, last seen at LAST_SEEN (UTC)
mine_seen() { mine "$1" "$2" "$C|tool_error|high|2|jq missing"; jq --arg t "$3" '.groups[0].last_seen = $t' "$1" >"$1.tmp" && mv "$1.tmp" "$1"; }
mine "$SANDBOX/f1.json" 2026-10-14 "$C|tool_error|high|2|jq missing"
apply 2026-10-14 "$SANDBOX/f1.json" >/dev/null
TZ=Etc/GMT-3 "$SCRIPT" set F-001 --status fixed --fix abc1234 --date 2026-10-16
assert_eq "2026-10-15T21:00:00Z" "$(fld F-001 fixed_at)" "set --status fixed with a past --date stamps that local midnight, in UTC"
TZ=Etc/GMT-3 "$SCRIPT" set F-001 --status fixed --fix abc1234 --rung script --date 2026-10-17
assert_eq "2026-10-15T21:00:00Z" "$(fld F-001 fixed_at)" "setting fixed again with the same fix keeps fixed_at"
mine_seen "$SANDBOX/f2.json" 2026-10-16 2026-10-15T21:00:00Z
OUT="$(apply 2026-10-16 "$SANDBOX/f2.json")"
assert_eq "fixed" "$(fld F-001 status)" "last seen at fixed_at: stays fixed"
assert_eq "" "$(jq -r '[.regressed[].id] | join(" ")' <<<"$OUT")" "and is not reported as regressed"
grep -q '^- 2026-10-16 (2×)' "$FRICTION_WIKI/F-001.md" && pass "the sighting is still recorded as evidence" || fail "the sighting is still recorded as evidence" "$(cat "$FRICTION_WIKI/F-001.md")"
mine_seen "$SANDBOX/f3.json" 2026-10-17 2026-10-17T06:00:00Z
OUT="$(apply 2026-10-17 "$SANDBOX/f3.json")"
assert_eq "regressed" "$(fld F-001 status)" "last seen after fixed_at: regressed"
assert_eq "F-001" "$(jq -r '[.regressed[].id] | join(" ")' <<<"$OUT")" "and reported"
before="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"$SCRIPT" set F-001 --status fixed --fix def5678
after="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(fld F-001 fixed_at)"
[[ ! "$stamp" < "$before" && ! "$stamp" > "$after" ]] && pass "set --status fixed for today stamps the current time" || fail "set --status fixed for today stamps the current time" "[$stamp] not in [$before, $after]"
TZ=Etc/GMT-3 "$SCRIPT" set F-001 --status fixed --fix fed9876 --date 2026-10-20
assert_eq "2026-10-19T21:00:00Z" "$(fld F-001 fixed_at)" "a new fix sha re-stamps fixed_at"
stamp="$(fld F-001 fixed_at)"
"$SCRIPT" set F-001 --status regressed --date 2026-10-18
assert_eq "$stamp" "$(fld F-001 fixed_at)" "another status leaves fixed_at alone"
"$SCRIPT" set F-001 --status fixed --fix def5678 --date 2026-10-18
mine "$SANDBOX/f4.json" 2026-10-19 "$C|tool_error|high|1|jq missing"
apply 2026-10-19 "$SANDBOX/f4.json" >/dev/null
assert_eq "regressed" "$(fld F-001 status)" "a group without last_seen regresses as before"
rm -rf "$FRICTION_WIKI"

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
