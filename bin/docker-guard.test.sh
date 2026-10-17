#!/bin/bash
# Tests for bin/docker-guard, the PreToolUse hook that refuses a Gradle test run
# while Docker is down. A stub `docker` on PATH stands in for the daemon and
# records every call, so "allowed without calling docker" is checkable.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DOCKER_GUARD_UNDER_TEST:-$TEST_DIR/docker-guard}"
PY="$(command -v python3)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ERR="$WORK/err"
CALLS="$WORK/calls"
mkdir "$WORK/up" "$WORK/down" "$WORK/none"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 0\n' "$CALLS" > "$WORK/up/docker"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 1\n' "$CALLS" > "$WORK/down/docker"
chmod +x "$WORK/up/docker" "$WORK/down/docker"

run() { # run <docker state: up|down|none> <command> -> exit code of the hook
    : > "$CALLS"
    jq -n --arg c "$2" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
        | env PATH="$WORK/$1" "$PY" "$SCRIPT" >/dev/null 2>"$ERR"
}
blocks() { run "$2" "$3"; local code=$?; [ "$code" -eq 2 ] && pass "$1" || fail "$1" "exit $code for: $3"; }
allows() { run "$2" "$3"; local code=$?; [ "$code" -eq 0 ] && pass "$1" || fail "$1" "exit $code for: $3 ($(cat "$ERR"))"; }
skips() { # allowed and docker never called
    run "$2" "$3"; local code=$?
    if [ "$code" -ne 0 ]; then fail "$1" "exit $code for: $3"
    elif [ -s "$CALLS" ]; then fail "$1" "docker was called for: $3"
    else pass "$1"; fi
}

echo "docker down"
blocks "gradlew test" down './gradlew test'
blocks "bare gradle test" down 'gradle test'
blocks "module task with a filter" down "./gradlew :core_rest:test --tests '*Foo*'"
blocks "module check" down './gradlew :core_rest:check'
blocks "build" down './gradlew build'
blocks "integrationTest" down './gradlew integrationTest'
blocks "filter alone" down './gradlew --tests Foo'
blocks "after cd and &&" down 'cd backend && ./gradlew clean test'
blocks "inside bash -c" down 'bash -c "./gradlew test"'
blocks "with flags before the task" down './gradlew --no-daemon -p backend test'
blocks "with an unrelated env var" down 'CI=1 ./gradlew test'
blocks "-x of another task still runs test" down './gradlew test -x checkstyleMain'
run down './gradlew test'
case "$(cat "$ERR")" in *"Docker is not running"*"open -a Docker"*) pass "says why and how to fix" ;; *) fail "says why and how to fix" "$(cat "$ERR")" ;; esac

echo "docker up"
allows "gradlew test" up './gradlew test'
allows "module test with a filter" up "./gradlew :core_rest:test --tests '*Foo*'"

echo "docker missing"
blocks "gradlew test" none './gradlew test'

echo "no docker call needed"
skips "compileTestGroovy" down './gradlew compileTestGroovy'
skips "compileJava" down './gradlew :core_rest:compileJava'
skips "classes and assemble" down './gradlew classes assemble'
skips "-x test alone" down './gradlew classes -x test'
skips "--exclude-task test alone" down './gradlew assemble --exclude-task test'
skips "non-gradle command" down 'git status'
skips "the word test in another command" down 'npm test'
skips "gradle word in a path argument only" down 'cat docs/gradlew-notes.md'
skips "ordinary command, docker up" up 'ls'

echo "bypass"
skips "DOCKER_GUARD=off" down 'DOCKER_GUARD=off ./gradlew test'
skips "DOCKER_GUARD=off after another assignment" down 'CI=1 DOCKER_GUARD=off ./gradlew :core_rest:test'
blocks "DOCKER_GUARD=on does not bypass" down 'DOCKER_GUARD=on ./gradlew test'

echo "other calls"
printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' | env PATH="$WORK/down" "$PY" "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "non-Bash tools pass" || fail "non-Bash tools pass" "blocked"
printf 'not json' | env PATH="$WORK/down" "$PY" "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "bad input never blocks" || fail "bad input never blocks" "blocked"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
