#!/bin/bash
# ecfx-daily-commits: list the user's commits in ~/projects/ecfx-* repos,
# including nested checkouts (e.g. ecfx-dashboard/src/protobufs).
#
# Usage: collect.sh [SINCE] [UNTIL]
#   SINCE  git --since value (default: "today 00:00")
#   UNTIL  git --until value (optional)
set -euo pipefail

SINCE="${1:-today 00:00}"
UNTIL="${2:-}"
ROOT="$HOME/projects"
AUTHOR="Mamyr"           # matches both "Dmitry Mamyrev" and "Dzmitry Mamyrau"
PRIMARY="Dmitry Mamyrev" # commits by other author spellings get "(authored as …)"

# Newline-delimited sets, not associative arrays: /bin/bash here is 3.2.
#
# A checkout is visited once per git object store: linked worktrees of the same
# repo share a --git-common-dir, so keying on it collapses them to one section.
SEEN_STORE=$'\n'
# Separate clones of the same project (e.g. ecfx-dashboard and a bare
# ecfx-dashboard.git with worktrees) have distinct stores but carry the same
# commits, so a commit is reported once, under the first repo that holds it.
SEEN_COMMIT=$'\n'

# seen SET_NAME VALUE — true if already present; records it either way.
seen() {
  local name="$1" value="$2" current
  eval "current=\$$name"
  case "$current" in
    *"$value"$'\n'*) return 0 ;;
  esac
  eval "$name=\$current\$value\$'\\n'"
  return 1
}

# repo_name DIR — prefer the origin remote's basename (a nested checkout like
# src/protobufs is really ecfx-protobufs); fall back to the directory name.
repo_name() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || { basename "$1"; return; }
  basename "${url%.git}"
}

# report_repo DIR LABEL — print "LABEL" + oldest-first commit bullets, or nothing.
report_repo() {
  local dir="$1" label="$2" store log bullets=() h s an

  store=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  seen SEEN_STORE "$store" && return 0

  # --branches/--remotes/--tags, NOT --all: --all would include refs/stash,
  # polluting the report with "WIP on ..." / "index on ..." entries.
  # %x1f (unit separator) can't occur in a subject, unlike '|'.
  local args=(log --branches --remotes --tags --reverse --since="$SINCE" --author="$AUTHOR" --pretty=format:'%h%x1f%s%x1f%an')
  [ -n "$UNTIL" ] && args+=(--until="$UNTIL")
  log=$(git -C "$dir" "${args[@]}" 2>/dev/null) || return 0
  [ -n "$log" ] || return 0

  while IFS=$'\x1f' read -r h s an; do
    # Full hash: short hashes can differ in width between repos.
    local full
    full=$(git -C "$dir" rev-parse "$h" 2>/dev/null) || full="$h"
    seen SEEN_COMMIT "$full" && continue
    if [ "$an" = "$PRIMARY" ]; then
      bullets+=("$(printf -- '- %s — %s' "$h" "$s")")
    else
      bullets+=("$(printf -- '- %s — %s (authored as %s)' "$h" "$s" "$an")")
    fi
  done <<<"$log"

  [ ${#bullets[@]} -gt 0 ] || return 0
  printf '%s\n\n' "$label"
  printf '%s\n' "${bullets[@]}"
  printf '\n'
}

# Top-level clones first, so a project's own checkout claims its commits before
# a nested copy of the same repo does (ecfx-protobufs, not ".../src/protobufs").
for d in "$ROOT"/ecfx-*/; do
  d="${d%/}"
  [ -e "$d/.git" ] || continue
  report_repo "$d" "$(repo_name "$d")"
done

# Then nested checkouts inside each project (separate repos like src/protobufs).
# .git may be a directory (clone) or a file (submodule/worktree gitfile).
for d in "$ROOT"/ecfx-*/; do
  d="${d%/}"
  [ -e "$d/.git" ] || continue
  while IFS= read -r g; do
    nd=$(dirname "$g")
    report_repo "$nd" "$(repo_name "$nd") (via ${nd#"$ROOT"/})"
  done < <(find "$d" -mindepth 2 -maxdepth 4 -name .git -not -path '*/node_modules/*' 2>/dev/null)
done
