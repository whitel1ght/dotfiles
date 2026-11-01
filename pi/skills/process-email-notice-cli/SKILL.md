---
name: process-email-notice-cli
description: >-
  Build the CLI from the current branch and run a .eml email notice through the ECFX receipt-processing pipeline as a direct JVM invocation inside the container.
---


# Process Email Notice (CLI / In-Container Variant)

Build the CLI from the current branch and run any `.eml` email notice through the ECFX receipt-processing pipeline as a **direct JVM invocation inside the claude-code-container** — no inner Docker container, no docker-socket-proxy, no DinD. Then analyze the full lifecycle outcome the same way the base skill does.

## Allowed Tools
Bash, Read, Write, Grep, Glob

## Description

This is the **in-container counterpart** of `/process-email-notice`. It supports the same use cases — local repro, fix validation, debugging, full-pipeline exercise, OOM reproduction (when invoked with prod-matching `--heap`) — but runs the JVM in the parent container's network namespace so the existing egress firewall and HTTP-attempt monitor see every outbound call.

Use it for any of:
- Reproduce a customer-reported failure for a specific receipt.
- Validate a fix on the current branch before merging.
- Step through the full receipt-processing pipeline (parsing → fetch → stamping → combine/store → link extraction → title extraction → storage → notifications).
- Exercise a new processor or new behavior with a known good `.eml`.
- Force prod-matching memory limits to reproduce OOM / cgroup-kill scenarios — pass `--heap 2304m` (or whatever prod sets) and the JVM uses the same heap/GC flags as the Docker harness.

The skill is **provider-agnostic** (PACER, NYSCEF, Tyler, TrueFiling, Missouri, Florida, MiFILE, CourtDrive, PAUnified, …).

## When to use this skill instead of `process-email-notice`

| You are running... | Use |
|---|---|
| Inside the `claude-code-container` (developer or reviewer role) | **`process-email-notice-cli` (this skill)** |
| On a developer's Mac with the receipts harness Docker container | `process-email-notice` |

## Why a separate skill exists

The base `process-email-notice` skill builds and runs an isolated Docker container per `.eml`. Inside the claude-code-container, spawning a child container via DinD breaks the egress controls in two ways:

1. **Bypasses the firewall.** Containers spawned by DinD live in `dind-net`, a separate network namespace, so the iptables allowlist in `scripts/init-firewall.sh` does not apply.
2. **Invisible to the egress monitor.** Layer 1 (logback HTTP_JSON) and Layer 2 (NFLOG netlink reader) only observe the `claude-code-container`'s netns.

Running the JVM directly in the parent container's namespace fixes both — every HTTP attempt the email processor makes flows through the firewall and is captured in `~/Desktop/claude-shared/network-monitor/`.

## User-Invocable

When the user invokes this skill, gather the following parameters if not provided:

**Required:**
- **EML_PATH** — Path to the `.eml` file. Absolute path, path relative to the project root (`/workspace/ecfx-backend`), or a partial filename — the skill searches `test-emails/` recursively.

**Optional (with defaults):**
- **HEAP** — JVM max heap (default `2304m` — matches the base skill's prod-matching default; pass `1728m` to mirror the Docker harness's `MaxRAMPercentage=75.0` of 2304 MB cgroup). Examples: `512m`, `1024m`, `2304m`, `4096m`.
- **FIRM** — Firm ID to process as (default `1`).
- **CLEAR_REDIS** — Flush Redis before running (default `yes`). Set to `no` when testing duplicate-detection or session-cached behaviors.
- **CLEAR_PRIOR_RUN** — Detect + clear any prior run of THIS specific inbox item before launching (default `auto`, mirrors the base skill). Inspects `private.inbox_item` for rows whose `raw_content` byte length matches the `.eml` file size and clears just those rows + their dependent `court_document`, `court_envelope`, `inbox_item_process_job`, `inbox_item_notification` rows (case + jurisdiction are preserved). Values:
  - `auto` (default) — detect + clear if found; no-op if no prior run exists.
  - `yes` — always attempt the clear (no detection skip).
  - `no` — never clear; the run will likely hit duplicate-detection (`ProcessorResult.duplicate()`) if a prior run exists.
- **CLEAR_DATABASE** — Delete ALL envelope/document/inbox_item rows for this firm before running (default `no`). Use only for a completely fresh slate — `CLEAR_PRIOR_RUN=auto` is usually enough.
- **BUILD** — Rebuild `cli-all.jar` from current branch (default `auto`). Same staleness rules as the base skill:
  - `auto` — rebuild if any of: jar missing, any `.java` under `projects/` is newer than the jar, or the current `git HEAD` differs from `.last-built-head`.
  - `yes` — always rebuild.
  - `no` — never rebuild; fail fast if the jar is missing.

If the user invokes the skill inline (e.g., `/process-email-notice-cli some-notice.eml --heap 1024m --firm 2`), parse those and proceed.

## CRITICAL: Execution Strategy

**This skill MUST run with minimal user interaction.** Combine operations into the fewest possible Bash tool calls. Target **3 Bash calls** for a standard run, mirroring the base skill:

1. **Setup** — resolve EML, verify infra, optional Redis flush / DB clear, env-var presence check.
2. **Build** — `gradle :cli:shadowJar` if stale (skipped automatically if nothing changed).
3. **Launch + monitor** — start the CLI in the background, arm a `Monitor` on the live log until exit.

Phase 4 (post-run analysis) runs as one more Bash call after the container exits.

Typical timings:
- Fully cached run: Phase 1 ≈ 1s, Phase 2 ≈ 0.5s, Phase 3 = EML processing time.
- Fresh branch switch: Phase 2 ≈ 60-90s for jar rebuild.

---

## Phase 1: Setup, verify infra, clear state

Single Bash call. Substitute the resolved parameter values:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ---- Parameters (substituted by the agent) ----
PROJECT_ROOT="${PROJECT_ROOT:-/workspace/ecfx-backend}"
EML_INPUT="<USER_PROVIDED_FILENAME>"
HEAP="<HEAP>"
FIRM="<FIRM>"
CLEAR_REDIS="<yes|no>"
CLEAR_PRIOR_RUN="<auto|yes|no>"
CLEAR_DATABASE="<yes|no>"

