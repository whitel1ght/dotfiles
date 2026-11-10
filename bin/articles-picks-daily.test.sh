#!/bin/bash
# Tests for bin/articles-picks-daily. nvm and articles are stubs in a sandbox: the nvm stub puts
# a fake node dir on PATH, the articles stub records its arguments and the PATH it saw.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/articles-picks-daily"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
mkdir -p "$SANDBOX/brew/opt/nvm" "$SANDBOX/node/bin" "$SANDBOX/home"
cat >"$SANDBOX/brew/opt/nvm/nvm.sh" <<EOF
nvm() { [ "\$1 \$2 \$3" = "use --silent default" ] && PATH="$SANDBOX/node/bin:\$PATH"; }
EOF

# has_picks → writes the articles stub (answers `picks --help` per has_picks, logs the rest)
stub() {
  cat >"$SANDBOX/articles" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "picks --help" ]; then exit $1; fi
echo "\$*" >"$SANDBOX/calls"
echo "\$PATH" >"$SANDBOX/path"
EOF
  chmod +x "$SANDBOX/articles"
}
run() { rm -f "$SANDBOX/calls" "$SANDBOX/path"; HOME="$SANDBOX/home" HOMEBREW_PREFIX="$SANDBOX/brew" ARTICLES_CMD="$SANDBOX/articles" PATH="/usr/bin:/bin" bash "$SCRIPT" "$@"; }

echo "articles-picks-daily"
stub 0
OUT="$(run)"
RC=$?
assert_eq "0" "$RC" "with the picks command it exits 0"
assert_eq "picks" "$(cat "$SANDBOX/calls" 2>/dev/null)" "and runs articles picks"
assert_has "$SANDBOX/node/bin" "$(cat "$SANDBOX/path" 2>/dev/null)" "with nvm's default node on PATH (pi needs it)"
assert_has "articles picks" "$OUT" "and logs a dated line first"

run --dry-run >/dev/null
assert_eq "picks --dry-run" "$(cat "$SANDBOX/calls" 2>/dev/null)" "arguments pass through"

stub 2
OUT="$(run)"
RC=$?
assert_eq "0" "$RC" "without the picks command it still exits 0"
assert_eq "no" "$([ -e "$SANDBOX/calls" ] && echo yes || echo no)" "and runs nothing"
assert_has "no picks command yet" "$OUT" "and says why"

rm -rf "$SANDBOX/brew/opt/nvm"
stub 0
run >/dev/null
assert_eq "picks" "$(cat "$SANDBOX/calls" 2>/dev/null)" "no nvm installed: it still runs (pi may bring its own node)"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
