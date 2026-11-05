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
chmod +x "$STUBS"/*

export DIARY_DIR="$DIARY" LOG PLAN_PICK_FZF="$STUBS/fzf" PLAN_PICK_JT="$STUBS/jt" PLAN_PICK_OPEN="$STUBS/open"
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
assert_eq "fzf --height=100% --with-nth=3 --delimiter=\\t
jt ECFX-17482" "$(cat "$LOG")" "ticket row execs jt with the key (fzf gets with-nth and delimiter)"

: > "$LOG"; FZF_PICK="dashboard!2289" "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "mr pick exits 0"
assert_eq "fzf --height=100% --with-nth=3 --delimiter=\\t
open https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289" "$(cat "$LOG")" "mr row opens its url"

: > "$LOG"; FZF_EXIT=130 "$SCRIPT"; rc=$?
assert_eq "0" "$rc" "fzf cancel exits 0"
assert_eq "fzf --height=100% --with-nth=3 --delimiter=\\t" "$(cat "$LOG")" "fzf cancel runs nothing"

# empty plan
export DAY_AGENT_DATE=2026-01-01
: > "$LOG"; err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
assert_eq "0" "$rc" "no diary exits 0"
assert_eq "plan-pick: nothing to pick" "$err" "no diary says nothing to pick"
assert_eq "" "$(cat "$LOG")" "no diary never starts fzf"

printf '# x\n<!-- start-day:start -->\n- [ ] just words\n<!-- start-day:end -->\n' > "$DIARY/2026-01-02.md"
export DAY_AGENT_DATE=2026-01-02
err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
assert_eq "0" "$rc" "no rows exits 0"
assert_eq "plan-pick: nothing to pick" "$err" "no rows says nothing to pick"
assert_eq "" "$(cat "$LOG")" "no rows never starts fzf"

# a <!-- pN --> followed by text does not key the line
printf '# x\n<!-- start-day:start -->\n- [ ] call back <!-- p5 --> after lunch\n<!-- start-day:end -->\n' > "$DIARY/2026-01-03.md"
printf '# agent notes 2026-01-03\n## p5\n- mr: admin!77 https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/77\n' > "$DIARY/.agent/2026-01-03.md"
export DAY_AGENT_DATE=2026-01-03
err=$("$SCRIPT" 2>&1 >/dev/null); rc=$?
assert_eq "plan-pick: nothing to pick" "$err" "mid-line <!-- p5 --> is not a key: no MR row"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