# ---- Paths ----
# Persist marker + last-run env on the workspace volume so they survive
# claude-code-container restarts (HOME may be ephemeral).
SKILL_STATE_DIR="${SKILL_STATE_DIR:-/workspace/.process-email-notice-cli}"
mkdir -p "$SKILL_STATE_DIR"
HEAD_MARKER="$SKILL_STATE_DIR/.last-built-head"
LAST_RUN_ENV="$SKILL_STATE_DIR/.last-run.env"

cd "$PROJECT_ROOT"

# ---- Step 1: Resolve EML path (absolute / project-relative / test-emails / recursive search) ----
echo "=== Step 1: Resolve .eml file ==="
if [ -f "$EML_INPUT" ]; then
    EML_PATH="$(realpath "$EML_INPUT")"
elif [ -f "$PROJECT_ROOT/$EML_INPUT" ]; then
    EML_PATH="$PROJECT_ROOT/$EML_INPUT"
elif [ -f "$PROJECT_ROOT/test-emails/$EML_INPUT" ]; then
    EML_PATH="$PROJECT_ROOT/test-emails/$EML_INPUT"
else
    EML_PATH="$(find "$PROJECT_ROOT/test-emails" -type f -name "*${EML_INPUT##*/}*" -name "*.eml" 2>/dev/null | head -1)"
fi
if [ -z "${EML_PATH:-}" ] || [ ! -f "$EML_PATH" ]; then
    echo "ERROR: could not resolve .eml '$EML_INPUT' under $PROJECT_ROOT/test-emails"
    exit 1
fi
echo "  Found: $EML_PATH"
echo "  Size:  $(ls -lh "$EML_PATH" | awk '{print $5}')"

# ---- Step 2: Verify infra (postgres + redis sidecars) ----
echo ""
echo "=== Step 2: Verify infrastructure ==="
INFRA_OK=true

# Postgres / Redis / RabbitMQ are reached differently depending on where the
# skill runs:
#   - Mac developer with docker-compose port mappings  → localhost:<port>
#   - Inside a sibling container on the same compose network → DNS names
#     `postgres`, `redis`, `rabbit`
#
# Rather than force the operator to set DATABASE_HOST / REDIS_HOST / RABBITMQ_HOST
# manually, we probe a *list* of candidates per service. Order:
#   1. Explicit env var ($DATABASE_HOST, $REDIS_HOST, $RABBITMQ_HOST). Highest
#      priority; lets ad-hoc setups override everything.
#   2. localhost — covers the Mac docker-compose case.
#   3. The compose-style DNS name (`postgres`, `redis`, `rabbit`) — covers the
#      sibling-container case.
# First reachable candidate wins. The resolved host/port are exported via
# LAST_RUN_ENV so Phase 3 can use the same values when launching the JVM (and
# can rewrite REDIS_URI / DATASOURCES_DEFAULT_URL on the fly if the env-file
# strings name an unreachable host).
#
# Each probe prefers the native client tool (pg_isready / redis-cli) but falls
# back to a raw TCP probe so the skill works on hosts without those clients.
#
# probe_tcp must work under both bash and zsh. The Claude Code "Bash tool"
# actually pipes scripts through the user's $SHELL — typically zsh — and the
# `</dev/tcp/host/port` pseudo-device is a bash-only feature that silently
# fails under zsh. Probe order, falling through on failure:
#   1. nc -z (if `nc` installed)
#   2. python3 socket.create_connection (always available in claude-code-container)
#   3. bash /dev/tcp redirect (only works if running under bash)
probe_tcp() {
    local host="$1" port="$2"
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$host" "$port" >/dev/null 2>&1 && return 0 || return 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket,sys; s=socket.socket(); s.settimeout(2); s.connect((sys.argv[1], int(sys.argv[2]))); s.close()" "$host" "$port" >/dev/null 2>&1
        return $?
    fi
    (echo > /dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

# Build the candidate list for a service: explicit env var (if set) first,
# then localhost, then the compose DNS name. De-duplicates so an explicit
# `DATABASE_HOST=localhost` doesn't probe localhost twice.
build_candidates() {
    local explicit="$1" compose_name="$2"
    local out=()
    [ -n "$explicit" ] && out+=("$explicit")
    [ "$explicit" != "localhost" ] && out+=("localhost")
    [ "$explicit" != "$compose_name" ] && [ "localhost" != "$compose_name" ] && out+=("$compose_name")
    printf '%s\n' "${out[@]}"
}

# ---- Postgres ----
PGPORT="${DATABASE_PORT:-5432}"
PGUSER="${DATABASE_USER:-ecfx}"
PGDATABASE="${DATABASE_NAME:-ecfx}"
PGHOST=""
for cand in $(build_candidates "${DATABASE_HOST:-}" "postgres"); do
    if command -v pg_isready >/dev/null 2>&1 && pg_isready -h "$cand" -p "$PGPORT" -U "$PGUSER" -q 2>/dev/null; then
        PGHOST="$cand"; echo "  Postgres ($cand:$PGPORT): OK (pg_isready)"; break
    elif probe_tcp "$cand" "$PGPORT"; then
        PGHOST="$cand"; echo "  Postgres ($cand:$PGPORT): OK (TCP probe)"; break
    else
        echo "  Postgres ($cand:$PGPORT): not reachable"
    fi
done
if [ -z "$PGHOST" ]; then
    echo "  Postgres: DOWN on all candidates — start your postgres on port $PGPORT"
    INFRA_OK=false
fi

# ---- Redis ----
# Use $REDIS_HOST / $REDIS_PORT if set; otherwise parse REDIS_URI for hints;
# otherwise probe the candidate list with default port 6379.
REDIS_PORT="${REDIS_PORT:-}"
REDIS_HOST_HINT="${REDIS_HOST:-}"
if [ -z "$REDIS_HOST_HINT" ] && [ -n "${REDIS_URI:-}" ]; then
    _r="${REDIS_URI#*//}"
    REDIS_HOST_HINT="${_r%%:*}"
    case "$_r" in
        *:*) REDIS_PORT="${REDIS_PORT:-${_r##*:}}";;
    esac
fi
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_HOST=""
for cand in $(build_candidates "$REDIS_HOST_HINT" "redis"); do
    if command -v redis-cli >/dev/null 2>&1 && redis-cli -h "$cand" -p "$REDIS_PORT" PING 2>/dev/null | grep -q PONG; then
        REDIS_HOST="$cand"; echo "  Redis ($cand:$REDIS_PORT): OK (PONG)"; break
    elif probe_tcp "$cand" "$REDIS_PORT"; then
        REDIS_HOST="$cand"; echo "  Redis ($cand:$REDIS_PORT): OK (TCP probe)"; break
    else
        echo "  Redis ($cand:$REDIS_PORT): not reachable"
    fi
done
if [ -z "$REDIS_HOST" ]; then
    echo "  Redis: DOWN on all candidates — start your redis on port $REDIS_PORT"
    INFRA_OK=false
fi

# ---- RabbitMQ (optional) ----
RABBIT_PORT="${RABBITMQ_PORT:-5672}"
RABBIT_HOST=""
for cand in $(build_candidates "${RABBITMQ_HOST:-}" "rabbit"); do
    if probe_tcp "$cand" "$RABBIT_PORT"; then
        RABBIT_HOST="$cand"; echo "  RabbitMQ ($cand:$RABBIT_PORT): OK"; break
    fi
done
[ -z "$RABBIT_HOST" ] && echo "  RabbitMQ: DOWN on all candidates (optional — warn only)"

[ "$INFRA_OK" = "true" ] || { echo "ERROR: infrastructure check failed"; exit 1; }

# ---- Step 2b: Locate the provider env file + verify required keys ----
# Mirrors the base skill, which bind-mounts harness/pacer-oom.env into the
# container. We use the same file shape (renamed receipts.env) and load it
# in Phase 3 before launching the JVM, so every provider credential, signing
# key, and integration URL is present.
#
# SECURITY: the real env file contains AWS keys, court-system credentials,
# OpenAI tokens, signing keys, etc. It is NEVER committed to git. The
# repository ships a `harness/receipts.env.example` template with
# placeholders; the skill bootstraps a real file from the template on first
# run and fails fast until you fill in the placeholders.
#
# Resolution order (first hit wins):
#   1) $RECEIPTS_ENV_FILE if exported.
#   2) $PROJECT_ROOT/.claude/receipts.env (project-local override; gitignored).
#   3) ${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/receipts.env (per-user; outside the plugin, so updates keep it).
# If none exist, copy the .example template into slot (3) and abort with
# instructions to populate it.
echo ""
echo "=== Step 2b: Provider env file ==="
SKILL_DIR="${CLAUDE_SKILL_DIR:-}"
[ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR/harness" ] \
    || { echo "ERROR: \${CLAUDE_SKILL_DIR} was not substituted (SKILL_DIR='$SKILL_DIR') — set SKILL_DIR to this skill's base directory" >&2; exit 1; }
SKILL_HARNESS_DIR="$SKILL_DIR/harness"
SKILL_DEFAULT_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/receipts.env"
SKILL_EXAMPLE_ENV="$SKILL_HARNESS_DIR/receipts.env.example"
if [ -n "${RECEIPTS_ENV_FILE:-}" ] && [ -f "$RECEIPTS_ENV_FILE" ]; then
    ENV_FILE="$RECEIPTS_ENV_FILE"
elif [ -f "$PROJECT_ROOT/.claude/receipts.env" ]; then
    ENV_FILE="$PROJECT_ROOT/.claude/receipts.env"
elif [ -f "$SKILL_DEFAULT_ENV" ]; then
    ENV_FILE="$SKILL_DEFAULT_ENV"
elif [ -f "$SKILL_EXAMPLE_ENV" ]; then
    mkdir -p "$(dirname "$SKILL_DEFAULT_ENV")" && chmod 700 "$(dirname "$SKILL_DEFAULT_ENV")"
    cp "$SKILL_EXAMPLE_ENV" "$SKILL_DEFAULT_ENV"
    chmod 600 "$SKILL_DEFAULT_ENV" 2>/dev/null || true
    echo "  BOOTSTRAP: copied template -> $SKILL_DEFAULT_ENV"
    echo "             Populate the __FILL_ME_IN__ / __username__ / __password__ placeholders"
    echo "             with real values, then re-run. (File is gitignored.)"
    echo "  ERROR: receipts.env is unpopulated; cannot run."
    exit 1
else
    echo "  ERROR: No receipts.env or receipts.env.example found. Expected one of:"
    echo "    \$RECEIPTS_ENV_FILE"
    echo "    $PROJECT_ROOT/.claude/receipts.env"
    echo "    $SKILL_DEFAULT_ENV  (or $SKILL_EXAMPLE_ENV to bootstrap)"
    exit 1
fi
echo "  Using: $ENV_FILE"

# Refuse to launch with placeholder values still present (catches half-edits).
if grep -qE "__FILL_ME_IN__|__username__|__password__" "$ENV_FILE"; then
    echo "  ERROR: $ENV_FILE still contains placeholder values:"
    grep -nE "__FILL_ME_IN__|__username__|__password__" "$ENV_FILE" | head -10
    echo "  Replace each placeholder with the real credential before re-running."
    exit 1
fi

# Verify the file actually defines the keys the receipt processor needs.
# This catches half-populated env files (the base skill's #1 source of pain).
REQUIRED_KEYS=(
    REDIS_URI
    DATASOURCES_DEFAULT_URL
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    ECFX_ENVIRONMENT
    ECFX_BASE_DOMAIN
    ECFX_DOCUMENT_BUCKET
    ECFX_ENC_SERVICE_USERNAME
    ECFX_ENC_SERVICE_PW
    PACER_USERNAME
    PACER_PASSWORD
    CAMOUFOX_GRID_URL
    OPENAI_STAMP_COMPARISON_API_KEY
    TITLE_EXTRACT_CLIENT_URL
    URL_SIGNING_PRIVATE_KEY
    URL_SIGNING_PUBLIC_KEY
)
MISSING_KEYS=()
for k in "${REQUIRED_KEYS[@]}"; do
    grep -qE "^${k}=" "$ENV_FILE" || MISSING_KEYS+=("$k")
done
if [ "${#MISSING_KEYS[@]}" -gt 0 ]; then
    echo "  WARN: missing keys in $ENV_FILE:"
    printf '    - %s\n' "${MISSING_KEYS[@]}"
    echo "  (Provider-specific runs that need these will fail. Copy missing keys from the base skill's harness/pacer-oom.env.)"
else
    echo "  All required keys present (${#REQUIRED_KEYS[@]} checked)."
fi
echo "ENV_FILE='$ENV_FILE'" >> /tmp/.cli-env-file.tmp  # consumed below

# ---- Step 3: State management ----
echo ""
echo "=== Step 3: State management ==="
if [ "$CLEAR_REDIS" = "yes" ]; then
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" FLUSHDB >/dev/null && echo "  Redis: FLUSHED (redis-cli)"
    else
        # No redis-cli on host — speak RESP directly over TCP.
        # FLUSHDB has no args; one-liner per https://redis.io/commands/flushdb
        if printf '*1\r\n$7\r\nFLUSHDB\r\n' | nc -w 2 "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null | grep -q '^+OK'; then
            echo "  Redis: FLUSHED (RESP via nc)"
        else
            echo "  Redis: WARN — FLUSHDB attempt failed (continuing)"
        fi
    fi
else
    echo "  Redis: preserved"
fi

# CLEAR_PRIOR_RUN — surgical cleanup of any prior run of THIS .eml.
#
# The application doesn't store the public `inbox_xxx` ID as a column on
# `private.inbox_item` (it's derived from the UUID `id` at display time), so
# we identify "this inbox" by matching `length(raw_content)` to the EML
# file's byte size. This is the same selector cleanup-inbox-item uses.
#
# Cascade order (FK-safe):
#   1. inbox_item_process_job   .parent_id       -> inbox_item.id   (NOT inbox_item_id)
#   2. inbox_item_notification  .inbox_item_id   -> inbox_item.id
#   3. court_document           .inbox_item_id   -> inbox_item.id   (nullable)
#   4. court_envelope           (only those left orphaned by step 3)
#   5. inbox_item               itself
#   6. Orphan envelope sweep    — firm-scoped, removes any court_envelope rows
#      that have no court_document referencing them. This catches envelopes left
#      behind when a prior run's court_document.inbox_item_id was already null
#      (or the FK link was broken in some other way) so step 4 above couldn't
#      find them. Without this, a re-run hits Tyler's `hasEnvelope` DB check
#      via the doc-hash-derived envelope reference_id and returns DUPLICATE
#      with court_document=0 — even though Redis dedupe was flushed.
# Case + jurisdiction rows are preserved (so the rerun reuses them).
if [ "$CLEAR_PRIOR_RUN" != "no" ]; then
    # Shell function (NOT a string variable) so the `psql` invocation
    # word-splits correctly under both bash and zsh. The previous
    # `PSQL="psql -h ..."; $PSQL -c "..."` pattern works under bash but
    # under zsh `$PSQL` is a single token, producing
    # `command not found: psql -h postgres ...` and silently skipping
    # the SQL. The Claude Code "Bash tool" actually pipes through the
    # user's $SHELL (typically zsh), so the function form is required.
    psql_run() { psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tAq "$@"; }
    EML_BYTES=$(wc -c < "$EML_PATH" | tr -d ' ')
    # Tolerance ±200 bytes to absorb minor encoding differences when the
    # ingestion pipeline normalizes line endings / strips trailing whitespace.
    LO=$(( EML_BYTES - 200 ))
    HI=$(( EML_BYTES + 200 ))
    PRIOR_COUNT=$(psql_run -c "SELECT count(*) FROM private.inbox_item
                              WHERE firm_id = $FIRM
                                AND length(raw_content) BETWEEN $LO AND $HI;" 2>/dev/null | tr -d '[:space:]')
    # Orphan envelopes are also a "prior run" indicator even when the inbox
    # row was already cleaned up — count them so we trigger the cleanup pass.
    ORPHAN_ENV_COUNT=$(psql_run -c "
        SELECT count(*) FROM private.court_envelope env
         WHERE firm_id = $FIRM
           AND NOT EXISTS (
               SELECT 1 FROM private.court_document cd
                WHERE cd.envelope_id = env.id);" 2>/dev/null | tr -d '[:space:]')
    PRIOR_COUNT=${PRIOR_COUNT:-0}
    ORPHAN_ENV_COUNT=${ORPHAN_ENV_COUNT:-0}
    if [ "$PRIOR_COUNT" -gt 0 ] || [ "$ORPHAN_ENV_COUNT" -gt 0 ] || [ "$CLEAR_PRIOR_RUN" = "yes" ]; then
        echo "  Prior run: detected $PRIOR_COUNT inbox row(s), $ORPHAN_ENV_COUNT orphan envelope(s) for firm=$FIRM (bytes≈$EML_BYTES); clearing..."
        # PostgreSQL CTEs only scope to a single statement, so we materialize
        # the target inbox and envelope IDs into temp tables (same connection)
        # and reference them across all six DELETEs in one transaction.
        psql_run -v ON_ERROR_STOP=1 <<SQL || echo "  WARN: cleanup failed"
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
-- Orphan envelope sweep: any envelope for this firm with no documents
-- pointing at it. This catches envelopes from earlier partial cleanups and
-- prevents Tyler/etc.'s hasEnvelope DB check from short-circuiting a rerun
-- with DUPLICATE.
DELETE FROM private.court_envelope env
 WHERE firm_id = $FIRM
   AND NOT EXISTS (
       SELECT 1 FROM private.court_document cd
        WHERE cd.envelope_id = env.id);
COMMIT;
SQL
        echo "  Prior run: CLEARED ($PRIOR_COUNT inbox_item row(s) + $ORPHAN_ENV_COUNT orphan envelope(s) + dependents)"
    elif [ "$CLEAR_PRIOR_RUN" = "auto" ]; then
        echo "  Prior run: none detected for this EML (firm=$FIRM, bytes≈$EML_BYTES)"
    fi
else
    echo "  Prior run: CLEAR_PRIOR_RUN=no, skipping detection"
fi

# Optional full firm-scoped wipe — rare; prefer CLEAR_PRIOR_RUN=auto.
if [ "$CLEAR_DATABASE" = "yes" ]; then
    echo "  Database: clearing ALL receipt rows for firm=$FIRM..."
    # Function form for zsh-compatibility (see CLEAR_PRIOR_RUN block).
    psql_run_full() { psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tAq "$@"; }
    psql_run_full <<SQL >/dev/null 2>&1 || echo "  WARN: partial cleanup (some tables may not exist)"
DELETE FROM private.inbox_item_process_job WHERE firm_id = $FIRM;
DELETE FROM private.inbox_item_notification WHERE firm_id = $FIRM;
DELETE FROM private.court_document WHERE firm_id = $FIRM;
DELETE FROM private.court_envelope WHERE firm_id = $FIRM;
DELETE FROM private.inbox_item WHERE firm_id = $FIRM;
SQL
    echo "  Database: CLEARED (firm-wide)"
else
    echo "  Database: firm-wide clear not requested"
fi

# ---- Step 4: Branch info (for the run summary) ----
echo ""
echo "=== Step 4: Current branch ==="
echo "  branch: $(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo unknown)"
echo "  head:   $(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) — $(git -C "$PROJECT_ROOT" log -1 --format='%s' 2>/dev/null | cut -c1-80)"

# ---- Step 5: Persist resolved values for Phase 2 / 3 ----
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/process-email-cli-$TS.log"
{
  echo "EML_PATH='$EML_PATH'"
  echo "HEAP='$HEAP'"
  echo "FIRM='$FIRM'"
  echo "LOG_FILE='$LOG_FILE'"
  echo "TS='$TS'"
  echo "PROJECT_ROOT='$PROJECT_ROOT'"
  echo "SKILL_STATE_DIR='$SKILL_STATE_DIR'"
  echo "ENV_FILE='$ENV_FILE'"
  # Resolved infra hosts/ports — Phase 3 uses these to rewrite localhost-shaped
  # URIs in receipts.env on the fly when the actual reachable host is different
  # (e.g. running inside a sibling container where postgres/redis live at the
  # compose DNS name rather than localhost).
  echo "RESOLVED_PGHOST='$PGHOST'"
  echo "RESOLVED_PGPORT='$PGPORT'"
  echo "RESOLVED_REDIS_HOST='$REDIS_HOST'"
  echo "RESOLVED_REDIS_PORT='$REDIS_PORT'"
  echo "RESOLVED_RABBIT_HOST='$RABBIT_HOST'"
  echo "RESOLVED_RABBIT_PORT='$RABBIT_PORT'"
} > "$LAST_RUN_ENV"

echo ""
echo "=== Ready ==="
echo "  eml:    $EML_PATH"
echo "  heap:   $HEAP"
echo "  firm:   $FIRM"
echo "  log:    $LOG_FILE"
```

---

## Phase 2: Build (only rebuilds when stale)

Single Bash call. Same staleness logic as the base skill: `BUILD=auto` is the default and is a no-op when the jar matches HEAD.

```bash
#!/usr/bin/env bash
set -euo pipefail

. /workspace/.process-email-notice-cli/.last-run.env
BUILD="<auto|yes|no>"

cd "$PROJECT_ROOT"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo none)"
JAR_GLOB="$PROJECT_ROOT/projects/cli/build/libs/cli-*-all.jar"

# Decide whether to build.
NEED_BUILD="no"; REASON=""
if [ "$BUILD" = "yes" ]; then
    NEED_BUILD="yes"; REASON="BUILD=yes (forced)"
elif [ "$BUILD" = "no" ]; then
    if ! ls $JAR_GLOB >/dev/null 2>&1; then
        echo "ERROR: BUILD=no but no cli-*-all.jar found. Run with BUILD=auto or BUILD=yes."
        exit 1
    fi
    REASON="BUILD=no (jar present)"
else
    if ! ls $JAR_GLOB >/dev/null 2>&1; then
        NEED_BUILD="yes"; REASON="cli-*-all.jar missing"
    else
        NEWEST_JAR="$(ls -t $JAR_GLOB | head -1)"
        if find "$PROJECT_ROOT/projects" -name '*.java' -newer "$NEWEST_JAR" -print -quit 2>/dev/null | grep -q .; then
            NEED_BUILD="yes"; REASON=".java source newer than cli-all.jar"
        elif [ -f "$HEAD_MARKER" ] && [ "$(cat "$HEAD_MARKER")" != "$CURRENT_HEAD" ]; then
            NEED_BUILD="yes"; REASON="git HEAD changed since last build ($(cut -c1-7 "$HEAD_MARKER") → ${CURRENT_HEAD:0:7})"
        elif [ ! -f "$HEAD_MARKER" ]; then
            NEED_BUILD="yes"; REASON="no marker file — first build on this branch"
        else
            REASON="all checks pass (jar + HEAD marker current)"
        fi
    fi
fi

echo "=== Phase 2: Build decision ==="
echo "  BUILD mode: $BUILD"
echo "  Decision:   $NEED_BUILD — $REASON"

if [ "$NEED_BUILD" = "yes" ]; then
    echo ""
    echo "=== Building :cli:shadowJar ==="
    if [ -x "$PROJECT_ROOT/gradlew" ]; then
        GRADLE_OPTS="${GRADLE_OPTS:--Xms2048m -Xmx2048m}" "$PROJECT_ROOT/gradlew" --no-daemon :cli:shadowJar 2>&1 | tail -10
        BUILD_RC="${PIPESTATUS[0]}"
    else
        # Fallback: system gradle (provided by claude-code-container at /opt/gradle/bin/gradle)
        GRADLE_OPTS="${GRADLE_OPTS:--Xms2048m -Xmx2048m}" gradle --no-daemon :cli:shadowJar 2>&1 | tail -10
        BUILD_RC="${PIPESTATUS[0]}"
    fi
    [ "$BUILD_RC" -eq 0 ] || { echo "  ERROR: gradle build failed"; exit 1; }
    echo "$CURRENT_HEAD" > "$HEAD_MARKER"
    echo "  Marker updated: $HEAD_MARKER → $CURRENT_HEAD"
fi

JAR="$(ls -t $JAR_GLOB | head -1)"
[ -f "$JAR" ] || { echo "ERROR: shadowJar output not found at $JAR_GLOB"; exit 1; }
echo "JAR='$JAR'" >> "$LAST_RUN_ENV"
echo "  jar:    $JAR"
```

---

## Phase 3: Launch and Monitor

Launch the CLI in the background, redirect stdout+stderr to the timestamped log file, then arm a `Monitor` that streams the key phase transitions. Mirrors the base skill's Phase 2b.

```bash
#!/usr/bin/env bash
set -uo pipefail

. /workspace/.process-email-notice-cli/.last-run.env

# Heap-dump destination on the shared workspace volume so the host operator
# can grab dumps without `docker cp`.
DUMP_DIR="${HEAP_DUMP_DIR:-/workspace/shared/heap-dumps}"
mkdir -p "$DUMP_DIR"
chmod 775 "$DUMP_DIR" 2>/dev/null || true
HEAP_DUMP_PATH="$DUMP_DIR/heap-${TS}.hprof"

cd "$PROJECT_ROOT"

# Load the provider env file resolved in Phase 1. This is the parity hook with
# the base skill's `docker run --env-file pacer-oom.env`: every REDIS_URI,
# DATASOURCES_DEFAULT_URL, AWS_*, PACER_*, TYLERS_*, OPENAI_*, CAMOUFOX_GRID_URL,
# URL_SIGNING_*, etc. is exported to the JVM.
#
# IMPORTANT: We do NOT use `set -a; . "$ENV_FILE"; set +a`. Docker's --env-file
# treats values literally, but `source` runs them through the shell parser, so
# values containing literal `$` (bcrypt hashes like SENDGRID_INBOUND_PASSWORD,
# URL_SIGNING_PRIVATE_KEY base64, etc.) fail with "parameter not set" and
# truncate the env. Instead, parse KEY=VALUE per line and export verbatim.
# Per-run rewrite of localhost-shaped infra URIs. The receipts.env template
# defaults to localhost (the Mac docker-compose shape). When Phase 1 resolves
# postgres/redis/rabbit at a different host (e.g. the compose DNS name from
# inside a sibling container), we rewrite those keys at export time so the JVM
# connects to the same host that Phase 1 just verified. Other env-file values
# pass through verbatim.
rewrite_uri_host() {
    # Replace the host portion of `scheme://host[:port]/...` URIs and bare
    # `host:port` HOSTS, but only when the existing host is `localhost` /
    # `127.0.0.1` and the resolved host is different.
    local val="$1" resolved_host="$2"
    [ -z "$resolved_host" ] && { printf '%s' "$val"; return; }
    [ "$resolved_host" = "localhost" ] && { printf '%s' "$val"; return; }
    case "$val" in
        *//localhost*|*//127.0.0.1*)
            printf '%s' "$val" | sed -E "s#//(localhost|127\.0\.0\.1)#//$resolved_host#"
            ;;
        *)
            printf '%s' "$val"
            ;;
    esac
}

while IFS= read -r line; do
    # Skip comments and blanks
    case "$line" in ''|\#*) continue;; esac
    # Split on FIRST '='. Tolerate leading "export ".
    line="${line#export }"
    key="${line%%=*}"
    val="${line#*=}"
    # Strip surrounding double-quotes if present
    case "$val" in
        \"*\") val="${val#\"}"; val="${val%\"}";;
    esac
    # Validate KEY: must be a valid env var name
    case "$key" in
        [A-Za-z_]*) ;;
        *) continue;;
    esac
    # Rewrite localhost-shaped URIs to the Phase-1-resolved host when needed.
    case "$key" in
        REDIS_URI)               val="$(rewrite_uri_host "$val" "${RESOLVED_REDIS_HOST:-}")" ;;
        DATASOURCES_DEFAULT_URL) val="$(rewrite_uri_host "$val" "${RESOLVED_PGHOST:-}")" ;;
    esac
    export "$key=$val"
