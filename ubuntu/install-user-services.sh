#!/usr/bin/env bash
# Install the source-verified, user-scoped sync timer without activating it.
# Explicit activation is `install-user-services.sh enable`; it never uses sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
UNITS=(dotfiles-autosync@.service dotfiles-autosync@.timer dotfiles-decisions.service dotfiles-frictions.service dotfiles-frictions.timer)

usage() {
  cat <<'EOF'
Install user-scoped dotfiles autosync units (wiki and artifacts, every 15 minutes).

Usage: ubuntu/install-user-services.sh {dry-run|install|enable|enable-decisions|status|remove|manual}

  dry-run  Show planned unit files and commands; make no changes (default).
  install  Copy units and reload the user manager, but do not enable/start them.
  enable   Explicitly install, enable wiki + artifacts timers and friction tick.
  enable-decisions  Explicitly start the persistent decisions Telegram bot (after pairing).
  status   Report unit and sync status; works without systemd.
  remove   Stop/disable and remove only these managed units; repos are untouched.
  manual   Print commands for manual one-shot sync without systemd.

Activation (only after reviewing this setup):
  ubuntu/install-user-services.sh enable
Status/logs:
  ubuntu/install-user-services.sh status
  journalctl --user -u 'dotfiles-autosync@*.service' --since today
  journalctl --user -u dotfiles-frictions.service --since today
  journalctl --user -u dotfiles-decisions.service --since today
Removal:
  ubuntu/install-user-services.sh remove
Manual fallback:
  ~/.local/bin/wiki-sync                 # ~/wiki
  WIKI_DIR="$HOME/artifacts" WIKI_SYNC_STATE="$HOME/.local/state/artifacts-sync" WIKI_SYNC_NAME=artifacts ~/.local/bin/wiki-sync
  ~/.local/bin/friction-cards tick    # only after the friction runtime is installed

Only the literal autosync instances wiki and artifacts are allowed. Their timer
is 900 seconds; friction tick is 120 seconds. The decisions Telegram process is
a persistent KeepAlive service in the source, not a periodic timer, and must only
be started after `decisions telegram pair`. `install` and `dry-run` never enable
or start anything. Never uses sudo or changes repository data.
EOF
}

log() { printf '[user-services] %s\n' "$*"; }
fail() { printf '[user-services] ERROR: %s\n' "$*" >&2; exit 1; }
unit_src() { printf '%s/%s' "$REPO_ROOT/ubuntu/systemd/user" "$1"; }

have_systemd_user() {
  command -v "$SYSTEMCTL" >/dev/null 2>&1 || return 1
  "$SYSTEMCTL" --user show-environment >/dev/null 2>&1
}

copy_units() {
  mkdir -p "$UNIT_DIR"
  for unit in "${UNITS[@]}"; do
    [ -r "$(unit_src "$unit")" ] || fail "missing source unit $(unit_src "$unit")"
    if ! cmp -s "$(unit_src "$unit")" "$UNIT_DIR/$unit"; then
      install -m 0644 "$(unit_src "$unit")" "$UNIT_DIR/$unit"
      log "installed $UNIT_DIR/$unit"
    else
      log "$unit is unchanged"
    fi
  done
  "$SYSTEMCTL" --user daemon-reload
}

