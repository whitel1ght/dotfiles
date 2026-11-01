#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# PROJECT_ROOT must point at the ecfx-backend repo (where gradlew + projects/cli live).
# Default: the git root of the current working directory. Override via env var.
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "$PROJECT_ROOT" ] || [ ! -f "$PROJECT_ROOT/gradlew" ]; then
    echo "Error: PROJECT_ROOT='${PROJECT_ROOT:-<unset>}' is not an ecfx-backend checkout (no gradlew found)."
    echo "Either run this script from inside the ecfx-backend repo, or set PROJECT_ROOT:"
    echo "  PROJECT_ROOT=/path/to/ecfx-backend $0"
    exit 1
fi

echo "=== Step 1: Building CLI shadowJar ==="
echo "Project root: $PROJECT_ROOT"
cd "$PROJECT_ROOT"
GRADLE_OPTS="-Xms2048m -Xmx2048m" ./gradlew --no-daemon :cli:shadowJar

echo ""
echo "=== Step 2: Copying CLI JAR ==="
# v4 shadowJar produces cli-{version}-all.jar (no archiveFileName override in build.gradle).
# Find the newest matching jar and copy it with a stable name.
SRC_JAR=$(ls -t "$PROJECT_ROOT/projects/cli/build/libs/"cli-*-all.jar 2>/dev/null | head -1)
if [ -z "$SRC_JAR" ]; then
    echo "Error: shadowJar output not found at $PROJECT_ROOT/projects/cli/build/libs/cli-*-all.jar"
    exit 1
fi
cp "$SRC_JAR" "$SCRIPT_DIR/cli-all.jar"
echo "Copied $(basename "$SRC_JAR") -> cli-all.jar ($(du -h "$SCRIPT_DIR/cli-all.jar" | cut -f1))"

echo ""
echo "=== Step 3: Building Docker image ==="
docker build -t ecfx-pacer-oom-test "$SCRIPT_DIR"

echo ""
echo "=== Done ==="
echo "Image: ecfx-pacer-oom-test"
echo "Next: ./run-email.sh <path-to-eml>"