done < "$ENV_FILE"

# Echo the resolved infra targets so the run log makes the rewrite visible.
echo "  resolved postgres: ${RESOLVED_PGHOST:-?}:${RESOLVED_PGPORT:-?}"
echo "  resolved redis:    ${RESOLVED_REDIS_HOST:-?}:${RESOLVED_REDIS_PORT:-?}"
echo "  resolved rabbit:   ${RESOLVED_RABBIT_HOST:-?}:${RESOLVED_RABBIT_PORT:-?}"

echo "=== Phase 3: Launch CLI in background ==="
echo "  env file:  $ENV_FILE"
echo "  heap:      $HEAP"
echo "  firm:      $FIRM"
echo "  eml:       $EML_PATH"
echo "  log:       $LOG_FILE"
echo "  heap dump: $HEAP_DUMP_PATH (on OOM only)"

# JVM flags — mirror pacer-oom.env from the base skill so OOM behavior matches prod:
#   -Dmicronaut.environments=local : load application-local.yml (DB user/password
#                                    + non-default datasource overrides). The base
#                                    skill's Dockerfile baked this in via ENTRYPOINT;
#                                    we set it explicitly here. Override with
#                                    MICRONAUT_ENVIRONMENTS=... if you need a
#                                    different profile.
#   -Xmx                          : explicit heap cap (overridable via HEAP).
#   ExitOnOutOfMemoryError        : kill the JVM immediately on OOM (no zombie state).
#   HeapDumpOnOutOfMemoryError    : write hprof before exit.
#   HeapDumpPath                  : on shared volume → host-visible.
#   MaxDirectMemorySize=192m      : bound Netty / NIO off-heap so direct-OOM is reproducible.
#   UseG1GC + MaxGCPauseMillis    : prod GC profile (G1, 200ms pause target).
#   -Xlog:gc*                     : GC events into stdout for post-run heap analysis.
# Quoted in an array so zsh doesn't try to glob `-Xlog:gc*`.
MN_ENV="${MICRONAUT_ENVIRONMENTS:-local}"
JVM_ARGS=(
  "-Dmicronaut.environments=${MN_ENV}"
  "-Xmx${HEAP}"
  "-XX:+ExitOnOutOfMemoryError"
  "-XX:+HeapDumpOnOutOfMemoryError"
  "-XX:HeapDumpPath=${HEAP_DUMP_PATH}"
  "-XX:MaxDirectMemorySize=192m"
  "-XX:+UseG1GC"
  "-XX:MaxGCPauseMillis=200"
  "-Xlog:gc*"
)
nohup java "${JVM_ARGS[@]}" -jar "$JAR" email-receipt --firm "$FIRM" "$EML_PATH" \
    > "$LOG_FILE" 2>&1 &
