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
printf '# comment\nclaude.ai\n\nyoutube.com\n' > "$SANDBOX/direct.txt"

# profile_field <direct-list> <key> — read one key out of the decoded profile
profile_field() {
    local l; l="$("$SCRIPT" routing "$1")"
    echo "${l#happ://routing/onadd/}" | base64 -d \
        | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)[\"$2\"]))"
}

echo "render-happ.py — routing"
link="$("$SCRIPT" routing "$SANDBOX/direct.txt")"
assert_contains "$link" "happ://routing/onadd/" "emits an add-and-activate link"
assert_eq '["domain:claude.ai", "domain:youtube.com"]' "$(profile_field "$SANDBOX/direct.txt" DirectSites)" "keeps the listed apexes and their subdomains off the VPS"
assert_eq '[]' "$(profile_field "$SANDBOX/direct.txt" ProxySites)" "proxies nothing by name — the default covers it"
assert_eq '[]' "$(profile_field "$SANDBOX/direct.txt" BlockSites)" "blocks nothing on the phone"
assert_eq '"true"' "$(profile_field "$SANDBOX/direct.txt" GlobalProxy)" "everything unlisted goes through the VPS"
assert_eq '"direct-proxy-block"' "$(profile_field "$SANDBOX/direct.txt" RouteOrder)" "checks direct, then proxy, then block"
assert_eq '"DoU"' "$(profile_field "$SANDBOX/direct.txt" DomesticDNSType)" "unlisted DNS stays on the local resolver"
assert_eq '["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "127.0.0.0/8"]' \
    "$(profile_field "$SANDBOX/direct.txt" DirectIp)" "keeps the private networks off the VPS"

# An empty direct list means everything is proxied, which is the intent. The
# profile must render with no direct sites rather than refuse.
printf '# everything through the VPS right now\n' > "$SANDBOX/empty.txt"
"$SCRIPT" routing "$SANDBOX/empty.txt" >/dev/null 2>&1 \
    && pass "an empty direct list renders" || fail "an empty direct list renders" "non-zero exit"
decode() { local l; l="$("$SCRIPT" routing "$SANDBOX/empty.txt")"; echo "${l#happ://routing/onadd/}" | base64 -d; }
assert_eq '[]' "$(profile_field "$SANDBOX/empty.txt" DirectSites)" \
    "an empty direct list keeps nothing off the VPS"
assert_eq '"true"' "$(profile_field "$SANDBOX/empty.txt" GlobalProxy)" \
    "an empty direct list still proxies by default"
decode() { local l; l="$("$SCRIPT" routing "$SANDBOX/direct.txt")"; echo "${l#happ://routing/onadd/}" | base64 -d; }

"$SCRIPT" routing "$TEST_DIR/direct-domains.txt" >/dev/null \
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
