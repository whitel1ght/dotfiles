#!/bin/bash
# Tests for bin/diary-links. Works on files in a sandbox; nothing touches a real diary.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/diary-links"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dl-XXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

D=https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests
A=https://gitlab.com/ecfx/ecfx-admin/-/merge_requests

# fixture NAME: stdin becomes the file; prints its path
fixture() { cat > "$SANDBOX/$1.md"; echo "$SANDBOX/$1.md"; }
# wrap_plan: the stdin lines inside a start-day block, with habits around
plan() { printf '# day\n\n- [ ] habit [x](https://h.example/x)\n\n### ECFX\n\n<!-- start-day:start -->\n'; cat; printf '<!-- start-day:end -->\n\n- [x] outside [a](https://o.example/a)\n'; }

echo "basic conversion"
f=$(plan <<EOF2 | fixture basic
- [x] ECFX-18169 review fixes pushed to [dashboard!2231]($D/2231) (stuck)
EOF2
)
"$SCRIPT" "$f"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_eq "$(plan <<EOF2
- [x] ECFX-18169 review fixes pushed to dashboard!2231 (stuck)  [↗][dashboard!2231]

[dashboard!2231]: $D/2231
EOF2
)" "$(cat "$f")" "label stays as text, ref trails, def at block end"
out=$("$SCRIPT" "$f" 2>&1); assert_eq "" "$out" "prints nothing"

echo "multiple links, dedupe, order"
f=$(plan <<EOF2 | fixture multi
- [/] spec [dashboard!2239]($D/2239) and [admin!305]($A/305) again [dashboard!2239]($D/2239)
- [ ] other [admin!305]($A/305) · note: x
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<EOF2
- [/] spec dashboard!2239 and admin!305 again dashboard!2239  [↗][dashboard!2239] [↗][admin!305]
- [ ] other admin!305 · note: x  [↗][admin!305]

[dashboard!2239]: $D/2239
[admin!305]: $A/305
EOF2
)" "$(cat "$f")" "two refs, deduped per line, defs once in first-appearance order"

