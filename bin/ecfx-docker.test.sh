#!/bin/bash
# Tests for bin/ecfx-docker. docker, pgrep and ps are stubbed on PATH, so
# nothing here touches a real daemon; the docker stub logs every call it gets.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/ecfx-docker"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"; STATE="$SANDBOX/state"
LOG="$SANDBOX/docker.log"
mkdir -p "$STUBS" "$FIX" "$STATE"

# name<TAB>compose project<TAB>service<TAB>status. Two ECFX stacks (the backend
# clone and a worktree), one unrelated project, and a TestContainers leftover
# with no compose labels at all.
printf 'ecfx_postgres\tecfx-backend\tpostgres\tUp 36 minutes\n' > "$FIX/ps.txt"
printf 'ecfx_rabbit\tecfx-18785\trabbit\tUp 36 minutes\n' >> "$FIX/ps.txt"
printf 'billing_api\tbilling\tapi\tUp 2 hours\n' >> "$FIX/ps.txt"
printf 'ryuk-9f3c1a\t\t\tUp 1 hour\n' >> "$FIX/ps.txt"
printf 'ecfx-workspace-redis-1\tecfx-workspace\tredis\tExited (0) 5 hours ago\n' > "$FIX/ps_all.txt"
: > "$FIX/pgrep.txt"
: > "$FIX/ps_args.txt"

cat > "$STUBS/docker" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
case "\$1" in
    ps)
        for a in "\$@"; do
            if [ "\$a" = --all ]; then cat "$FIX/ps_all.txt"; exit 0; fi
        done
        cat "$FIX/ps.txt"
        ;;
esac
exit 0
EOF
cat > "$STUBS/pgrep" <<'EOF'
#!/bin/bash
[ -s "$FIX/pgrep.txt" ] || exit 1
cat "$FIX/pgrep.txt"
EOF
cat > "$STUBS/ps" <<'EOF'
#!/bin/bash
cat "$FIX/ps_args.txt"
EOF
chmod +x "$STUBS/docker" "$STUBS/pgrep" "$STUBS/ps"

run() {
    PATH="$STUBS:$PATH" FIX="$FIX" ECFX_DOCKER_STATE="$STATE" "$SCRIPT" "$@" 2>&1
}
stops() { grep -c '^stop ' "$LOG" 2>/dev/null || true; }

echo "ecfx-docker — status"
out="$(run status)"
assert_contains "$out" "ecfx_postgres" "lists a running ECFX container"
assert_contains "$out" "ecfx-backend/postgres" "with its compose project and service"
assert_contains "$out" "ecfx_rabbit" "and the worktree stack's container"
assert_lacks "$out" "billing_api" "ignores another project's container"
assert_lacks "$out" "ryuk-9f3c1a" "ignores a TestContainers leftover with no compose labels"
assert_contains "$out" "busy: no" "reports idle when nothing is marked or running"

echo "ecfx-docker — pause"
out="$(run pause)"; rc=$?
assert_eq 0 "$rc" "exits 0 when idle"
assert_contains "$out" "stopped 2" "stops both ECFX containers"
assert_contains "$(cat "$LOG")" "stop -t 30 ecfx_postgres ecfx_rabbit" "asks for a graceful stop of exactly those two"
assert_lacks "$(cat "$LOG")" "billing_api" "never touches another project's container"
assert_eq "ecfx_postgres
ecfx_rabbit" "$(cat "$STATE/paused")" "snapshots what it stopped"

echo "ecfx-docker — pause while a check is marked busy"
: > "$LOG"
run busy-on 'backend!6842' > /dev/null
out="$(run pause)"; rc=$?
assert_eq 1 "$rc" "refuses to stop"
assert_contains "$out" "backend!6842" "and names the busy check"
assert_eq 0 "$(stops)" "no stop was issued"
out="$(run status)"
assert_contains "$out" "busy: check marked busy: backend!6842" "status shows the busy label"
run busy-off 'backend!6842' > /dev/null
out="$(run status)"
assert_contains "$out" "busy: no" "busy-off clears it"

echo "ecfx-docker — pause while a test process runs"
: > "$LOG"
echo 4242 > "$FIX/pgrep.txt"
echo '/usr/bin/java -cp x GradleWorkerMain daemon' > "$FIX/ps_args.txt"
out="$(run pause)"; rc=$?
assert_eq 1 "$rc" "refuses to stop during a test run"
assert_contains "$out" "test or build running" "and says why"
assert_eq 0 "$(stops)" "no stop was issued"

echo "ecfx-docker — an agent's task text is not a test run"
echo 'node /x/pi-subagents/runner-peer-preload.mjs run npx vitest run src/a.test.ts' > "$FIX/ps_args.txt"
out="$(run pause)"; rc=$?
assert_eq 0 "$rc" "pauses when only an agent process mentions a test runner"
assert_contains "$out" "stopped 2" "and stops the stack"

echo "ecfx-docker — pause --force"
: > "$LOG"
echo '/usr/bin/java -cp x GradleWorkerMain daemon' > "$FIX/ps_args.txt"
run busy-on 'backend!6851' > /dev/null
out="$(run pause --force)"; rc=$?
assert_eq 0 "$rc" "--force stops it anyway"
assert_eq 1 "$(stops)" "one stop was issued"
run busy-off 'backend!6851' > /dev/null
: > "$FIX/pgrep.txt"

echo "ecfx-docker — resume"
: > "$LOG"
out="$(run resume)"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_contains "$(cat "$LOG")" "start ecfx_postgres ecfx_rabbit" "starts exactly what pause stopped"
assert_eq "" "$(cat "$STATE/paused")" "and clears the snapshot"
out="$(run resume)"; rc=$?
assert_eq 1 "$rc" "with no snapshot and no names it refuses to guess"
out="$(run resume ecfx_postgres)"; rc=$?
assert_eq 0 "$rc" "an explicit name always works"
assert_contains "$(cat "$LOG")" "start ecfx_postgres" "and starts that one"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
