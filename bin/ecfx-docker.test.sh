#!/bin/bash
# Tests for bin/ecfx-docker. docker, pgrep and ps are stubbed on PATH, so
# nothing here touches a real daemon; the docker stub logs every call it gets
# and moves containers between its running and exited lists the way the real
# one would.
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
cat > "$FIX/ps.orig" <<'EOF'
ecfx_postgres	ecfx-backend	postgres	Up 36 minutes
ecfx_rabbit	ecfx-18785	rabbit	Up 36 minutes
billing_api	billing	api	Up 2 hours
ryuk-9f3c1a			Up 1 hour
EOF
cat > "$FIX/ps_all.orig" <<'EOF'
ecfx-workspace-redis-1	ecfx-workspace	redis	Exited (0) 5 hours ago
EOF
: > "$FIX/pgrep.txt"
: > "$FIX/ps_args.txt"

reset_stack() { # every ECFX container running again, daemon up, log clean
    cp "$FIX/ps.orig" "$FIX/ps.txt"
    cp "$FIX/ps_all.orig" "$FIX/ps_all.txt"
    : > "$FIX/daemon_up"
    : > "$LOG"
}
reset_stack

cat > "$STUBS/docker" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
daemon_err() { echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock.' >&2; exit 1; }
drop_from() { # drop_from FILE NAME...
    local f="\$1"; shift
    local n
    for n in "\$@"; do
        grep -v "^\$n" "\$f" > "\$f.new" || true
        mv "\$f.new" "\$f"
    done
}
case "\$1" in
    info)
        [ -f "$FIX/daemon_up" ] || exit 1
        ;;
    desktop)
        case "\${2:-}" in
            version) echo 'Docker Desktop CLI version: v0.1.0' ;;
            start) : > "$FIX/daemon_up" ;;
            stop) rm -f "$FIX/daemon_up" ;;
        esac
        ;;
    ps)
        [ -f "$FIX/daemon_up" ] || daemon_err
        for a in "\$@"; do
            if [ "\$a" = --all ]; then cat "$FIX/ps_all.txt"; exit 0; fi
        done
        cat "$FIX/ps.txt"
        ;;
    stop)
        [ -f "$FIX/daemon_up" ] || daemon_err
        shift
        skip=0
        for a in "\$@"; do
            if [ "\$skip" = 1 ]; then skip=0; continue; fi
            case "\$a" in
                -t) skip=1; continue ;;
                -*) continue ;;
            esac
            drop_from "$FIX/ps.txt" "\$a"
            printf '%s\tecfx-backend\tstub\tExited (0) just now\n' "\$a" >> "$FIX/ps_all.txt"
        done
        ;;
    start)
        [ -f "$FIX/daemon_up" ] || daemon_err
        shift
        for a in "\$@"; do
            case "\$a" in -*) continue ;; esac
            drop_from "$FIX/ps_all.txt" "\$a"
            printf '%s\tecfx-backend\tstub\tUp 2 seconds\n' "\$a" >> "$FIX/ps.txt"
        done
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
snapshot() { cat "$STATE/paused" 2>/dev/null; }

echo "ecfx-docker — status"
out="$(run status)"
assert_contains "$out" "docker desktop: up" "reports the daemon state"
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
assert_lacks "$(cat "$LOG")" "stop -t 30 billing_api" "never touches another project's container"
assert_eq "ecfx_postgres
ecfx_rabbit" "$(snapshot)" "snapshots what it stopped"
assert_contains "$(cat "$LOG")" "desktop stop" "then quits Docker Desktop"
assert_contains "$out" "Docker Desktop stopped" "and says so"
out="$(run status)"
assert_contains "$out" "docker desktop: stopped" "status reports the daemon down"
assert_contains "$out" "(daemon stopped)" "and does not pretend to list containers"
assert_contains "$out" "ecfx_postgres" "while the pause snapshot survives it"

echo "ecfx-docker — pause with the daemon already down"
: > "$LOG"
out="$(run pause)"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_contains "$out" "already stopped" "and says the daemon is already down"
assert_eq "ecfx_postgres
ecfx_rabbit" "$(snapshot)" "keeps the snapshot resume needs"
assert_eq 0 "$(stops)" "issues no container stop it cannot see"

