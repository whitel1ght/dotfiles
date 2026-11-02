#!/usr/bin/env bash
# Static integration checks for Pi prompts whose runtime commands are covered
# by their own disposable-fixture helper suites.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
STATUS="$ROOT/pi/prompts/status.md"
SYSTEM="$ROOT/pi/prompts/system.md"
DAILY="$ROOT/pi/extensions/daily"

# /status is a thin read-only view over the tested local CLI, not a second API client.
grep -Fq '~/.local/bin/day-status $ARGUMENTS' "$STATUS"
! grep -Eqi 'curl |glab |jira-api' "$STATUS"
bash "$ROOT/bin/day-status.test.sh" >/dev/null 2>&1

# /system's idle review is backed by the imported Pi ideas extension and bin helper.
grep -Fq 'ideas due' "$SYSTEM"
grep -Fq 'read ~/.pi/agent/prompts/ideas.md' "$SYSTEM"
grep -Fq 'import { IdeasNudger } from "./ideas.ts"' "$DAILY/index.ts"
test -f "$DAILY/ideas.ts" && test -x "$ROOT/bin/ideas"
echo 'PASS Pi status/system workflow contracts'
