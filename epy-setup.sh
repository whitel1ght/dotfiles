#!/bin/bash
#
# Install the epy terminal ebook reader and patch in vertical padding.
#
# epy is a Python application, so it goes in via pipx rather than the Brewfile.
# It must run on Python 3.12 or older: the last release (2023.6.11) imports
# `imghdr`, which was removed from the stdlib in 3.13. pipx otherwise picks the
# newest Python on the machine and the install import-errors on first run.
#
# epy has no vertical padding setting, so epy/vertical-padding.patch adds one
# (Setting.VerticalPadding, default 1). pipx replaces site-packages wholesale on
# upgrade, so the patch is re-applied on every run rather than applied once.
#
# The dictionary side needs nothing installed: bin/macdict reaches the macOS
# dictionaries through ctypes and install.sh links it into ~/.local/bin.

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
PIPX="${PIPX:-pipx}"
BREW="${BREW:-brew}"
PATCH_FILE="${PATCH_FILE:-$DOTFILES_DIR/epy/vertical-padding.patch}"

PACKAGE="epy-reader"
# epy imports `imghdr`, removed from the stdlib in 3.13.
PYTHON_FORMULA="python@3.12"

usage() {
    cat <<EOF
Usage: $(basename "$0") [install|status]

  install   Install epy via pipx and apply the vertical padding patch (default)
  status    Report the installed version and whether the patch is applied

Re-run after 'pipx upgrade epy-reader': upgrading replaces site-packages and
drops the patch. Running this again restores it.
EOF
}

# The interpreter pipx should build the venv against. Homebrew's prefix differs
# between Apple Silicon and Intel, so ask brew rather than hardcoding a path.
resolve_python() {
    local prefix
    prefix="$("$BREW" --prefix "$PYTHON_FORMULA" 2>/dev/null || true)"

    if [ -n "$prefix" ] && [ -x "$prefix/bin/python3.12" ]; then
        echo "$prefix/bin/python3.12"
        return 0
    fi

    return 1
}

is_installed() {
    "$PIPX" list --short 2>/dev/null | grep -q "^$PACKAGE "
}

# Where the installed epy_reader package lives. Asking the venv's own
# interpreter avoids hardcoding a python3.X path segment.
site_packages_dir() {
    if [ -n "${EPY_SITE_PACKAGES:-}" ]; then
        echo "$EPY_SITE_PACKAGES"
        return 0
    fi

    local venvs venv
    venvs="$("$PIPX" environment --value PIPX_LOCAL_VENVS 2>/dev/null || true)"
    [ -n "$venvs" ] || return 1
    venv="$venvs/$PACKAGE"
    [ -x "$venv/bin/python" ] || return 1

    "$venv/bin/python" -c \
        'import epy_reader, os; print(os.path.dirname(os.path.dirname(epy_reader.__file__)))' \
        2>/dev/null
}

# 0 = applied, 1 = not applied, 2 = neither (patch no longer matches the source)
patch_state() {
    local dir="$1"

    if patch -d "$dir" -p1 --dry-run -sf < "$PATCH_FILE" >/dev/null 2>&1; then
        return 1
    fi
    if patch -d "$dir" -p1 -R --dry-run -sf < "$PATCH_FILE" >/dev/null 2>&1; then
        return 0
    fi
    return 2
}

cmd_install() {
    local python_bin site_dir

    if ! command -v "$PIPX" >/dev/null 2>&1; then
        log_error "pipx not found — run ./brew-install.sh first"
        return 1
    fi

    if is_installed; then
        log_info "$PACKAGE already installed"
    else
        if ! python_bin="$(resolve_python)"; then
            log_error "$PYTHON_FORMULA not found — run ./brew-install.sh first"
            return 1
        fi

        # Force PyPI: a CodeArtifact (or other private) index in ~/.config/pip
        # applies to every pip invocation, and its token expires.
        log_info "Installing $PACKAGE against $python_bin"
        PIP_INDEX_URL="https://pypi.org/simple" PIP_EXTRA_INDEX_URL="" \
            "$PIPX" install --python "$python_bin" "$PACKAGE"
    fi

    if ! site_dir="$(site_packages_dir)" || [ -z "$site_dir" ]; then
        log_error "Could not locate the installed $PACKAGE package"
        return 1
    fi

    set +e
    patch_state "$site_dir"
    local state=$?
    set -e

    case "$state" in
        0) log_info "Vertical padding patch already applied" ;;
        1)
            patch -d "$site_dir" -p1 -s < "$PATCH_FILE"
            log_info "Applied vertical padding patch"
            ;;
        *)
            log_warn "Patch does not match the installed $PACKAGE — skipping"
            log_warn "epy probably updated; refresh $PATCH_FILE against the new source"
            return 1
            ;;
    esac

    # Superseded by bin/macdict, which needs no venv. Left behind by an earlier
    # pyobjc-based version of the dictionary wrapper.
    if [ -d "$HOME/.local/share/epy-dict" ]; then
        rm -rf "$HOME/.local/share/epy-dict"
        log_info "Removed the obsolete epy-dict venv"
    fi
}

cmd_status() {
    local site_dir

    if ! command -v "$PIPX" >/dev/null 2>&1; then
        log_warn "pipx not installed"
        return 0
    fi

    if ! is_installed; then
        log_warn "$PACKAGE: not installed"
        return 0
    fi

    log_info "$PACKAGE: $("$PIPX" list --short 2>/dev/null | grep "^$PACKAGE " | head -1)"

    if site_dir="$(site_packages_dir)" && [ -n "$site_dir" ]; then
        set +e
        patch_state "$site_dir"
        local state=$?
        set -e
        case "$state" in
            0) log_info "vertical padding patch: applied" ;;
            1) log_warn "vertical padding patch: NOT applied — run '$(basename "$0") install'" ;;
            *) log_warn "vertical padding patch: stale (does not match installed source)" ;;
        esac
    else
        log_warn "could not locate the installed package"
    fi

    if command -v macdict >/dev/null 2>&1; then
        log_info "macdict: $(command -v macdict)"
    else
        log_warn "macdict: not on PATH — run ./install.sh"
    fi
}

case "${1:-install}" in
    install) cmd_install ;;
    status)  cmd_status ;;
    -h|--help|help) usage ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 2
        ;;
esac
