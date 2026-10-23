#!/bin/bash
# Tests for bin/gitlab-api-guard, the PreToolUse hook that keeps GitLab API
# writes to JSON bodies from a file. Each case feeds it the JSON Claude Code
# (and pi's claude-hooks extension) sends for a Bash call.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/gitlab-api-guard"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
run() { # run <command> -> exit code of the hook
    jq -n --arg c "$1" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
        | "$SCRIPT" >/dev/null 2>"$ERR"
}
blocks() { run "$2"; local code=$?; [ "$code" -eq 2 ] && pass "$1" || fail "$1" "exit $code for: $2"; }
allows() { run "$2"; local code=$?; [ "$code" -eq 0 ] && pass "$1" || fail "$1" "exit $code for: $2 ($(cat "$ERR"))"; }
says() { # says <name> <command> <text the reason must contain>
    run "$2"
    case "$(cat "$ERR")" in *"$3"*) pass "$1" ;; *) fail "$1" "reason: $(cat "$ERR")" ;; esac
}

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

API=https://gitlab.com/api/v4/projects/123/merge_requests/9/notes
JSON="-H 'Content-Type: application/json'"

echo "body from stdin"
blocks "glab api --input -" "glab api projects/123/merge_requests/9/notes -X POST --input -"
blocks "glab api --input=-" "glab api projects/123/issues -X POST --input=-"
blocks "glab api --input /dev/stdin" "glab api projects/123/issues -X POST --input /dev/stdin"
blocks "piped into glab api" "jq -n '{body:\"hi\"}' | glab api projects/123/merge_requests/9/notes -X POST --input -"
blocks "heredoc into glab api" "glab api projects/123/merge_requests/9/notes -X POST --input - <<'EOF'
{\"body\": \"it's done\"}
EOF"
blocks "curl --data @-" "echo '{}' | curl -X POST $JSON --data @- $API"
blocks "curl -d @-" "curl $JSON -d @- $API < body.json"
blocks "curl -d@- attached" "curl $JSON -d@- $API"
blocks "curl --data-binary @-" "printf '{}' | curl $JSON --data-binary @- $API"
blocks "curl --data=@/dev/stdin" "curl $JSON --data=@/dev/stdin $API"
blocks "curl --json @-" "echo '{}' | curl --json @- $API"
blocks "curl heredoc" "curl -sS $JSON --data @- $API <<EOF
{\"body\": \"x\"}
EOF"
blocks "curl here-string" "curl $JSON --data @- $API <<< \"\$body\""
blocks "inside bash -c" "bash -c \"echo {} | glab api projects/1/issues -X POST --input -\""
blocks "after cd and &&" "cd /tmp && glab api projects/1/issues --method POST --input -"
blocks "with env prefix" "GITLAB_TOKEN=\$(secret GITLAB_TOKEN) curl $JSON --data @- $API"
says "says how to send it" "glab api x --input -" "--input body.json"

echo "curl write without a JSON content type"
blocks "-X POST with -d" "curl -X POST -d '{\"body\":\"x\"}' $API"
blocks "--request PUT" "curl --request PUT --data @body.json $API"
blocks "-XPATCH clustered" "curl -sSXPATCH --data @b.json $API"
blocks "-d alone implies POST" "curl -H 'PRIVATE-TOKEN: t' -d @body.json $API"
blocks "--data-raw" "curl -X POST --data-raw '{\"a\":1}' $API"
blocks "only a token header" "curl -X POST --header \"PRIVATE-TOKEN: \$(secret GITLAB_TOKEN)\" --data @b.json $API"
blocks "-X POST with no body" "curl -X POST https://gitlab.com/api/v4/projects/1/merge_requests/2/approve"
blocks "over --url" "curl -X POST --data @b.json --url $API"
blocks "line continuation" "curl -X POST \\
  --data @b.json \\
  $API"
says "says which header" "curl -X POST -d @b.json $API" "Content-Type: application/json"

echo "allowed"
allows "curl GET" "curl -sS -H 'PRIVATE-TOKEN: t' $API"
allows "curl -X GET" "curl -X GET $API"
allows "curl -G with -d query" "curl -G -d per_page=100 $API"
allows "curl DELETE" "curl -X DELETE $API/5"
allows "curl POST with JSON header and file" "curl -X POST $JSON --data @body.json $API"
allows "header case and charset" "curl -X PUT -H 'content-type:application/json; charset=utf-8' -d @b.json $API"
allows "--header= form" "curl -X POST --header='Content-Type: application/json' -d @b.json $API"
allows "headers from a file" "curl -X POST -H @headers.txt -d @b.json $API"
allows "--json from a file" "curl --json @body.json $API"
allows "-F upload" "curl -X POST -F file=@shot.png https://gitlab.com/api/v4/projects/1/uploads"
allows "--data-raw '@-' is literal, not stdin" "curl $JSON --data-raw '@-' $API"
allows "other host, stdin body" "echo '{}' | curl -X POST --data @- https://example.com/api"
allows "other host, no header" "curl -X POST -d a=b https://hooks.slack.com/x"
allows "URL in a variable" "curl -X POST -d @b.json \"\$GITLAB_API/projects/1/notes\""
allows "glab api -f fields" "glab api projects/123/merge_requests/9/notes -X POST -f body=hi"
allows "glab api -F fields" "glab api projects/123/issues -X POST -F title=x -F confidential=true"
allows "glab api --input file" "glab api projects/123/merge_requests/9 -X PUT --input body.json"
allows "glab api GET" "glab api projects/123/merge_requests/9"
allows "glab api piped out" "glab api projects/123/merge_requests | jq '.[].iid'"
allows "stdin piped into glab, no --input" "echo x | glab api projects/1/issues -X POST -f title=x"
allows "glab mr note" "glab mr note 9 -m 'done'"
allows "words in a commit message" "git commit -m 'refuse curl -X POST --data @- to gitlab.com/api'"
allows "grep for it" "rg -n 'glab api .* --input -' bin/"
allows "echo of a curl line" "echo curl -X POST -d @b.json $API"
allows "unbalanced quote passes" "curl -X POST -d '{ $API"
allows "ordinary command" "git status"

echo "other calls"
printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' | "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "non-Bash tools pass" || fail "non-Bash tools pass" "blocked"
printf 'not json' | "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "bad input never blocks" || fail "bad input never blocks" "blocked"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
