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

# repo_name DIR — prefer the origin remote's basename (a nested checkout like
# src/protobufs is really ecfx-protobufs); fall back to the directory name.
repo_name() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || { basename "$1"; return; }
  basename "${url%.git}"
}

# report_repo DIR LABEL — print "LABEL" + oldest-first commit bullets, or nothing.
report_repo() {
  local dir="$1" label="$2" log
  # --branches/--remotes/--tags, NOT --all: --all would include refs/stash,
  # polluting the report with "WIP on ..." / "index on ..." entries.
  local args=(log --branches --remotes --tags --reverse --since="$SINCE" --author="$AUTHOR" --pretty=format:'%h|%s|%an')
  [ -n "$UNTIL" ] && args+=(--until="$UNTIL")
  log=$(git -C "$dir" "${args[@]}" 2>/dev/null) || return 0
  [ -n "$log" ] || return 0
  printf '%s\n\n' "$label"
  while IFS='|' read -r h s an; do
    if [ "$an" = "$PRIMARY" ]; then
      printf -- '- %s — %s\n' "$h" "$s"
    else
      printf -- '- %s — %s (authored as %s)\n' "$h" "$s" "$an"
    fi
  done <<<"$log"
  printf '\n'
}

for d in "$ROOT"/ecfx-*/; do
  d="${d%/}"
  [ -e "$d/.git" ] || continue
  report_repo "$d" "$(repo_name "$d")"
  # Nested checkouts inside the project (separate repos like src/protobufs).
  # .git may be a directory (clone) or a file (submodule/worktree gitfile).
  while IFS= read -r g; do
    nd=$(dirname "$g")
    report_repo "$nd" "$(repo_name "$nd") (via ${nd#"$ROOT"/})"
  done < <(find "$d" -mindepth 2 -maxdepth 4 -name .git -not -path '*/node_modules/*' 2>/dev/null)
done
