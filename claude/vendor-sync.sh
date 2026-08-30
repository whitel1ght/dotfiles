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
        # A source name is also a directory name and a plugin name, so keep it
        # to [A-Za-z0-9][A-Za-z0-9._-]* — that rules out `/`, `.`, `..`, and
        # names starting with `-` that would be read as options downstream.
        case "$name" in
            [A-Za-z0-9]*) ;;
            *) log_error "Invalid source name: $name"; return 1 ;;
        esac
        case "$name" in
            *[!A-Za-z0-9._-]*) log_error "Invalid source name: $name"; return 1 ;;
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

# Echo the commit SHA a ref points at, without cloning.
#
# Two traps a bare `git ls-remote "$repo" "$ref"` falls into:
#   - its pattern tail-matches whole path components, so `main` also matches
#     refs/heads/changeset-release/main — and the bot branch sorts first;
#   - an annotated tag's own line carries the *tag object* id, and the peeled
#     `refs/tags/<t>^{}` line never matches the pattern, so pinning a tag would
#     record a non-commit id.
# Asking for the three fully qualified names and choosing between them fixes
# both. HEAD is neither a head nor a tag, so it is looked up on its own.
resolve_ref() {
    local repo="$1" ref="${2:-HEAD}" out sha
    if [ "$ref" = "HEAD" ]; then
        out="$(git ls-remote "$repo" HEAD 2>/dev/null)" || return 1
        sha="$(printf '%s\n' "$out" | awk '$2=="HEAD" { print $1; exit }')"
    else
        out="$(git ls-remote "$repo" \
            "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null)" || return 1
        sha="$(printf '%s\n' "$out" | awk -v r="$ref" '
            $2=="refs/tags/" r "^{}" { tagc=$1 }
            $2=="refs/tags/" r       { tag=$1 }
            $2=="refs/heads/" r      { br=$1 }
            END { if (tagc!="") print tagc; else if (tag!="") print tag; else print br }')"
    fi
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

# A source is current only if the sha matches, the wrapper is loadable, and the
# requested skill set is unchanged — otherwise a manifest edit would be ignored,
# and a wrapper whose generated metadata went missing would never be repaired.
source_is_current() {
    local name="$1" sha="$2" want have
    [ "$(locked_sha "$name")" = "$sha" ] || return 1
    [ -d "$VENDOR_DIR/$name/skills" ] || return 1
    [ -f "$VENDOR_DIR/$name/.claude-plugin/plugin.json" ] || return 1
    want="$(source_skills "$name" | sort)"
    have="$(locked_skills "$name" | sort)"
    [ "$want" = "$have" ]
}

# Shallow, sparse, pinned to a sha. Also grabs root licence files for
# attribution. Requires the remote to allow fetching a bare sha (GitHub,
# GitLab, and local fixtures with uploadpack.allowAnySHA1InWant do).
fetch_source() {
    local repo="$1" sha="$2" dest="$3"; shift 3
    git init -q "$dest" || return 1
    git -C "$dest" remote add origin "$repo" || return 1
    git -C "$dest" sparse-checkout set --no-cone "$@" '/LICENSE*' '/COPYING*' || return 1
    git -C "$dest" fetch -q --depth 1 origin "$sha" || return 1
    git -C "$dest" checkout -q FETCH_HEAD || return 1
    return 0
}

# Drop the staging directory, and the wrapper too when this was a first-ever
# sync that never produced content — an empty wrapper survives prune (the source
# is still in the manifest) and install.sh would symlink it into ~/.claude/skills/.
abandon_staged() {
    rm -rf "$1/.skills.staged"
    rmdir "$1" 2>/dev/null
    return 0
}

