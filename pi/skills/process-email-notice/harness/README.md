# NYSCEF Receipt Processing Local Test Guide

How to build, run, and monitor NYSCEF (and other) receipt processing tests locally using the Docker-based CLI test harness in `test-emails/StuckJobException/`.

## Prerequisites

- Docker Desktop running
- Local Docker infrastructure up: `docker-compose up redis rabbit postgres`
- Database migrated: `make migrate && make testfirm`
- `.eml` file for the notice you want to test (placed in this directory or any accessible path)
- `stuck-job-test.env` populated with required environment variables (see [Environment Variables](#environment-variables))
- Java 11 and Gradle available (managed via SDKMAN: `sdk env`)

## Directory Contents

```
test-emails/StuckJobException/
  build-container.sh        # Builds shadowJar + Docker image (one command)
  run-email.sh              # Runs a test against an .eml file
  Dockerfile                # Docker image definition (eclipse-temurin:11-jre)
  stuck-job-test.env        # Environment variables (secrets, DB, Redis, AWS, etc.)
  cli-all.jar               # Built artifact (created by build-container.sh)
  *.eml                     # Test email files
```

## Step 1: Build the Docker Test Image

This compiles the CLI shadowJar and packages it into a Docker image.

```bash
cd test-emails/StuckJobException/
sh ./build-container.sh
```

What it does:
1. Runs `GRADLE_OPTS="-Xms2048m -Xmx2048m" ./gradlew --no-daemon :cli:shadowJar` from the project root
2. Copies the built `cli-all.jar` (~365MB) into this directory
3. Builds Docker image `ecfx-stuck-job-test` from the Dockerfile

If you've already built the shadowJar and just need to rebuild the Docker image:

```bash
# Copy jar manually
cp ../../projects/cli/build/libs/cli-all.jar .

# Build image only
docker build -t ecfx-stuck-job-test .
```

## Step 2: Clear Redis Cache (if needed)

If testing hashing changes where hash values will differ from a previous run, flush the document hash cache:

```bash
# Flush specific hash keys
docker exec ecfx_redis redis-cli KEYS 'object_hash:doc_hasher:*' | \
  xargs -r docker exec -i ecfx_redis redis-cli DEL

# Or flush the entire Redis DB (simpler, clears everything)
docker exec ecfx_redis redis-cli FLUSHDB
```

The `run-email.sh` script does a `FLUSHDB` automatically before each run, so this is only needed for manual cleanup.

## Step 3: Run the Test

### Basic usage

```bash
sh ./run-email.sh <path-to-eml> [--memory 2304m] [--firm 1]
```

### Examples

```bash
# NYSCEF 483-document inbox (default 2304m memory, firm 1)
sh ./run-email.sh nyscef-inbox_io2o27qdpii7dhyi65vyuktt7a.eml --memory 2304m --firm 1

# Texas notice with lower memory
sh ./run-email.sh texas-inbox_xfjzl2ihv4i7dhjrzxbgckuzae.eml --memory 512m

# Absolute path to an .eml file
sh ./run-email.sh /path/to/notice.eml --firm 2 --memory 1024m
```

### What `run-email.sh` does

1. Resolves the `.eml` file path to absolute
2. Verifies the `ecfx-stuck-job-test` Docker image exists
3. Verifies `stuck-job-test.env` exists
4. Flushes Redis (`FLUSHDB`) to avoid stale duplicate detection
5. Runs the Docker container:
   ```
   docker run --rm \
     --memory=2304m --memory-swap=2304m \
     --env-file stuck-job-test.env \
     -v /path/to/notice.eml:/app/notice.eml:ro \
     ecfx-stuck-job-test \
     email-receipt --firm 1 /app/notice.eml
   ```

### Running in the background with logging

For long-running tests (e.g., 483 documents takes ~3 hours), run in the background:

```bash
LOG="/tmp/nyscef-test-run.log"
sh ./run-email.sh nyscef-inbox_io2o27qdpii7dhyi65vyuktt7a.eml \
    --memory 2304m --firm 1 > "$LOG" 2>&1 &
echo $! > /tmp/nyscef-test-pid.txt
echo "Started PID $(cat /tmp/nyscef-test-pid.txt), logging to $LOG"
```

## Step 4: Monitor the Test

### Quick status check

```bash
# Is it still running?
kill -0 $(cat /tmp/nyscef-test-pid.txt) 2>/dev/null && echo "RUNNING" || echo "FINISHED"

# Tail the log
tail -f /tmp/nyscef-test-run.log

# Check for OOM
grep "OutOfMemoryError" /tmp/nyscef-test-run.log
```

### Key log patterns to watch

| Pattern | Meaning |
|---------|---------|
| `Attempting to download document` | Downloading a doc from NYSCEF |
| `Document downloaded successfully` | Download completed |
| `extractTextForHashing COMPLETE` | Hashing OCR finished for one doc |
| `OCR NOT needed` | Doc used iText text only (no OCR) |
| `Phase 3: Selective OCR` | Only image pages sent to Tesseract |
| `Phase 3: Full OCR` | All pages sent to Tesseract |
| `Tesseract SUCCESS` / `Tesseract FAILED` | OCR outcome |
| `requesting GC before next document` | Memory pressure triggered GC |
| `CRITICAL: Heap` | Heap critically high (>85%) |
| `EMERGENCY: Heap` | Heap dangerously high (>90%) |
| `Terminating due to java.lang.OutOfMemoryError` | OOM — test failed |
| `PROCESSING COMPLETE` | All documents processed |
| `NYSCEF download retry` | A download failed and is being retried |

### Counting progress

```bash
LOG="/tmp/nyscef-test-run.log"

# Documents downloaded
grep -c "Document downloaded successfully" "$LOG"

# Hashing operations completed
grep -c "extractTextForHashing COMPLETE" "$LOG"

# OCR vs iText-only split
grep -c "OCR NOT needed" "$LOG"      # iText-only
grep -c "Selective OCR" "$LOG"        # Selective per-page OCR
grep -c "Full OCR" "$LOG"             # Full OCR

# Memory events
grep -c "requesting GC before next document" "$LOG"
grep -c "CRITICAL: Heap" "$LOG"
grep -c "Terminating due to java.lang.OutOfMemoryError" "$LOG"
```

### Monitor script

For comprehensive monitoring during a run, create a script like this:

```bash
#!/usr/bin/env bash
LOG="/tmp/nyscef-test-run.log"
PID_FILE="/tmp/nyscef-test-pid.txt"

count() { grep -c "$1" "$LOG" 2>/dev/null || echo 0; }

echo "==========================================="
echo " NYSCEF Test Monitor - $(date +%H:%M:%S)"
echo "==========================================="

PID=$(cat "$PID_FILE" 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    ELAPSED=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
    echo "  Status:           RUNNING (PID $PID, elapsed $ELAPSED)"
else
    echo "  Status:           FINISHED"
    if grep -q "Terminating due to java.lang.OutOfMemoryError" "$LOG" 2>/dev/null; then
        echo "  Result:           ** OOM DETECTED **"
    elif grep -q "PROCESSING COMPLETE" "$LOG" 2>/dev/null; then
        echo "  Result:           SUCCESS"
    else
        echo "  Result:           UNKNOWN (check log tail)"
    fi
fi
echo ""

echo "  --- Document Progress ---"
printf "  Docs downloaded:   %s\n" "$(count 'Document downloaded successfully')"
printf "  Hashing complete:  %s\n" "$(count 'extractTextForHashing COMPLETE')"
echo ""

echo "  --- Hashing Stats ---"
printf "  OCR NOT needed:    %s\n" "$(count 'OCR NOT needed')"
printf "  Selective OCR:     %s\n" "$(count 'Selective Tesseract SUCCESS')"
printf "  Full OCR:          %s\n" "$(count 'Phase 3: Full OCR')"
printf "  Tesseract FAILED:  %s\n" "$(count 'Tesseract FAILED')"
echo ""

echo "  --- Memory ---"
printf "  GC recovery:       %s\n" "$(count 'requesting GC before next document')"
printf "  Critical GC:       %s\n" "$(count 'CRITICAL: Heap')"
printf "  Emergency:         %s\n" "$(count 'EMERGENCY: Heap')"
printf "  OOM:               %s\n" "$(count 'Terminating due to java.lang.OutOfMemoryError')"
echo ""

# Hashing timing stats
TIMINGS=$(grep "extractTextForHashing COMPLETE" "$LOG" 2>/dev/null | sed 's/.*elapsed=//' | sed 's/ms.*//')
if [ -n "$TIMINGS" ]; then
    echo "  --- Hashing Timing ---"
    AVG=$(echo "$TIMINGS" | awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n; else print "N/A"}')
    MIN=$(echo "$TIMINGS" | sort -n | head -1)
    MAX=$(echo "$TIMINGS" | sort -n | tail -1)
    TOTAL_MIN=$(echo "$TIMINGS" | awk '{s+=$1} END {printf "%.1f", s/60000}')
    echo "  Avg: ${AVG}ms  Min: ${MIN}ms  Max: ${MAX}ms"
    echo "  Total hashing: ${TOTAL_MIN} min"
    echo ""
fi

LOG_LINES=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
echo "  Log lines: $LOG_LINES"
```

Run periodically with `watch`:

```bash
watch -n 30 sh /tmp/monitor.sh
```

## Docker Container Details

### JVM Configuration (Dockerfile)

The container uses `eclipse-temurin:11-jre` with these JVM flags:

| Flag | Value | Purpose |
|------|-------|---------|
| `MaxRAMPercentage` | 40.0 | Heap = 40% of container memory (922MB for 2304m) |
| `UseContainerSupport` | enabled | JVM reads cgroup memory limits |
| `ExitOnOutOfMemoryError` | enabled | Immediately exit on OOM (no zombie process) |
| `UseG1GC` | enabled | G1 garbage collector |
| `G1HeapRegionSize` | 4m | Region size for G1 |
| `MaxGCPauseMillis` | 200 | Target GC pause time |
| `ParallelRefProcEnabled` | enabled | Parallel reference processing |
| `MetaspaceSize` | 128m | Initial metaspace |
| `MaxMetaspaceSize` | 256m | Max metaspace |
| `Xlog:gc*` | enabled | GC logging to stdout |

### Memory Budget (2304MB container)

```
Java Heap:    922MB  (40% of 2304MB)
Camoufox:    ~600MB  (browser process, native memory)
Tesseract:   ~200MB  (OCR engine, native memory)
JVM non-heap: ~200MB (metaspace, thread stacks, code cache)
Headroom:    ~382MB
```

### Container execution

The `run-email.sh` script runs:
```
docker run --rm \
  --memory=2304m \          # Hard container memory limit
  --memory-swap=2304m \     # No swap (swap = memory, meaning 0 extra swap)
  --env-file stuck-job-test.env \
  -v /path/to/notice.eml:/app/notice.eml:ro \
  ecfx-stuck-job-test \
  email-receipt --firm 1 /app/notice.eml
```

The entrypoint is:
```
java -Dmicronaut.environments=local -jar /app/cli-all.jar email-receipt --firm 1 /app/notice.eml
```

## Environment Variables

The `stuck-job-test.env` file must contain:

| Variable | Purpose |
|----------|---------|
| `REDIS_URI` | Redis connection (e.g., `redis://host.docker.internal:6379`) |
| `DATASOURCES_DEFAULT_URL` | PostgreSQL JDBC URL |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3, Textract |
| `ECFX_ENVIRONMENT` | Environment name (e.g., `development`) |
| `ECFX_DOCUMENT_BUCKET` / `DOCUMENT_BUCKET` | S3 bucket for documents |
| `ECFX_ENC_SERVICE_USERNAME` / `ECFX_ENC_SERVICE_PW` | Encryption service credentials |
| `CAMOUFOX_GRID_URL` | Selenium grid URL for Camoufox browser |
| `SENTRY_DSN` | Sentry error reporting |

Plus court-specific credentials (PACER, Tyler, NYSCEF, etc.) depending on which processor you're testing.

## Processing Flow

When `run-email.sh` executes, the following processing pipeline runs:

1. **Startup** — Micronaut application context boots with `local` environment profile
2. **Email parsing** — The `.eml` file is read and parsed into an `EmailInboxItem`
3. **Processor selection** — 200+ receipt processors compete via `@Order` priority. The matching processor's `canProcess()` returns true based on email sender/subject
4. **NYSCEF-specific flow** (for NYSCEF notices):
   a. Parse email body for document links (court document IDs)
   b. Detect correction/duplicate path — if doc count > 20, enable OOM-prevention mode (clear document bodies after ID capture)
   c. Create a Camoufox WebDriver session for downloading
   d. **For each document** (streaming, one at a time):
      - Check memory pressure, run GC if needed
      - Download PDF via WebDriver from NYSCEF court site
      - **Hash the document** using `HashingTextExtractor`:
        - Phase 1: Extract text from all pages using iText, track which pages have images
        - Phase 2: Decide OCR strategy — iText-only, selective per-page OCR, or full OCR
        - Phase 3: If OCR needed, run Tesseract at 72 DPI grayscale (hashing-optimized)
        - Compute SHA-256 hash from metadata + document name + all page text
      - Check for duplicates via hash lookup in Redis
      - Encrypt document via encryption service
      - Store encrypted document in S3
      - Create `CourtDocument` entity in database
      - Clear document body from memory (OOM prevention)
   e. Quit WebDriver session
   f. Check if envelope already exists (duplicate/correction detection)
5. **Notification** — `ReceiptNotifierService` determines if user notification is needed
6. **Shutdown** — Clean up Tesseract/Textract resources, close database pool

### WebDriver Retry Logic

If a download fails (HTTP 500, browser crash, session death), the processor retries up to 3 times:
1. Quit the dead WebDriver
2. Wait 10 seconds
3. Create a fresh WebDriver session
4. Retry the download

This handles transient NYSCEF server errors and browser process crashes from native memory pressure (RSS approaching container limit).

## Troubleshooting

### OOM on Java heap
- Increase `--memory` or adjust `MaxRAMPercentage` in Dockerfile
- Check if a specific large document caused it (look for last `extractTextForHashing START` before OOM)

### Browser/WebDriver crash
- Look for `WebDriver session died` or `Target page, context or browser has been closed`
- Usually caused by container RSS approaching memory limit (native memory pressure)
- The retry mechanism should handle this automatically (up to 3 retries per document)

### "Envelope already exists" at end
- Normal for re-runs — previous test already created the envelope in the database
- The processor downloads and hashes all documents but skips storage if the envelope exists
- To test fresh: delete the envelope from the database before running

### Build failures
- Ensure `GRADLE_OPTS="-Xms2048m -Xmx2048m"` is set
- Run `sdk env` to switch to correct Java/Gradle versions
- Check Docker Desktop is running

### Redis connection errors
- Ensure `docker-compose up redis` is running
- Verify `REDIS_URI` in `stuck-job-test.env` uses `host.docker.internal` (not `localhost`)