echo "ecfx-docker — a second pause keeps the resume list"
: > "$FIX/daemon_up"   # the daemon is back, the containers are still stopped
: > "$LOG"
out="$(run pause)"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_contains "$out" "nothing running" "with nothing left to stop"
assert_eq "ecfx_postgres
ecfx_rabbit" "$(snapshot)" "and still knows what to resume"
assert_eq 0 "$(stops)" "issuing no stop"
out="$(run resume)"; rc=$?
assert_eq 0 "$rc" "so resume still works"
assert_contains "$(cat "$LOG")" "start ecfx_postgres ecfx_rabbit" "starting both"

echo "ecfx-docker — pause while a check is marked busy"
reset_stack
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

echo "ecfx-docker — a busy label that is an MR ref"
reset_stack
run busy-on 'ecfx/ecfx-backend!6889' > /dev/null
out="$(run status)"
assert_contains "$out" "busy: check marked busy: ecfx_ecfx-backend!6889" "the slash becomes an underscore, not a directory"
assert_eq 0 "$(find "$STATE/busy" -mindepth 1 -type d | wc -l)" "nothing nested was created"
out="$(run pause)"; rc=$?
assert_eq 1 "$rc" "and it still holds pause"
run busy-off 'ecfx/ecfx-backend!6889' > /dev/null
out="$(run status)"
assert_contains "$out" "busy: no" "busy-off clears it by the same ref"

echo "ecfx-docker — pause while a test process runs"
reset_stack
echo 4242 > "$FIX/pgrep.txt"
echo '/usr/bin/java -cp x GradleWorkerMain daemon' > "$FIX/ps_args.txt"
out="$(run pause)"; rc=$?
assert_eq 1 "$rc" "refuses to stop during a test run"
assert_contains "$out" "test or build running" "and says why"
assert_eq 0 "$(stops)" "no stop was issued"

echo "ecfx-docker — an agent's task text is not a test run"
reset_stack
echo 'node /x/pi-subagents/runner-peer-preload.mjs run npx vitest run src/a.test.ts' > "$FIX/ps_args.txt"
out="$(run pause)"; rc=$?
assert_eq 0 "$rc" "pauses when only an agent process mentions a test runner"
assert_contains "$out" "stopped 2" "and stops the stack"

echo "ecfx-docker — pause --force"
reset_stack
echo '/usr/bin/java -cp x GradleWorkerMain daemon' > "$FIX/ps_args.txt"
run busy-on 'backend!6851' > /dev/null
out="$(run pause --force)"; rc=$?
assert_eq 0 "$rc" "--force stops it anyway"
assert_eq 1 "$(stops)" "one stop was issued"
run busy-off 'backend!6851' > /dev/null
: > "$FIX/pgrep.txt"

echo "ecfx-docker — resume starts the daemon first"
: > "$LOG"
out="$(run resume)"; rc=$?
assert_eq 0 "$rc" "exits 0"
assert_contains "$(cat "$LOG")" "desktop start" "brings Docker Desktop back"
assert_contains "$out" "Docker Desktop up" "and reports it"
assert_contains "$(cat "$LOG")" "start ecfx_postgres ecfx_rabbit" "then starts exactly what pause stopped"
assert_eq "" "$(snapshot)" "and clears the snapshot"
out="$(run resume)"; rc=$?
assert_eq 1 "$rc" "with no snapshot and no names it refuses to guess"
out="$(run resume ecfx_postgres)"; rc=$?
assert_eq 0 "$rc" "an explicit name always works"
assert_contains "$(cat "$LOG")" "start ecfx_postgres" "and starts that one"

echo "ecfx-docker — daemon-up"
: > "$LOG"
out="$(run daemon-up)"; rc=$?
assert_eq 0 "$rc" "exits 0 when the daemon is already up"
assert_contains "$out" "already up" "and says so"
assert_lacks "$(cat "$LOG")" "desktop start" "without touching Docker Desktop"
rm -f "$FIX/daemon_up"
: > "$LOG"
out="$(run daemon-up)"; rc=$?
assert_eq 0 "$rc" "exits 0 from a cold start"
assert_contains "$(cat "$LOG")" "desktop start" "starts Docker Desktop"
assert_contains "$out" "no containers started" "and says it left the stack alone"
assert_eq 0 "$(grep -c '^start ecfx' "$LOG" 2>/dev/null || true)" "starting no container"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
