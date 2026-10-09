#!/bin/bash
# Tests for bin/daily-stats. Diary files are a sandbox DIARY_DIR; glab is
# stubbed on PATH, so nothing here reaches GitLab.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/daily-stats"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"; DIARY="$SANDBOX/diary"
mkdir -p "$STUBS" "$FIX" "$DIARY"

cat > "$STUBS/glab" <<'STUB'
#!/bin/bash
echo "$*" >> "${FIX:?}/glab.log"
[ -n "${GLAB_DOWN:-}" ] && exit 1
case "$*" in
    *merge_requests\?scope=created_by_me\&state=merged*) cat "$FIX/merged.json" ;;
    *) echo '{}' ;;
esac
STUB
chmod +x "$STUBS/glab"

# Shapes follow GitLab's merge request list: references.full, web_url, merged_at.
cat > "$FIX/merged.json" <<'JSON'
[{"iid":6576,"title":"Retrieve names","web_url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576","merged_at":"2026-10-07T09:00:00.000Z","references":{"short":"!6576","relative":"!6576","full":"ecfx/ecfx-backend!6576"}},
 {"iid":2185,"title":"Nits","web_url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2185","merged_at":"2026-10-06T08:00:00.000Z","references":{"short":"!2185","relative":"!2185","full":"ecfx/ecfx-dashboard!2185"}}]
JSON

