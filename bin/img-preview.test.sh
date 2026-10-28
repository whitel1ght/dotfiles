#!/bin/bash
# Tests for bin/img-preview. Stub `chafa`, `bat` and `tmux` on PATH log how they
# were called, so nothing is drawn and no real tmux server is asked.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/img-preview"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

STUBS="$SANDBOX/stubs"
NOBAT="$SANDBOX/nobat"
mkdir -p "$STUBS" "$NOBAT"
export LOG="$SANDBOX/calls"

for tool in chafa bat; do
    printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n[ -z "${STUB_CHAFA_FAILS:-}" ] || [ "%s" != chafa ] || exit 1\n' \
        "$tool" "$tool" > "$STUBS/$tool"
    chmod +x "$STUBS/$tool"
done
cat > "$STUBS/tmux" <<'STUB'
#!/bin/bash
case "$*" in
    *client_termname*) printf '%s\n' "${STUB_CLIENT_TERM:-xterm-ghostty}" ;;
esac
STUB
chmod +x "$STUBS/tmux"
cp "$STUBS/chafa" "$STUBS/tmux" "$NOBAT/"

# A real 1x1 PNG, so `file` recognises it by its bytes, not its name.
PNG="$SANDBOX/shot.png"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' \
    | base64 -d > "$PNG"
TXT="$SANDBOX/notes.md"
printf 'line one\nline two\n' > "$TXT"
SVG="$SANDBOX/logo.svg"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>\n' > "$SVG"

run() {
    : > "$LOG"
    env -u TMUX -u TERM_PROGRAM PATH="$STUBS:/usr/bin:/bin" "$@" 2>&1
}

echo "text files"
out="$(run bash "$SCRIPT" "$TXT")"
grep -q "^bat .*$TXT" "$LOG" \
    && pass "a text file goes to bat" \
    || fail "a text file goes to bat" "$(cat "$LOG")"
grep -q '^chafa' "$LOG" \
    && fail "a text file never reaches chafa" "$(cat "$LOG")" \
    || pass "a text file never reaches chafa"
out="$(: > "$LOG"; env -u TMUX PATH="$NOBAT:/usr/bin:/bin" bash "$SCRIPT" "$TXT" 2>&1)"
printf '%s\n' "$out" | grep -q 'line two' \
    && pass "without bat, the file is printed as is" \
    || fail "without bat, the file is printed as is" "$out"
run bash "$SCRIPT" "$SVG" >/dev/null
grep -q '^bat' "$LOG" && ! grep -q '^chafa' "$LOG" \
    && pass "an SVG is shown as text" \
    || fail "an SVG is shown as text" "$(cat "$LOG")"

echo "images"
run TMUX=/tmp/sock FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=12 bash "$SCRIPT" "$PNG" >/dev/null
grep -q -- "^chafa .*-f kitty --passthrough tmux .*-s 40x12 .*$PNG" "$LOG" \
    && pass "in tmux under Ghostty: kitty placeholders sized to the preview" \
    || fail "in tmux under Ghostty: kitty placeholders sized to the preview" "$(cat "$LOG")"
run TMUX=/tmp/sock STUB_CLIENT_TERM=xterm-kitty FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=12 \
    bash "$SCRIPT" "$PNG" >/dev/null
grep -q -- '-f kitty --passthrough tmux' "$LOG" \
    && pass "in tmux under kitty: kitty placeholders" \
    || fail "in tmux under kitty: kitty placeholders" "$(cat "$LOG")"
run TMUX=/tmp/sock STUB_CLIENT_TERM=xterm-256color FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=12 \
    bash "$SCRIPT" "$PNG" >/dev/null
grep -q -- '-f symbols' "$LOG" \
    && pass "in tmux under another terminal: symbols" \
    || fail "in tmux under another terminal: symbols" "$(cat "$LOG")"
run TERM_PROGRAM=ghostty FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=12 bash "$SCRIPT" "$PNG" >/dev/null
grep -q -- '-f kitty' "$LOG" && ! grep -q -- '--passthrough tmux' "$LOG" \
    && pass "Ghostty without tmux: kitty, no tmux wrapping" \
    || fail "Ghostty without tmux: kitty, no tmux wrapping" "$(cat "$LOG")"
out="$(run TMUX=/tmp/sock STUB_CHAFA_FAILS=1 FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=12 \
    bash "$SCRIPT" "$PNG")"
printf '%s\n' "$out" | grep -q 'PNG image data, 1 x 1' \
    && pass "an image chafa cannot decode falls back to its info line" \
    || fail "an image chafa cannot decode falls back to its info line" "$out"

echo "--text (for popups, where tmux passes no images)"
out="$(run TMUX=/tmp/sock bash "$SCRIPT" --text "$PNG")"
printf '%s\n' "$out" | grep -q 'PNG image data, 1 x 1' && printf '%s\n' "$out" | grep -q '[0-9] B' \
    && pass "an image prints its kind, size in pixels and bytes" \
    || fail "an image prints its kind, size in pixels and bytes" "$out"
grep -q '^chafa' "$LOG" \
    && fail "--text never draws" "$(cat "$LOG")" \
    || pass "--text never draws"
run bash "$SCRIPT" --text "$TXT" >/dev/null
grep -q "^bat .*$TXT" "$LOG" \
    && pass "--text still shows a text file" \
    || fail "--text still shows a text file" "$(cat "$LOG")"

echo "--view (a whole window)"
run TMUX=/tmp/sock COLUMNS=100 LINES=30 bash "$SCRIPT" --view "$PNG" < /dev/null >/dev/null
grep -q -- "-f kitty --passthrough tmux .*-s 100x28 .*$PNG" "$LOG" \
    && pass "draws to the window size, two rows kept for the caption" \
    || fail "draws to the window size, two rows kept for the caption" "$(cat "$LOG")"

echo "bad input"
out="$(run bash "$SCRIPT" "$SANDBOX/missing.png")"; code=$?
[ "$code" -ne 0 ] && printf '%s\n' "$out" | grep -q 'no such file' \
    && pass "a missing file is named and fails" \
    || fail "a missing file is named and fails" "exit $code: $out"
out="$(run bash "$SCRIPT")"; code=$?
[ "$code" -ne 0 ] && printf '%s\n' "$out" | grep -q 'usage' \
    && pass "no file prints usage" \
    || fail "no file prints usage" "exit $code: $out"

echo "wiring"
ROOT="$TEST_DIR/.."
rg -q '^set -g allow-passthrough on$' "$ROOT/tmux/.tmux.conf" \
    && pass "tmux passes images from visible panes" \
    || fail "tmux passes images from visible panes" "no 'set -g allow-passthrough on'"
rg -q "^export FZF_CTRL_T_OPTS=\"--preview 'img-preview \{\}'\"" "$ROOT/zsh/.zshrc" \
    && pass "Ctrl-T previews through img-preview" \
    || fail "Ctrl-T previews through img-preview" "$(rg -n FZF_CTRL_T_OPTS "$ROOT/zsh/.zshrc")"
rg -q "fzf-tab:complete:\(nvim\|vim\|vi\|bat\|cat\|less\|open\):\*' fzf-preview 'img-preview \\\$realpath'" "$ROOT/zsh/.zshrc" \
    && pass "file completions preview through img-preview" \
    || fail "file completions preview through img-preview" "$(rg -n "bat\|cat" "$ROOT/zsh/.zshrc")"
rg -q '^brew "chafa"$' "$ROOT/Brewfile" \
    && pass "chafa is in the Brewfile" \
    || fail "chafa is in the Brewfile" "missing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
