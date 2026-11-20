#!/bin/bash
# Tests for bin/jokes-week. curl and pi are stubs on PATH serving fixtures, so no
# network and no LLM: Arctic Shift JSON, a dailyjokes.co page, and a canned ranking.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/jokes-week"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) fail "$1" "[$3] unexpectedly in: $2" ;; *) pass "$1" ;; esac; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"; mkdir -p "$BIN"

# fixed "now" and posts: fresh = now-1d, old = now-8d (outside the 7-day window)
NOW=1795200000
FRESH=$((NOW - 86400))
OLD=$((NOW - 8 * 86400))
FRESH_DATE="$(date -r "$FRESH" +%m/%d/%Y)"
OLD_DATE="$(date -r "$OLD" +%m/%d/%Y)"
LONG="$(python3 -c 'print("x " * 1400)')"
STORY="$(python3 -c 'print("y " * 150)')"  # 300 chars: past the default 240 cap

cat > "$SANDBOX/reddit.json" <<EOF
{"data": [
 {"title": "Joke A setup", "selftext": "Joke A punchline", "score": 500, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/a1"},
 {"title": "Joke A setup", "selftext": "Joke A punchline", "score": 480, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/a2"},
 {"title": "Joke B", "selftext": "", "score": 300, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/b1"},
 {"title": "Low score joke", "selftext": "", "score": 10, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/c1"},
 {"title": "Old joke", "selftext": "", "score": 900, "created_utc": $OLD, "permalink": "/r/TestSub/comments/d1"},
 {"title": "Too long", "selftext": "$LONG", "score": 700, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/e1"},
 {"title": "Story length", "selftext": "$STORY", "score": 600, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/f1"},
 {"title": "Meme caption", "selftext": "", "score": 800, "created_utc": $FRESH, "permalink": "/r/TestSub/comments/g1", "post_hint": "image"}
]}
EOF

cat > "$SANDBOX/dailyjokes.html" <<EOF
<html><body>
<div class="joke">
  <div class="joke_date_id"><div class="joke_date">$FRESH_DATE from Daily Jokes</div><div class="joke_id">#1</div></div>
  <div class="joke_title"><a href="https://www.dailyjokes.co/joke/fresh-one/"><span>Fresh daily joke</span></a></div>
  <div class="joke_text"><p>Daily joke D text.</p></div>
  <div class="joke_footer">footer</div>
</div>
<div class="joke">
  <div class="joke_date_id"><div class="joke_date">$OLD_DATE from Daily Jokes</div><div class="joke_id">#2</div></div>
  <div class="joke_title"><a href="https://www.dailyjokes.co/joke/old-one/"><span>Old daily joke</span></a></div>
  <div class="joke_text"><p>Old joke E text.</p></div>
  <div class="joke_footer">footer</div>
</div>
</body></html>
EOF

# curl stub: dispatch on URL, ignore the other flags
cat > "$BIN/curl" <<EOF
#!/bin/bash
url="\${@: -1}"
case "\$url" in
  *arctic-shift*) cat "$SANDBOX/reddit.json" ;;
  *dailyjokes*)   cat "$SANDBOX/dailyjokes.html" ;;
  *) echo '{}' ;;
esac
EOF
# pi stub: picks candidate 2 (dailyjokes D) then 0 (A), ignoring scores
cat > "$BIN/pi" <<'EOF'
#!/bin/sh
cat > /dev/null
echo "2,0"
EOF
chmod +x "$BIN/curl" "$BIN/pi"

export PATH="$BIN:$PATH" JOKES_NOW="$NOW" JOKES_SUBS=TestSub \
  JOKES_OUT_DIR="$SANDBOX/out" JOKES_MIN_SCORE=50 JOKES_TOP_N=3

echo "llm-ranked run"
out="$("$SCRIPT" 2>"$SANDBOX/err")"
check "exit ok" "0" "$?"
has "header has the date" "$out" "# Funniest jokes of the week"
has "first pick is what the LLM chose (dailyjokes)" "$out" "## 1. dailyjokes.co"
has "second pick follows LLM order" "$out" "## 2. r/TestSub"
has "joke text kept" "$out" "Daily joke D text."
has "reddit permalink" "$out" "https://www.reddit.com/r/TestSub/comments/"
has "score shown" "$out" "500 pts"
check "repost deduped (A appears once)" "1" "$(printf '%s\n' "$out" | grep -c 'Joke A punchline')"
hasnt "low-score filtered" "$out" "Low score joke"
hasnt "old post filtered" "$out" "Old joke"
hasnt "too-long post filtered" "$out" "Too long"
hasnt "story-length post filtered at the default cap" "$out" "Story length"
hasnt "image post filtered" "$out" "Meme caption"
hasnt "old daily joke filtered" "$out" "Old joke E text"
check "saved to out dir" "1" "$(ls "$SANDBOX/out" | grep -c '\.md$')"
has "log counts candidates" "$(cat "$SANDBOX/err")" "unique candidates"

echo "--no-llm ranks by score"
out="$("$SCRIPT" --no-llm 2>/dev/null)"
first="$(printf '%s\n' "$out" | grep '^## 1' )"
has "top-scored joke first without LLM" "$first" "r/TestSub"
hasnt "no pi stub needed" "$(PATH="$SANDBOX/emptybin" "$SCRIPT" --no-llm 2>&1 >/dev/null; echo)" "pi"

echo "--json dumps candidates"
out="$("$SCRIPT" --json 2>/dev/null)"
check "json parses" "0" "$(printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; echo $?)"
has "json has sources" "$out" '"source"'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
