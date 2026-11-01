#!/bin/bash
# Tests for render.py. Renders against the real config.template.json — a
# fixture template would let the template and the renderer drift apart, which
# is exactly the failure that produces a silently wrong routing config. Domain
# lists and secrets are throwaway files in a sandbox; nothing is installed and
# sing-box is never invoked.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/render.py"
TEMPLATE="$TEST_DIR/config.template.json"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then pass "$label"
    else fail "$label" "expected [$expected] got [$actual]"; fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) pass "$label" ;;
        *) fail "$label" "[$needle] not found in [$haystack]" ;;
    esac
}

# assert_fails <label> -- <cmd...>  (any non-zero exit counts as a failure)
assert_fails() {
    local label="$1"; shift 2
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" != "0" ]; then pass "$label"
    else fail "$label" "expected non-zero exit, got 0; output: $out"; fi
}

new_sandbox() {
    ROOT="$(mktemp -d)"
    OUT="$ROOT/config.json"
    cat > "$ROOT/secrets.env" <<'EOF'
VLESS_SERVER=203.0.113.10
VLESS_PORT=443
VLESS_UUID=00000000-0000-0000-0000-000000000000
VLESS_SNI=example.com
VLESS_PBK=testpublickey
VLESS_SID=abcd
EOF
    printf 'anthropic.com\n' > "$ROOT/direct.txt"
    printf 'reddit.com\n' > "$ROOT/block.txt"
    : > "$ROOT/reader.txt"
}

render() {
    "$SCRIPT" "$TEMPLATE" "$ROOT/direct.txt" "$ROOT/block.txt" "$ROOT/reader.txt" \
        "$ROOT/secrets.env" "$OUT"
}

