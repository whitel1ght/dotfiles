#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/ubuntu/install-user-services.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_BIN_HOME="$TMP/bin"
mkdir -p "$HOME" "$XDG_BIN_HOME" "$TMP/mockbin" "$HOME/wiki/.git" "$HOME/artifacts/.git" "$HOME/wiki/work/friction" "$HOME/.local/share/decisions/bin"
LOG="$TMP/systemctl.log"; export LOG
cat > "$TMP/mockbin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
[ "$1 $2" != '--user show-environment' ] || exit 0
MOCK
chmod +x "$TMP/mockbin/systemctl"
export SYSTEMCTL="$TMP/mockbin/systemctl"
cat > "$XDG_BIN_HOME/wiki-sync" <<'MOCK'
#!/usr/bin/env bash
printf 'wiki-sync %s %s\n' "${WIKI_DIR:-}" "${1:-}" >> "$LOG"
MOCK
chmod +x "$XDG_BIN_HOME/wiki-sync"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$XDG_BIN_HOME/friction-cards"
chmod +x "$XDG_BIN_HOME/friction-cards"
for helper in frictions friction-ledger coach-fix; do printf '#!/usr/bin/env bash\\nexit 0\\n' > "$XDG_BIN_HOME/$helper"; chmod +x "$XDG_BIN_HOME/$helper"; done
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$HOME/.local/share/decisions/bin/decisions"
chmod +x "$HOME/.local/share/decisions/bin/decisions"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$XDG_BIN_HOME/decisions"
chmod +x "$XDG_BIN_HOME/decisions"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$TMP/mockbin/secret"
chmod +x "$TMP/mockbin/secret"
export PATH="$TMP/mockbin:$PATH"

"$SCRIPT" dry-run >/dev/null
[ ! -e "$XDG_CONFIG_HOME/systemd/user/dotfiles-autosync@.service" ]
"$SCRIPT" install >/dev/null
[ -f "$XDG_CONFIG_HOME/systemd/user/dotfiles-autosync@.service" ]
[ -f "$XDG_CONFIG_HOME/systemd/user/dotfiles-autosync@.timer" ]
[ -f "$XDG_CONFIG_HOME/systemd/user/dotfiles-decisions.service" ]
[ -f "$XDG_CONFIG_HOME/systemd/user/dotfiles-frictions.timer" ]
! grep -q 'enable\|start --now' "$LOG"
"$SCRIPT" install >/dev/null
[ "$(grep -c 'daemon-reload' "$LOG")" -eq 2 ]
"$SCRIPT" enable >/dev/null
grep -q 'enable --now dotfiles-autosync@wiki.timer' "$LOG"
grep -q 'enable --now dotfiles-autosync@artifacts.timer' "$LOG"
grep -q 'enable --now dotfiles-frictions.timer' "$LOG"
if "$SCRIPT" enable-decisions >/dev/null 2>&1; then
  echo 'unpaired Telegram service unexpectedly enabled' >&2; exit 1
fi
mkdir -p "$HOME/.local/state/run-day/decisions"
printf '{"paired":true}\\n' > "$HOME/.local/state/run-day/decisions/telegram.json"
"$SCRIPT" enable-decisions >/dev/null
grep -q 'enable --now dotfiles-decisions.service' "$LOG"
"$SCRIPT" status >/dev/null
grep -q 'wiki-sync /.*\/wiki status' "$LOG"
grep -q 'wiki-sync /.*\/artifacts status' "$LOG"
"$SCRIPT" manual >/dev/null
# No-systemd mode is a useful status/manual fallback and refuses installation.
SYSTEMCTL="$TMP/no-systemctl" "$SCRIPT" status >/dev/null
SYSTEMCTL="$TMP/no-systemctl" "$SCRIPT" manual >/dev/null
if SYSTEMCTL="$TMP/no-systemctl" "$SCRIPT" install >/dev/null 2>&1; then
  echo 'install unexpectedly succeeded without systemd' >&2; exit 1
fi
"$SCRIPT" remove >/dev/null
[ ! -e "$XDG_CONFIG_HOME/systemd/user/dotfiles-autosync@.service" ]
[ ! -e "$XDG_CONFIG_HOME/systemd/user/dotfiles-autosync@.timer" ]
[ ! -e "$XDG_CONFIG_HOME/systemd/user/dotfiles-decisions.service" ]
[ ! -e "$XDG_CONFIG_HOME/systemd/user/dotfiles-frictions.timer" ]
echo 'passed: installer dry-run, idempotent install, explicit activation, status, manual fallback and removal'
