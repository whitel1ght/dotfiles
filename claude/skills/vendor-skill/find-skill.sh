#!/bin/bash
# Find vendorable skill paths in a remote repo, without cloning its content.
#
#   find-skill.sh <repo> [name]
#
# With no name, prints every directory containing a SKILL.md. With a name,
# prints the matching ones — an exact basename match if there is one, otherwise
# every substring match, leaving the caller to disambiguate.
#
# Exit: 0 printed at least one path, 1 nothing matched, 2 could not read the repo.
set -uo pipefail

# owner/repo is shorthand for GitHub. Anything with a scheme, an ssh host, or a
# leading path separator is already a git URL and is passed through untouched.
expand_repo_url() {
    local repo="$1"
    case "$repo" in
        *://*|*@*:*|/*|.*) printf '%s\n' "$repo"; return 0 ;;
    esac
    case "$repo" in
        */*/*) printf '%s\n' "$repo" ;;
        */*)   printf '%s\n' "https://github.com/$repo.git" ;;
        *)     printf '%s\n' "$repo" ;;
    esac
}

# The dotfiles repo root, resolved from this script's PHYSICAL location. The
# script is symlinked into ~/.claude/skills/, so following the link matters:
# dirname of the symlink would point at the wrong tree entirely.
repo_root() {
    local src="${BASH_SOURCE[0]}" dir
    while [ -L "$src" ]; do
        dir="$(cd "$(dirname "$src")" && pwd -P)"
        src="$(readlink "$src")"
        case "$src" in /*) ;; *) src="$dir/$src" ;; esac
    done
    (cd "$(dirname "$src")/../../.." && pwd -P)
}

# Every directory holding a SKILL.md, one per line; the repo root prints as ".".
# A blobless, checkout-less shallow clone fetches trees only — enough to list
# paths, and a fraction of the transfer. Servers that refuse the filter just warn
# and send everything, which still works.
list_skills() {
    local url="$1" tmp out
    tmp="$(mktemp -d)" || return 2

    if ! git clone -q --filter=blob:none --no-checkout --depth 1 "$url" "$tmp/r" 2>/dev/null; then
        rm -rf "$tmp"
        return 2
    fi

    out="$(git -C "$tmp/r" ls-tree -r --name-only HEAD 2>/dev/null \
        | grep 'SKILL\.md$' \
        | sed -e 's#/SKILL\.md$##' -e 's#^SKILL\.md$#.#' \
        | sort -u)"
    rm -rf "$tmp"

    [ -n "$out" ] || return 1
    printf '%s\n' "$out"
}

# Exact basename match wins outright; otherwise every basename containing the
# name is printed, so the caller can ask which one was meant.
#
# Matching is on the BASENAME, never the whole path: the argument is a skill
# name, so "engineering" must not select every skill filed under that category.
match_skills() {
    local name="$1" paths="$2" exact hits
    exact="$(printf '%s\n' "$paths" | while IFS= read -r p; do
        [ "$(basename "$p")" = "$name" ] && printf '%s\n' "$p"
    done)"
    if [ -n "$exact" ]; then
        printf '%s\n' "$exact"
        return 0
    fi

    hits="$(printf '%s\n' "$paths" | while IFS= read -r p; do
        case "$(basename "$p")" in *"$name"*) printf '%s\n' "$p" ;; esac
    done)"
    [ -n "$hits" ] || return 1
    printf '%s\n' "$hits"
}

main() {
    local repo="${1:-}" name="${2:-}" url paths

    # --url resolves the canonical clone URL and stops. Callers need it to look a
    # repo up in vendor.json, where sources are recorded by full URL — matching a
    # shorthand against that would miss and create a duplicate wrapper.
    if [ "$repo" = "--url" ]; then
        if [ -z "$name" ]; then
            echo "usage: find-skill.sh --url <repo>" >&2
            return 2
        fi
        expand_repo_url "$name"
        return 0
    fi

    if [ -z "$repo" ]; then
        echo "usage: find-skill.sh <repo> [name]" >&2
        return 2
    fi

    url="$(expand_repo_url "$repo")"

    paths="$(list_skills "$url")"
    case $? in
        2) echo "cannot read $url" >&2; return 2 ;;
        1) echo "no skills found in $url" >&2; return 1 ;;
    esac

    if [ -z "$name" ]; then
        printf '%s\n' "$paths"
        return 0
    fi

    if ! match_skills "$name" "$paths"; then
        echo "no skill matching '$name' in $url" >&2
        return 1
    fi
}

# Run only when executed, not when sourced — the tests source this file to
# exercise individual functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
