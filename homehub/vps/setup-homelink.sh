#!/usr/bin/env bash
#
# VPS side of the home link, run as whitelight (ssh vps 'bash -s' < this file).
#
# Appends ONE restricted authorized_keys line for the ThinkPad's homelink key.
# The VPS has no root access for us (no sudo, PermitRootLogin no, fail2ban
# active), so instead of a dedicated tunnel user we lock the key down under
# the existing whitelight account:
#
#   command="/bin/false"          no shell, ever
#   restrict                      no agent/X11/PTY forwarding, the base set
#   port-forwarding               re-allow -R/-L (restrict drops it)...
#   permitlisten=127.0.0.1:12222  ...but only for the home-link reverse port
#   permitopen=127.0.0.1:1        direct forwards only to a dead port
#
# No sudo, no sshd_config changes, additive only: existing lines are kept.
# Idempotent — safe to re-run.

set -euo pipefail

HOMELINK_KEY='command="/bin/false",restrict,port-forwarding,permitlisten="127.0.0.1:12222",permitopen="127.0.0.1:1" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNPSMtyF5MTEGLL+STJkVybINS2V5zuLuS5AlfzUaXw homelink'

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

if grep -q ' homelink$' ~/.ssh/authorized_keys; then
    echo "homelink line already present; nothing to do"
else
    printf '%s\n' "$HOMELINK_KEY" >> ~/.ssh/authorized_keys
    echo "appended homelink line"
fi