# Replace the wrapper's skills/ wholesale so upstream deletions propagate.
# Staged in a sibling directory first, so a validation failure never leaves a
# half-written tree.
install_source() {
    local name="$1" stage="$2"; shift 2
    local wrapper="$VENDOR_DIR/$name"
    local staged="$wrapper/.skills.staged"
    local p base lic

    mkdir -p "$wrapper" || return 1
    rm -rf "$staged"
    mkdir -p "$staged" || { abandon_staged "$wrapper"; return 1; }

    for p in "$@"; do
        if [ ! -f "$stage/$p/SKILL.md" ]; then
            log_error "$name: no SKILL.md at '$p'"
            abandon_staged "$wrapper"
            return 1
        fi
        # Byte-exactness forbids rewriting a fetched tree, not refusing one.
        # `cp -R` copies links verbatim, so a hostile upstream could commit
        # skills/x -> /etc/passwd into this public repo. Refuse the source.
        if [ -n "$(find "$stage/$p" \! -type d \! -type f -print -quit)" ]; then
            log_error "$name: '$p' contains a symlink or special file"
            abandon_staged "$wrapper"
            return 1
        fi
        base="$(basename "$p")"
        cp -R "$stage/$p" "$staged/$base" || { abandon_staged "$wrapper"; return 1; }
    done

    rm -rf "$wrapper/skills"
    mv "$staged" "$wrapper/skills" || { abandon_staged "$wrapper"; return 1; }

    # Wholesale replacement covers skills/ only, so a licence dropped upstream
    # would otherwise leave a stale copy the README no longer points at.
    lic="$(detected_license "$stage")"
    if [ -n "$lic" ]; then
        cp "$stage/$lic" "$wrapper/UPSTREAM-LICENSE" || return 1
    else
        rm -f "$wrapper/UPSTREAM-LICENSE"
    fi
    return 0
}

# Name of the upstream licence file found, or empty.
detected_license() {
    local stage="$1" f
    for f in LICENSE LICENSE.md COPYING; do
        # `-f` and `cp` both follow links, so an upstream LICENSE symlinked to a
        # host path would copy that host file's content into this public repo.
        # Same exposure the skills/ tree refuses; here just look past it.
        [ -L "$stage/$f" ] && continue
        [ -f "$stage/$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    printf '\n'
}

write_plugin_manifest() {
    local name="$1" sha="$2"; shift 2
    local dir="$VENDOR_DIR/$name/.claude-plugin"
    local paths_json p
    mkdir -p "$dir" || return 1

    paths_json="$(for p in "$@"; do printf '%s\n' "./skills/$(basename "$p")"; done \
        | jq -R . | jq -s .)"

    jq -n \
        --arg name "$name" \
        --arg version "0.0.0+${sha:0:7}" \
        --arg desc "$GENERATED_NOTE Vendored skills for $name." \
        --argjson skills "$paths_json" \
        '{ "$schema": "https://anthropic.com/claude-code/plugin.schema.json",
           name: $name, version: $version, description: $desc, skills: $skills }' \
        > "$dir/plugin.json"
}

write_readme() {
    local name="$1" repo="$2" ref="$3" sha="$4" license="$5"; shift 5
    local p
    {
        echo "# Vendored skills: $name"
        echo
        echo "$GENERATED_NOTE"
        echo
        echo "| Field | Value |"
        echo "| --- | --- |"
        echo "| Source | \`$repo\` |"
        echo "| Ref | \`$ref\` |"
        echo "| Commit | \`$sha\` |"
        if [ -n "$license" ]; then
            echo "| Licence | $license (see \`UPSTREAM-LICENSE\`) |"
        else
            echo "| Licence | unknown (upstream ships none) |"
        fi
        echo
        echo "## Skills"
        echo
        for p in "$@"; do
            echo "- \`$(basename "$p")\` — upstream \`$p\`"
        done
        echo
        echo "Contents of \`skills/\` are byte-exact copies of upstream."
        echo "To modify one, copy it into \`claude/skills/\` instead — edits here"
        echo "are destroyed on the next sync."
    } > "$VENDOR_DIR/$name/README.md"
}

