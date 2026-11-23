#!/bin/bash
# Tests for bin/session-save, which turns a marked Claude or pi session into Markdown under
# ~/wiki/learning/sessions/. Every run uses temp dirs; nothing reaches the real wiki.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/session-save"
DATA="$TEST_DIR/testdata/session-save"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { if eval "$2"; then pass "$1"; else fail "$1" "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TZ=UTC
export SESSION_SAVE_DIR="$TMP/wiki/learning/sessions"
export SESSION_SAVE_STATE="$TMP/state"
export CLAUDE_PROJECTS_DIR="$TMP/claude-projects"
SID=11111111-2222-3333-4444-555555555555
mkdir -p "$CLAUDE_PROJECTS_DIR/-Users-x-projects-rust"
cp "$DATA/claude.jsonl" "$CLAUDE_PROJECTS_DIR/-Users-x-projects-rust/$SID.jsonl"
LOG="$CLAUDE_PROJECTS_DIR/-Users-x-projects-rust/$SID.jsonl"

echo "claude: save"
out="$("$SCRIPT" save --harness claude --session "$SID" 2>"$TMP/err")"; rc=$?
F="$SESSION_SAVE_DIR/2026-11-20-rust-lifetimes-11111111.md"
check "exits 0" '[ "$rc" -eq 0 ]'
check "prints the written path" '[ "$out" = "$F" ]'
check "writes one file named <date>-rust-lifetimes-<sid8>.md" '[ -f "$F" ] && [ "$(ls "$SESSION_SAVE_DIR" | wc -l | tr -d " ")" = 1 ]'
body="$(cat "$F" 2>/dev/null)"
has() { case "$body" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
check "frontmatter title" 'has "title: Rust lifetimes"'
check "frontmatter harness" 'has "harness: claude"'
check "frontmatter session_id" 'has "session_id: $SID"'
check "frontmatter cwd" 'has "cwd: /Users/x/projects/rust"'
check "frontmatter saved" 'has "saved: "'
check "user heading with time" 'has "## You · 10:00"'
check "claude heading with time" 'has "## Claude · 10:00"'
check "consecutive assistant records share one heading" '[ "$(grep -c "^## Claude · 10:00" "$F")" = 1 ]'
check "user text kept" 'has "Explain lifetimes in Rust"'
check "assistant text kept" 'has "A lifetime names how long a reference is valid."'
check "no thinking" '! has "secret thoughts here"'
check "no system-reminder" '! has "hidden reminder"'
check "no isMeta text" '! has "meta caveat text"'
check "no sidechain text" '! has "Sidechain chatter"'
check "slash command shown as typed" 'grep -qx "/learn-mark" "$F"'
check "tool call as one line" 'has "> ran Bash: "'
check "secret in a tool input redacted" 'has "[redacted]" && ! has "abcdefghijklmnopqrstuvwxyz123456"'
wline="$(grep "^> ran Write: " "$F")"
check "huge tool input cut to 200 chars" '[ -n "$wline" ] && [ "${#wline}" -le $((13 + 200)) ]'
check "file stays short" '[ "$(wc -l <"$F")" -lt 100 ]'
check "subagent report in details" 'has "<details><summary>Subagent report</summary>" && has "Subagent found:"'
check "secret in a subagent report redacted" 'has "GITLAB_TOKEN=[redacted]" && ! has "glpat-abc"'
check "plain tool output left out" '! has "plain bash output xyz"'

echo "claude: re-save after a title change"
sed 's/"Rust lifetimes"/"Borrow checker"/' "$DATA/claude.jsonl" >"$LOG"
"$SCRIPT" save --harness claude --session "$SID" >/dev/null 2>&1
check "exactly one file remains, under the new name" \
  '[ "$(ls "$SESSION_SAVE_DIR")" = "2026-11-20-borrow-checker-11111111.md" ]'
check "--title wins over the log" \
  '"$SCRIPT" save --harness claude --session "$SID" --title "My Notes!" >/dev/null && [ "$(ls "$SESSION_SAVE_DIR")" = "2026-11-20-my-notes-11111111.md" ]'

echo "claude: edge cases"
E=22222222-0000-0000-0000-000000000000
grep -v '"type": "user"' "$DATA/claude.jsonl" | sed "s/$SID/$E/g" >"$CLAUDE_PROJECTS_DIR/-Users-x-projects-rust/$E.jsonl"
out="$("$SCRIPT" save --harness claude --session "$E" 2>&1)"; rc=$?
check "no typed user prompt: exit 0, nothing written" '[ "$rc" -eq 0 ] && [ -z "$out" ] && ! ls "$SESSION_SAVE_DIR" | grep -q 22222222'
"$SCRIPT" save --harness claude --session 99999999-nope >/dev/null 2>&1; rc=$?
check "unknown session exits 1" '[ "$rc" -eq 1 ]'
out="$(python3 -W error::SyntaxWarning -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$SCRIPT" 2>&1)"
check "compiles without a SyntaxWarning (F-152)" '[ -z "$out" ]'

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
