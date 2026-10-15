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
grep -q '^- F-002 — jq is not on the PATH of the subagent shell → /fix-friction F-002$' <<<"$OUT" && pass "regressed item line ends with /fix-friction" || fail "regressed item line" "$OUT"
grep -q '^- F-001 — Outlook MCP needs re-auth → /fix-friction F-001$' <<<"$OUT" && pass "proposed item line ends with /fix-friction" || fail "proposed item line" "$OUT"
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

export FRICTION_WIKI="$SANDBOX/cap"; DF="$FRICTION_WIKI/directions.md"
assert_eq "" "$("$SCRIPT" directions render)" "no file renders nothing"
long="$(printf 'word%.0s ' $(seq 1 25))"
for i in $(seq 1 30); do "$SCRIPT" directions add --rule "global rule $i $long" --scope global --date "2026-09-$(printf '%02d' "$i")" >/dev/null; done
"$SCRIPT" directions add --rule "Reviews keep one comment" --scope reviews --date 2026-10-01 >/dev/null
out="$("$SCRIPT" directions render)"
[ "$(printf '%s' "$out" | wc -c)" -le 2048 ] && pass "render stays within 2 KB" || fail "render size" "$(printf '%s' "$out" | wc -c)"
assert_eq "yes" "$(grep -q 'Reviews keep one comment \[reviews\]' <<<"$out" && grep -q 'global rule 30 ' <<<"$out" && ! grep -q 'global rule 1 ' <<<"$out" && echo yes || echo no)" "the oldest global rules are folded first"
grep -Eq '^- [0-9]+ more in ~/wiki/friction/directions.md$' <<<"$out" && pass "the folded rules are summarised in one line" || fail "summary line" "$out"
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
grep -q '^3 active directions share the scope "docs" (D-.*, D-.*, D-.*): run /fix-friction' <<<"$OUT" && pass "3 directions on one scope suggest /fix-friction" || fail "scope suggestion" "$OUT"
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
assert_eq "644" "$(stat -f %Lp "$FRICTION_WIKI/$fid.md" 2>/dev/null || stat -c %a "$FRICTION_WIKI/$fid.md")" "F-file is 0644"
assert_eq "644" "$(stat -f %Lp "$LED" 2>/dev/null || stat -c %a "$LED")" "ledger.md is 0644"
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
           '{"directions": [{"rule": "r"}]}' 'not json'; do
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
