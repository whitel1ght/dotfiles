#!/bin/bash
# Tests for bin/art. A sandbox folder stands in for ~/artifacts, and OPEN_CMD and
# fzf are stubs that log what they were given, so nothing opens for real.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/art"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
A="$SANDBOX/artifacts"
mk() { mkdir -p "$A/$1"; printf '<title>%s</title>\n<p>x</p>\n' "$2" > "$A/$1/$1.html"; printf '%s\n' "$3" > "$A/$1/url"; }
mk system-map "Dmitry's System Map" https://claude.ai/artifact/AAA
mk daily-run-system "Daily Run System" https://claude.ai/artifact/BBB
mk retrieve-v2-ui-decisions "Retrieve v2 UI Decisions" https://claude.ai/artifact/CCC
mkdir -p "$A/not-an-artifact"   # a folder without a page is skipped

BIN="$SANDBOX/bin"; mkdir -p "$BIN"
LOG="$SANDBOX/open.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$LOG" > "$BIN/opener"
# fzf stub: prints the line whose name matches $FZF_PICK, or exits 130 (esc)
cat > "$BIN/fzf" <<'EOF'
#!/bin/sh
[ -n "${FZF_PICK:-}" ] || exit 130
awk -F'\t' -v p="$FZF_PICK" '$1 == p { print; found = 1; exit } END { exit !found }'
EOF
chmod +x "$BIN/opener" "$BIN/fzf"
export ARTIFACTS_DIR="$A" OPEN_CMD="$BIN/opener" PATH="$BIN:$PATH"
run() { : > "$LOG"; "$SCRIPT" "$@" 2>&1; }

echo "list"
out="$(run --list)"
check "one line per artifact with a page" "3" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
has "name, then title" "$out" "system-map	Dmitry's System Map"
has "title read from the page" "$out" "Retrieve v2 UI Decisions"
case "$out" in *not-an-artifact*) fail "folders without a page are skipped" "$out" ;; *) pass "folders without a page are skipped" ;; esac

echo "open by name"
run map >/dev/null; check "a unique match opens the local page" "$A/system-map/system-map.html" "$(cat "$LOG")"
run Retrieve >/dev/null; check "matching is case-insensitive and covers the title" "$A/retrieve-v2-ui-decisions/retrieve-v2-ui-decisions.html" "$(cat "$LOG")"
run --url daily >/dev/null; check "--url opens the published page" "https://claude.ai/artifact/BBB" "$(cat "$LOG")"
out="$(run nothing-like-this)"; code=$?
check "no match exits 1" "1" "$code"
has "and says so" "$out" "no artifact matches"

echo "picker"
FZF_PICK=daily-run-system run >/dev/null; check "picker opens the pick" "$A/daily-run-system/daily-run-system.html" "$(cat "$LOG")"
FZF_PICK=retrieve-v2-ui-decisions run s >/dev/null; check "several matches go to the picker" "$A/retrieve-v2-ui-decisions/retrieve-v2-ui-decisions.html" "$(cat "$LOG")"
run >/dev/null; code=$?
check "esc in the picker is not an error" "0" "$code"
check "and opens nothing" "" "$(cat "$LOG")"

echo "preview"
out="$(run --preview system-map)"
has "preview shows the title" "$out" "Dmitry's System Map"
has "preview shows the link" "$out" "https://claude.ai/artifact/AAA"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