BG_PID=$!
disown
echo "  bg_pid=$BG_PID"
echo "BG_PID='$BG_PID'" >> "$LAST_RUN_ENV"
echo "HEAP_DUMP_PATH='$HEAP_DUMP_PATH'" >> "$LAST_RUN_ENV"
```

Then arm a `Monitor` with this filter (same one the base skill uses — covers any provider):

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

Keep the `Monitor` armed until the JVM exits (`wait $BG_PID` finishes). When it exits, the log will end with the JVM's final stdout — Phase 4 turns that into a structured summary.

---

## Phase 4: Post-Run Analysis

One Bash call once the JVM has exited. Mirrors the base skill's Phase 3 + adds the egress-monitor delta.

```bash
#!/usr/bin/env bash
set -uo pipefail

. /workspace/.process-email-notice-cli/.last-run.env

# Wait for the background JVM to finish (no-op if already exited).
if [ -n "${BG_PID:-}" ] && kill -0 "$BG_PID" 2>/dev/null; then
    wait "$BG_PID" 2>/dev/null || true
fi
EXIT_CODE=$(grep -oE 'Exit code: [0-9]+' "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $3}')
EXIT_CODE="${EXIT_CODE:-?}"

echo "=== Final result ==="
case "$EXIT_CODE" in
    0)   echo "RESULT: Processing completed (exit 0) — see log for CUSTOMER ACTION vs PROCESSING COMPLETE" ;;
    137) echo "RESULT: Killed (SIGKILL — likely cgroup OOM, log truncated)" ;;
    143) echo "RESULT: Terminated (SIGTERM)" ;;
    ?)   echo "RESULT: JVM exit code not captured — process may still be running" ;;
    *)   echo "RESULT: Exit code $EXIT_CODE" ;;
