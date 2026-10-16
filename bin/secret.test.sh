#!/bin/bash
# Tests for bin/secret. SECRETS_FILE points at a sandbox file, so the real
# ~/.secrets is never read.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/secret"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { # check <label> <want> <got>
    [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export SECRETS_FILE="$SANDBOX/secrets.env"
cat > "$SECRETS_FILE" <<'EOF'
# Jira: the API token from id.atlassian.com
JIRA_TOKEN=tok-123
  JIRA_USER = me@example.com
QUOTED="has spaces"
SINGLE='single'
export EXPORTED=yes
WITH_EQUALS=a=b=c
EMPTY=
EOF

echo "secret NAME"
check "prints the value" "tok-123" "$("$SCRIPT" JIRA_TOKEN)"
check "trims spaces around name and value" "me@example.com" "$("$SCRIPT" JIRA_USER)"
check "strips double quotes" "has spaces" "$("$SCRIPT" QUOTED)"
check "strips single quotes" "single" "$("$SCRIPT" SINGLE)"
check "accepts an export prefix" "yes" "$("$SCRIPT" EXPORTED)"
check "keeps = inside the value" "a=b=c" "$("$SCRIPT" WITH_EQUALS)"
check "no trailing newline so \$(...) and pipes match" "7" "$("$SCRIPT" JIRA_TOKEN | wc -c | tr -d ' ')"

out="$("$SCRIPT" MISSING 2>&1)"; code=$?
check "missing name exits 1" "1" "$code"
case "$out" in *MISSING*) pass "names the missing secret" ;; *) fail "names the missing secret" "$out" ;; esac

"$SCRIPT" EMPTY >/dev/null 2>&1; check "empty value counts as missing" "1" "$?"
"$SCRIPT" "# Jira" >/dev/null 2>&1; check "comments are not names" "1" "$?"

out="$(SECRETS_FILE="$SANDBOX/nope" "$SCRIPT" JIRA_TOKEN 2>&1)"; code=$?
check "missing file exits 1" "1" "$code"
case "$out" in *nope*) pass "names the missing file" ;; *) fail "names the missing file" "$out" ;; esac

echo "secret -l"
check "lists names, not values" "JIRA_TOKEN JIRA_USER QUOTED SINGLE EXPORTED WITH_EQUALS" "$("$SCRIPT" -l | tr '\n' ' ' | sed 's/ $//')"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
