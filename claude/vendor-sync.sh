#!/bin/bash
# Fetch cherry-picked third-party Claude skills into claude/vendor/.
# Driven by vendor.json; records what it did in vendor.lock.json.
# No `set -e`: a failing source must not abort the remaining sources.
set -uo pipefail

VENDOR_ROOT="${VENDOR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MANIFEST="$VENDOR_ROOT/vendor.json"
LOCKFILE="$VENDOR_ROOT/vendor.lock.json"
VENDOR_DIR="$VENDOR_ROOT/vendor"
GENERATED_NOTE="Managed by claude/vendor-sync.sh — do not edit by hand."

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[vendor]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[vendor]${NC} $1"; }
log_error() { echo -e "${RED}[vendor]${NC} $1" >&2; }

require_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    log_error "jq is required but not installed. Run ./brew-install.sh"
    return 1
}

source_names() { jq -r '.sources[].name' "$MANIFEST"; }

source_field() {
    jq -r --arg n "$1" --arg f "$2" \
        '.sources[] | select(.name == $n) | .[$f] // ""' "$MANIFEST"
}

source_skills() {
    jq -r --arg n "$1" '.sources[] | select(.name == $n) | .skills[]' "$MANIFEST"
}

# Rejects anything that would produce a broken or ambiguous vendor tree.
validate_manifest() {
    if [ ! -f "$MANIFEST" ]; then
        log_error "No manifest at $MANIFEST"
        return 1
    fi
    if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
        log_error "Manifest is not valid JSON: $MANIFEST"
        return 1
    fi

    local names name repo paths basenames
    names="$(source_names)" || return 1
    if [ -z "$names" ]; then
        log_error "Manifest declares no sources"
        return 1
    fi

    if [ "$(printf '%s\n' "$names" | sort | uniq -d)" != "" ]; then
        log_error "Duplicate source names in manifest"
        return 1
    fi

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in
            */*|.|..) log_error "Invalid source name: $name"; return 1 ;;
        esac

        repo="$(source_field "$name" repo)"
        if [ -z "$repo" ]; then
            log_error "Source '$name' has no repo"
            return 1
        fi

        paths="$(source_skills "$name")"
        if [ -z "$paths" ]; then
            log_error "Source '$name' lists no skills"
            return 1
        fi

        # Wrapper namespacing means cross-source names cannot clash, but two
        # upstream paths sharing a basename would collide inside one wrapper.
        basenames="$(printf '%s\n' "$paths" | while IFS= read -r p; do
            [ -n "$p" ] && basename "$p"
        done)"
        if [ "$(printf '%s\n' "$basenames" | sort | uniq -d)" != "" ]; then
            log_error "Source '$name' has skills sharing a basename: $(printf '%s\n' "$basenames" | sort | uniq -d | tr '\n' ' ')"
            return 1
        fi
    done <<< "$names"

    return 0
}

main() {
    require_jq || return 1
    validate_manifest || return 1
    log_info "Manifest valid"
    return 0
}

# Run only when executed, not when sourced — the test suite sources this file
# to exercise individual functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
