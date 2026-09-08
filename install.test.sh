#!/bin/bash
# Tests install.sh's seeding of machine-local config files.
#
# Runs the real install.sh against a sandbox HOME with every optional step
# disabled, so nothing on this machine is touched: no brew, no launchctl, no
# network, and every symlink lands inside the sandbox.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/install.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_contains() {
    case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in output" ;; esac
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

run_install() {
    HOME="$SANDBOX" \
    SKILLS_SYNC=0 MACOS_DAEMONS=0 REDDITTUI_SETUP=0 REDLIB_SETUP=0 \
    ECFX_TOOLING=0 ZSH_SETUP=0 KEYBOARD_SETUP=0 TMUX_SETUP=0 PROXY_SETUP=0 \
    CLAUDE_COMPONENTS_DIR=/nonexistent \
        bash "$SCRIPT" 2>&1
}

# The files seeded from a committed template, and the mode each must land with.
# sing-box is covered by the sandbox run too, but only when PROXY_SETUP is on;
# it is disabled here because setup_proxy also probes for the sing-box binary.
SEEDED="\
.gitconfig.local:644
.zshrc.local:600
.config/mrglass/secrets.env:600"

echo "install.sh — local config seeding"

echo "first run"
out="$(run_install)"

while IFS=: read -r rel mode; do
    [ -n "$rel" ] || continue
    if [ -f "$SANDBOX/$rel" ]; then
        pass "seeded $rel"
        actual="$(stat -f %Lp "$SANDBOX/$rel")"
        [ "$actual" = "$mode" ] && pass "$rel has mode $mode" \
            || fail "$rel has mode $mode" "got $actual"
    else
        fail "seeded $rel" "file absent"
    fi
done <<< "$SEEDED"

assert_contains "$out" "INERT until filled in" "prints the needs-attention summary"

# --- the seeded copies must not set anything ------------------------------
echo "inertness"
# env -i is REQUIRED, not tidiness. Sourcing in the current environment lets
# ${JIRA_EMAIL:-} fall back to the real value this machine already exports via
# .zshenv, so the test would both pass for the wrong reason on a clean machine
# and PRINT A LIVE API TOKEN into its output on a configured one.
#
# For the same reason the failure message reports only which names were set,
# never their values.
leaked="$(env -i HOME="$SANDBOX" bash -c '
    . "$HOME/.zshrc.local" 2>/dev/null
    . "$HOME/.config/mrglass/secrets.env" 2>/dev/null
    for v in CLOUD NOTES_USER NOTES_PORT NOTES_REMOTE_DIR JIRA_EMAIL JIRA_API_TOKEN; do
        eval "x=\${$v:-}"
        [ -n "$x" ] && printf "%s " "$v"
    done')"
[ -z "$leaked" ] \
    && pass "seeded shell configs export nothing" \
    || fail "seeded shell configs export nothing" "these were set: $leaked"

# An empty trailing PATH element means "current directory" — a real hazard.
pathv="$( . "$SANDBOX/.zshrc.local" 2>/dev/null; echo "${PATH:-}" )"
case "$pathv" in *:) fail "seeded .zshrc.local leaves no empty PATH element" "PATH ends in ':'" ;;
                 *) pass "seeded .zshrc.local leaves no empty PATH element" ;; esac

# git must not pick up an identity from the seeded file.
if git config -f "$SANDBOX/.gitconfig.local" --get user.name >/dev/null 2>&1; then
    fail "seeded .gitconfig.local sets no user.name" "a name is active"
else
    pass "seeded .gitconfig.local sets no user.name"
fi
# commit.template pointing at a missing path aborts every commit.
if git config -f "$SANDBOX/.gitconfig.local" --get commit.template >/dev/null 2>&1; then
    fail "seeded .gitconfig.local sets no commit.template" "a template is active"
else
    pass "seeded .gitconfig.local sets no commit.template"
fi

# --- a second run must never overwrite real credentials -------------------
echo "idempotence"
echo "export NOTES_USER=real-value" >> "$SANDBOX/.zshrc.local"
before="$(shasum -a 256 < "$SANDBOX/.zshrc.local")"
out2="$(run_install)"
after="$(shasum -a 256 < "$SANDBOX/.zshrc.local")"
[ "$before" = "$after" ] && pass "re-run leaves an existing file untouched" \
    || fail "re-run leaves an existing file untouched" "checksum changed"
case "$out2" in *"INERT until filled in"*) fail "re-run seeds nothing new" "summary printed again" ;;
                *) pass "re-run seeds nothing new" ;; esac

# --- a missing template must warn, not crash ------------------------------
echo "missing template"
out3="$(HOME="$SANDBOX" bash -c '
    log_warn() { echo "[WARN] $1"; }
    log_info() { echo "[INFO] $1"; }
    SEEDED_CONFIGS=()
    '"$(sed -n '/^seed_local_config()/,/^}/p' "$SCRIPT")"'
    seed_local_config /nonexistent/template.example "$HOME/should-not-exist" 600 hint
    echo "survived rc=$?"
')"
assert_contains "$out3" "Missing template" "warns on a missing template"
assert_contains "$out3" "survived rc=0" "does not abort the install"
[ -e "$SANDBOX/should-not-exist" ] && fail "creates nothing when template missing" "file created" \
    || pass "creates nothing when template missing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
