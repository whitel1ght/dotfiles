#!/bin/bash
# Tests for bin/pi-autoupdate and the zsh `pi` function. pi is a stub (PI_BIN, and first on PATH
# for the zsh check) that logs its calls, so nothing is installed or updated.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/pi-autoupdate"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export SANDBOX LOG="$SANDBOX/pi.log" PI_AUTOUPDATE_STATE="$SANDBOX/state"
mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/pi" <<'STUB'
#!/bin/bash
echo "pi $* | stdin=$([ -t 0 ] && echo tty || echo closed)" >>"$LOG"
[ "$1" != update ] && exit 0
[ ! -f "$SANDBOX/slow" ] || sleep 30
[ ! -f "$SANDBOX/fail" ] || { echo "npm ERR! network unreachable"; exit 1; }
echo "Updated packages"; echo "pi is already up to date (v1.4.0)"
STUB
chmod +x "$SANDBOX/bin/pi"
export PI_BIN="$SANDBOX/bin/pi"
# The chord guard must never walk the real release trees during these tests.
export PI_RELEASES="$SANDBOX/releases-empty"
mkdir -p "$PI_RELEASES"
run() { : >"$LOG"; ERR="$("$SCRIPT" "$@" 2>&1 >/dev/null)"; RC=$?; }
calls() { grep -c 'update --all' "$LOG" 2>/dev/null || true; }

echo "pi-autoupdate"
run; assert_eq "0|1" "$RC|$(calls)" "an interactive start runs pi update --all"
assert_has "stdin=closed" "$(cat "$LOG")" "with stdin closed"
assert_has "pi: pi and its extensions are up to date" "$ERR" "and says so"
run --model openai/x --models "openai/*"; assert_eq "0" "$(calls)" "within 10 min of the last update: no second wait"
rm -rf "$PI_AUTOUPDATE_STATE"
run --model openai/x; assert_eq "1" "$(calls)" "an alias's flags still update"

echo "pi-autoupdate — not an interactive session"
for args in "update --all" "install npm:x" "list" "config" "-p hello" "--print hi" "--help" "-v" "--mode rpc"; do
  rm -rf "$PI_AUTOUPDATE_STATE"
  # shellcheck disable=SC2086
  run $args; assert_eq "0|0" "$RC|$(calls)" "pi $args: no update"
done

echo "pi-autoupdate — failures never stop pi"
rm -rf "$PI_AUTOUPDATE_STATE"; touch "$SANDBOX/fail"
run; assert_eq "0" "$RC" "a failed update exits 0"
assert_has "update failed (npm ERR! network unreachable), starting anyway" "$ERR" "with its last line"
run; assert_eq "1" "$(calls)" "a failed update is tried again next start"
rm -f "$SANDBOX/fail"; rm -rf "$PI_AUTOUPDATE_STATE"; touch "$SANDBOX/slow"
START=$(date +%s); ERR="$(PI_UPDATE_TIMEOUT=1 "$SCRIPT" 2>&1 >/dev/null)"; RC=$?
assert_eq "0" "$RC" "a slow update exits 0"
[ $(($(date +%s) - START)) -lt 8 ] && pass "after the timeout" || fail "timeout" "took $(($(date +%s) - START))s"
assert_has "timed out after 1s, starting anyway" "$ERR" "and says so"
rm -f "$SANDBOX/slow"

