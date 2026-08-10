#!/bin/bash
# qa-comment: gather the raw facts a QA comment is built from.
#
# This script collects; it does not judge. Deciding what QA should actually
# click, and which of these changes can break something else, is the model's
# job — see SKILL.md. Everything here is mechanical and reproducible so the
# model spends its effort on the parts that need reasoning.
#
# Usage: analyse.sh [BASE]
#   BASE  branch to diff against (default: origin/master, then master)
set -uo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
  for candidate in origin/master origin/main master main; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then BASE="$candidate"; break; fi
  done
fi
[ -n "$BASE" ] || { echo "ERROR: no base branch found (tried origin/master, origin/main, master, main)" >&2; exit 1; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || {
  echo "ERROR: no merge base between $BASE and HEAD" >&2; exit 1; }

section() { printf '\n===== %s =====\n' "$1"; }

section "BRANCH"
echo "branch:     $BRANCH"
echo "base:       $BASE"
echo "merge-base: $(git rev-parse --short "$MERGE_BASE")"
# A ticket id in the branch name or commits is the most reliable source.
echo "ticket:     $(echo "$BRANCH" | grep -oiE '[A-Z]+-[0-9]+' | head -1)"

section "COMMITS"
git log --oneline "$MERGE_BASE..HEAD"

section "FILES CHANGED"
git diff --stat "$MERGE_BASE..HEAD"

section "FILES BY TYPE"
# Grouping matters: a template change is usually one page, a shared stylesheet
# or a base view class can be every page. The model uses this split to decide
# how hard to look for blast radius.
git diff --name-only "$MERGE_BASE..HEAD" | awk '
  /\.(css|scss)$/            { css = css "\n  " $0; next }
  /\.js$/                    { js  = js  "\n  " $0; next }
  /templates\/.*\.html$/     { tpl = tpl "\n  " $0; next }
  # Tests before the generic .py rule, or they fall through to PYTHON.
  /(^|\/)tests?\//           { tst = tst "\n  " $0; next }
  /(^|\/)(base|__init__)\.py$/ { core = core "\n  " $0; next }
  /\.py$/                    { py  = py  "\n  " $0; next }
                             { other = other "\n  " $0 }
  END {
    if (css)   print "STYLESHEETS (check what else loads these):" css
    if (js)    print "\nSCRIPTS:" js
    if (tpl)   print "\nTEMPLATES:" tpl
    if (core)  print "\nCORE/BASE (inherited widely — check subclasses):" core
    if (py)    print "\nPYTHON:" py
    if (tst)   print "\nTESTS (not user-facing):" tst
    if (other) print "\nOTHER:" other
  }'

section "NEW / DELETED FILES"
git diff --name-status --diff-filter=AD "$MERGE_BASE..HEAD" || true

section "CSS SELECTORS ADDED OR REMOVED"
# The blast radius of a stylesheet change is "everything using these selectors",
# which is not visible in the file list. Emitting them lets the model grep for
# users rather than guess.
git diff -U0 "$MERGE_BASE..HEAD" -- '*.css' '*.scss' 2>/dev/null \
  | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
  | grep -E '\{\s*$' | sed 's/ *{[[:space:]]*$//' | sort -u || echo "  (none)"

section "PYTHON DEFINITIONS TOUCHED"
git diff -U0 "$MERGE_BASE..HEAD" -- '*.py' 2>/dev/null \
  | grep -E '^[+-]\s*(def|class) ' | sed 's/^\(.\)[[:space:]]*/\1 /' | sort -u || echo "  (none)"

section "USER-FACING STRINGS CHANGED"
# Copy changes are the ones QA can verify by reading, and the ones most often
# missed in a diff review.
git diff -U0 "$MERGE_BASE..HEAD" -- '*.py' '*.html' 2>/dev/null \
  | grep -E "^[+-].*(flash\(|<h[1-6]|<label|<button|value=|placeholder=|aria-label=)" \
  | grep -vE '^(\+\+\+|---)' | cut -c1-160 | head -40 || echo "  (none)"

section "ROUTES DEFINED IN CHANGED PYTHON"
# Approximate: shows routes declared in the files that changed. Nested/blueprint
# prefixes are NOT resolved — the model should confirm real URLs before quoting
# them to QA.
for f in $(git diff --name-only "$MERGE_BASE..HEAD" -- '*.py'); do
  [ -f "$f" ] || continue
  hits=$(grep -nE "@(expose|app\.route|bp\.route|[a-z_]+\.route)\(" "$f" 2>/dev/null | head -12)
  [ -n "$hits" ] && printf '%s:\n%s\n' "$f" "$hits"
done
echo "  (verify actual URLs — blueprint prefixes are not resolved here)"

section "TEMPLATES: WHO RENDERS THEM"
for f in $(git diff --name-only "$MERGE_BASE..HEAD" -- '*templates/*.html'); do
  base="$(basename "$f")"
  echo "$base:"
  grep -rn --include='*.py' --include='*.html' -F "$base" . 2>/dev/null \
    | grep -v "^\./$f:" | grep -vE '(^\./\.git/|/node_modules/)' | cut -c1-140 | head -6 \
    || echo "  (no explicit references — may be a flask-admin convention name)"
done

section "TEST RESULT"
# Whether the branch is green is a fact QA benefits from knowing.
if [ -x venv/bin/python ] && [ -d tests ]; then
  venv/bin/python -m pytest tests/ -q 2>&1 | tail -3
elif command -v pytest >/dev/null 2>&1 && [ -d tests ]; then
  pytest -q 2>&1 | tail -3
else
  echo "  (no test runner detected — state this rather than claiming green)"
fi

section "END"