instances=(wiki artifacts)
case "${1:-dry-run}" in
  -h|--help) usage ;;
  dry-run)
    usage
    printf '\nWould install from %s to %s; would not enable/start units.\n' "$REPO_ROOT/ubuntu/systemd/user" "$UNIT_DIR"
    ;;
  install)
    have_systemd_user || fail 'user systemd manager is unavailable; use manual fallback or retry in a logged-in session'
    copy_units
    log 'installed but inactive; explicitly run: ubuntu/install-user-services.sh enable'
    ;;
  enable)
    have_systemd_user || fail 'user systemd manager is unavailable; units were not activated'
    [ -x "$USER_BIN/wiki-sync" ] || fail "missing $USER_BIN/wiki-sync; link the sync helper first"
    [ -x "$USER_BIN/frictions" ] || fail "missing $USER_BIN/frictions; link the friction wrapper first"
    [ -x "$USER_BIN/friction-cards" ] || fail "missing $USER_BIN/friction-cards; link the friction helper first"
    [ -x "$USER_BIN/friction-ledger" ] || fail "missing $USER_BIN/friction-ledger; link the friction helper first"
    [ -x "$USER_BIN/coach-fix" ] || fail "missing $USER_BIN/coach-fix; link the friction helper first"
    [ -d "$HOME/wiki/.git" ] || fail "$HOME/wiki is not a git repository; wiki timer was not activated"
    [ -d "$HOME/artifacts/.git" ] || fail "$HOME/artifacts is not a git repository; artifacts timer was not activated"
    [ -x "$HOME/.local/share/decisions/bin/decisions" ] || fail 'the optional decisions executable is not built; see integration setup instructions'
    [ -d "$HOME/wiki/work/friction" ] || fail 'friction wiki directory is missing; the friction timer was not activated'
    command -v jq >/dev/null 2>&1 || fail 'jq is required for friction-cards; the friction timer was not activated'
    copy_units
    for instance in "${instances[@]}"; do "$SYSTEMCTL" --user enable --now "dotfiles-autosync@$instance.timer"; done
    "$SYSTEMCTL" --user enable --now dotfiles-frictions.timer
    log 'enabled wiki, artifacts and friction timers'
    ;;
  enable-decisions)
    have_systemd_user || fail 'user systemd manager is unavailable; decisions bot was not started'
    [ -x "$USER_BIN/decisions" ] || fail "missing $USER_BIN/decisions; install the decisions helper first"
    [ -x "$HOME/.local/share/decisions/bin/decisions" ] || fail 'the optional decisions executable is not built; decisions Telegram was not started'
    [ -s "${RUN_DAY_STATE_DIR:-$HOME/.local/state/run-day}/decisions/telegram.json" ] || fail 'Telegram is not paired; run decisions telegram pair first'
    command -v secret >/dev/null 2>&1 || fail 'secret helper is missing; Telegram credentials are not configured'
    copy_units
    "$SYSTEMCTL" --user enable --now dotfiles-decisions.service
    log 'enabled decisions Telegram service'
    ;;
  status)
    if [ ! -x "$USER_BIN/wiki-sync" ]; then log "wiki-sync unavailable: $USER_BIN/wiki-sync is not installed"; fi
    if [ ! -x "$USER_BIN/frictions" ] || [ ! -x "$USER_BIN/friction-cards" ] || [ ! -x "$USER_BIN/friction-ledger" ] || [ ! -x "$USER_BIN/coach-fix" ] || [ ! -x "$HOME/.local/share/decisions/bin/decisions" ]; then
      log 'friction timer unavailable: build the optional decisions executable and install friction-cards/friction-ledger/coach-fix'
    fi
    if have_systemd_user; then
      for instance in "${instances[@]}"; do
        "$SYSTEMCTL" --user status --no-pager "dotfiles-autosync@$instance.timer" || true
      done
      "$SYSTEMCTL" --user status --no-pager dotfiles-frictions.timer || true
      "$SYSTEMCTL" --user status --no-pager dotfiles-decisions.service || true
    else
      log 'systemd user manager unavailable; timers are not queryable'
    fi
    for instance in "${instances[@]}"; do
      if [ "$instance" = wiki ]; then
        env WIKI_DIR="$HOME/wiki" WIKI_SYNC_STATE="$STATE_DIR/wiki-sync" WIKI_SYNC_NAME=wiki "$USER_BIN/wiki-sync" status 2>&1 || true
      else
        env WIKI_DIR="$HOME/artifacts" WIKI_SYNC_STATE="$STATE_DIR/artifacts-sync" WIKI_SYNC_NAME=artifacts "$USER_BIN/wiki-sync" status 2>&1 || true
      fi
    done
    ;;
  remove)
    if have_systemd_user; then
      for instance in "${instances[@]}"; do
        "$SYSTEMCTL" --user disable --now "dotfiles-autosync@$instance.timer" 2>/dev/null || true
        "$SYSTEMCTL" --user stop "dotfiles-autosync@$instance.service" 2>/dev/null || true
      done
      "$SYSTEMCTL" --user disable --now dotfiles-frictions.timer 2>/dev/null || true
      "$SYSTEMCTL" --user stop dotfiles-frictions.service 2>/dev/null || true
      "$SYSTEMCTL" --user disable --now dotfiles-decisions.service 2>/dev/null || true
    else
      log 'systemd user manager unavailable; removing unit files without service commands'
    fi
    for unit in "${UNITS[@]}"; do rm -f -- "$UNIT_DIR/$unit"; done
    if have_systemd_user; then "$SYSTEMCTL" --user daemon-reload; fi
    log 'removed managed timers and unit files; wiki and artifacts data/state were preserved'
    ;;
  manual)
    printf '%s\n' \
      '~/.local/bin/wiki-sync' \
      'WIKI_DIR="$HOME/artifacts" WIKI_SYNC_STATE="$XDG_STATE_HOME/dotfiles/artifacts-sync" WIKI_SYNC_NAME=artifacts ~/.local/bin/wiki-sync'
    ;;
  *) usage >&2; exit 2 ;;
esac