echo "zsh pi function"
if command -v zsh >/dev/null; then
  mkdir -p "$SANDBOX/zbin"; ln -sf "$SCRIPT" "$SANDBOX/zbin/pi-autoupdate"; ln -sf "$SANDBOX/bin/pi" "$SANDBOX/zbin/pi"
  rm -rf "$PI_AUTOUPDATE_STATE"; : >"$LOG"
  fn="$(sed -n '/^pi() {/p' "$TEST_DIR/../zsh/.zshrc")"
  PATH="$SANDBOX/zbin:$PATH" PI_BIN="$SANDBOX/zbin/pi" zsh -fc "$fn; pi --model x hello" 2>/dev/null
  assert_eq "pi update --all|pi --model x hello" "$(cut -d'|' -f1 "$LOG" | sed 's/ $//' | paste -sd '|' -)" "the function updates, then starts pi with the same arguments"
  : >"$LOG"; PATH="$SANDBOX/bin:$PATH" zsh -fc "$fn; pi --model y" 2>/dev/null
  assert_eq "pi --model y" "$(cut -d'|' -f1 "$LOG" | sed 's/ $//')" "without pi-autoupdate installed, pi still starts"
fi

echo "pi-autoupdate — chord guard"
# Fake release trees plus stubbed npm and registry: nothing real is installed or fetched.
CH="$SANDBOX/chord"
mkdir -p "$CH/bin" "$CH/state" "$CH/registry"
export NPM_LOG="$CH/npm.log"
cat >"$CH/bin/npm" <<'STUB'
#!/bin/bash
echo "$PWD :: $*" >>"$NPM_LOG"
[ ! -f "$SANDBOX/chord/npm-fail" ] || exit 1
[ ! -f "$SANDBOX/chord/npm-touch" ] || printf ' \n' >>"$PWD/package.json"
exit 0
STUB
chmod +x "$CH/bin/npm"
cat >"$CH/bin/curl" <<'STUB'
#!/bin/bash
url="${!#}"; v="${url##*/}"
[ -f "$SANDBOX/chord/registry/$v" ] || exit 22
printf '{"name":"@earendil-works/chord","version":"%s"}\n' "$v"
STUB
chmod +x "$CH/bin/curl"
mk_release() { # version, tree name -> path on stdout
  local d="$CH/releases/$2"
  mkdir -p "$d"
  printf '{\n  "name": "@earendil-works/pi-coding-agent",\n  "version": "%s"\n}\n' "$1" >"$d/package.json"
  printf '{"lockfileVersion": 3}\n' >"$d/package-lock.json"
  printf '%s\n' "$d"
}
reg_has() { : >"$CH/registry/$1"; }
chord_reset() { rm -rf "$CH/releases" "$CH/state" "$CH/npm-fail" "$CH/npm-touch"; mkdir -p "$CH/releases"; : >"$NPM_LOG"; }
chord() { ERR="$(PI_AUTOUPDATE_STATE="$CH/state" PI_RELEASES="$CH/releases" NPM_BIN="$CH/bin/npm" CURL_BIN="$CH/bin/curl" "$SCRIPT" chord-check 2>&1 >/dev/null)"; RC=$?; }
chord_log() { cat "$CH/state/chord.log" 2>/dev/null; }
snapshot() { sha256sum "$1/package.json" "$1/package-lock.json" | cut -d' ' -f1 | paste -sd' ' -; }

chord_reset; R="$(mk_release 1.5.0 1.5.0)"; reg_has 1.5.0; BEFORE="$(snapshot "$R")"; BEFORE_PI="$(sha256sum "$PI_BIN" | cut -d' ' -f1)"
: >"$LOG"; chord
assert_eq "0" "$RC" "chord-check always exits 0"
assert_eq "0" "$(calls)" "chord-check does not run pi update"
assert_eq "$(cd "$R" && pwd -P) :: i --no-save --package-lock=false --no-audit --no-fund @earendil-works/chord@1.5.0" "$(cat "$NPM_LOG")" "a 1.5.0 tree without chord gets chord@1.5.0 from its own directory, with the updater-safe flags"
assert_eq "$BEFORE" "$(snapshot "$R")" "and npm leaves package.json and package-lock.json byte-identical"
assert_has "1.5.0 installed @earendil-works/chord@1.5.0 (manifests unchanged)" "$(chord_log)" "the heal is logged to chord.log"

