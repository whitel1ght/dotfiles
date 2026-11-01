---
name: process-email-notice
description: >-
  Build the CLI from the current branch and run a .eml email notice through the ECFX receipt-processing pipeline inside a self-contained Docker container.
---


# Process Email Notice

Build the CLI from the current branch, run any `.eml` email notice through the ECFX receipt-processing pipeline inside a self-contained Docker container, and analyze the full lifecycle outcome.

## Allowed Tools
Bash, Read, Write, Grep, Glob

## Description

Use this skill when the user wants to process an email notice (`.eml` file) through the ECFX receipt-processing CLI in a Docker container — for any local repro, fix validation, debugging, or feature exercise. The skill is **general-purpose**; it is not OOM-specific even though the historical container name and env file say `pacer-oom`. Common uses:

- Reproduce a customer-reported failure for a specific receipt.
- Validate a fix on the current branch before merging.
- Step through the full receipt-processing pipeline (parsing → fetch → stamping → combine/store → link extraction → title extraction → storage → notifications).
- Exercise a new processor or new behavior with a known good `.eml`.
- Force prod-matching memory limits (the historical OOM use case) — still supported and is the default.

This skill always builds the current branch's code, so the container reflects whatever is checked out.

Handles the full lifecycle:
- Resolves the `.eml` path (exact, relative, or partial-name search under `test-emails/`).
- Verifies infrastructure (Redis, Postgres, RabbitMQ, Docker image, env file).
- Optionally clears Redis / database state.
- Rebuilds the CLI shadowJar + Docker image from the current branch.
- Launches the container with production-matching memory limits.
- Monitors logs in real time for key phase transitions.
- Produces a structured outcome summary.

Works for any court system (PACER, NYSCEF, Tyler, TrueFiling, Missouri, Florida, MiFILE, CourtDrive, PAUnified, etc.) — provider-agnostic.

## User-Invocable

When the user invokes this skill, gather the following parameters if not provided:

**Required:**
- **EML_PATH**: Path to the `.eml` file. Absolute path, path relative to the project root, or partial filename — the skill searches `test-emails/` recursively if a partial is given.

**Optional (with defaults):**
- **MEMORY**: Container memory limit (default: `2304m` — matches prod DuploCloud). Examples: `512m`, `1024m`, `2304m`, `4096m`.
- **FIRM**: Firm ID to process as (default: `1`).
- **CLEAR_REDIS**: Flush Redis before running (default: `yes`). Set to `no` when testing duplicate-detection or session-cached behaviors.
- **CLEAR_PRIOR_RUN**: Detect and clear any prior run of this specific inbox item before launching (default: `auto`). Identifies "this inbox" by matching `length(raw_content)` on `private.inbox_item` to the `.eml` file size (±200 bytes). Clears just those rows + their dependent `inbox_item_process_job`, `inbox_item_notification`, `court_document`, and orphaned `court_envelope` rows. Case + jurisdiction rows are preserved so the rerun reuses them. Safer than `CLEAR_DATABASE=yes`. Values: `auto` (detect + clear if found), `yes` (always attempt clear), `no` (never clear, fail fast if prior run exists).
- **CLEAR_DATABASE**: Delete ALL envelope/documents/inbox_items for this firm before running (default: `no`). Set to `yes` only for a completely fresh test slate — `CLEAR_PRIOR_RUN=auto` is usually sufficient.
- **BUILD**: Rebuild CLI + Docker image from current branch (default: `auto`). Values:
  - `auto` — build only if one of these is true: (a) `cli-all.jar` doesn't exist, (b) the jar is older than any `.java` source under `projects/`, (c) the Docker image doesn't exist, (d) the Docker image is older than `cli-all.jar`, (e) the current `git HEAD` differs from the HEAD recorded in the marker file `~/.cache/process-email-notice/.last-built-head`.
  - `yes` — always rebuild (forces full jar + image rebuild regardless of staleness).
  - `no` — never rebuild (fails fast if no image exists).

If the user provides parameters inline (e.g., `/process-email-notice some-notice.eml --memory 1024m --firm 2`), parse them and proceed.

## CRITICAL: Execution Strategy

**This skill MUST run with minimal user interaction.** Combine operations into the fewest possible Bash tool calls. Target: **3 Bash calls for a standard run**:

1. **Setup** — resolve file, detect inbox_id, verify infra, auto-clear prior run of THIS inbox (default).
2. **Build** — `gradlew :cli:shadowJar` + `./build-container.sh`, **skipped automatically if nothing changed since last build** (staleness check via git HEAD + file mtimes).
3. **Launch + monitor** — start the container in the background, arm a `Monitor` on the live log until exit.

Typical timings:
- Fully cached run (no code changes, no prior inbox state): Phase 1 ≈ 2s, Phase 2 ≈ 0.5s, Phase 3 = EML processing time (varies by bundle).
- Fresh branch switch: Phase 2 ≈ 60-90s for jar rebuild + Docker image pack.
- Re-run same EML after prior crash: Phase 1 adds ~1s to detect + clear the prior inbox_item row.

**Always use the existing `harness/run-email.sh` script (alongside this SKILL.md) — do NOT hand-craft `docker run` commands.** The harness has correct memory flags, env file, bind-mount paths, and heap-dump output directory baked in. It is provider-agnostic.

---

## Phase 1: Setup, Verify, Clear State

Single Bash call. Substitute the resolved parameter values into this script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# PROJECT_ROOT auto-detects from the current git checkout; override via env if needed.
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
# CLAUDE_SKILL_DIR is this skill's own directory — Claude Code substitutes it
# before running this script. Use :- so an unsubstituted var doesn't abort
# under set -u before the guard below can print a helpful error.
SKILL_DIR="${CLAUDE_SKILL_DIR:-}"
[ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR/harness" ] \
    || { echo "ERROR: \${CLAUDE_SKILL_DIR} was not substituted (SKILL_DIR='$SKILL_DIR') — set SKILL_DIR to this skill's base directory" >&2; exit 1; }
HARNESS_DIR="$SKILL_DIR/harness"
EML_NAME="<USER_PROVIDED_FILENAME>"
MEMORY="<MEMORY>"
FIRM="<FIRM>"
CLEAR_REDIS="<yes|no>"
CLEAR_PRIOR_RUN="<auto|yes|no>"
CLEAR_DATABASE="<yes|no>"

# Step 1 — Resolve .eml file (exact, project-relative, test-emails, or recursive search)
echo "=== Step 1: Resolve .eml File ==="
if [ -f "$EML_NAME" ]; then
    EML_ABS_PATH="$(cd "$(dirname "$EML_NAME")" && pwd)/$(basename "$EML_NAME")"
elif [ -f "$PROJECT_ROOT/$EML_NAME" ]; then
    EML_ABS_PATH="$PROJECT_ROOT/$EML_NAME"
elif [ -f "$PROJECT_ROOT/test-emails/$EML_NAME" ]; then
    EML_ABS_PATH="$PROJECT_ROOT/test-emails/$EML_NAME"
else
    FOUND=$(find "$PROJECT_ROOT/test-emails" -name "*${EML_NAME}*" -name "*.eml" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        EML_ABS_PATH="$FOUND"
    else
        echo "ERROR: Could not find .eml file: $EML_NAME"
        echo "Searched: \$EML_NAME, \$PROJECT_ROOT/\$EML_NAME, test-emails/, and recursive find"
        exit 1
    fi
fi
echo "  Found: $EML_ABS_PATH"
echo "  Size:  $(ls -lh "$EML_ABS_PATH" | awk '{print $5}')"

# Step 1b — Compute EML byte length for prior-run detection.
# The application doesn't store a stable column we can match the public
# `inbox_xxx` ID against (it's derived from the UUID at display time), so we
# identify "this inbox" by matching `length(raw_content)` on private.inbox_item
# to the EML file's byte size — same selector cleanup-inbox-item uses.
EML_BYTES=$(wc -c < "$EML_ABS_PATH" | tr -d ' ')
echo "  EML bytes: $EML_BYTES (used for CLEAR_PRIOR_RUN detection)"

# Step 2 — Verify infrastructure (Redis + Postgres required; RabbitMQ optional)
echo ""
echo "=== Step 2: Verify Infrastructure ==="
INFRA_OK=true
docker exec ecfx_redis redis-cli PING >/dev/null 2>&1 && echo "  Redis: OK" || { echo "  Redis: DOWN (try: docker-compose up redis)"; INFRA_OK=false; }
docker exec ecfx_postgres pg_isready -U ecfx >/dev/null 2>&1 && echo "  Postgres: OK" || { echo "  Postgres: DOWN (try: docker-compose up postgres)"; INFRA_OK=false; }
docker exec ecfx_rabbit rabbitmq-diagnostics -q ping >/dev/null 2>&1 && echo "  RabbitMQ: OK" || echo "  RabbitMQ: DOWN (optional — warn only)"
# Resolution order (first hit wins), same convention as process-email-notice-cli:
#   1) $PACER_OOM_ENV_FILE if exported.
#   2) ${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/pacer-oom.env (per-user; outside the plugin, so a
#      version bump keeps it).
# If neither exists, bootstrap slot (2) from the committed template and fail fast.
PACER_ENV_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/pacer-oom.env"
PACER_ENV_FILE="${PACER_OOM_ENV_FILE:-$PACER_ENV_DEFAULT}"
if [ -f "$PACER_ENV_FILE" ]; then
    # Refuse to run with placeholder values still present.
    if grep -qE "__FILL_ME_IN__|__username__|__password__" "$PACER_ENV_FILE"; then
        echo "  Env file pacer-oom.env: PLACEHOLDERS PRESENT — populate with real values:"
        grep -nE "__FILL_ME_IN__|__username__|__password__" "$PACER_ENV_FILE" | head -5
        INFRA_OK=false
    else
        echo "  Env file pacer-oom.env: OK ($PACER_ENV_FILE)"
    fi
elif [ -f "$HARNESS_DIR/pacer-oom.env.example" ]; then
    # First run on this machine — bootstrap from the committed template, which has placeholders
    # for every secret, into the per-user location. The real file is gitignored there too.
    mkdir -p "$(dirname "$PACER_ENV_DEFAULT")" && chmod 700 "$(dirname "$PACER_ENV_DEFAULT")"
    cp "$HARNESS_DIR/pacer-oom.env.example" "$PACER_ENV_DEFAULT"
    chmod 600 "$PACER_ENV_DEFAULT" 2>/dev/null || true
    echo "  Env file pacer-oom.env: BOOTSTRAPPED from template -> $PACER_ENV_DEFAULT"
    echo "    → Populate __FILL_ME_IN__ / __username__ / __password__ placeholders, then re-run."
    INFRA_OK=false
else
    echo "  Env file: MISSING (and no .example template — re-install the skill)"
    INFRA_OK=false
fi
test -x "$HARNESS_DIR/run-email.sh" && echo "  run-email.sh: OK" || { echo "  run-email.sh: MISSING or not executable"; INFRA_OK=false; }
if [ "$INFRA_OK" = "false" ]; then echo "ERROR: Infrastructure check failed"; exit 1; fi

# Step 3 — State management (Redis, prior-run detection, optional full DB clear)
echo ""
echo "=== Step 3: State Management ==="
if [ "$CLEAR_REDIS" = "yes" ]; then
    docker exec ecfx_redis redis-cli FLUSHDB >/dev/null && echo "  Redis: FLUSHED"
else
    echo "  Redis: preserved"
fi

# Step 3b — CLEAR_PRIOR_RUN: detect + clear a prior run of THIS specific .eml.
#
# Identifies "this inbox" by matching length(raw_content) on private.inbox_item
# to the EML byte size (±200). Cascade order (FK-safe):
#   1. inbox_item_process_job   .parent_id       -> inbox_item.id
#   2. inbox_item_notification  .inbox_item_id   -> inbox_item.id
#   3. court_document           .inbox_item_id   -> inbox_item.id (nullable)
#   4. court_envelope           (only those left orphaned by step 3)
#   5. inbox_item               itself
# Case + jurisdiction rows are preserved.
if [ "$CLEAR_PRIOR_RUN" != "no" ]; then
    LO=$(( EML_BYTES - 200 ))
    HI=$(( EML_BYTES + 200 ))
    PRIOR_COUNT=$(docker exec ecfx_postgres psql -U ecfx -d ecfx -tA -c \
        "SELECT count(*) FROM private.inbox_item WHERE firm_id = $FIRM AND length(raw_content) BETWEEN $LO AND $HI;" \
        2>/dev/null | tr -d '[:space:]')
    PRIOR_COUNT=${PRIOR_COUNT:-0}
    if [ "$PRIOR_COUNT" -gt 0 ] || [ "$CLEAR_PRIOR_RUN" = "yes" ]; then
        echo "  Prior run detected (rows=$PRIOR_COUNT, firm=$FIRM, bytes≈$EML_BYTES) — clearing..."
        # PostgreSQL CTEs only scope to a single statement, so we materialize
        # the target inbox + envelope IDs into temp tables and reference them
        # across all five DELETEs in one transaction.
        docker exec -i ecfx_postgres psql -U ecfx -d ecfx -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || echo "  WARN: cleanup failed"
BEGIN;
CREATE TEMP TABLE _target_inboxes ON COMMIT DROP AS
    SELECT id FROM private.inbox_item
     WHERE firm_id = $FIRM
       AND length(raw_content) BETWEEN $LO AND $HI;
CREATE TEMP TABLE _target_envelopes ON COMMIT DROP AS
    SELECT DISTINCT envelope_id AS id
      FROM private.court_document
     WHERE firm_id = $FIRM
       AND inbox_item_id IN (SELECT id FROM _target_inboxes)
       AND envelope_id IS NOT NULL;
DELETE FROM private.inbox_item_process_job
 WHERE firm_id = $FIRM AND parent_id IN (SELECT id FROM _target_inboxes);
DELETE FROM private.inbox_item_notification
 WHERE firm_id = $FIRM AND inbox_item_id IN (SELECT id FROM _target_inboxes);
DELETE FROM private.court_document
 WHERE firm_id = $FIRM AND inbox_item_id IN (SELECT id FROM _target_inboxes);
DELETE FROM private.court_envelope
 WHERE firm_id = $FIRM AND id IN (SELECT id FROM _target_envelopes)
   AND NOT EXISTS (
       SELECT 1 FROM private.court_document cd
        WHERE cd.envelope_id = private.court_envelope.id
   );
DELETE FROM private.inbox_item
 WHERE firm_id = $FIRM AND id IN (SELECT id FROM _target_inboxes);
COMMIT;
SQL
        echo "  Prior run: CLEARED ($PRIOR_COUNT inbox_item row(s) + dependents)"
    else
        echo "  Prior run: none detected for this EML (skipping clear)"
    fi
else
    echo "  Prior run: CLEAR_PRIOR_RUN=no, skipping detection"
fi

# Step 3c — Optional full firm-scoped DB clear (rare; prefer 3b)
if [ "$CLEAR_DATABASE" = "yes" ]; then
    echo "  Database: clearing ALL receipts tables for firm=$FIRM..."
    docker exec ecfx_postgres psql -U ecfx -d ecfx -c "
        DELETE FROM private.inbox_item_process_job WHERE firm_id = $FIRM;
        DELETE FROM private.inbox_item_notification WHERE firm_id = $FIRM;
        DELETE FROM private.court_document WHERE firm_id = $FIRM;
        DELETE FROM private.court_envelope WHERE firm_id = $FIRM;
        DELETE FROM private.inbox_item WHERE firm_id = $FIRM;
    " >/dev/null 2>&1 || echo "  WARN: some tables may not have existed"
    echo "  Database: CLEARED (firm-wide)"
else
    echo "  Database: firm-wide clear not requested"
fi

# Step 4 — Current branch info (for the run summary)
echo ""
echo "=== Step 4: Current Branch ==="
cd "$PROJECT_ROOT"
echo "  branch: $(git branch --show-current)"
echo "  head:   $(git rev-parse --short HEAD) — $(git log -1 --format='%s' | cut -c1-80)"

# Step 5 — Export EML path + log file for the next call
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/process-email-$TIMESTAMP.log"
echo ""
echo "=== Ready ==="
echo "  eml:       $EML_ABS_PATH"
echo "  inbox_id:  ${INBOX_ID:-'(none parsed)'}"
echo "  log:       $LOG_FILE"
echo "  memory:    $MEMORY"
echo "  firm:      $FIRM"
```

Capture `EML_ABS_PATH` and `LOG_FILE` for use in Phase 2b.

---

## Phase 2: Build (only rebuilds when stale)

Single Bash call. The script auto-detects whether a rebuild is needed; for a cached run (nothing changed since last build) both `gradlew` and `docker build` are skipped and total Phase 2 time is < 1 second.

Staleness detection runs these checks in order; a rebuild fires on the first `true`:

1. **`BUILD=yes`** (force flag) → always rebuild.
2. **`BUILD=no`** → never rebuild; error out if image is missing.
3. **`BUILD=auto`** (default) — rebuild if ANY of:
   - `cli-all.jar` does not exist, OR
   - `cli-all.jar` is older than the newest `.java` source under `projects/`, OR
   - Docker image `ecfx-pacer-oom-test` does not exist, OR
   - Docker image is older than `cli-all.jar`, OR
   - The current `git HEAD` differs from the HEAD recorded in `~/.cache/process-email-notice/.last-built-head`.

Marker file (`.last-built-head`) is updated on every successful build so subsequent runs on the same commit skip immediately.

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
SKILL_DIR="${CLAUDE_SKILL_DIR:-}"
[ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR/harness" ] \
    || { echo "ERROR: \${CLAUDE_SKILL_DIR} was not substituted (SKILL_DIR='$SKILL_DIR') — set SKILL_DIR to this skill's base directory" >&2; exit 1; }
HARNESS_DIR="$SKILL_DIR/harness"
BUILD="<auto|yes|no>"
MARKER_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/process-email-notice"
MARKER_FILE="$MARKER_DIR/.last-built-head"
CLI_JAR="$PROJECT_ROOT/projects/cli/build/libs/cli-0.0.1-SNAPSHOT-all.jar"
IMAGE_TAG="ecfx-pacer-oom-test:latest"

cd "$PROJECT_ROOT"
CURRENT_HEAD=$(git rev-parse HEAD)

# Decide whether to build
NEED_BUILD="no"
REASON=""

if [ "$BUILD" = "yes" ]; then
    NEED_BUILD="yes"; REASON="BUILD=yes (forced)"
elif [ "$BUILD" = "no" ]; then
    if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
        echo "ERROR: BUILD=no but image $IMAGE_TAG does not exist. Run with BUILD=auto or BUILD=yes."
        exit 1
    fi
    NEED_BUILD="no"; REASON="BUILD=no (image present, no build requested)"
else
    # BUILD=auto — staleness checks
    if [ ! -f "$CLI_JAR" ]; then
        NEED_BUILD="yes"; REASON="cli-all.jar missing"
    elif [ -n "$(find "$PROJECT_ROOT/projects" -name '*.java' -newer "$CLI_JAR" -print -quit 2>/dev/null)" ]; then
        NEED_BUILD="yes"; REASON=".java source newer than cli-all.jar"
    elif ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
        NEED_BUILD="yes"; REASON="docker image $IMAGE_TAG missing"
    else
        # Image exists — check if it's older than the jar (jar got rebuilt but container didn't)
        JAR_MTIME=$(stat -f %m "$CLI_JAR" 2>/dev/null || stat -c %Y "$CLI_JAR")
        IMAGE_CREATED=$(docker image inspect "$IMAGE_TAG" --format '{{.Created}}' 2>/dev/null | \
            xargs -I{} date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo '{}' | cut -c1-19)" +%s 2>/dev/null || echo 0)
        if [ "$JAR_MTIME" -gt "$IMAGE_CREATED" ]; then
            NEED_BUILD="yes"; REASON="cli-all.jar newer than docker image"
        elif [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE" 2>/dev/null)" != "$CURRENT_HEAD" ]; then
            NEED_BUILD="yes"; REASON="git HEAD changed since last build ($(cut -c1-7 "$MARKER_FILE") → ${CURRENT_HEAD:0:7})"
        elif [ ! -f "$MARKER_FILE" ]; then
            NEED_BUILD="yes"; REASON="no marker file — first build on this branch"
        else
            NEED_BUILD="no"; REASON="all checks pass (jar + image + HEAD marker current)"
        fi
    fi
fi

echo "=== Phase 2: Build decision ==="
echo "  BUILD mode: $BUILD"
echo "  Decision:   $NEED_BUILD — $REASON"

if [ "$NEED_BUILD" = "yes" ]; then
    echo ""
    echo "=== Building ==="
    cd "$PROJECT_ROOT"
    ./gradlew :cli:shadowJar 2>&1 | tail -5
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  ERROR: gradle build failed"; exit 1; }
    # Export PROJECT_ROOT so build-container.sh (running from $HARNESS_DIR in
    # claude-components) doesn't fall back to its local git root.
    cd "$HARNESS_DIR"
    PROJECT_ROOT="$PROJECT_ROOT" ./build-container.sh 2>&1 | tail -5
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  ERROR: docker image build failed"; exit 1; }
    mkdir -p "$MARKER_DIR"
    echo "$CURRENT_HEAD" > "$MARKER_FILE"
    echo "  Marker updated: $MARKER_FILE → $CURRENT_HEAD"
else
    echo "  (skipped — reusing existing jar + image)"
fi
```

### Notes on staleness detection

- Uses `find ... -newer` for source-file mtime comparison, which handles incremental edits naturally (no need to parse Gradle's incremental-build cache).
- The `.last-built-head` marker catches the case where you checkout a different branch (jar and source files have matching mtimes but the commit is different) — this is common when switching between feature branches.
- Does NOT parse `git status` for uncommitted changes intentionally: `find -newer` already covers that (editing a source file updates its mtime).
- To force a rebuild without modifying any file, just pass `BUILD=yes` or delete the marker file.

This rebuilds the CLI jar from the current branch and wraps it into the `ecfx-pacer-oom-test` Docker image. Build takes ~60-90s clean, ~10s incremental.

---

## Phase 2b: Launch and Monitor

Launch the container in the background via `run-email.sh`, redirect stdout+stderr to the timestamped log, then arm a `Monitor` that streams the key phase transitions.

```bash
cd "$HARNESS_DIR" && \
  nohup ./run-email.sh "$EML_ABS_PATH" --memory "$MEMORY" --firm "$FIRM" > "$LOG_FILE" 2>&1 &
BG_PID=$!
disown
echo "Launched bg_pid=$BG_PID, log=$LOG_FILE"
```

Then arm a `Monitor` with this filter. It catches the phase transitions that matter for any receipt-processing run regardless of provider:

```
tail -F $LOG_FILE 2>/dev/null | grep -E --line-buffered "\
HTTP_STREAM COMPLETE|heap_used_mb=|\
MODE_SELECTED|PACER_STAMP_DEFER.*(START|COMPLETE)|\
PACER_COMBINE|storePacerBundleIndividually|action=storing_individually|\
DOCUMENT_LINK_EXTRACTOR.*(Phase|pages)|\
UnknownProcessingException|OutOfMemory|ExitOnOutOfMemory|Killed|\
PROCESSING COMPLETE|CUSTOMER ACTION|FAILURE|\
Exception|RESULT:|Exit code:"
```

Keep the `Monitor` armed until `RESULT:` / `Exit code:` line fires. The `run-email.sh` script prints both when the container exits.

---

## Phase 3: Post-Run Analysis

One Bash call once the container has exited. Pulls summary data from the log file into a structured report.

```bash
LOG_FILE="/tmp/process-email-<TIMESTAMP>.log"

echo "=== Final result ==="
grep -E "RESULT:|Exit code:" "$LOG_FILE" | tail -3

echo ""
echo "=== Peak heap observed ==="
grep -oE "heap_used_mb=[0-9]+" "$LOG_FILE" | sort -t= -k2 -n | tail -3

echo ""
echo "=== Key phase transitions ==="
grep -vE "^\[[0-9]+\.[0-9]+s\]" "$LOG_FILE" | \
  grep -E "MODE_SELECTED|STAMP_DEFER.*(START|COMPLETE)|SKIPPING_OVER_SIZE_LIMIT|action=storing_individually|DOCUMENT_LINK_EXTRACTOR.*Phase 1 complete|PROCESSING COMPLETE|CUSTOMER ACTION|FAILURE" | \
  tail -20

echo ""
echo "=== Exceptions thrown during processing ==="
grep -vE "^\[[0-9]+\.[0-9]+s\]" "$LOG_FILE" | \
  grep -oE "[A-Z][a-zA-Z]+Exception" | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== Heap dumps (if any) ==="
ls -lh "${XDG_CACHE_HOME:-$HOME/.cache}/process-email-notice/dumps/"*.hprof 2>/dev/null | head -3 || echo "  (none produced)"
```

---

## Presenting Results to the User

Structure the summary as:

1. **Outcome** — one-line verdict: `PROCESSING COMPLETE` / `CUSTOMER ACTION REQUIRED` / specific `Exception` / container killed / exit code.
2. **Branch + commit** — which code the container was built from.
3. **Timeline** — key phase transitions with wall-clock timestamps.
4. **Heap trajectory** — peak JVM heap + whether a heap dump was produced.
5. **Exceptions** — count and class distribution from the log.
6. **Next steps** — if the user was reproducing a bug, link to the Jira ticket and the relevant `claude-docs/` design doc. Cite specific log lines or file paths for any evidence referenced.

---

## Reference: Docker Container Configuration

`ecfx-pacer-oom-test` image (**historical name** — the harness was originally built for the ECFX-13618 PACER OOM repro. It is fully provider- and use-case-agnostic; we kept the name to avoid breaking existing scripts and marker files):
- **Base:** Gradle-built shadowJar from the current branch.
- **Entry:** `java -jar /app/cli-all.jar email-receipt --firm $FIRM /app/notice.eml`.
- **Memory** (via `run-email.sh`): `--memory $MEMORY --memory-swap $MEMORY` (swap disabled, matches prod).
- **JVM flags** (via `pacer-oom.env`):
  - `-XX:MaxRAMPercentage=75.0` (1728 MB heap cap on a 2304 MB container).
  - `-XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError`.
  - `-XX:HeapDumpPath=/tmp/dumps/heap_%p.hprof`.
  - `-XX:MaxDirectMemorySize=192m`.
  - `-XX:+UseG1GC -XX:MaxGCPauseMillis=200`.
  - `-Xlog:gc*` (GC events in container stdout).
- **Bind-mounts:**
  - `<EML_PATH>:/app/notice.eml:ro`.
  - `${XDG_CACHE_HOME:-$HOME/.cache}/process-email-notice/dumps:/tmp/dumps` (heap dumps survive
    container removal — deliberately outside the plugin's install path, which a version bump
    replaces wholesale).
- **Shared infra (docker-compose):**
  - `ecfx_redis`, `ecfx_postgres`, `ecfx_rabbit`.

---

## Reference: Processing Flow (per receipt processor)

1. Email parsed → provider detection.
2. Jurisdiction + case resolution.
3. Credential lookup.
4. Provider-specific HTTP fetch or browser automation.
5. Per-doc post-fetch: stamp detection, optional embedded-PDF extraction.
6. Combine vs individual-store decision (based on firm preference + bundle size).
7. Per-doc web-link extraction (`DocumentLinkExtractor`, gated by `firm.getExtractDocumentWebLinks()`).
8. Title extraction (`FAIDocumentTitleExtractionService`).
9. Encryption + storage via `DocumentStorageService`.
10. Notifications / webhooks via `ReceiptNotifierService`.

### Possible Final Outcomes

| Outcome | Log signature | CLI exit |
| --- | --- | --- |
| Full success | `PROCESSING COMPLETE` + `Job processing completed successfully` | 0 |
| Customer action required | `CUSTOMER ACTION REQUIRED FAILURE` | 0 |
| Retryable error | `Handling auto-retryable exception` | 0 (CLI returns; prod would requeue) |
| Terminal exception | `Handling non-user receipt processing exception` + ECFX-action state | 0 |
| JVM OOM | `java.lang.OutOfMemoryError` + heap dump in `dumps/` | non-zero |
| Container (cgroup) killed | GC thrashing, no OOM in log, log ends mid-processing | 137 |

### Processor-Specific Notes

- **PACER:** streaming HTTP client with 500 MB combine cap. Embedded-PDF extraction for HTML-wrapped responses. Individual-store fallback when combine exceeds cap.
- **TrueFiling Michigan:** POST login routes through buffering client upfront; GET errors recover body via buffering re-issue.
- **NYSCEF / Tyler / Peachcourt:** Playwright browser automation via Camoufox grid at `host.docker.internal:4445`.
- **Missouri:** browser-based, uses legacy string-matching classifier.

---

## Reference: Finding Test Emails

```
find "$(git rev-parse --show-toplevel)/test-emails" -name "*.eml" -type f
```

Common sub-directories:
- `test-emails/ECFX-NNNN/` — per-ticket reproduction bundles.
- `test-emails/PacerOOM/incident-bundle.eml` — symlink to the canonical ECFX-13618 heavy bundle.
- `test-emails/OOM/` — small basic test cases.

---

## Companion Skills

- **`setup-jurisdiction-and-case`** — if processing fails with "jurisdiction not mapped" or "case not found", use this to seed the firm jurisdiction + case records before retrying.
- **`cleanup-inbox-item`** — if you want to re-run the SAME inbox item (prod `inbox_*` ID), use this to clear its prior state first. Complements `CLEAR_DATABASE=yes`.
- **`notice-processing-results`**, **`notice-failure-results`**, **`processor-report`**, **`stuck-jobs-report`** — post-hoc CloudWatch aggregation reports for prod receipt-processing outcomes. Unrelated to local repro but useful after a fix deploy.