# Read a value out of the rendered config. $1 is a python expression over `c`.
q() { python3 -c "
import json,sys
c=json.load(open('$OUT'))
print($1)
" 2>&1; }

echo "render.py"

# --- the inversion itself ----------------------------------------------------
# Everything not listed goes through the VPS: unmatched traffic hits the proxy
# outbound, and unmatched DNS hits the resolver that reaches it through the
# tunnel. There is no selector left to flip that at runtime.
new_sandbox
render >/dev/null 2>&1

assert_eq "proxy" "$(q "c['route']['final']")" \
    "unmatched traffic is proxied"
assert_eq "dns-proxy" "$(q "c['dns']['final']")" \
    "unmatched DNS goes through the tunnel"
assert_eq "0" "$(q "len([o for o in c['outbounds'] if o['type']=='selector'])")" \
    "no selector outbound to flip at runtime"

# --- blocked domains reach both rule sets ------------------------------------
# render.py's own docstring warns that DNS and route rules diverging is a
# silent leak; the same argument applies to a block that only covers one.
new_sandbox
printf 'reddit.com\npikabu.ru\n' > "$ROOT/block.txt"
render >/dev/null 2>&1

assert_eq "['reddit.com', 'pikabu.ru']" \
    "$(q "[r for r in c['route']['rules'] if r.get('action')=='reject'][0]['domain']")" \
    "route reject rule carries the apex domains"

assert_eq "['.reddit.com', '.pikabu.ru']" \
    "$(q "[r for r in c['route']['rules'] if r.get('action')=='reject'][0]['domain_suffix']")" \
    "route reject rule carries dotted suffixes for subdomains"

assert_eq "['reddit.com', 'pikabu.ru']" \
    "$(q "[r for r in c['dns']['rules'] if r.get('action')=='reject'][0]['domain']")" \
    "dns reject rule carries the apex domains"

# --- first-match ordering ----------------------------------------------------
# route.rules is first-match. A blocked domain that also matched the direct rule
# would go out instead of being rejected if the direct rule came first.
new_sandbox
render >/dev/null 2>&1

assert_eq "True" \
    "$(q "min(i for i,r in enumerate(c['route']['rules']) if r.get('action')=='reject') < min(i for i,r in enumerate(c['route']['rules']) if r.get('outbound')=='direct' and 'domain' in r)")" \
    "route reject rule precedes the direct rule"

assert_eq "True" \
    "$(q "min(i for i,r in enumerate(c['dns']['rules']) if r.get('action')=='reject') < min(i for i,r in enumerate(c['dns']['rules']) if r.get('server')=='dns-local')")" \
    "dns reject rule precedes the dns-local rule"

# --- empty direct list -------------------------------------------------------
# An empty direct list means everything is proxied, which is the intent. It
# must drop the rule rather than emit "domain": [], which matches nothing but
# invites the reader to think direct routing is configured.
new_sandbox
: > "$ROOT/direct.txt"
render >/dev/null 2>&1

assert_eq "0" "$(q "len([r for r in c['route']['rules'] if r.get('outbound')=='direct' and 'domain' in r])")" \
    "empty direct list leaves no route direct rule"
assert_eq "0" "$(q "len([r for r in c['dns']['rules'] if r.get('server')=='dns-local'])")" \
    "empty direct list leaves no dns-local rule"
assert_eq "True" "$(q "any(r.get('ip_is_private') for r in c['route']['rules'])")" \
    "empty direct list leaves the private-network rule intact"
assert_eq "proxy" "$(q "c['route']['final']")" \
    "empty direct list still proxies by default"

# A direct list of nothing but comments is the same as an empty one.
new_sandbox
printf '# everything through the VPS right now\n\n' > "$ROOT/direct.txt"
render >/dev/null 2>&1
assert_eq "0" "$(q "len([r for r in c['route']['rules'] if r.get('outbound')=='direct' and 'domain' in r])")" \
    "comment-only direct list leaves no direct rule"

# --- empty blocklist ---------------------------------------------------------
# An empty blocklist is legitimate. It must drop the rules rather than emit
# "domain": [], which matches nothing but invites the reader to think blocking
# is configured.
new_sandbox
: > "$ROOT/block.txt"
render >/dev/null 2>&1

assert_eq "0" "$(q "len([r for r in c['route']['rules'] if r.get('action')=='reject'])")" \
    "empty blocklist leaves no route reject rule"
assert_eq "0" "$(q "len([r for r in c['dns']['rules'] if r.get('action')=='reject'])")" \
    "empty blocklist leaves no dns reject rule"
assert_eq "True" "$(q "any(r.get('outbound')=='direct' and 'domain' in r for r in c['route']['rules'])")" \
    "empty blocklist leaves the direct rule intact"

# A blocklist of nothing but comments is the same as an empty one.
new_sandbox
printf '# nothing blocked right now\n\n' > "$ROOT/block.txt"
render >/dev/null 2>&1
assert_eq "0" "$(q "len([r for r in c['route']['rules'] if r.get('action')=='reject'])")" \
    "comment-only blocklist leaves no reject rule"

# --- overlap between the two lists -------------------------------------------
# Block wins on first-match, so an overlap silently disables a direct entry.
# That is always a mistake, so refuse rather than pick a winner.
new_sandbox
printf 'anthropic.com\nreddit.com\n' > "$ROOT/direct.txt"
printf 'reddit.com\n' > "$ROOT/block.txt"

assert_fails "overlapping domain refuses to render" -- render
out="$(render 2>&1)"
assert_contains "$out" "reddit.com" "overlap error names the offending domain"

# --- reader exceptions -------------------------------------------------------
# A reader domain is blocked for everything except the feed reader, so the
# allow rule has to carry process_name, be reachable before the reject, and
# follow the default: its traffic is tunnelled and resolved through the tunnel.
new_sandbox
printf 'reddit.com\n' > "$ROOT/block.txt"
printf 'reddit.com\n' > "$ROOT/reader.txt"
render >/dev/null 2>&1

assert_eq "['newsboat']" \
    "$(q "[r for r in c['route']['rules'] if 'process_name' in r][0]['process_name']")" \
    "route allow rule matches on the reader process"
assert_eq "['reddit.com']" \
    "$(q "[r for r in c['route']['rules'] if 'process_name' in r][0]['domain']")" \
    "route allow rule carries the reader domain"
assert_eq "['newsboat']" \
    "$(q "[r for r in c['dns']['rules'] if 'process_name' in r][0]['process_name']")" \
    "dns allow rule matches on the reader process"

assert_eq "proxy" \
    "$(q "[r for r in c['route']['rules'] if 'process_name' in r][0]['outbound']")" \
    "route allow rule follows the proxied default"
assert_eq "dns-proxy" \
    "$(q "[r for r in c['dns']['rules'] if 'process_name' in r][0]['server']")" \
    "dns allow rule resolves through the tunnel"

assert_eq "True" \
    "$(q "min(i for i,r in enumerate(c['route']['rules']) if 'process_name' in r) < min(i for i,r in enumerate(c['route']['rules']) if r.get('action')=='reject')")" \
    "route allow rule precedes the reject rule"
assert_eq "True" \
    "$(q "min(i for i,r in enumerate(c['dns']['rules']) if 'process_name' in r) < min(i for i,r in enumerate(c['dns']['rules']) if r.get('action')=='reject')")" \
    "dns allow rule precedes the reject rule"

# --- a reader domain that is not blocked is a no-op ---------------------------
# Nothing is being excepted from, so the entry does nothing. Always a mistake.
new_sandbox
printf 'reddit.com\n' > "$ROOT/block.txt"
printf 'pikabu.ru\n' > "$ROOT/reader.txt"
assert_fails "unblocked reader domain refuses to render" -- render
out="$(render 2>&1)"
assert_contains "$out" "pikabu.ru" "unblocked-reader error names the offending domain"

# --- empty reader list --------------------------------------------------------
new_sandbox
: > "$ROOT/reader.txt"
render >/dev/null 2>&1
assert_eq "0" "$(q "len([r for r in c['route']['rules'] if 'process_name' in r])")" \
    "empty reader list leaves no route allow rule"
assert_eq "0" "$(q "len([r for r in c['dns']['rules'] if 'process_name' in r])")" \
    "empty reader list leaves no dns allow rule"
assert_eq "1" "$(q "len([r for r in c['route']['rules'] if r.get('action')=='reject'])")" \
    "empty reader list leaves blocking intact"

# --- a secret containing __ is not a leftover placeholder ---------------------
# REALITY public keys are base64url, which uses underscores, so a key can
# contain "__" by chance. The unsubstituted-placeholder guard used to run after
# secret substitution and read that as a leftover marker, failing the render
# for one key in some and rendering fine after regenerating — the worst kind of
# intermittent.
new_sandbox
cat > "$ROOT/secrets.env" <<'EOF'
VLESS_SERVER=203.0.113.10
VLESS_PORT=443
VLESS_UUID=00000000-0000-0000-0000-000000000000
VLESS_SNI=example.com
VLESS_PBK=abc__def__ghi
VLESS_SID=abcd
EOF
render >/dev/null 2>&1
assert_eq "0" "$?" "a secret containing __ still renders"
assert_eq "abc__def__ghi" \
    "$(q "c['outbounds'][0]['tls']['reality']['public_key']")" \
    "the double underscore survives into the rendered config"

# --- a genuinely unknown placeholder is still caught --------------------------
new_sandbox
TEMPLATE_ORIG="$TEMPLATE"
TEMPLATE="$ROOT/broken-template.json"
sed 's|"log"|"__NOT_A_REAL_MARKER__": 1, "log"|' "$TEMPLATE_ORIG" > "$TEMPLATE"
assert_fails "an unknown __MARKER__ in the template refuses to render" -- render
TEMPLATE="$TEMPLATE_ORIG"

# --- argument handling -------------------------------------------------------
new_sandbox
assert_fails "wrong argument count refuses to render" -- \
    "$SCRIPT" "$TEMPLATE" "$ROOT/direct.txt" "$ROOT/block.txt" "$ROOT/secrets.env" "$OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
