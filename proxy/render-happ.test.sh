#!/bin/bash
# Tests for render-happ.py. Domain lists and secrets are throwaway files in a
# sandbox; the real lists are only read, to check they still render.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/render-happ.py"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
printf '# comment\nclaude.ai\n\nyoutube.com\n' > "$SANDBOX/proxy.txt"

decode() { local l; l="$("$SCRIPT" routing "$SANDBOX/proxy.txt")"; echo "${l#happ://routing/onadd/}" | base64 -d; }
field() { decode | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)[\"$1\"]))"; }

echo "render-happ.py — routing"
link="$("$SCRIPT" routing "$SANDBOX/proxy.txt")"
assert_contains "$link" "happ://routing/onadd/" "emits an add-and-activate link"
assert_eq '["domain:claude.ai", "domain:youtube.com"]' "$(field ProxySites)" "proxies the list as apex-plus-subdomain matches"
assert_eq '[]' "$(field BlockSites)" "blocks nothing on the phone"
assert_eq '"false"' "$(field GlobalProxy)" "everything unlisted goes direct"

printf '# nothing\n' > "$SANDBOX/empty.txt"
"$SCRIPT" routing "$SANDBOX/empty.txt" >/dev/null 2>&1 \
    && fail "refuses an empty proxy list" "exit 0" || pass "refuses an empty proxy list"

"$SCRIPT" routing "$TEST_DIR/proxy-domains.txt" >/dev/null \
    && pass "the real list renders" || fail "the real list renders" "non-zero exit"

echo "render-happ.py — server"
cat > "$SANDBOX/secrets.env" <<'EOF'
VLESS_SERVER=203.0.113.7
VLESS_PORT=443
VLESS_UUID=11111111-2222-3333-4444-555555555555
VLESS_SNI=www.example.com
VLESS_PBK=pub_key-x
VLESS_SID=abcd
EOF
link="$("$SCRIPT" server "$SANDBOX/secrets.env")"
assert_contains "$link" "vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?" "builds the vless address"
for p in security=reality flow=xtls-rprx-vision sni=www.example.com pbk=pub_key-x sid=abcd fp=chrome; do
    assert_contains "$link" "$p" "carries $p, matching the sing-box outbound"
done
sed -i '' '/VLESS_PBK/d' "$SANDBOX/secrets.env"
"$SCRIPT" server "$SANDBOX/secrets.env" >/dev/null 2>&1 \
    && fail "refuses incomplete secrets" "exit 0" || pass "refuses incomplete secrets"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
