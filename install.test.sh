#!/usr/bin/env bash
# Exercise install.sh entirely inside temporary HOME/XDG roots. No apt, network,
# sudo, service manager, live tmux server, or real credentials are touched.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$TEST_DIR/install.sh"
PASS=0
FAIL=0
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass() { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n         %s\n' "$1" "$2"; }
assert_link() {
    local target="$1" source="$2" label="$3"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        pass "$label"
    else
        fail "$label" "expected $target -> $source; got $(readlink "$target" 2>/dev/null || echo missing)"
    fi
}

HOME_DIR="$SANDBOX/home"
XDG_DIR="$HOME_DIR/.config"
mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.claude/commands" "$HOME_DIR/.repy"
printf 'user command\n' > "$HOME_DIR/.claude/commands/user.md"
printf 'existing file\n' > "$HOME_DIR/.tmux.conf"
printf 'foreign target\n' > "$SANDBOX/foreign-notes"
ln -s "$SANDBOX/foreign-notes" "$HOME_DIR/.local/bin/notes"

run_install() {
    env HOME="$HOME_DIR" XDG_CONFIG_HOME="$XDG_DIR" \
        DOTFILES_LINKS_ONLY=1 DRY_RUN=0 \
        KEYBOARD_SETUP=1 ZSH_SETUP=1 TMUX_SETUP=1 REPY_SETUP=1 SDKMAN_SETUP=1 \
        OLLAMA_SETUP=1 NEWSBOAT_SETUP=1 SKILLS_SYNC=1 CLAUDE_HOOKS=1 \
        CLAUDE_MARKETPLACE=1 \
        bash "$SCRIPT" 2>&1
}

echo 'install.sh — first run'
out="$(run_install)"

assert_link "$XDG_DIR/i3/config" "$TEST_DIR/i3/config" 'links the Ubuntu i3 config'
assert_link "$XDG_DIR/i3/scripts" "$TEST_DIR/i3/scripts" 'links Ubuntu i3 helpers'
assert_link "$XDG_DIR/ghostty/config" "$TEST_DIR/ghostty/config" 'links Ghostty config'
assert_link "$HOME_DIR/.config/nvim" "$TEST_DIR/nvim" 'links Neovim tree'
assert_link "$HOME_DIR/.tmux.conf" "$TEST_DIR/tmux/.tmux.conf" 'backs up and links tmux config'
[ -f "$HOME_DIR/.tmux.conf.backup" ] && pass 'backs up the preexisting tmux config' \
    || fail 'backs up the preexisting tmux config' 'backup absent'
assert_link "$HOME_DIR/.zshrc" "$TEST_DIR/zsh/.zshrc" 'links .zshrc'
assert_link "$HOME_DIR/.zprofile" "$TEST_DIR/zsh/.zprofile" 'links .zprofile'
assert_link "$HOME_DIR/.zshenv" "$TEST_DIR/zsh/.zshenv" 'links .zshenv'
assert_link "$HOME_DIR/.p10k.zsh" "$TEST_DIR/zsh/.p10k.zsh" 'links p10k config'
assert_link "$HOME_DIR/.gitconfig" "$TEST_DIR/git/.gitconfig" 'links portable Git config'
assert_link "$XDG_DIR/superfile/config.toml" "$TEST_DIR/superfile/config.toml" 'links Superfile to XDG'
assert_link "$XDG_DIR/newsboat/config" "$TEST_DIR/newsboat/config" 'links Newsboat config'
assert_link "$XDG_DIR/mrglass/config.yaml" "$TEST_DIR/mrglass/config.yaml" 'links mrglass config'
assert_link "$HOME_DIR/.local/bin/proxyctl" "$TEST_DIR/bin/proxyctl" 'keeps Ubuntu proxyctl'
assert_link "$HOME_DIR/.local/bin/clipboard-copy" "$TEST_DIR/bin/clipboard-copy" 'links Linux clipboard helper'
assert_link "$HOME_DIR/.local/bin/wt" "$TEST_DIR/bin/wt" 'links worktree helper'
[ "$(readlink "$HOME_DIR/.local/bin/notes")" = "$SANDBOX/foreign-notes" ] \
    && pass 'preserves a foreign helper symlink' || fail 'preserves a foreign helper symlink' 'foreign link changed'
[ -f "$HOME_DIR/.claude/commands/user.md" ] \
    && pass 'preserves unrelated Claude commands' || fail 'preserves unrelated Claude commands' 'user command missing'
[ ! -e "$HOME_DIR/.config/aerospace" ] \
    && pass 'does not install AeroSpace config' || fail 'does not install AeroSpace config' 'unexpected path exists'
[ ! -e "$HOME_DIR/Library" ] \
    && pass 'does not create macOS Library paths' || fail 'does not create macOS Library paths' 'unexpected path exists'

for rel in .zshrc.local .gitconfig.local .config/mrglass/secrets.env .config/sing-box/secrets.env; do
    [ -f "$HOME_DIR/$rel" ] && pass "seeds $rel" || fail "seeds $rel" 'file absent'
done
[ "$(stat -c %a "$HOME_DIR/.zshrc.local")" = 600 ] && pass '.zshrc.local mode is 600' || fail '.zshrc.local mode is 600' 'wrong mode'
[ "$(stat -c %a "$HOME_DIR/.gitconfig.local")" = 644 ] && pass '.gitconfig.local mode is 644' || fail '.gitconfig.local mode is 644' 'wrong mode'
[ "$(stat -c %a "$HOME_DIR/.config/mrglass/secrets.env")" = 600 ] && pass 'mrglass secrets mode is 600' || fail 'mrglass secrets mode is 600' 'wrong mode'
[ "$(stat -c %a "$HOME_DIR/.config/sing-box/secrets.env")" = 600 ] && pass 'proxy secrets mode is 600' || fail 'proxy secrets mode is 600' 'wrong mode'

if env -i HOME="$HOME_DIR" bash -c '
    . "$HOME/.zshrc.local"
    . "$HOME/.config/mrglass/secrets.env"
    . "$HOME/.config/sing-box/secrets.env"
    for v in CLOUD NOTES_USER NOTES_PORT NOTES_REMOTE_DIR JIRA_EMAIL JIRA_API_TOKEN \
             VLESS_SERVER VLESS_PORT VLESS_UUID VLESS_SNI VLESS_PBK VLESS_SID; do
        eval "x=\${$v:-}"
        [ -z "$x" ] || exit 1
    done
'; then
    pass 'seeded local templates are inert'
else
    fail 'seeded local templates are inert' 'a placeholder assignment was active'
fi

printf 'export NOTES_USER=real-user\n' >> "$HOME_DIR/.zshrc.local"
before="$(sha256sum "$HOME_DIR/.zshrc.local")"
out2="$(run_install)"
after="$(sha256sum "$HOME_DIR/.zshrc.local")"
[ "$before" = "$after" ] && pass 'rerun preserves existing local values' \
    || fail 'rerun preserves existing local values' 'local file changed'
[ ! -e "$HOME_DIR/.tmux.conf.backup.1" ] && pass 'rerun does not create redundant backups' \
    || fail 'rerun does not create redundant backups' 'extra backup appeared'
[ "$(readlink "$HOME_DIR/.local/bin/notes")" = "$SANDBOX/foreign-notes" ] \
    && pass 'rerun still preserves foreign symlinks' || fail 'rerun still preserves foreign symlinks' 'foreign link changed'

# A broken link into this checkout is owned and repairable.
rm "$HOME_DIR/.local/bin/jt"
ln -s "$TEST_DIR/bin/does-not-exist" "$HOME_DIR/.local/bin/jt"
run_install >/dev/null
assert_link "$HOME_DIR/.local/bin/jt" "$TEST_DIR/bin/jt" 'repairs a broken dotfiles-owned helper symlink'

# DRY_RUN must create no paths, even when every optional flag is requested.
FRESH="$SANDBOX/fresh"
env HOME="$FRESH" XDG_CONFIG_HOME="$FRESH/.config" DRY_RUN=1 \
    DOTFILES_LINKS_ONLY=0 KEYBOARD_SETUP=1 SDKMAN_SETUP=1 ZSH_SETUP=1 TMUX_SETUP=1 \
    REPY_SETUP=1 OLLAMA_SETUP=1 NEWSBOAT_SETUP=1 CLAUDE_HOOKS=1 CLAUDE_MARKETPLACE=1 \
    SKILLS_SYNC=1 bash "$SCRIPT" > "$SANDBOX/dry-run.log" 2>&1
[ ! -e "$FRESH" ] && pass 'dry run creates no HOME paths' || fail 'dry run creates no HOME paths' 'HOME was created'

# Repy must not switch a legacy data prefix behind the user's back.
LEGACY="$SANDBOX/legacy"
mkdir -p "$LEGACY/.repy"
printf 'reading state\n' > "$LEGACY/.repy/states.db"
env HOME="$LEGACY" XDG_CONFIG_HOME="$LEGACY/.config" DOTFILES_LINKS_ONLY=1 \
    bash "$SCRIPT" > "$SANDBOX/legacy.log" 2>&1
[ ! -e "$LEGACY/.config/repy/configuration.json" ] \
    && pass 'preserves the legacy repy state prefix' || fail 'preserves the legacy repy state prefix' 'XDG config link created'
[ -f "$LEGACY/.repy/states.db" ] && pass 'leaves repy reading state untouched' || fail 'leaves repy reading state untouched' 'state changed'

# Explicit Claude-hook setup must append only the dotfiles hooks and retain
# unrelated hooks/settings. All writes are confined to another sandbox HOME.
HOOK_HOME="$SANDBOX/hooks-home"
mkdir -p "$HOOK_HOME/.claude"
cat > "$HOOK_HOME/.claude/settings.json" <<'JSON'
{"customSetting":true,"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"user-start"}]}],"WorktreeCreate":[{"hooks":[{"type":"command","command":"user-create"}]}]}}
JSON
env HOME="$HOOK_HOME" XDG_CONFIG_HOME="$HOOK_HOME/.config" CLAUDE_HOOKS=1 \
    bash "$SCRIPT" > "$SANDBOX/hooks.log" 2>&1
HOME="$HOOK_HOME" jq -e '.customSetting == true
  and any(.hooks.SessionStart[]?.hooks[]?; .command == "user-start")
  and any(.hooks.WorktreeCreate[]?.hooks[]?; .command == "user-create")
  and any(.hooks.WorktreeCreate[]?.hooks[]?; .command == (env.HOME + "/.local/bin/wt hook-create"))
  and any(.hooks.WorktreeRemove[]?.hooks[]?; .command == (env.HOME + "/.local/bin/wt hook-remove"))' \
  "$HOOK_HOME/.claude/settings.json" >/dev/null \
    && pass 'Claude hooks merge without replacing user hooks/settings' \
    || fail 'Claude hooks merge without replacing user hooks/settings' 'merged settings differ'
before="$(sha256sum "$HOOK_HOME/.claude/settings.json")"
env HOME="$HOOK_HOME" XDG_CONFIG_HOME="$HOOK_HOME/.config" CLAUDE_HOOKS=1 \
    bash "$SCRIPT" >/dev/null 2>&1
after="$(sha256sum "$HOOK_HOME/.claude/settings.json")"
[ "$before" = "$after" ] && pass 'Claude hook merge is idempotent' \
    || fail 'Claude hook merge is idempotent' 'rerun changed settings'

# Ubuntu command-name compatibility links are executable links, not aliases.
SHIM_HOME="$SANDBOX/shims-home"
SHIM_BIN="$SANDBOX/shim-bin"
mkdir -p "$SHIM_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM_BIN/fdfind"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM_BIN/batcat"
chmod +x "$SHIM_BIN/fdfind" "$SHIM_BIN/batcat"
env HOME="$SHIM_HOME" XDG_CONFIG_HOME="$SHIM_HOME/.config" \
    PATH="$SHIM_BIN:/usr/bin:/bin" DOTFILES_LINKS_ONLY=1 bash "$SCRIPT" >/dev/null 2>&1
[ "$(readlink "$SHIM_HOME/.local/bin/fd")" = "$SHIM_BIN/fdfind" ] \
    && pass 'creates fd -> fdfind executable shim when needed' \
    || fail 'creates fd -> fdfind executable shim when needed' 'link absent or incorrect'
[ "$(readlink "$SHIM_HOME/.local/bin/bat")" = "$SHIM_BIN/batcat" ] \
    && pass 'creates bat -> batcat executable shim when needed' \
    || fail 'creates bat -> batcat executable shim when needed' 'link absent or incorrect'

# A user-owned root-level config link into the repository is not a managed
# dotfiles link merely because its target happens to be inside the checkout.
ROOT_CONFIG_HOME="$SANDBOX/root-config-home"
mkdir -p "$ROOT_CONFIG_HOME"
ln -s "$TEST_DIR/README.md" "$ROOT_CONFIG_HOME/.gitconfig"
env HOME="$ROOT_CONFIG_HOME" XDG_CONFIG_HOME="$ROOT_CONFIG_HOME/.config" \
    DOTFILES_LINKS_ONLY=1 bash "$SCRIPT" > "$SANDBOX/root-config.log" 2>&1
[ "$(readlink "$ROOT_CONFIG_HOME/.gitconfig")" = "$TEST_DIR/README.md" ] \
    && pass 'preserves a root-level user Git config symlink' \
    || fail 'preserves a root-level user Git config symlink' 'symlink changed'

echo
printf 'passed: %s  failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
