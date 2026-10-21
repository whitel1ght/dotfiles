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
    SKILLS_SYNC=0 MACOS_DAEMONS=0 REPY_SETUP=0 DECISIONS_SETUP="${DECISIONS_SETUP:-0}" \
    DECISIONS_TELEGRAM_AGENT="${DECISIONS_TELEGRAM_AGENT:-0}" \
    ECFX_TOOLING=0 ZSH_SETUP=0 KEYBOARD_SETUP=0 TMUX_SETUP=0 PROXY_SETUP=0 WIKI_SYNC_AGENT=0 \
    CLAUDE_COMPONENTS_DIR=/nonexistent \
        bash "$SCRIPT" 2>&1
}

# The files seeded from a committed template, and the mode each must land with.
# sing-box is covered by the sandbox run too, but only when PROXY_SETUP is on;
# it is disabled here because setup_proxy also probes for the sing-box binary.
SEEDED="\
.gitconfig.local:644
.zshrc.local:600
.secrets/secrets.env:600"

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
    for v in CLOUD NOTES_USER NOTES_PORT NOTES_REMOTE_DIR JIRA_EMAIL JIRA_API_TOKEN; do
        eval "x=\${$v:-}"
        [ -n "$x" ] && printf "%s " "$v"
    done')"
[ -z "$leaked" ] \
    && pass "seeded shell configs export nothing" \
    || fail "seeded shell configs export nothing" "these were set: $leaked"

# --- wiki sync ---------------------------------------------------------------
echo "wiki sync"
[ -L "$SANDBOX/.local/bin/wiki-sync" ] && pass "wiki-sync is on PATH" || fail "wiki-sync is on PATH" "not linked"
[ -L "$SANDBOX/.local/bin/decide" ] && [ -L "$SANDBOX/.local/bin/decisions" ] \
    && pass "decide and decisions are on PATH" || fail "decide and decisions are on PATH" "not linked"
[ -L "$SANDBOX/.local/bin/art" ] && pass "art is on PATH" || fail "art is on PATH" "not linked"
[ -e "$SANDBOX/.local/bin/notes" ] && fail "the rsync notes command is gone" "still linked" || pass "the rsync notes command is gone"
[ -e "$SANDBOX/Library/LaunchAgents/local.wiki-sync.plist" ] && fail "WIKI_SYNC_AGENT=0 installs no agent" "plist written" \
    || pass "WIKI_SYNC_AGENT=0 installs no agent"

# --- gradle ------------------------------------------------------------------
echo "gradle"
[ "$(readlink "$SANDBOX/.gradle/init.d/groovy-heap.gradle")" = "$TEST_DIR/gradle/init.d/groovy-heap.gradle" ] \
    && pass "groovy-heap.gradle is linked into ~/.gradle/init.d" \
    || fail "groovy-heap.gradle is linked into ~/.gradle/init.d" "$(ls -l "$SANDBOX/.gradle/init.d/groovy-heap.gradle" 2>&1)"

# --- ~/.secrets -------------------------------------------------------------
echo "secrets"
[ "$(stat -f %Lp "$SANDBOX/.secrets")" = "700" ] && pass "~/.secrets has mode 700" \
    || fail "~/.secrets has mode 700" "got $(stat -f %Lp "$SANDBOX/.secrets")"
names="$(SECRETS_FILE="$SANDBOX/.secrets/secrets.env" "$TEST_DIR/bin/secret" -l)"
[ -z "$names" ] && pass "seeded secrets.env sets no name" || fail "seeded secrets.env sets no name" "set: $names"
[ "$(readlink "$SANDBOX/.config/ecfx/jira.env")" = "$SANDBOX/.secrets/secrets.env" ] \
    && pass "ecfx jira.env links to secrets.env" || fail "ecfx jira.env links to secrets.env" "$(ls -l "$SANDBOX/.config/ecfx/jira.env" 2>&1)"
[ -L "$SANDBOX/.local/bin/secret" ] && [ -L "$SANDBOX/.local/bin/secrets" ] \
    && pass "secret and secrets are on PATH" || fail "secret and secrets are on PATH" "not linked"
settings="$SANDBOX/.claude/settings.json"
jq -e --arg g "$TEST_DIR/bin/secrets-guard" \
    '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[].command] | index($g) != null' "$settings" >/dev/null \
    && pass "Claude runs secrets-guard before Bash" || fail "Claude runs secrets-guard before Bash" "$(jq -c .hooks.PreToolUse "$settings" 2>&1)"
jq -e --arg g "$TEST_DIR/bin/docker-guard" \
    '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[].command] | index($g) != null' "$settings" >/dev/null \
    && pass "Claude runs docker-guard before Bash" || fail "Claude runs docker-guard before Bash" "$(jq -c .hooks.PreToolUse "$settings" 2>&1)"
