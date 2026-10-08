#!/bin/bash
# Tests for bin/open-path. Everything runs inside a sandbox HOME with stub
# `tmux` and `fzf` on PATH, so no real tmux server, editor or picker is touched.
# Exercises the --list code path (token extraction + disk-check resolve) against
# fake Claude Code and pi transcripts; the interactive fzf picker is not tested.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/open-path"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

STUBS="$SANDBOX/stubs"
HOME_DIR="$SANDBOX/home"
PROJ="$HOME_DIR/projects/dotfiles"
DECOY_PROJ="$HOME_DIR/projects/other"
PANE="%"

mkdir -p "$STUBS" "$PROJ" "$DECOY_PROJ"

# Slug derivation must match the script's: non-alphanumerics -> '-'.
SLUG="$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')"
DECOY_SLUG="$(printf '%s' "$DECOY_PROJ" | sed 's/[^A-Za-z0-9]/-/g')"

# Real files the transcripts and pane content point at.
: > "$PROJ/alpha.txt"   # pi transcript, with a :line suffix
: > "$PROJ/beta.md"     # claude transcript
: > "$PROJ/notes.md"    # visible pane content, relative path
: > "$DECOY_PROJ/real.rb"  # exists, but under a different project slug

# Stub tmux: answer the format lookups and capture-pane the script makes.
cat > "$STUBS/tmux" <<'STUB'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        *pane_current_path*) printf '%s\n' "$STUB_CWD"; exit 0 ;;
        *session_name*)      printf '%s\n' "test";       exit 0 ;;
    esac
done
case "$1" in
    capture-pane) printf '%s\n' "$STUB_PANE" ;;
    show-option)  printf '%s\n' "nvim" ;;
esac
STUB
chmod +x "$STUBS/tmux"

# fzf is never reached under --list; stub it so the run is hermetic.
printf '#!/bin/bash\nexit 0\n' > "$STUBS/fzf"
chmod +x "$STUBS/fzf"

# Transcripts: one pi, one claude, one decoy under a different slug. The pi
# entry carries a :line suffix; the claude one a path that does not exist and
# must be filtered out by the disk check.
mkdir -p "$HOME_DIR/.pi/agent/sessions/$SLUG" "$HOME_DIR/.claude/projects/$SLUG" \
         "$HOME_DIR/.claude/projects/$DECOY_SLUG"
printf '{"type":"message","message":{"content":[{"type":"text","text":"edited %s/alpha.txt:42"}]}}\n' \
    "$PROJ" > "$HOME_DIR/.pi/agent/sessions/$SLUG/2026-10-08T10-00-00-000Z_abc.jsonl"
printf '{"type":"message","message":{"content":[{"type":"text","text":"read %s/beta.md and %s/ghost.txt"}]}}\n' \
    "$PROJ" "$PROJ" > "$HOME_DIR/.claude/projects/$SLUG/session-1.jsonl"
printf '{"type":"message","message":{"content":[{"type":"text","text":"read %s/real.rb"}]}}\n' \
    "$DECOY_PROJ" > "$HOME_DIR/.claude/projects/$DECOY_SLUG/session-1.jsonl"

export STUB_CWD="$PROJ"
export STUB_PANE="reading notes.md before the edit"

list_paths() {
    HOME="$HOME_DIR" PATH="$STUBS:$PATH" bash "$SCRIPT" --list "$PANE" 2>&1
}

echo "pi and claude transcripts"
out="$(list_paths)"
printf '%s\n' "$out" | grep -qF "$PROJ/alpha.txt" \
    && pass "finds a path from the pi transcript" \
    || fail "finds a path from the pi transcript" "$out"
printf '%s\n' "$out" | grep -qF "$PROJ/beta.md" \
    && pass "finds a path from the claude transcript" \
    || fail "finds a path from the claude transcript" "$out"
printf '%s\n' "$out" | grep -qF "$PROJ/notes.md" \
    && pass "finds a relative path from the visible pane" \
    || fail "finds a relative path from the visible pane" "$out"
printf '%s\n' "$out" | grep -qF "$(printf '%s\t42' "$PROJ/alpha.txt")" \
    && pass "keeps the :line number from the transcript" \
    || fail "keeps the :line number from the transcript" "$out"
printf '%s\n' "$out" | grep -qF "ghost.txt" \
    && fail "drops transcript paths that do not exist" "ghost.txt listed" \
    || pass "drops transcript paths that do not exist"
printf '%s\n' "$out" | grep -qF "real.rb" \
    && fail "ignores transcripts of other projects" "decoy slug listed" \
    || pass "ignores transcripts of other projects"

echo "no transcripts for the project"
export STUB_CWD="$HOME_DIR/empty"
# The pane's relative path resolves against the pane's cwd, so the file has to
# exist there for it to survive the disk check.
mkdir -p "$HOME_DIR/empty"
: > "$HOME_DIR/empty/notes.md"
out="$(list_paths)"
printf '%s\n' "$out" | grep -qF "$HOME_DIR/empty/notes.md" \
    && pass "still finds the pane path without transcripts" \
    || fail "still finds the pane path without transcripts" "$out"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] \
    && pass "offers only the pane path" \
    || fail "offers only the pane path" "$out"

echo "missing tools"
out="$(HOME="$HOME_DIR" PATH="$STUBS:/usr/bin:/bin" bash "$SCRIPT" --list "$PANE" 2>&1)"
printf '%s\n' "$out" | grep -q "missing required tool(s)" \
    && pass "names a missing dependency instead of failing silently" \
    || fail "names a missing dependency instead of failing silently" "$out"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
