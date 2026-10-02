#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
MEMORY="2304m"
FIRM="1"

usage() {
    echo "Usage: $0 <path-to-eml> [--memory 2304m] [--firm 1]"
    echo ""
    echo "Runs the CLI email-receipt processor inside Docker with memory limits."
    echo ""
    echo "Arguments:"
    echo "  <path-to-eml>   Path to .eml file (required)"
    echo "  --memory MEM    Container memory limit (default: 2304m)"
    echo "  --firm ID       Firm ID to process as (default: 1)"
    echo ""
    echo "Examples:"
    echo "  ./run-email.sh texas-inbox_xfjzl2ihv4i7dhjrzxbgckuzae.eml"
    echo "  ./run-email.sh texas-inbox_xfjzl2ihv4i7dhjrzxbgckuzae.eml --memory 512m"
    echo "  ./run-email.sh /absolute/path/to/notice.eml --firm 2 --memory 1024m"
    exit 1
}

# Must have at least one arg
if [ $# -lt 1 ]; then
    usage
fi

# First positional arg is the email path
EML_PATH="$1"
shift

# Parse optional flags
while [ $# -gt 0 ]; do
    case "$1" in
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --firm)
            FIRM="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            usage
            ;;
    esac
done

# Resolve to absolute path (handle both relative and absolute)
if [[ "$EML_PATH" != /* ]]; then
    # Relative path — resolve relative to current working directory
    EML_PATH="$(cd "$(dirname "$EML_PATH")" && pwd)/$(basename "$EML_PATH")"
fi

# Verify .eml file exists
if [ ! -f "$EML_PATH" ]; then
    echo "Error: File not found: $EML_PATH"
    exit 1
fi

# Verify Docker image exists
if ! docker image inspect ecfx-pacer-oom-test >/dev/null 2>&1; then
    echo "Error: Docker image 'ecfx-pacer-oom-test' not found."
    echo "Run ./build-container.sh first."
    exit 1
fi

# Resolve the provider env file. Deliberately outside $SCRIPT_DIR (the plugin's own install
# path, replaced wholesale on every version bump) unless nothing else exists there yet, in which
# case SKILL.md's Phase 1 setup bootstraps the per-user copy from harness/pacer-oom.env.example.
CONFIG_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/pacer-oom.env"
ENV_FILE="${PACER_OOM_ENV_FILE:-$CONFIG_ENV_FILE}"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file not found: $ENV_FILE"
    echo "Run this skill's Phase 1 setup first (it bootstraps from pacer-oom.env.example), or set \$PACER_OOM_ENV_FILE."
    exit 1
fi

# Heap dump output directory on host — bind-mounted into container so dumps survive
# container deletion. Timestamp-named to keep runs distinct. Outside $SCRIPT_DIR for the same
# reason as ENV_FILE: a version bump must not delete dumps a prior run produced.
DUMP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/process-email-notice/dumps"
mkdir -p "$DUMP_DIR"

echo "=== Running Stuck Job Reproduction ==="
echo "Email:  $EML_PATH"
echo "Memory: $MEMORY"
echo "Firm:   $FIRM"
echo ""

# Clear Redis keys to avoid false duplicate detection from previous runs
echo "Clearing Redis keys..."
docker exec ecfx_redis redis-cli FLUSHDB 2>/dev/null \
    && echo "Redis keys cleared." \
    || echo "Warning: Could not flush Redis (is ecfx_redis container running?). Continuing anyway..."
echo ""

docker run --rm \
    --memory="$MEMORY" \
    --memory-swap="$MEMORY" \
    --env-file "$ENV_FILE" \
    -v "$EML_PATH:/app/notice.eml:ro" \
    -v "$DUMP_DIR:/tmp/dumps" \
    ecfx-pacer-oom-test \
    email-receipt --firm "$FIRM" /app/notice.eml

EXIT_CODE=$?

echo ""
echo "=== Exit code: $EXIT_CODE ==="
case ${EXIT_CODE} in
    0)   echo "RESULT: Processing completed successfully" ;;
    1)   echo "RESULT: Processing failed (check logs for exception)" ;;
    124) echo "RESULT: TIMEOUT — likely hung" ;;
    137) echo "RESULT: OOM KILLED by Docker cgroup (SIGKILL) — reproduces the incident" ;;
    *)   echo "RESULT: Unknown exit code $EXIT_CODE" ;;
esac

# List any heap dumps produced
if ls "$DUMP_DIR"/*.hprof >/dev/null 2>&1; then
    echo ""
    echo "=== Heap dumps ==="
    ls -lh "$DUMP_DIR"/*.hprof
fi

exit $EXIT_CODE