chord_reset; mk_release 0.84.0 0.84.0 >/dev/null; reg_has 0.84.0
chord; assert_eq "0" "$RC" "a 0.84.0 tree exits 0"
assert_eq "" "$(cat "$NPM_LOG")" "a pre-0.85 host may omit chord: npm is never called"
assert_has "0.84.0 exempt" "$(chord_log)" "and the exemption is logged"

chord_reset; R="$(mk_release 1.6.0 1.6.0)"
chord; assert_eq "0" "$RC" "a 1.x tree with no registry version still exits 0"
assert_eq "" "$(cat "$NPM_LOG")" "with no npm call"
assert_has "no @earendil-works/chord@1.6.0 on the registry" "$ERR" "warns that the registry lacks it"
assert_has "1.6.0 missing, no @earendil-works/chord@1.6.0 on the registry, skipped" "$(chord_log)" "and logs the skip"

chord_reset; mk_release 1.5.0 1.5.0 >/dev/null; reg_has 1.5.0; touch "$CH/npm-fail"
chord; assert_eq "0" "$RC" "a failing npm install still exits 0"
assert_has "could not install @earendil-works/chord@1.5.0" "$ERR" "warns about the failed install"
assert_has "npm install of @earendil-works/chord@1.5.0 failed, skipped" "$(chord_log)" "and logs it as skipped"

chord_reset; R="$(mk_release 1.5.0 1.5.0)"; reg_has 1.5.0; touch "$CH/npm-touch"
chord; assert_eq "0" "$RC" "an npm that rewrites the manifest still exits 0"
assert_has "npm rewrote package.json/package-lock.json" "$ERR" "warns that the tree is no longer updater-identical"
assert_has "not a clean heal" "$(chord_log)" "and logs it as not a clean heal"

chord_reset; R="$(mk_release 1.5.0 1.5.0)"; reg_has 1.5.0
mkdir -p "$R/node_modules/@earendil-works/chord"
printf '{"name":"@earendil-works/chord","version":"1.5.0","type":"module","exports":"./index.js"}\n' >"$R/node_modules/@earendil-works/chord/package.json"
printf 'export const chord = 1;\n' >"$R/node_modules/@earendil-works/chord/index.js"
chord; assert_eq "0" "$RC" "a tree that already resolves chord exits 0"
assert_eq "" "$(cat "$NPM_LOG")" "and nothing is installed"
assert_has "1.5.0 ok" "$(chord_log)" "and it is logged as ok"

chord_reset; mk_release 1.5.0 1.5.0 >/dev/null; reg_has 1.5.0
ERR="$(PI_AUTOUPDATE_STATE="$CH/state" PI_RELEASES="$CH/releases" NPM_BIN="$CH/bin/npm" CURL_BIN="$CH/bin/curl" "$SCRIPT" 2>&1 >/dev/null)"; RC=$?
assert_eq "0" "$RC" "a successful update still exits 0"
assert_has "up to date" "$ERR" "and says so"
assert_eq "1" "$(wc -l <"$NPM_LOG" | tr -d ' ')" "the guard heals the chord the update dropped"
assert_has "1.5.0 installed @earendil-works/chord@1.5.0" "$(chord_log)" "logged under the run's state dir"

chord_reset; mk_release 1.5.0 1.5.0 >/dev/null; reg_has 1.5.0; touch "$SANDBOX/slow"
ERR="$(PI_UPDATE_TIMEOUT=1 PI_AUTOUPDATE_STATE="$CH/state" PI_RELEASES="$CH/releases" NPM_BIN="$CH/bin/npm" CURL_BIN="$CH/bin/curl" "$SCRIPT" 2>&1 >/dev/null)"; RC=$?
rm -f "$SANDBOX/slow"
assert_eq "0|0" "$RC|$(cat "$NPM_LOG" | wc -l | tr -d ' ')" "a timed-out update exits 0 without running the guard"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
