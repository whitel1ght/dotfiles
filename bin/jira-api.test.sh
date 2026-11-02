#!/usr/bin/env bash
# jira-api contract tests; curl is stubbed and credentials are disposable values.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$JIRA_CURL_LOG"
echo '{"ok":true}'
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH" JIRA_CURL_LOG="$TMP/curl.log" JIRA_EMAIL=test@example.invalid JIRA_API_TOKEN=fixture-token
out="$("$ROOT/bin/jira-api" GET issue/ECFX-1)"
[[ "$out" == '{"ok":true}' ]]
grep -Fx -- '-u' "$JIRA_CURL_LOG" >/dev/null
grep -Fx -- 'test@example.invalid:fixture-token' "$JIRA_CURL_LOG" >/dev/null
grep -Fx -- 'https://ecfxdev.atlassian.net/rest/api/3/issue/ECFX-1' "$JIRA_CURL_LOG" >/dev/null
out="$("$ROOT/bin/jira-api" POST issue/ECFX-1 '{"a":1}')"
grep -Fx -- '{"a":1}' "$JIRA_CURL_LOG" >/dev/null
if env -u JIRA_EMAIL -u JIRA_API_TOKEN PATH="$TMP/bin:$PATH" "$ROOT/bin/jira-api" GET issue/X >/dev/null 2>&1; then
  echo 'FAIL: missing credentials should stop before curl' >&2; exit 1
fi
echo 'PASS jira-api stubbed request contract'
