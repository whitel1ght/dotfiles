#!/bin/bash
# Tests for bin/olink. Everything runs inside a sandbox HOME with a stub
# `opencode` on PATH that logs each call, so no real config or server is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/olink"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

SRC="$SANDBOX/dotfiles/opencode"
HOME_DIR="$SANDBOX/home"
DEST="$HOME_DIR/.config/opencode"
STUBS="$SANDBOX/stubs"
LOG="$SANDBOX/opencode.log"

mkdir -p \
    "$SRC/commands" "$SRC/skills/alpha" "$SRC/agents" "$SRC/modules" \
    "$SRC/themes" "$SRC/plugins" \
    "$HOME_DIR" "$STUBS"

printf '{}\n'    > "$SRC/opencode.jsonc"
printf '# cmd\n' > "$SRC/commands/review.md"
printf '# skill\n' > "$SRC/skills/alpha/SKILL.md"
printf '# agent\n' > "$SRC/agents/expert.md"
printf '# module\n' > "$SRC/modules/patterns.md"
printf '{}\n'    > "$SRC/themes/storm.json"
printf '// ts\n' > "$SRC/plugins/gate.ts"

cat > "$STUBS/opencode" <<'EOF'
#!/bin/bash
echo "$*" >> "$OPENCODE_LOG"
exit 0
EOF
chmod +x "$STUBS/opencode"

run_olink() {
    HOME="$HOME_DIR" DOTFILES_DIR="$SANDBOX/dotfiles" OPENCODE_CONFIG_DIR="$DEST" \
    OPENCODE_LOG="$LOG" PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"
}

assert_link() { # dest src label
    if [ -L "$1" ]; then
        [ "$(readlink "$1")" = "$2" ] && pass "$3" \
            || fail "$3" "points to $(readlink "$1")"
    else
        fail "$3" "not a symlink"
    fi
}

echo "olink — create"
out="$(run_olink)"
assert_link "$DEST/opencode.jsonc" "$SRC/opencode.jsonc" "links the config file"
assert_link "$DEST/command" "$SRC/commands" "links commands into singular command/"
assert_link "$DEST/skills" "$SRC/skills" "links skills/"
assert_link "$DEST/agents" "$SRC/agents" "links agents/"
assert_link "$DEST/modules" "$SRC/modules" "links modules/"
assert_link "$DEST/themes/storm.json" "$SRC/themes/storm.json" "links theme entries"
assert_link "$DEST/plugins/gate.ts" "$SRC/plugins/gate.ts" "links plugin entries"
grep -q 'reload' "$LOG" && pass "runs opencode reload" \
    || fail "runs opencode reload" "no reload logged"

echo "idempotence"
: > "$LOG"
run_olink >/dev/null
[ -e "$DEST/skills.backup" ] && fail "second run makes no backup" "skills.backup appeared" \
    || pass "second run makes no backup"
assert_link "$DEST/skills" "$SRC/skills" "second run keeps the link"

echo "repair"
# A link pointing somewhere wrong and one broken outright: both must be fixed,
# which is the one thing install.sh's create_symlink will not do.
ln -sfn /nonexistent/wrong "$DEST/agents"
out="$(run_olink)"
assert_link "$DEST/agents" "$SRC/agents" "re-points a wrong/broken link"
case "$out" in *"re-pointed"*) pass "reports the re-point" ;;
                *) fail "reports the re-point" "$out" ;; esac

echo "real path backup"
rm "$DEST/command"
mkdir -p "$DEST/command"; printf 'real\n' > "$DEST/command/local.md"
out="$(run_olink)"
[ -d "$DEST/command.backup" ] && [ -f "$DEST/command.backup/local.md" ] \
    && pass "backs up a real directory" \
    || fail "backs up a real directory" "no command.backup with its file"
assert_link "$DEST/command" "$SRC/commands" "links over the backup"

echo "dry run"
ln -sfn /nonexistent/wrong "$DEST/skills"
: > "$LOG"
out="$(run_olink -n)"
[ "$(readlink "$DEST/skills")" = "/nonexistent/wrong" ] \
    && pass "dry run leaves links untouched" \
    || fail "dry run leaves links untouched" "link changed to $(readlink "$DEST/skills")"
grep -q 'reload' "$LOG" && fail "dry run does not reload" "reload logged" \
    || pass "dry run does not reload"
case "$out" in *"would re-point"*) pass "dry run reports the pending change" ;;
                *) fail "dry run reports the pending change" "$out" ;; esac

echo "flags"
: > "$LOG"
run_olink --no-reload >/dev/null
grep -q 'reload' "$LOG" && fail "--no-reload skips reload" "reload logged" \
    || pass "--no-reload skips reload"
assert_link "$DEST/skills" "$SRC/skills" "--no-reload still relinks"

run_olink --bogus >/dev/null 2>&1
[ $? -eq 2 ] && pass "unknown option exits 2" || fail "unknown option exits 2" "wrong status"

DOTFILES_DIR=/nonexistent HOME="$HOME_DIR" \
    OPENCODE_CONFIG_DIR="$DEST" PATH="$STUBS:$PATH" bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 1 ] && pass "missing source exits 1" || fail "missing source exits 1" "wrong status"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