jq -e '.permissions.deny | index("Read(~/.secrets/**)") != null and index("Edit(~/.secrets/**)") != null and index("Read(~/.config/ecfx/jira.env)") != null' "$settings" >/dev/null \
    && pass "Claude file tools are denied ~/.secrets" || fail "Claude file tools are denied ~/.secrets" "$(jq -c .permissions.deny "$settings" 2>&1)"

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
n="$(jq --arg g "$TEST_DIR/bin/secrets-guard" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $g)] | length' "$SANDBOX/.claude/settings.json")"
[ "$n" = "1" ] && pass "re-run adds the guard hook once" || fail "re-run adds the guard hook once" "found $n"
n="$(jq --arg g "$TEST_DIR/bin/docker-guard" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $g)] | length' "$SANDBOX/.claude/settings.json")"
[ "$n" = "1" ] && pass "re-run adds the docker hook once" || fail "re-run adds the docker hook once" "found $n"
n="$(jq '[.permissions.deny[] | select(. == "Read(~/.secrets/**)")] | length' "$SANDBOX/.claude/settings.json")"
[ "$n" = "1" ] && pass "re-run adds each deny rule once" || fail "re-run adds each deny rule once" "found $n"

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

# --- global commands must stay out of the context window ------------------
echo "claude commands"
for cmd in "$TEST_DIR"/claude/commands/*.md; do
    [ -e "$cmd" ] || continue
    name="$(basename "$cmd")"
    if sed -n '1,/^---$/{/^---$/!p;}' <(tail -n +2 "$cmd") | grep -qx 'disable-model-invocation: true'; then
        pass "$name is invoke-only"
    else
        fail "$name is invoke-only" "missing disable-model-invocation: true in frontmatter"
    fi
    [ -L "$SANDBOX/.claude/commands/$name" ] && pass "$name linked into ~/.claude/commands" \
        || fail "$name linked into ~/.claude/commands" "no symlink in sandbox"
done

# --- decisions app ------------------------------------------------------------
echo "decisions app"
STUB="$SANDBOX/stub-bin"; mkdir -p "$STUB"
cat > "$STUB/cargo" <<'EOF'
#!/bin/bash
echo "$*" >> "$HOME/cargo.log"
root=""; while [ $# -gt 0 ]; do [ "$1" = --root ] && root="$2"; shift; done
mkdir -p "$root/bin" && printf '#!/bin/sh\n' > "$root/bin/decisions" && chmod +x "$root/bin/decisions"
EOF
chmod +x "$STUB/cargo"
FIXTURE="$SANDBOX/decisions-src"; mkdir -p "$FIXTURE/src"
printf '[package]\nname = "decisions"\n' > "$FIXTURE/Cargo.toml"; printf 'fn main() {}\n' > "$FIXTURE/src/main.rs"; : > "$FIXTURE/Cargo.lock"
run_decisions() { PATH="$STUB:$PATH" DECISIONS_SETUP=1 DECISIONS_SRC="$FIXTURE" run_install; }
run_decisions >/dev/null
[ -x "$SANDBOX/.local/share/decisions/bin/decisions" ] && pass "builds the decisions app" || fail "builds the decisions app" "$(cat "$SANDBOX/cargo.log" 2>&1)"
assert_contains "$(cat "$SANDBOX/cargo.log")" "install --locked --quiet --path $FIXTURE --root $SANDBOX/.local/share/decisions" "with cargo install --locked into ~/.local/share/decisions"
run_decisions >/dev/null
[ "$(wc -l < "$SANDBOX/cargo.log" | tr -d ' ')" = 1 ] && pass "skips the build when the sources did not change" || fail "skips the build when the sources did not change" "$(cat "$SANDBOX/cargo.log")"
[ "$(readlink "$SANDBOX/.local/bin/run-day-inbox-answer")" = "$TEST_DIR/bin/run-day-inbox-answer" ] && pass "the run-day inbox hook is linked" || fail "the run-day inbox hook is linked" "$(ls -l "$SANDBOX/.local/bin/run-day-inbox-answer" 2>&1)"
out="$(PATH="$STUB:$PATH" DECISIONS_SETUP=1 DECISIONS_SRC="$SANDBOX/nowhere" run_install)"
assert_contains "$out" "clone https://github.com/whitel1ght/decisions" "a missing source says where to get it"

# --- decisions Telegram agent ---------------------------------------------------
echo "decisions telegram agent"
cat > "$STUB/launchctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$HOME/launchctl.log"
EOF
chmod +x "$STUB/launchctl"
AGENT="$SANDBOX/Library/LaunchAgents/local.decisions-telegram.plist"
run_tg() { PATH="$STUB:$PATH" DECISIONS_TELEGRAM_AGENT=1 run_install; }
out="$(run_tg)"
[ -e "$AGENT" ] && fail "no agent before pairing" "plist written" || pass "no agent before pairing"
assert_contains "$out" "decisions telegram pair" "says to pair first"
mkdir -p "$SANDBOX/.local/state/run-day/decisions"
printf '{\n  "chat_id": 42,\n  "enabled": true\n}\n' > "$SANDBOX/.local/state/run-day/decisions/telegram.json"
run_tg >/dev/null
[ -e "$AGENT" ] && pass "installs the agent once paired" || fail "installs the agent once paired" "no plist"
assert_contains "$(cat "$AGENT" 2>/dev/null)" "<string>$SANDBOX/.local/bin/decisions</string>" "the agent runs the decisions wrapper"
assert_contains "$(cat "$AGENT" 2>/dev/null)" "<string>run</string>" "with telegram run"
assert_contains "$(cat "$SANDBOX/launchctl.log" 2>/dev/null)" "bootstrap gui/" "and loads it"
n=$(grep -c bootstrap "$SANDBOX/launchctl.log" 2>/dev/null)
run_tg >/dev/null
[ "$(grep -c bootstrap "$SANDBOX/launchctl.log" 2>/dev/null)" = "$n" ] && pass "an unchanged agent is not reloaded" || fail "an unchanged agent is not reloaded" "$(cat "$SANDBOX/launchctl.log")"
echo '// changed' >> "$FIXTURE/src/main.rs"
DECISIONS_SETUP=1 DECISIONS_SRC="$FIXTURE" run_tg >/dev/null
assert_contains "$(cat "$SANDBOX/launchctl.log" 2>/dev/null)" "kickstart -k gui/" "a rebuilt binary restarts the bot"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
