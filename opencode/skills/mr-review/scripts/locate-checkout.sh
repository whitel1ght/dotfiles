#!/usr/bin/env bash
#
# locate-checkout.sh — find the absolute path to a local clone of a GitLab repo.
#
# Usage:
#   locate-checkout.sh <owner>/<repo>
#
# Stdout: the absolute path to the local clone (single match only).
# Stderr: diagnostic output (multiple matches, errors).
#
# Exit codes:
#   0 — single match found, path printed on stdout. Cached for next time.
#   1 — no match found under any search root.
#   2 — multiple matches; user must pick one and write it to the paths file.
#
# Auto-discovery strategy:
#   1. Check $HOME/.config/mr-review/paths.json (if present) for an explicit
#      override. If a match is present and the directory still exists, use it.
#   2. Scan common source roots (~/Documents/source, ~/code, ~/src, ~/projects,
#      ~/work) up to 4 levels deep for .git directories whose origin remote
#      matches <owner>/<repo>. Supports both SSH and HTTPS remote URL forms.
#   3. On exactly one match, cache to paths.json so subsequent calls are O(1).
#   4. On multiple matches, print all candidates to stderr and exit 2 — user
#      decides which is canonical and writes it to paths.json explicitly.
#
# paths.json format:
#   {
#     "owner/repo":      "/absolute/path/to/local/clone",
#     "owner/other":     "/absolute/path/to/another/clone"
#   }

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <owner>/<repo>" >&2
    exit 1
fi

target="$1"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mr-review"
paths_file="$config_dir/paths.json"

# 1. Check explicit override first.
if [[ -f "$paths_file" ]] && command -v jq >/dev/null 2>&1; then
    explicit=$(jq -r --arg key "$target" '.[$key] // empty' "$paths_file" 2>/dev/null || true)
    if [[ -n "$explicit" && -d "$explicit/.git" ]]; then
        echo "$explicit"
        exit 0
    fi
fi

# 2. Auto-discover.
roots=(
    "$HOME/Documents/source"
    "$HOME/code"
    "$HOME/src"
    "$HOME/projects"
    "$HOME/work"
    "$HOME/dev"
)

matches=()
for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r -d '' git_dir; do
        repo_dir=$(dirname "$git_dir")

        # Skip submodules, worktrees, etc. that have a .git file rather than directory.
        [[ -d "$git_dir" ]] || continue

        remote=$(git -C "$repo_dir" config --get remote.origin.url 2>/dev/null || true)
        [[ -z "$remote" ]] && continue

        # Normalize: strip trailing .git and any trailing slash.
        normalized="${remote%.git}"
        normalized="${normalized%/}"

        # Match SSH form: git@host:owner/repo
        # Match HTTPS form: https://host/owner/repo or https://user@host/owner/repo
        # In both, the suffix is "<owner>/<repo>" — match by suffix.
        if [[ "$normalized" == *":$target" ]] || [[ "$normalized" == */"$target" ]]; then
            matches+=("$repo_dir")
        fi
    done < <(find "$root" -maxdepth 4 -type d -name ".git" -print0 2>/dev/null)
done

# Deduplicate (handles symlinked roots, etc.).
if [[ ${#matches[@]} -gt 0 ]]; then
    # shellcheck disable=SC2207
    unique=($(printf "%s\n" "${matches[@]}" | sort -u))
else
    unique=()
fi

case ${#unique[@]} in
    0)
        echo "No local clone of '$target' found under: ${roots[*]}" >&2
        echo "" >&2
        echo "Either clone it, or add an explicit mapping to $paths_file:" >&2
        echo "  {\"$target\": \"/abs/path/to/clone\"}" >&2
        exit 1
        ;;
    1)
        echo "${unique[0]}"
        # Cache for next time. Best-effort; ignore failures.
        if command -v jq >/dev/null 2>&1; then
            mkdir -p "$config_dir" 2>/dev/null || true
            if [[ -f "$paths_file" ]]; then
                if jq --arg key "$target" --arg val "${unique[0]}" \
                      '. + {($key): $val}' "$paths_file" > "$paths_file.tmp" 2>/dev/null; then
                    mv "$paths_file.tmp" "$paths_file" 2>/dev/null || rm -f "$paths_file.tmp"
                fi
            else
                echo "{\"$target\": \"${unique[0]}\"}" | jq . > "$paths_file" 2>/dev/null || true
            fi
        fi
        exit 0
        ;;
    *)
        echo "Multiple local clones of '$target' found:" >&2
        printf '  %s\n' "${unique[@]}" >&2
        echo "" >&2
        echo "Pick the canonical one and write it to $paths_file:" >&2
        echo "  {\"$target\": \"<chosen-path>\"}" >&2
        exit 2
        ;;
esac
