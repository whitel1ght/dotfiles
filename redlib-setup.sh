#!/bin/bash
#
# Bring up self-hosted Redlib, the backend reddittui reads reddit through.
#
# Background is in redlib/compose.yaml. The short version: reddit put logged-out
# old.reddit.com behind a login wall on 30 June 2026, which killed every
# scraping client. Redlib emulates the official app client instead, so it still
# works and still needs no account.
#
# This script owns the two things that must not live in git:
#
#   ~/.config/redlib/certs/{cert,key}.pem   private key
#   ~/.config/redlib/Caddyfile              sits next to it, mounted read-only
#
# The certificate is generated with mkcert, whose CA is already in the System
# keychain, so Go's http client inside reddittui trusts it with no flags and no
# sudo. It is issued for localhost only and expires in about three years;
# `status` warns before that happens.

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Seams for the test suite; all default to the real thing.
CONFIG_DIR="${REDLIB_CONFIG_DIR:-$HOME/.config/redlib}"
COMPOSE_FILE="${REDLIB_COMPOSE:-$DOTFILES_DIR/redlib/compose.yaml}"
CADDYFILE_SRC="${REDLIB_CADDYFILE:-$DOTFILES_DIR/redlib/Caddyfile}"
DOCKER="${DOCKER:-docker}"
MKCERT="${MKCERT:-mkcert}"

CERT_DIR="$CONFIG_DIR/certs"
ENDPOINT="https://localhost:8443"

usage() {
    cat <<EOF
Usage: $(basename "$0") [up|down|status|cert]

  up       Generate the cert if missing, then start the stack (default)
  down     Stop the stack; leaves the certificate in place
  status   Container state, certificate expiry, and a live fetch
  cert     Regenerate the certificate, then restart the stack

The backend is reachable at $ENDPOINT once up. reddittui is pointed at it by
reddittui/reddittui.toml; nothing else on the machine should need it.
EOF
}

require_docker() {
    if ! command -v "$DOCKER" >/dev/null 2>&1; then
        log_error "docker not found — install Docker Desktop first"
        return 1
    fi
    if ! "$DOCKER" info >/dev/null 2>&1; then
        log_error "the docker daemon is not running"
        return 1
    fi
}

# Copied rather than symlinked: the compose file mounts this path into the
# container, and Docker cannot follow a symlink that points outside the mount.
sync_caddyfile() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$CADDYFILE_SRC" ]; then
        log_error "missing $CADDYFILE_SRC"
        return 1
    fi
    if ! cmp -s "$CADDYFILE_SRC" "$CONFIG_DIR/Caddyfile"; then
        cp "$CADDYFILE_SRC" "$CONFIG_DIR/Caddyfile"
        log_info "Updated $CONFIG_DIR/Caddyfile"
    fi
}

generate_cert() {
    if ! command -v "$MKCERT" >/dev/null 2>&1; then
        log_error "mkcert not found — run ./brew-install.sh first"
        return 1
    fi

    # Without the CA in a trust store the certificate verifies nowhere, and
    # reddittui would fail with an opaque x509 error rather than a clear one.
    if ! "$MKCERT" -CAROOT >/dev/null 2>&1; then
        log_error "mkcert has no CA — run 'mkcert -install' (needs sudo) first"
        return 1
    fi

    mkdir -p "$CERT_DIR"
    ( cd "$CERT_DIR" && "$MKCERT" -cert-file cert.pem -key-file key.pem \
        localhost 127.0.0.1 ::1 >/dev/null 2>&1 )
    chmod 600 "$CERT_DIR/key.pem"
    log_info "Generated a locally-trusted certificate in $CERT_DIR"
}

cert_expiry() {
    [ -f "$CERT_DIR/cert.pem" ] || return 1
    openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate 2>/dev/null \
        | sed 's/^notAfter=//'
}