echo "non-MR links"
f=$(plan <<'EOF2' | fixture jira
- [ ] ticket [ECFX-1](https://x.atlassian.net/browse/ECFX-1) see [the doc](https://x.atlassian.net/wiki/1)
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<'EOF2'
- [ ] ticket ECFX-1 see the doc  [↗][ECFX-1] [↗][the doc]

[ECFX-1]: https://x.atlassian.net/browse/ECFX-1
[the doc]: https://x.atlassian.net/wiki/1
EOF2
)" "$(cat "$f")" "jira and wiki links convert like MRs"

echo "label collision"
f=$(plan <<EOF2 | fixture coll
- [ ] a [x!1]($D/1)
- [ ] b [x!1]($A/1)
- [ ] c [x!1]($A/1) [x!1]($D/1)
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<EOF2
- [ ] a x!1  [↗][x!1]
- [ ] b x!1  [↗][x!1~2]
- [ ] c x!1 x!1  [↗][x!1~2] [↗][x!1]

[x!1]: $D/1
[x!1~2]: $A/1
EOF2
)" "$(cat "$f")" "second URL gets ~2 in the ref only and is reused"

echo "idempotency"
cp "$f" "$SANDBOX/before"; "$SCRIPT" "$f"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "second run changes nothing"
"$SCRIPT" --check "$f"; assert_eq 0 "$?" "--check exits 0 on a converted file"

echo "mixed already-converted and new"
f=$(plan <<EOF2 | fixture mixed
- [x] done dashboard!2231  [↗][dashboard!2231]
- [ ] new [admin!305]($A/305) and [dashboard!2231]($D/2231)
- [ ] more dashboard!2231 and [dashboard!2240]($D/2240)  [↗][dashboard!2231]

[dashboard!2231]: $D/2231
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<EOF2
- [x] done dashboard!2231  [↗][dashboard!2231]
- [ ] new admin!305 and dashboard!2231  [↗][admin!305] [↗][dashboard!2231]
- [ ] more dashboard!2231 and dashboard!2240  [↗][dashboard!2231] [↗][dashboard!2240]

[dashboard!2231]: $D/2231
[admin!305]: $A/305
[dashboard!2240]: $D/2240
EOF2
)" "$(cat "$f")" "new links merge into existing refs and defs, defs re-sorted"
cp "$f" "$SANDBOX/before"; "$SCRIPT" "$f"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "idempotent after a merge"

echo "both blocks, one file"
f=$(fixture both <<EOF2
### ECFX

<!-- start-day:start -->
- [ ] plan [dashboard!1]($D/1)
<!-- start-day:end -->

<!-- daily-report:start -->
- [x] report [admin!2]($A/2) · merged
<!-- daily-report:end -->
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(cat <<EOF2
### ECFX

<!-- start-day:start -->
- [ ] plan dashboard!1  [↗][dashboard!1]

[dashboard!1]: $D/1
<!-- start-day:end -->

<!-- daily-report:start -->
- [x] report admin!2 · merged  [↗][admin!2]

[admin!2]: $A/2
<!-- daily-report:end -->
EOF2
)" "$(cat "$f")" "each block gets its own defs"

echo "outside the blocks"
f=$(plan <<EOF2 | fixture outside
- [ ] in [dashboard!1]($D/1)
EOF2
)
"$SCRIPT" "$f"
assert_eq "- [ ] habit [x](https://h.example/x)" "$(sed -n 3p "$f")" "habit line before is untouched"
assert_eq "- [x] outside [a](https://o.example/a)" "$(tail -1 "$f")" "line after is untouched"
assert_eq 1 "$(grep -c '^<!-- start-day:\(start\|end\) -->$' "$f" | sed 's/2/1/')" "markers kept"

echo "code spans"
f=$(plan <<EOF2 | fixture code
- [ ] run \`[a](https://c.example/a)\` then [dashboard!1]($D/1)
- [ ] only \`\`[b](https://c.example/b)\`\` here
EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<EOF2
- [ ] run \`[a](https://c.example/a)\` then dashboard!1  [↗][dashboard!1]
- [ ] only \`\`[b](https://c.example/b)\`\` here

[dashboard!1]: $D/1
EOF2
)" "$(cat "$f")" "links in code spans stay inline"

echo "no links, empty block"
f=$(plan <<'EOF2' | fixture plain
**First**
- [ ] nothing to do   
EOF2
)
cp "$f" "$SANDBOX/before"; "$SCRIPT" "$f"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "a block without links is byte-identical"
f=$(printf '<!-- start-day:start -->\n<!-- start-day:end -->\n' | fixture empty)
cp "$f" "$SANDBOX/before"; "$SCRIPT" "$f"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "empty block is untouched"
f=$(printf '# no blocks [a](https://a.example)\n' | fixture noblock)
"$SCRIPT" --check "$f"; assert_eq 0 "$?" "a file without blocks needs nothing"

echo "--check"
f=$(plan <<EOF2 | fixture chk
- [ ] a [dashboard!1]($D/1)
EOF2
)
cp "$f" "$SANDBOX/before"
"$SCRIPT" --check "$f" 2>/dev/null; assert_eq 1 "$?" "--check exits 1 when a rewrite is due"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "--check leaves the file alone"

echo "defs placement"
f=$(plan <<EOF2 | fixture place
- [ ] a [dashboard!1]($D/1)


- [ ] b [admin!2]($A/2)

EOF2
)
"$SCRIPT" "$f"
assert_eq "$(plan <<EOF2
- [ ] a dashboard!1  [↗][dashboard!1]


- [ ] b admin!2  [↗][admin!2]

[dashboard!1]: $D/1
[admin!2]: $A/2
EOF2
)" "$(cat "$f")" "one blank line before defs, none after, directly above the end marker"
f=$(plan <<EOF2 | fixture stale
- [ ] a dashboard!1  [↗][dashboard!1]

[dashboard!1]: $D/1
[gone!9]: $D/9
EOF2
)
cp "$f" "$SANDBOX/before"; "$SCRIPT" "$f"
assert_eq "$(cat "$SANDBOX/before")" "$(cat "$f")" "unreferenced defs are kept"

echo "file handling"
out=$("$SCRIPT" "$SANDBOX/missing.md" 2>&1); rc=$?
assert_eq 1 "$rc" "missing file exits 1"
case "$out" in *"no such file"*) pass "missing file says so" ;; *) fail "missing file says so" "$out" ;; esac
f=$(plan <<EOF2 | fixture mode
- [ ] a [dashboard!1]($D/1)
EOF2
)
chmod 640 "$f"; "$SCRIPT" "$f"
assert_eq 640 "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" "mode preserved"
assert_eq 0 "$(ls -A "$SANDBOX" | grep -c '^\.diary-links')" "no temp file left"
mkdir -p "$SANDBOX/home"; today=$(date +%F)
plan <<EOF2 > "$SANDBOX/home/$today.md"
- [ ] a [dashboard!1]($D/1)
EOF2
DIARY_DIR="$SANDBOX/home" "$SCRIPT"
assert_eq 1 "$(grep -c '\[↗\]\[dashboard!1\]' "$SANDBOX/home/$today.md")" "default file is today's diary in DIARY_DIR"
case "$("$SCRIPT" -h)" in *"trailing refs"*) pass "-h prints usage" ;; *) fail "-h prints usage" "" ;; esac

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