run() { (TZ=UTC PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" "$SCRIPT" "$@" 2>&1); }
out_only() { (TZ=UTC PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" "$SCRIPT" "$@" 2>/dev/null); }
jqf() { jq -c "$1" <<<"$2"; }

day() { # date, then body lines on stdin become the start-day block
  { printf '# %s\n\n## habits tracking\n\n- [X] habit line outside the block\n\n### ECFX\n\n<!-- start-day:start -->\n#### Plan\n\n' "$1"
    cat; printf '<!-- start-day:end -->\n\n<!-- daily-report:start -->\n- [x] report line, not counted\n<!-- daily-report:end -->\n'; } > "$DIARY/$1.md"
}

day 2026-10-05 <<'EOF2'
**First**
- [x] merge [ecfx-admin!296](https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/296) (ecfx-17451) · merged
- [X] ecfx-17937 fix [dashboard!2231](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231) · draft MR [dashboard!2240](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2240)
- [>] ecfx-6659 sync with @smtsuchi
- [ ] review @bkeeling's backend [!6584](https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6584)
  - [!] nested sub-item blocked · blocked: waiting on product
- [/] ecfx-18171 pick up filter
Meetings: none listed.
EOF2
day 2026-10-06 <<'EOF2'
- [x] backend [!6575](https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6575) and again [!2231](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231)
- [>] ecfx-6659 sync with @smtsuchi · note: levi waiting
- [>] ecfx-9999 once only
- [ ] open item
EOF2
day 2026-10-07 <<'EOF2'
- [>] ecfx-6659   sync with   @smtsuchi
- [x] reply in DM (no link)
EOF2
printf '# 2026-10-08\n\n- [X] habit only, no start-day block\n- [x] not counted\n' > "$DIARY/2026-10-08.md"
printf '# 2026-09-30\n\n<!-- start-day:start -->\n- [x] out of range\n<!-- start-day:end -->\n' > "$DIARY/2026-09-30.md"
echo "template" > "$DIARY/template.md"

echo "daily-stats — schema"
out=$(out_only 2026-10-05 2026-10-09)
assert_eq '["from","to","days","items","repeat_deferred","done_mr_links","merged_mrs"]' "$(jqf 'keys_unsorted' "$out")" "top-level keys, in the spec's order"
assert_eq '["planned","done","blocked","deferred","open"]' "$(jqf '.items|keys_unsorted' "$out")" "item keys, in the spec's order"
assert_eq '"2026-10-05"' "$(jqf '.from' "$out")" "from echoed"
assert_eq '"2026-10-09"' "$(jqf '.to' "$out")" "to echoed"
assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "exactly one line of output"

echo "daily-stats — counting"
assert_eq "3" "$(jqf '.days' "$out")" "days counts diary files that have a start-day block (the no-block 10-08 and out-of-range 09-30 are skipped)"
assert_eq '{"planned":12,"done":4,"blocked":1,"deferred":4,"open":3}' "$(jqf '.items' "$out" | jq -c '{planned,done,blocked,deferred,open}')" "planned/done/blocked/deferred/open, [X] counted done, nested line counted, habits and daily-report lines ignored"
assert_eq "12" "$(jqf '.items | .done + .blocked + .deferred + .open' "$out")" "planned equals the sum of the states"

echo "daily-stats — repeat_deferred"
assert_eq '[{"text":"ecfx-6659 sync with @smtsuchi","times":3}]' "$(jqf '.repeat_deferred' "$out")" "same text deferred on 3 days (spacing, case and evidence suffix ignored); a once-deferred item is not listed"

echo "daily-stats — done_mr_links"
assert_eq '{"ecfx-admin":["https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/296"],"ecfx-backend":["https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6575"],"ecfx-dashboard":["https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231","https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2240"]}' "$(jqf '.done_mr_links' "$out")" "links on done lines only, grouped by repo name, deduplicated (!2231 twice), evidence links included, the open line's !6584 left out"

echo "daily-stats — merged_mrs"
assert_eq '[{"repo":"ecfx/ecfx-dashboard","iid":2185,"title":"Nits","url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2185","merged_at":"2026-10-06T08:00:00.000Z"},{"repo":"ecfx/ecfx-backend","iid":6576,"title":"Retrieve names","url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576","merged_at":"2026-10-07T09:00:00.000Z"}]' "$(jqf '.merged_mrs' "$out")" "merged MRs with the spec's fields, oldest first"
assert_contains "$(cat "$FIX/glab.log")" "merged_after=2026-10-05T00%3A00%3A00%2B00%3A00" "asks GitLab from the start of the first day"
assert_contains "$(cat "$FIX/glab.log")" "merged_before=2026-10-10T00%3A00%3A00%2B00%3A00" "up to the start of the day after the last"
assert_contains "$(cat "$FIX/glab.log")" "scope=created_by_me" "only my MRs"
: > "$FIX/glab.log"
(TZ=Etc/GMT-3 PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" "$SCRIPT" 2026-10-05 2026-10-05 >/dev/null 2>&1)
assert_contains "$(cat "$FIX/glab.log")" "merged_after=2026-10-05T00%3A00%3A00%2B03%3A00" "the day boundaries are local midnight, in the local UTC offset"

: > "$FIX/glab.log"
(TZ=Europe/Berlin PATH="$STUBS:$PATH" FIX="$FIX" DIARY_DIR="$DIARY" "$SCRIPT" 2026-10-25 2026-10-25 >/dev/null 2>&1)
assert_contains "$(cat "$FIX/glab.log")" "merged_after=2026-10-25T00%3A00%3A00%2B02%3A00" "DST day: the offset is read at midnight (+02:00), not at the current time of day"
assert_contains "$(cat "$FIX/glab.log")" "merged_before=2026-10-26T00%3A00%3A00%2B01%3A00" "and the next midnight, after the switch, is +01:00"

echo "daily-stats — trailing refs"
D=https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests
day 2026-10-12 <<EOF2
- [x] ECFX-1 fix dashboard!2231 and admin!305  [↗][dashboard!2231] [↗][admin!305]
- [x] again dashboard!2231  [↗][dashboard!2231]
- [x] other repo dashboard!9  [↗][dashboard!9~2]
- [ ] open dashboard!7  [↗][dashboard!7]
- [x] old style [dashboard!2240]($D/2240)

[dashboard!2231]: $D/2231
[admin!305]: https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/305
[dashboard!9~2]: $D/9
[dashboard!7]: $D/7
EOF2
day 2026-10-13 <<EOF2
- [>] ecfx-5 later dashboard!7  [↗][dashboard!7]

[dashboard!7]: $D/7
EOF2
day 2026-10-14 <<EOF2
- [>] ecfx-5 later dashboard!7  [↗][dashboard!7]

[dashboard!7]: $D/7
EOF2
out=$(out_only 2026-10-12 2026-10-14)
assert_eq '{"ecfx-admin":["https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/305"],"ecfx-dashboard":["'$D'/9","'$D'/2231","'$D'/2240"]}' "$(jqf '.done_mr_links' "$out")" "refs resolve through the block's defs, mix with inline links, dedupe, skip open lines"
assert_eq '[{"text":"ecfx-5 later dashboard!7","times":2}]' "$(jqf '.repeat_deferred' "$out")" "trailing refs are not part of a deferred item's text"
rm -f "$DIARY/2026-10-1"[234].md

echo "daily-stats — help"
assert_contains "$("$SCRIPT" --help)" "daily-stats <from YYYY-MM-DD> <to YYYY-MM-DD>" "--help prints the usage line"

echo "daily-stats — edges"
out=$(out_only 2026-10-08 2026-10-08)
assert_eq '{"from":"2026-10-08","to":"2026-10-08","days":0,"items":{"planned":0,"done":0,"blocked":0,"deferred":0,"open":0},"repeat_deferred":[],"done_mr_links":{},"merged_mrs":[{"repo":"ecfx/ecfx-dashboard","iid":2185,"title":"Nits","url":"https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2185","merged_at":"2026-10-06T08:00:00.000Z"},{"repo":"ecfx/ecfx-backend","iid":6576,"title":"Retrieve names","url":"https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576","merged_at":"2026-10-07T09:00:00.000Z"}]}' "$out" "a range with no start-day block is all zeros (days 0), never an error"
rm -rf "$DIARY"; out=$(out_only 2026-10-05 2026-10-09)
assert_eq '0' "$(jqf '.days' "$out")" "a missing diary directory counts as no days"
mkdir -p "$DIARY"
out=$(out_only 2026-10-05 2026-10-05)
assert_eq '0' "$(jqf '.items.planned' "$out")" "an empty diary directory counts as no items"

echo "daily-stats — failures"
out=$(GLAB_DOWN=1 out_only 2026-10-05 2026-10-09)
assert_eq "" "$out" "GitLab down: nothing on stdout"
GLAB_DOWN=1 run 2026-10-05 2026-10-09 >/dev/null; assert_eq "1" "$?" "GitLab down: exit 1"
assert_contains "$(GLAB_DOWN=1 run 2026-10-05 2026-10-09)" "GitLab unavailable" "GitLab down: says why on stderr"
run 2026-10-09 2026-10-05 >/dev/null; assert_eq "1" "$?" "from after to is an error"
run 2026-13-45 2026-10-05 >/dev/null; assert_eq "1" "$?" "an impossible date is an error"
run yesterday today >/dev/null; assert_eq "1" "$?" "only YYYY-MM-DD is accepted"
run 2026-10-05 >/dev/null; assert_eq "1" "$?" "one argument is an error"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
