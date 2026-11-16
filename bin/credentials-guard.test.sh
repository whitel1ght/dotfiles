#!/bin/bash
# Tests for bin/credentials-guard, the PreToolUse hook that keeps stored
# credentials (CI variables, keyrings, credential files) out of agent transcripts.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${CREDENTIALS_GUARD_UNDER_TEST:-$TEST_DIR/credentials-guard}"
PY="$(command -v python3)"
PASS=0
FAIL=0
ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

run() {
    jq -n --arg c "$1" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
        | "$PY" "$SCRIPT" >/dev/null 2>"$ERR"
}
blocks() { run "$1"; local code=$?; [ "$code" -eq 2 ] && pass "blocks: $1" || fail "blocks: $1" "exit $code"; }
allows() { run "$1"; local code=$?; [ "$code" -eq 0 ] && pass "allows: $1" || fail "allows: $1" "exit $code ($(cat "$ERR"))"; }

echo "GitLab CI/CD variables (what the 2026-11-16 fixer did)"
blocks 'glab variable get DUPLO_TOKEN_PROD -R ecfx/ecfx-observability > /tmp/var_DUPLO_TOKEN_PROD'
blocks 'glab variable list -R ecfx/ecfx-observability'
blocks 'glab variable export --group ecfx'
blocks 'glab api projects/84206032/variables/SLACK_WEBHOOK_PROD | jq -r .value'
blocks 'glab api "groups/ecfx/variables?per_page=100"'
blocks 'curl -s -H "PRIVATE-TOKEN: x" https://gitlab.com/api/v4/projects/1/variables'
allows 'glab api projects/84206032/merge_requests/90'
allows 'glab mr view 90 -R ecfx/ecfx-observability'
allows 'rg -n "variables" src/'

echo "token stores"
blocks 'secret-tool lookup service glab'
blocks 'security find-generic-password -s gitlab -w'
blocks 'glab auth status --show-token'
blocks 'glab auth status -h gitlab.com -t'
blocks 'glab config get token --host gitlab.com'
blocks 'gh auth token'
blocks 'printf "host=gitlab.com\n" | git credential fill'
allows 'glab auth status'
allows 'git config --get user.email'

echo "credential files"
blocks 'cat ~/.aws/credentials'
blocks "grep -A3 default /home/dmitry/.aws/credentials"
blocks 'cat ~/.config/glab-cli/config.yml'
blocks 'jq . ~/.docker/config.json'
blocks 'cat ~/.netrc'
blocks 'cat ~/.pgpass'
blocks 'cat ~/.git-credentials'
blocks 'aws configure get aws_secret_access_key'
blocks 'aws configure export-credentials --format env'
allows 'aws sts get-caller-identity'
allows 'cat ~/.aws/config'

echo "CodeArtifact"
blocks 'aws codeartifact get-authorization-token --domain ecfx --query authorizationToken --output text > /tmp/ca_token.txt'
blocks 'aws codeartifact get-authorization-token --domain ecfx --query authorizationToken --output text'
blocks 'T=$(aws codeartifact get-authorization-token --domain ecfx --output text); echo "$T" > /tmp/ca_token.txt'
allows 'export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain ecfx --query authorizationToken --output text) && ./gradlew test 2>&1 | tail -20'

echo "unreadable input passes"
echo 'not json' | "$PY" "$SCRIPT" >/dev/null 2>&1 && pass "garbage passes" || fail "garbage passes" "non-zero"
jq -n '{tool_name:"Read", tool_input:{file_path:"/x"}}' | "$PY" "$SCRIPT" >/dev/null 2>&1 && pass "other tools pass" || fail "other tools pass" "non-zero"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
