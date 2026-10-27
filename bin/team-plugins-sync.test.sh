#!/bin/bash
# Tests for bin/team-plugins-sync. claude and plink are stubs that log their calls; the plugin list
# comes from a fixture, so no real plugin, cache or pi config is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/team-plugins-sync"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }
assert_lacks() { case "$2" in *"$1"*) fail "$3" "[$1] found in [$2]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export SANDBOX LOG="$SANDBOX/calls.log"
mkdir -p "$SANDBOX/bin" "$SANDBOX/proj/dash"
cat >"$SANDBOX/bin/claude" <<'STUB'
#!/bin/bash
echo "claude $* | cwd=$PWD | stdin=$([ -t 0 ] && echo tty || echo closed)" >>"$LOG"
case "$*" in
  "plugin marketplace update ecfx-components") [ ! -f "$SANDBOX/market.fail" ] || { echo "marketplace offline" >&2; exit 1; } ;;
  "plugin list --json") cat "$SANDBOX/list.json" ;;
  "plugin update "*)
    id="$3"
    [ ! -f "$SANDBOX/fail-$id" ] || { echo "Error: needs confirmation of a marketplace command" >&2; exit 1; }
    echo "Checking for updates…"
    if [ -f "$SANDBOX/uptodate-$id" ]; then echo '{"outcome":"ok","updateOutcome":"up_to_date","oldVersion":"1.0.6","newVersion":"1.0.6"}'
    else echo '{"outcome":"ok","updateOutcome":"updated"}'; fi ;;
  *) echo "unexpected: $*" >&2; exit 2 ;;
esac
STUB
printf '#!/bin/bash\necho "plink $*" >>"$LOG"\n[ ! -f "$SANDBOX/plink.fail" ] || { echo "plink: skills dir missing" >&2; exit 1; }\necho "lots of plink output"\n' >"$SANDBOX/bin/plink"
chmod +x "$SANDBOX/bin/claude" "$SANDBOX/bin/plink"
export PATH="$SANDBOX/bin:$PATH"
[ "$(command -v claude)" = "$SANDBOX/bin/claude" ] || { echo "refusing to run: the claude stub is not first on PATH"; exit 1; }

entry() { # id scope version folderVersion [projectPath]
  jq -nc --arg id "$1" --arg s "$2" --arg v "$3" --arg f "$4" --arg p "${5:-}" \
    '{id: $id, scope: $s, version: $v, folderVersion: $f} + (if $p == "" then {} else {projectPath: $p} end)'
}
list() { printf '%s\n' "$@" | jq -s . >"$SANDBOX/list.json"; }
run() { : >"$LOG"; OUT="$("$SCRIPT" 2>&1)"; RC=$?; }

echo "team-plugins-sync"
list "$(entry backend@ecfx-components user 1.0.5 1.0.7)" \
  "$(entry shared@ecfx-components user 1.0.6 1.0.6)" \
  "$(entry shared@ecfx-components project 1.0.5 1.0.6 "$SANDBOX/proj/dash")" \
  "$(entry shared@ecfx-components project 1.0.5 1.0.6 "$SANDBOX/proj/gone")" \
  "$(entry daily@dmitry-dotfiles user 0.1.0 0.2.0)" \
  "$(entry admin@ecfx-components user 1.0.2)"
run
assert_eq "0" "$RC" "exits 0"
assert_has "claude plugin marketplace update ecfx-components |" "$(head -1 "$LOG")" "the marketplace is refreshed first"
assert_has "claude plugin update backend@ecfx-components --scope user --json | cwd=$HOME" "$(cat "$LOG")" "a user-scope plugin behind its folder is updated from home"
assert_has "claude plugin update shared@ecfx-components --scope project --json | cwd=$SANDBOX/proj/dash" "$(cat "$LOG")" "a project-scope one from its project"
assert_lacks "proj/gone" "$(cat "$LOG")" "a project that no longer exists is skipped"
assert_eq "2" "$(grep -c 'plugin update' "$LOG")" "nothing up to date, from another marketplace, or without a folder version is updated"
assert_lacks " -y" "$(cat "$LOG")" "never -y: a marketplace command is never accepted unseen"
assert_lacks "stdin=tty" "$(cat "$LOG")" "stdin closed"
assert_has "plink" "$(tail -1 "$LOG")" "then plink, last"
assert_has "- backend: 1.0.5 → 1.0.7" "$OUT" "each update is reported with its versions"
assert_has "- shared (project dash): 1.0.5 → 1.0.6" "$OUT" "a project install names its project"
assert_lacks "lots of plink output" "$OUT" "plink's own output stays quiet"
assert_has "team plugins: 2 updated, 0 failed; pi skills regenerated; new sessions load them" "$OUT" "a summary line"

echo "team-plugins-sync — a stale listed version that needs nothing"
list "$(entry shared@ecfx-components project 1.0.5 1.0.6 "$SANDBOX/proj/dash")"
touch "$SANDBOX/uptodate-shared@ecfx-components"
run
assert_eq "1" "$(grep -c 'plugin update' "$LOG")" "the update is asked for"
assert_lacks "- shared" "$OUT" "but claude's up_to_date answer is not reported as an update"
assert_has "team plugins: all up to date" "$OUT" "and it counts as up to date"
rm -f "$SANDBOX/uptodate-shared@ecfx-components"

echo "team-plugins-sync — all current"
list "$(entry shared@ecfx-components user 1.0.6 1.0.6)"
run
assert_eq "0" "$(grep -c 'plugin update' "$LOG")" "nothing to update"
assert_has "team plugins: all up to date; pi skills regenerated" "$OUT" "says so"

echo "team-plugins-sync — failures"
list "$(entry backend@ecfx-components user 1.0.5 1.0.7)" "$(entry ui-review@ecfx-components user 1.0.2 1.0.3)"
touch "$SANDBOX/fail-backend@ecfx-components" "$SANDBOX/market.fail" "$SANDBOX/plink.fail"
run
assert_eq "0" "$RC" "still exits 0"
assert_has "- marketplace refresh failed: marketplace offline" "$OUT" "a failed marketplace refresh is reported"
assert_has "- backend: update failed: Error: needs confirmation of a marketplace command" "$OUT" "a failed update names the plugin and why"
assert_has "- ui-review: 1.0.2 → 1.0.3" "$OUT" "the others still update"
assert_has "- plink failed: plink: skills dir missing" "$OUT" "a failed plink is reported"
assert_has "team plugins: 1 updated, 1 failed" "$OUT" "counted"
rm -f "$SANDBOX"/fail-* "$SANDBOX/market.fail" "$SANDBOX/plink.fail"

echo "team-plugins-sync — no plugin list"
printf 'not json' >"$SANDBOX/list.json"
run
assert_eq "0" "$RC" "exits 0"
assert_has "could not read the plugin list" "$OUT" "says it could not read the list"
assert_has "plink" "$(cat "$LOG")" "pi still gets its skills"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