update_lock() {
    local name="$1" repo="$2" ref="$3" sha="$4" license="$5"; shift 5
    local skills_json p tmp
    [ -f "$LOCKFILE" ] || echo '{"sources":{}}' > "$LOCKFILE"

    skills_json="$(for p in "$@"; do
        jq -n --arg k "$(basename "$p")" --arg v "$p" '{($k): $v}'
    done | jq -s 'add // {}')"

    # mktemp makes the file 0600 and mv preserves that; the lockfile is a
    # committed, world-readable sibling of every other file here.
    tmp="$(mktemp)"
    jq --arg n "$name" --arg repo "$repo" --arg ref "$ref" --arg sha "$sha" \
       --arg lic "$license" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson skills "$skills_json" \
       '.sources[$n] = { repo: $repo, ref: $ref, resolved: $sha,
                         fetchedAt: $at, license: $lic, skills: $skills }' \
       "$LOCKFILE" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$LOCKFILE"
}

# The wrapper's generated metadata. A partial write leaves a wrapper Claude Code
# cannot load, so any failure must fail the source instead of being recorded as
# a success in the lockfile.
write_artefacts() {
    local name="$1" repo="$2" ref="$3" sha="$4" license="$5"; shift 5
    write_plugin_manifest "$name" "$sha" "$@" || return 1
    write_readme "$name" "$repo" "$ref" "$sha" "$license" "$@" || return 1
    update_lock "$name" "$repo" "$ref" "$sha" "$license" "$@" || return 1
    return 0
}

# Remove wrappers and lock entries no longer named in the manifest, so
# deleting a manifest entry uninstalls the skill.
prune_removed() {
    local names entry name tmp
    names="$(source_names)"

    [ -d "$VENDOR_DIR" ] && for entry in "$VENDOR_DIR"/*; do
        [ -d "$entry" ] || continue
        name="$(basename "$entry")"
        # -xF and `--`: the name is data, not a pattern and not an option.
        if ! printf '%s\n' "$names" | grep -qxF -- "$name"; then
            log_info "$name: pruning (no longer in manifest)"
            rm -rf "$entry"
        fi
    done

    [ -f "$LOCKFILE" ] || return 0
    tmp="$(mktemp)"
    jq --argjson keep "$(printf '%s\n' "$names" | jq -R . | jq -s .)" \
       '.sources |= with_entries(select(.key as $k | $keep | index($k)))' \
       "$LOCKFILE" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$LOCKFILE"
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

        local tmp p
        local -a paths
        tmp="$(mktemp -d)"
        # No `mapfile` here: macOS /bin/bash is 3.2, which predates it.
        paths=()
        while IFS= read -r p; do
            [ -n "$p" ] && paths+=("$p")
        done <<< "$(source_skills "$name")"

        # ${paths[@]+…}: bash 3.2 treats an empty array as unset under `set -u`.
        if ! fetch_source "$repo" "$sha" "$tmp/src" ${paths[@]+"${paths[@]}"}; then
            log_warn "$name: fetch failed — keeping committed copy"
            rm -rf "$tmp"
            failed=1
            continue
        fi

        if ! install_source "$name" "$tmp/src" ${paths[@]+"${paths[@]}"}; then
            log_warn "$name: install failed — keeping committed copy"
            rm -rf "$tmp"
            failed=1
            continue
        fi

        local lic
        lic="$(detected_license "$tmp/src")"
        if ! write_artefacts "$name" "$repo" "$ref" "$sha" "$lic" ${paths[@]+"${paths[@]}"}; then
            log_warn "$name: could not write the generated wrapper metadata"
            rm -rf "$tmp"
            failed=1
            continue
        fi
        log_info "$name: vendored ${#paths[@]} skill(s)"
        rm -rf "$tmp"
    done <<< "$(source_names)"

    prune_removed
    [ "$failed" -eq 0 ] || return 2
    return 0
}

# Run only when executed, not when sourced — the test suite sources this file
# to exercise individual functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
