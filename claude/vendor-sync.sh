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

# Echo the SHA a ref points at, without cloning.
resolve_ref() {
    local repo="$1" ref="${2:-HEAD}" out sha
    out="$(git ls-remote "$repo" "$ref" 2>/dev/null)" || return 1
    sha="$(printf '%s\n' "$out" | head -n1 | cut -f1)"
    if [ ${#sha} -ne 40 ]; then return 1; fi
    printf '%s\n' "$sha"
}

locked_sha() {
    [ -f "$LOCKFILE" ] || return 0
    jq -r --arg n "$1" '.sources[$n].resolved // ""' "$LOCKFILE" 2>/dev/null
}

locked_skills() {
    [ -f "$LOCKFILE" ] || return 0
    jq -r --arg n "$1" '.sources[$n].skills // {} | .[]' "$LOCKFILE" 2>/dev/null
}

# A source is current only if the sha matches, the wrapper exists, and the
# requested skill set is unchanged — otherwise a manifest edit would be ignored.
source_is_current() {
    local name="$1" sha="$2" want have
    [ "$(locked_sha "$name")" = "$sha" ] || return 1
    [ -d "$VENDOR_DIR/$name/skills" ] || return 1
    want="$(source_skills "$name" | sort)"
    have="$(locked_skills "$name" | sort)"
    [ "$want" = "$have" ]
}

main() {
    require_jq || return 1
    validate_manifest || return 1

    local failed=0 name repo ref sha
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        repo="$(source_field "$name" repo)"
        ref="$(source_field "$name" ref)"
        [ -n "$ref" ] || ref="HEAD"

        sha="$(resolve_ref "$repo" "$ref")"
        if [ -z "$sha" ]; then
            log_warn "$name: cannot reach $repo at $ref — keeping committed copy"
            failed=1
            continue
        fi

        if source_is_current "$name" "$sha"; then
            log_info "$name: up to date (${sha:0:7})"
            continue
        fi

        log_info "$name: syncing to ${sha:0:7}"
    done <<< "$(source_names)"

    [ "$failed" -eq 0 ] || return 2
    return 0
}

# Run only when executed, not when sourced — the test suite sources this file
# to exercise individual functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