# Firefox and its forks keep their own certificate store and ignore the macOS
# System keychain entirely, so the mkcert CA that Go trusts is invisible to
# LibreWolf. That matters because reddittui's `o` key hands the browser a
# https://localhost:8443 URL (see the reddittui section in the root README),
# which would otherwise open onto a certificate warning.
#
# Idempotent: certutil -A replaces an existing nickname rather than duplicating
# it, but the check keeps the output quiet on repeat runs.
trust_firefox_profiles() {
    local caroot profile added=0

    command -v certutil >/dev/null 2>&1 || {
        log_warn "certutil not found (brew install nss) — skipping browser trust"
        log_warn "LibreWolf will warn about the certificate until it is added"
        return 0
    }

    caroot="$("$MKCERT" -CAROOT 2>/dev/null)" || return 0
    [ -f "$caroot/rootCA.pem" ] || return 0

    for profile in "$HOME/Library/Application Support/librewolf/Profiles"/*/ \
                   "$HOME/Library/Application Support/Firefox/Profiles"/*/; do
        [ -d "$profile" ] || continue
        [ -f "$profile/cert9.db" ] || continue

        if certutil -L -d sql:"$profile" 2>/dev/null | grep -q "mkcert"; then
            continue
        fi

        if certutil -A -d sql:"$profile" -t "C,," -n "mkcert development CA" \
                -i "$caroot/rootCA.pem" 2>/dev/null; then
            added=$((added + 1))
        fi
    done

    [ "$added" -gt 0 ] && log_info "Trusted the mkcert CA in $added browser profile(s)"
    return 0
}

cmd_up() {
    require_docker || return 1
    sync_caddyfile || return 1

    if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        generate_cert || return 1
    else
        log_info "Certificate already present in $CERT_DIR"
    fi

    trust_firefox_profiles

    "$DOCKER" compose -f "$COMPOSE_FILE" up -d
    log_info "Redlib is starting; reachable at $ENDPOINT"
    log_info "Check it with '$(basename "$0") status'"
}

cmd_down() {
    require_docker || return 1
    "$DOCKER" compose -f "$COMPOSE_FILE" down
    log_info "Stopped; the certificate in $CERT_DIR is left in place"
}

cmd_cert() {
    require_docker || return 1
    generate_cert || return 1
    sync_caddyfile || return 1
    trust_firefox_profiles
    # Caddy reads the certificate at startup, so a new one needs a restart.
    "$DOCKER" compose -f "$COMPOSE_FILE" restart caddy >/dev/null 2>&1 || true
    log_info "Certificate replaced and the TLS front end restarted"
}

cmd_status() {
    local expiry running body

    if ! command -v "$DOCKER" >/dev/null 2>&1 || ! "$DOCKER" info >/dev/null 2>&1; then
        log_warn "docker is not available; cannot report container state"
    else
        running="$("$DOCKER" ps --filter name=redlib --format '{{.Names}} {{.Status}}' 2>/dev/null)"
        if [ -z "$running" ]; then
            log_warn "no redlib containers running — run '$(basename "$0") up'"
        else
            echo "$running" | while read -r line; do log_info "$line"; done
        fi
    fi

    if expiry="$(cert_expiry)"; then
        log_info "certificate expires: $expiry"
    else
        log_warn "no certificate in $CERT_DIR — run '$(basename "$0") up'"
    fi

    # A live fetch is the only check that means anything: the containers can be
    # healthy while reddit refuses the upstream request.
    body="$(curl -sS --max-time 20 "$ENDPOINT/r/neovim" 2>/dev/null)" || {
        log_warn "$ENDPOINT is not answering"
        return 0
    }

    if printf '%s' "$body" | grep -q '<div class="post'; then
        log_info "live fetch: serving posts"
    elif printf '%s' "$body" | grep -qi 'rate.limit\|Failed to parse page JSON'; then
        log_warn "live fetch: reddit is rate-limiting this IP right now"
        log_warn "this is the same throttling newsboat/subreddits.txt documents;"
        log_warn "it clears on its own after a few idle minutes"
    else
        log_warn "live fetch: reachable but returned no posts"
    fi
}

case "${1:-up}" in
    up)     cmd_up ;;
    down)   cmd_down ;;
    status) cmd_status ;;
    cert)   cmd_cert ;;
    -h|--help|help) usage ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 2
        ;;
esac