esac

echo ""
echo "=== Peak heap observed ==="
grep -oE "heap_used_mb=[0-9]+" "$LOG_FILE" | sort -t= -k2 -n | tail -3 || echo "  (no heap_used_mb lines)"

echo ""
echo "=== Key phase transitions ==="
grep -E "MODE_SELECTED|STAMP_DEFER.*(START|COMPLETE)|SKIPPING_OVER_SIZE_LIMIT|action=storing_individually|DOCUMENT_LINK_EXTRACTOR.*Phase 1 complete|PROCESSING COMPLETE|CUSTOMER ACTION|FAILURE" "$LOG_FILE" | tail -20

echo ""
echo "=== Exceptions thrown ==="
grep -oE "[A-Z][a-zA-Z]+Exception" "$LOG_FILE" | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== Heap dumps (if any) ==="
ls -lh "${HEAP_DUMP_PATH%/*}"/*.hprof 2>/dev/null | tail -3 || echo "  (none produced)"

echo ""
echo "=== Egress monitor — most recent HTTP attempts ==="
tail -n 20 /workspace/shared/network-monitor/http-attempts.jsonl 2>/dev/null || echo "  (no attempts yet)"

echo ""
echo "=== Egress monitor — refresh pending-review.md ==="
python3 /usr/local/bin/egress-monitor/summarize.py 2>/dev/null || true
echo "  Open ~/Desktop/claude-shared/network-monitor/pending-review.md to review blocked hosts."
```

---

## Presenting Results to the User

Same structure as the base skill, plus the egress-monitor delta:

1. **Outcome** — one-line verdict: `PROCESSING COMPLETE` / `CUSTOMER ACTION REQUIRED` / specific `Exception` / OOM / exit code.
2. **Branch + commit** — which code the JVM was built from (captured in Phase 1).
3. **Timeline** — key phase transitions.
4. **Heap trajectory** — peak JVM heap + whether a heap dump was produced.
5. **Exceptions** — count and class distribution.
6. **Egress delta** — distinct hosts hit, any blocked hosts in `pending-review.md`. Highlight blocked hosts with the suggested `resolve_domain "..."` line so the operator can paste them into `scripts/init-firewall.sh`.
7. **Next steps** — if reproducing a bug, link to the Jira ticket and the relevant `claude-docs/` doc; cite specific log lines for evidence.

---

## Reference: Environment File

Provider credentials, integration URLs, and the Postgres/Redis URIs are loaded
from a single env file before the JVM is launched.

### Why a local-only file (and not a tracked file)

The env file contains real credentials — AWS keys, court-system creds (PACER,
Tylers, NJ Selenium, PTAB, ITC), OpenAI API key, signing keys, partner
secrets, etc. **It must never be committed.**

The repository ships `harness/receipts.env.example` with placeholders
(`__FILL_ME_IN__`, `__username__`, `__password__`) and gitignores the real
file. On first run the skill copies the template into the per-user slot and
fails fast until you populate it; the placeholder check refuses to launch
with any `__FILL_ME_IN__` left in the file.

### Resolution order (first hit wins)

1. `$RECEIPTS_ENV_FILE` (export in your shell to override).
2. `$PROJECT_ROOT/.claude/receipts.env` (project-local override; gitignored).
3. `${XDG_CONFIG_HOME:-$HOME/.config}/ecfx/receipts.env` (per-user; outside the plugin, which an update replaces).

If none exist, the skill copies
`${CLAUDE_SKILL_DIR}/harness/receipts.env.example`
to slot (3), `chmod 600`s it, and exits with instructions.

### What's in the template

The shipped `.example` file mirrors the base skill's `harness/pacer-oom.env.example`
key-for-key, with `REDIS_URI=redis://localhost:6379` and
`DATASOURCES_DEFAULT_URL=jdbc:postgresql://localhost:5432/...` so the skill
works **wherever the receipt-processing CLI is invoked** — a developer's Mac,
a CI runner, or inside a container that exposes Postgres/Redis on the local
loopback.

If you're running inside a container that has Postgres/Redis as named
sidecars on the same compose network rather than published ports, override
the relevant pieces (in your shell, in `docker-compose` env, or in
`$PROJECT_ROOT/.claude/receipts.env`):
- `DATABASE_HOST` (defaults `localhost`) and optional `DATABASE_PORT`.
- `REDIS_HOST` / `REDIS_PORT`, OR a full `REDIS_URI=redis://host:port`.
- `DATASOURCES_DEFAULT_URL=jdbc:postgresql://host:port/db?currentSchema=...`.
- `RABBITMQ_HOST` / `RABBITMQ_PORT`.

Camoufox + NJ Selenium still reach the macOS host via `host.docker.internal`,
which Docker Desktop resolves from inside any container.

### Bootstrap on a fresh machine

```bash
# After cloning, the skill auto-bootstraps on first run:
/process-email-notice-cli some.eml
# → BOOTSTRAP: copied template -> ~/.config/ecfx/receipts.env
# → ERROR: receipts.env is unpopulated; cannot run.

# Fill in placeholders (real values come from your password manager / 1Password):
${EDITOR:-vi} ~/.config/ecfx/receipts.env

# Re-run:
/process-email-notice-cli some.eml
```

To override one key without editing the per-user file (e.g. for a CI run with
different AWS creds), export `RECEIPTS_ENV_FILE=/path/to/ci-receipts.env`, or
drop a `.claude/receipts.env` in your project root — both win over the
per-user file.

## Reference: JVM Configuration

Defaults (same as the base skill's Docker harness — see `harness/pacer-oom.env`):

- `-Xmx $HEAP` (explicit cap; default `2304m`).
- `-XX:+ExitOnOutOfMemoryError` (kill JVM on OOM).
- `-XX:+HeapDumpOnOutOfMemoryError` + `-XX:HeapDumpPath=/workspace/shared/heap-dumps/heap-<ts>.hprof`.
- `-XX:MaxDirectMemorySize=192m` (bounds Netty / NIO off-heap).
- `-XX:+UseG1GC -XX:MaxGCPauseMillis=200`.
- `-Xlog:gc*`.

Note on heap sizing: the Docker harness uses `MaxRAMPercentage=75.0` against a 2304 MB cgroup → ~1728 MB heap. To mirror that exactly here, pass `--heap 1728m`. The default `2304m` matches the user-facing prod number; either is reasonable for repro.

---

## Reference: Processing Flow (per receipt processor)

1. Email parsed → provider detection.
2. Jurisdiction + case resolution.
3. Credential lookup.
4. Provider-specific HTTP fetch or browser automation.
5. Per-doc post-fetch: stamp detection, optional embedded-PDF extraction.
6. Combine vs individual-store decision (firm preference + bundle size).
7. Per-doc web-link extraction (`DocumentLinkExtractor`, gated by `firm.getExtractDocumentWebLinks()`).
8. Title extraction (`FAIDocumentTitleExtractionService`).
9. Encryption + storage via `DocumentStorageService`.
10. Notifications / webhooks via `ReceiptNotifierService`.

### Possible Final Outcomes

| Outcome | Log signature | JVM exit |
|---|---|---|
| Full success | `PROCESSING COMPLETE` + `Job processing completed successfully` | 0 |
| Customer action required | `CUSTOMER ACTION REQUIRED FAILURE` | 0 |
| Retryable error | `Handling auto-retryable exception` | 0 (CLI returns; prod requeues) |
| Terminal exception | `Handling non-user receipt processing exception` + ECFX-action state | 0 |
| JVM OOM | `java.lang.OutOfMemoryError` + heap dump in `/workspace/shared/heap-dumps/` | non-zero |
| External SIGKILL | log ends mid-processing, no OOM signature | 137 |

### Processor-Specific Notes

- **PACER:** streaming HTTP client with 500 MB combine cap. Embedded-PDF extraction for HTML-wrapped responses. Individual-store fallback when combine exceeds cap.
- **TrueFiling Michigan:** POST login routes through buffering client upfront; GET errors recover body via buffering re-issue.
- **NYSCEF / Tyler / Peachcourt:** Playwright browser automation via Camoufox grid at `$CAMOUFOX_GRID_URL`.
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

- **`/cleanup-inbox-item`** — surgical cleanup of a previously-processed test inbox item so the same `.eml` can be re-run. Run **before** this skill if you've already processed the `.eml` and want a fresh pass. Preserves case, jurisdiction, and credentials.
- **`/setup-jurisdiction-and-case`** — if processing fails with "jurisdiction not mapped" or "case not found", use this to seed the firm jurisdiction + case records before retrying.
- **`/process-email-notice`** — Mac/Docker counterpart of this skill (use when not in claude-code-container).
- **`notice-processing-results`**, **`notice-failure-results`**, **`processor-report`**, **`stuck-jobs-report`** — post-hoc CloudWatch aggregation reports for prod receipt-processing outcomes. Useful after a fix deploy.

---

## What this skill explicitly does NOT do

- It does **not** call `docker build`, `docker run`, or any docker command. That path is blocked by the docker-socket-proxy and would defeat the egress monitor anyway.
- It does **not** modify `scripts/init-firewall.sh` or the allowlist. The operator does that by hand after reviewing `pending-review.md`.
- It does **not** ship logs off the laptop. The shared folder is the only sink.
- It does **not** invoke other skills for you. If you need prior-run cleanup, run `/cleanup-inbox-item` first.

---

## Failure modes & remediation

| Symptom | Cause | Fix |
|---|---|---|
| `gradle: command not found` and `./gradlew` missing | Both the project wrapper and the system Gradle are absent. | The container ships system gradle at `/opt/gradle/bin/gradle`. Verify with `which gradle`. The wrapper should be checked in at `$PROJECT_ROOT/gradlew`. |
| `cli-*-all.jar` glob empty after build | `:cli:shadowJar` failed | Scroll up for the gradle error; common cause is missing protobuf submodule (`repos setup` fixes it). |
| `psql: connection refused` to `localhost:5432` | No Postgres listening on that port | Start your Postgres (e.g. `docker compose up -d postgres` from the project root) — or set `DATABASE_HOST` / `DATABASE_PORT` to point elsewhere. |
| `redis-cli: no PONG` from `localhost:6379` | No Redis listening on that port | Start your Redis — or override `REDIS_HOST` / `REDIS_PORT` (or `REDIS_URI`). |
| `java.net.ConnectException` to a court system URL | firewall blocked it | Open `~/Desktop/claude-shared/network-monitor/pending-review.md`, find the host, paste the `resolve_domain` line into `scripts/init-firewall.sh`, commit, restart the container. |
| `OutOfMemoryError` | run exceeded `--heap` | Re-run with a larger `--heap` (e.g., `4096m`). Heap dump should be in `/workspace/shared/heap-dumps/`. |
| "envelope already exists" / `ProcessorResult.duplicate()` | The `.eml` was already processed | Run `/cleanup-inbox-item <eml-path> --firm $FIRM` first. |
| Provider-specific 401 / NPE / "credentials not found" | Required key missing from `receipts.env` | Check Phase 2b output for the `WARN: missing keys` list; add them to your project-local `$PROJECT_ROOT/.claude/receipts.env` (preferred) or per-user `~/.config/ecfx/receipts.env`. |
| `ERROR: receipts.env is unpopulated; cannot run.` | First run auto-copied the template; placeholders not filled in | `${EDITOR} ~/.config/ecfx/receipts.env`, replace every `__FILL_ME_IN__` / `__username__` / `__password__`, re-run. |
| `ERROR: $ENV_FILE still contains placeholder values` | Half-edited env file | The skill prints exactly which lines still have placeholders — fix and re-run. |
| `ERROR: No receipts.env or receipts.env.example found` | Skill not installed correctly | Re-install via `claude-components` so the `harness/receipts.env.example` template is on disk. |
