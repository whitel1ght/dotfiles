---
name: setup-jurisdiction-and-case
description: >-
  Parse a court email (.eml), resolve the jurisdiction from provider CSVs, and create the firm jurisdiction, ECFX jurisdiction mapping, and case needed to process it.
---


# Setup Jurisdiction and Case

Automatically parse a court email (.eml), resolve the jurisdiction from provider CSVs, and create the firm jurisdiction, ECFX jurisdiction mapping, and case records in the local database.

## Allowed Tools
Bash, Read, Grep, Glob

## Description
Use this skill when processing a test email fails because the test firm is missing the jurisdiction mapping or case record. This skill parses the .eml file to extract the court name and case number, looks up the ECFX jurisdiction ID from the provider CSV files, then creates the necessary database records (firm jurisdiction, ECFX jurisdiction mapping, and case) if they don't already exist.

Common failure messages this skill resolves:
- `FAILED to find Mapped Jurisdiction for Jurisdiction <name> not mapped.`
- `FAILED to find ECFX jurisdiction: <explanation>`
- `Case not found` / `CaseNotFoundException`

This skill is designed to be called by other skills (like `process-email-notice`) when jurisdiction/case setup is needed before processing.

## User-Invocable
When the user invokes this skill, gather the following parameters if not provided:

**Required:**
- **EML_PATH**: Path to the `.eml` file. Can be absolute or relative to the project root.

**Optional (with defaults):**
- **FIRM**: Firm ID (default: `1`).
- **SKIP_CASE**: Set to `yes` to only set up the jurisdiction mapping without creating a case (default: `no`).

If the user provides parameters inline (e.g., `/setup-jurisdiction-and-case inbox_xxx.eml --firm 2`), parse them and proceed.

## CRITICAL: Execution Strategy

**This skill MUST run in a single Bash call.** The entire workflow — email parsing, CSV lookup, database checks, inserts, and validation — runs as one script.

---

## Phase 1: Setup Jurisdiction and Case

Run the entire workflow as a **single Bash call**. Substitute the resolved parameter values into this script:

```bash
#!/usr/bin/env bash
set -euo pipefail

EML_INPUT="<USER_PROVIDED_FILENAME>"
FIRM="<FIRM_ID>"
SKIP_CASE="<yes|no>"

# ========================================
# Locate the ecfx-backend project root
# ========================================
# We can't assume the repo lives in any one path on disk. Detection order:
#   1. Explicit $PROJECT_ROOT env var (must contain the marker file).
#   2. Walk up from $PWD — most reliable when Claude is invoked from inside
#      the repo (or any subdirectory).
#   3. `git rev-parse --show-toplevel` — covers the case where $PWD is in the
#      repo via a worktree/subdir but the upward-walk's stopping point misses.
#   4. Small list of common install paths as a last resort.
# Marker: `jurisdiction_metadata/Jurisdictions.csv` — a file the skill needs
# anyway, so finding it both locates AND validates the candidate.
PROJECT_MARKER="jurisdiction_metadata/Jurisdictions.csv"

find_project_root() {
    if [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/$PROJECT_MARKER" ]; then
        echo "$PROJECT_ROOT"; return 0
    fi
    local dir="$PWD"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/$PROJECT_MARKER" ]; then
            echo "$dir"; return 0
        fi
        dir=$(dirname "$dir")
    done
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$git_root" ] && [ -f "$git_root/$PROJECT_MARKER" ]; then
        echo "$git_root"; return 0
    fi
    for candidate in \
        "/workspace/ecfx-backend" \
        "$HOME/gitlab/ecfx-backend-v4/ecfx-backend" \
        "$HOME/gitlab/ecfx-backend" \
        "$HOME/code/ecfx-backend" \
        "$HOME/projects/ecfx-backend"
    do
        if [ -f "$candidate/$PROJECT_MARKER" ]; then
            echo "$candidate"; return 0
        fi
    done
    return 1
}

PROJECT_ROOT=$(find_project_root) || {
    echo "ERROR: Could not locate ecfx-backend project root."
    echo "  Looked for marker '$PROJECT_MARKER' via: \$PROJECT_ROOT, walk-up from \$PWD, git rev-parse, and common dirs."
    echo "  Set PROJECT_ROOT=/path/to/ecfx-backend and retry."
    exit 1
}
echo "  PROJECT_ROOT: $PROJECT_ROOT"

# ========================================
# Resolve Postgres connection
# ========================================
# Strategy:
#   1. If a local docker container named "ecfx_postgres" is running, exec psql inside it.
#   2. Otherwise, probe known TCP endpoints for an available postgres instance
#      (host "postgres" used by the dev container network, then localhost).
#   3. Set PSQL_MODE + connection vars, and expose run_psql() that works in either mode.
PG_USER="${PG_USER:-ecfx}"
PG_DB="${PG_DB:-ecfx}"
PG_PASSWORD="${PG_PASSWORD:-ecfx}"

PSQL_MODE=""
PG_HOST=""
PG_PORT=""

if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "ecfx_postgres"; then
    PSQL_MODE="docker"
    echo "  Postgres: docker container 'ecfx_postgres'"
else
    # Probe TCP candidates in order. First open one wins.
    for candidate in "postgres:5432" "localhost:5432" "127.0.0.1:5432" "host.docker.internal:5432"; do
        host="${candidate%%:*}"
        port="${candidate##*:}"
        if timeout 2 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
            PG_HOST="$host"
            PG_PORT="$port"
            PSQL_MODE="tcp"
            echo "  Postgres: TCP $PG_HOST:$PG_PORT"
            break
        fi
    done
fi

if [ -z "$PSQL_MODE" ]; then
    echo "ERROR: Could not find a reachable postgres instance."
    echo "  Tried: docker container 'ecfx_postgres', and TCP postgres:5432, localhost:5432, 127.0.0.1:5432, host.docker.internal:5432"
    echo "  Start the database (e.g. 'docker-compose up -d postgres') and retry."
    exit 1
fi

run_psql() {
    if [ "$PSQL_MODE" = "docker" ]; then
        docker exec ecfx_postgres psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
    else
        PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
    fi
}

# ========================================
# STEP 1: Resolve .eml File
# ========================================
echo "=== Step 1: Resolve .eml File ==="

if [ -f "$EML_INPUT" ]; then
    EML_FILE="$(cd "$(dirname "$EML_INPUT")" && pwd)/$(basename "$EML_INPUT")"
elif [ -f "$PROJECT_ROOT/$EML_INPUT" ]; then
    EML_FILE="$PROJECT_ROOT/$EML_INPUT"
elif [ -f "$PROJECT_ROOT/test-emails/$EML_INPUT" ]; then
    EML_FILE="$PROJECT_ROOT/test-emails/$EML_INPUT"
elif [ -f "$PROJECT_ROOT/test-emails/StuckJobException/$EML_INPUT" ]; then
    EML_FILE="$PROJECT_ROOT/test-emails/StuckJobException/$EML_INPUT"
else
    FOUND=$(find "$PROJECT_ROOT/test-emails" -name "*${EML_INPUT}*" -name "*.eml" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        EML_FILE="$FOUND"
    else
        echo "ERROR: Could not find .eml file: $EML_INPUT"
        exit 1
    fi
fi
echo "  File: $EML_FILE"

# ========================================
# STEP 2: Detect Provider
# ========================================
echo ""
echo "=== Step 2: Detect Provider ==="

# Extract From: address (handle multi-line headers and encoded addresses)
FROM_LINE=$(grep -m1 "^From:" "$EML_FILE" || true)
FROM_ADDR=$(echo "$FROM_LINE" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)

PROVIDER=""
PROVIDER_CSV=""

if echo "$FROM_ADDR" | grep -qi "nycourts.gov"; then
    PROVIDER="nyscef"
    PROVIDER_CSV="NYSCEF.csv"
elif echo "$FROM_ADDR" | grep -qi "uscourts.gov"; then
    PROVIDER="pacer"
    PROVIDER_CSV="PACER.csv"
elif echo "$FROM_ADDR" | grep -qi "tylertech\|tylerhost"; then
    PROVIDER="tyler"
    # Tyler has per-state CSVs; we'll search all Tylers_*.csv
    PROVIDER_CSV="Tylers_*.csv"
elif echo "$FROM_ADDR" | grep -qi "courts.mo.gov"; then
    PROVIDER="missouri"
    PROVIDER_CSV="Missouri.csv"
elif echo "$FROM_ADDR" | grep -qi "flcourts\|myflcourtaccess\|santarosaclerks"; then
    PROVIDER="florida"
    PROVIDER_CSV="Florida*.csv"
elif echo "$FROM_ADDR" | grep -qi "truefiling"; then
    PROVIDER="truefiling"
    PROVIDER_CSV="TrueFiling.csv"
elif echo "$FROM_ADDR" | grep -qi "njcourts"; then
    PROVIDER="njcourts"
    PROVIDER_CSV="NJCourts.csv"
elif echo "$FROM_ADDR" | grep -qi "courts.hawaii"; then
    PROVIDER="hawaii"
    PROVIDER_CSV="Hawaii.csv"
elif echo "$FROM_ADDR" | grep -qi "ohiocourtscases\|ohiocourts"; then
    PROVIDER="ohio"
    PROVIDER_CSV="Ohio.csv"
else
    PROVIDER="unknown"
    PROVIDER_CSV=""
fi

echo "  From:     $FROM_ADDR"
echo "  Provider: $PROVIDER"

# ========================================
# STEP 3: Extract Court Name (Signature)
# ========================================
echo ""
echo "=== Step 3: Extract Court Name ==="

COURT_NAME=""
SUBJECT=$(grep -m1 "^Subject:" "$EML_FILE" | sed 's/^Subject: //' | sed 's/^EXTERNAL EMAIL - //' || true)

case "$PROVIDER" in
    nyscef)
        # NYSCEF: court name is in <h1> tag in HTML body
        # Handle quoted-printable encoding (=\n line continuations and =XX hex codes)
        COURT_NAME=$(grep -A2 '<h1>' "$EML_FILE" | grep -v '<h1>' | grep -v '<span' | \
            sed 's/=$//' | sed 's/<br.*//' | sed 's/<\/h1>.*//' | \
            sed 's/=09//g' | sed 's/=20/ /g' | sed 's/=3D/=/g' | \
            tr -d '\r\n' | sed 's/^ *//' | sed 's/ *$//' | head -1)
        # Fallback: try extracting from <span> inside <h1>
        if [ -z "$COURT_NAME" ]; then
            COURT_NAME=$(sed -n 's/.*<h1>.*<span[^>]*>\([^<]*\).*/\1/p' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        fi
        ;;
    pacer)
        # PACER: jurisdiction signature is the subdomain from the From: address
        # e.g., "ecf_bounced@nysd.uscourts.gov" -> "nysd"
        COURT_NAME=$(echo "$FROM_ADDR" | sed 's/.*@//' | cut -d'.' -f1)
        # Remove "ecf" if present (e.g., "ca9ecf" -> "ca9")
        COURT_NAME=$(echo "$COURT_NAME" | sed 's/ecf$//')
        ;;
    tyler)
        # Tyler: try to extract court name from subject or body
        COURT_NAME=$(echo "$SUBJECT" | sed -n 's/.*Court:[[:space:]]*\([^,]*\).*/\1/p' || true)
        if [ -z "$COURT_NAME" ]; then
            COURT_NAME=$(sed -n 's/.*Court Name[: ]*\([^<]*\).*/\1/p' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        fi
        ;;
    truefiling)
        # TrueFiling: court name is in the HTML body, typically in a <td> or <p> after "Court:" or similar label
        # Also try extracting from subject line or body text patterns like "filed in <Court Name>"
        COURT_NAME=$(grep -oP 'filed\s+(?:in|with)\s+(?:the\s+)?\K[^<.]+' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        if [ -z "$COURT_NAME" ]; then
            # Fallback: look for court name in HTML table cells or bold text
            COURT_NAME=$(grep -oP '<b>\K[^<]*Court[^<]*' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        fi
        if [ -z "$COURT_NAME" ]; then
            # Fallback: search for "Court" label followed by value in HTML
            COURT_NAME=$(sed -n 's/.*Court[: ]*<[^>]*>\([^<]*\).*/\1/p' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        fi
        ;;
    missouri)
        # Missouri: extract from body
        COURT_NAME=$(sed -n 's/.*Court:[[:space:]]*\([^<]*\).*/\1/p' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        if [ -z "$COURT_NAME" ]; then
            COURT_NAME=$(sed -n 's/.*court_id[=:][[:space:]]*\([^&<]*\).*/\1/p' "$EML_FILE" | head -1)
        fi
        ;;
    *)
        # Generic: try common patterns
        COURT_NAME=$(sed -n 's/.*<h1[^>]*>\([^<]*\).*/\1/p' "$EML_FILE" | head -1 | sed 's/^ *//' | sed 's/ *$//')
        if [ -z "$COURT_NAME" ]; then
            COURT_NAME=$(echo "$SUBJECT" | sed -n 's/.*\(Court\|Filing\):[[:space:]]*\([^,\-]*\).*/\2/p' || true)
        fi
        ;;
esac

if [ -z "$COURT_NAME" ]; then
    echo "  ERROR: Could not extract court name from email."
    echo "  Subject: $SUBJECT"
    echo ""
    echo "  Hint: You can provide the court name manually. Search for it in the provider CSVs:"
    echo "    grep -ri 'partial_name' $PROJECT_ROOT/jurisdiction_metadata/Providers/"
    exit 1
fi

echo "  Court Name: $COURT_NAME"
echo "  Subject:    $SUBJECT"

# ========================================
# STEP 4: Extract Case Number
# ========================================
echo ""
echo "=== Step 4: Extract Case Number ==="

CASE_NUMBER=""

# Try provider-specific patterns first
case "$PROVIDER" in
    nyscef)
        # Pattern 1: Index #: <strong>XXXXXX/YYYY</strong>
        CASE_NUMBER=$(grep -o 'Index #:[^<]*<strong>[^<]*</strong>' "$EML_FILE" | head -1 | sed 's/.*<strong>//' | sed 's/<\/strong>.*//' | sed 's/=$//' | tr -d '\r\n' | sed 's/^ *//' | sed 's/ *$//')
        # Pattern 2: Case/Docket #:...digits-digits
        if [ -z "$CASE_NUMBER" ]; then
            CASE_NUMBER=$(grep -oE 'Case/Docket #:.*[0-9]+-[0-9]+' "$EML_FILE" | grep -oE '[0-9]+-[0-9]+' | head -1)
        fi
        # Pattern 3: Subject line tail XXXXXX/YYYY
        if [ -z "$CASE_NUMBER" ]; then
            CASE_NUMBER=$(echo "$SUBJECT" | grep -oE '[0-9]{4,}/[0-9]{4}' | head -1)
        fi
        ;;
    pacer)
        # PACER: case number from subject, format YY-#####-ABC or YY-#####-ABC123
        # The suffix can contain both letters and digits (e.g., LTS9, JLR)
        CASE_NUMBER=$(echo "$SUBJECT" | grep -oE '[0-9]+-[0-9]+(-[a-zA-Z0-9]+)?' | head -1)
        ;;
    tyler)
        # Tyler: "Case: XX-XX-XXXXX" in subject
        CASE_NUMBER=$(echo "$SUBJECT" | sed -n 's/.*Case:[[:space:]]*\([a-zA-Z0-9_-]*\).*/\1/p' | head -1)
        if [ -z "$CASE_NUMBER" ]; then
            CASE_NUMBER=$(echo "$SUBJECT" | sed -n 's/.*Case No\.* *\([a-zA-Z0-9_-]*\).*/\1/p' | head -1)
        fi
        ;;
    *)
        # Generic fallback chain
        CASE_NUMBER=$(echo "$SUBJECT" | grep -oE '[0-9]{4,}/[0-9]{4}' | head -1)
        if [ -z "$CASE_NUMBER" ]; then
            CASE_NUMBER=$(echo "$SUBJECT" | grep -oE '[0-9]+-[0-9]+(-[a-zA-Z0-9]+)?' | head -1)
        fi
        if [ -z "$CASE_NUMBER" ]; then
            CASE_NUMBER=$(echo "$SUBJECT" | sed -n 's/.*Case[: ]*\([a-zA-Z0-9/_-]*\).*/\1/p' | head -1)
        fi
        ;;
esac

# Handle quoted-printable artifacts in case number
if [ -n "$CASE_NUMBER" ]; then
    CASE_NUMBER=$(echo "$CASE_NUMBER" | sed 's/=$//' | tr -d '\r\n' | sed 's/^ *//' | sed 's/ *$//')
fi

if [ -z "$CASE_NUMBER" ] && [ "$SKIP_CASE" != "yes" ]; then
    echo "  WARNING: Could not extract case number from email."
    echo "  Subject: $SUBJECT"
    echo "  Proceeding with jurisdiction setup only (SKIP_CASE=yes)."
    SKIP_CASE="yes"
elif [ -n "$CASE_NUMBER" ]; then
    echo "  Case Number: $CASE_NUMBER"
else
    echo "  Case Number: (skipped)"
fi

# ========================================
# STEP 5: Resolve ECFX Jurisdiction ID
# ========================================
echo ""
echo "=== Step 5: Resolve ECFX Jurisdiction ID ==="

ECFX_JUR_ID=""
PROVIDERS_DIR="$PROJECT_ROOT/jurisdiction_metadata/Providers"

if [ -n "$PROVIDER_CSV" ] && [ "$PROVIDER_CSV" != "" ]; then
    # Search primary provider CSV(s)
    # NOTE: Provider CSVs have Windows line endings (\r\n). We must strip \r before
    # matching with $ anchors, otherwise ",signature$" won't match ",signature\r".
    for csv_file in $PROVIDERS_DIR/$PROVIDER_CSV; do
        if [ -f "$csv_file" ]; then
            # CSV format: ecfx_jurisdiction_id,signature
            MATCH=$(tr -d '\r' < "$csv_file" | grep -i ",${COURT_NAME}$" | head -1 || true)
            if [ -n "$MATCH" ]; then
                ECFX_JUR_ID=$(echo "$MATCH" | cut -d',' -f1)
                echo "  Found in: $(basename "$csv_file")"
                break
            fi
        fi
    done
fi

# Fallback: search ALL provider CSVs (strip \r from each before matching)
if [ -z "$ECFX_JUR_ID" ]; then
    echo "  Primary CSV search failed. Searching all provider CSVs..."
    for csv_file in "$PROVIDERS_DIR"/*.csv; do
        MATCH=$(tr -d '\r' < "$csv_file" | grep -i ",${COURT_NAME}$" | head -1 || true)
        if [ -n "$MATCH" ]; then
            ECFX_JUR_ID=$(echo "$MATCH" | cut -d',' -f1)
            echo "  Found in: $(basename "$csv_file")"
            break
        fi
    done
fi

# Fallback: partial/fuzzy match (strip \r for display)
if [ -z "$ECFX_JUR_ID" ]; then
    echo "  Exact match failed. Trying partial match..."
    # Try each word of the court name
    PARTIAL_MATCHES=$(cat "$PROVIDERS_DIR"/*.csv 2>/dev/null | tr -d '\r' | grep -i "$COURT_NAME" | head -5 || true)
    if [ -n "$PARTIAL_MATCHES" ]; then
        echo "  Possible matches:"
        echo "$PARTIAL_MATCHES" | while IFS= read -r line; do
            echo "    $line"
        done
        echo ""
        echo "  ERROR: No exact match found. Check the court name and try again."
        echo "  Court name extracted: '$COURT_NAME'"
    else
        echo "  ERROR: No matches found in any provider CSV for: '$COURT_NAME'"
    fi
    exit 1
fi

echo "  ECFX Jurisdiction ID: $ECFX_JUR_ID"

# Get canonical name from Jurisdictions.csv (strip \r for Windows line endings)
# CSV format: Country,Is State,Federal Category,Name,ID,State,ZoneID,ecfx_supported
JUR_LINE=$(tr -d '\r' < "$PROJECT_ROOT/jurisdiction_metadata/Jurisdictions.csv" | grep ",$ECFX_JUR_ID," | head -1)
if [ -z "$JUR_LINE" ]; then
    echo "  ERROR: ECFX jurisdiction ID '$ECFX_JUR_ID' not found in Jurisdictions.csv"
    exit 1
fi

# Extract Name field (4th column). Names may be CSV-quoted and contain commas
# (e.g. "Florida - First Circuit - Escambia, Okaloosa, Santa Rosa, Walton").
# Strip everything from the ID onward; then, if the remainder ends in a quote,
# pull out the quoted Name — otherwise take the last comma-separated field.
JUR_REMAINDER=$(echo "$JUR_LINE" | sed "s/,$ECFX_JUR_ID,.*//")
if [[ "$JUR_REMAINDER" == *'"' ]]; then
    JUR_CANONICAL_NAME=$(echo "$JUR_REMAINDER" | sed 's/.*,"\(.*\)"$/\1/')
else
    JUR_CANONICAL_NAME=$(echo "$JUR_REMAINDER" | rev | cut -d',' -f1 | rev)
fi

echo "  Canonical Name: $JUR_CANONICAL_NAME"

# ========================================
# STEP 6: Check/Create Firm Jurisdiction
# ========================================
echo ""
echo "=== Step 6: Check/Create Firm Jurisdiction ==="

# Escape single quotes for SQL
JUR_NAME_SQL=$(echo "$JUR_CANONICAL_NAME" | sed "s/'/''/g")

EXISTING_JUR=$(run_psql "SELECT id::text || '|' || name FROM public_v1.jurisdiction WHERE firm_id = $FIRM AND name = '$JUR_NAME_SQL' LIMIT 1;" 2>/dev/null || true)

JUR_STATUS=""
FIRM_JUR_UUID=""

if [ -n "$EXISTING_JUR" ] && [ "$EXISTING_JUR" != "" ]; then
    FIRM_JUR_UUID=$(echo "$EXISTING_JUR" | cut -d'|' -f1 | tr -d ' ')
    JUR_STATUS="ALREADY EXISTS"
    echo "  Status: ALREADY EXISTS"
    echo "  Firm Jurisdiction ID: $FIRM_JUR_UUID"
else
    # Insert new jurisdiction
    FIRM_JUR_UUID=$(run_psql "INSERT INTO public_v1.jurisdiction (firm_id, reference_id, name) VALUES ($FIRM, '$JUR_NAME_SQL', '$JUR_NAME_SQL') RETURNING id::text;" 2>/dev/null | head -1 | tr -d ' ')
    if [ -z "$FIRM_JUR_UUID" ]; then
        echo "  ERROR: Failed to insert jurisdiction"
        exit 1
    fi
    JUR_STATUS="CREATED"
    echo "  Status: CREATED"
    echo "  Firm Jurisdiction ID: $FIRM_JUR_UUID"
fi

# ========================================
# STEP 7: Check/Create ECFX Jurisdiction Mapping
# ========================================
echo ""
echo "=== Step 7: Check/Create ECFX Jurisdiction Mapping ==="

EXISTING_MAP=$(run_psql "SELECT firm_jurisdiction_id::text FROM private.ecfx_jurisdiction_mapping WHERE firm_id = $FIRM AND ecfx_jurisdiction_id = '$ECFX_JUR_ID' LIMIT 1;" 2>/dev/null || true)

MAP_STATUS=""

if [ -n "$EXISTING_MAP" ] && [ "$EXISTING_MAP" != "" ]; then
    MAP_STATUS="ALREADY EXISTS"
    echo "  Status: ALREADY EXISTS"
    echo "  Existing mapping: firm $FIRM -> $ECFX_JUR_ID -> $(echo "$EXISTING_MAP" | tr -d ' ')"
else
    run_psql "INSERT INTO private.ecfx_jurisdiction_mapping (firm_id, ecfx_jurisdiction_id, firm_jurisdiction_id, created_at) VALUES ($FIRM, '$ECFX_JUR_ID', '$FIRM_JUR_UUID'::uuid, NOW());" >/dev/null 2>/dev/null
    MAP_STATUS="CREATED"
    echo "  Status: CREATED"
    echo "  New mapping: firm $FIRM -> $ECFX_JUR_ID -> $FIRM_JUR_UUID"
fi

# ========================================
# STEP 8: Check/Create Case
# ========================================
CASE_STATUS=""
CASE_ID=""

if [ "$SKIP_CASE" = "yes" ]; then
    echo ""
    echo "=== Step 8: Case (SKIPPED) ==="
    CASE_STATUS="SKIPPED"
else
    echo ""
    echo "=== Step 8: Check/Create Case ==="

    CASE_NUM_SQL=$(echo "$CASE_NUMBER" | sed "s/'/''/g")

    EXISTING_CASE=$(run_psql "SELECT id::text || '|' || jurisdiction_id::text FROM public_v1.\"case\" WHERE firm_id = $FIRM AND case_number = '$CASE_NUM_SQL' LIMIT 1;" 2>/dev/null || true)

    if [ -n "$EXISTING_CASE" ] && [ "$EXISTING_CASE" != "" ]; then
        CASE_ID=$(echo "$EXISTING_CASE" | cut -d'|' -f1 | tr -d ' ')
        EXISTING_JUR_ID=$(echo "$EXISTING_CASE" | cut -d'|' -f2 | tr -d ' ')
        CASE_STATUS="ALREADY EXISTS"
        echo "  Status: ALREADY EXISTS"
        echo "  Case ID: $CASE_ID"

        # Check if jurisdiction matches
        if [ "$EXISTING_JUR_ID" = "$FIRM_JUR_UUID" ]; then
            echo "  Jurisdiction FK: MATCHES ($FIRM_JUR_UUID)"
        else
            echo "  WARNING: Case jurisdiction ($EXISTING_JUR_ID) does NOT match expected ($FIRM_JUR_UUID)"
            echo "  The case exists but points to a different jurisdiction. Not modifying."
        fi
    else
        CASE_ID=$(run_psql "INSERT INTO public_v1.\"case\" (firm_id, reference_id, case_number, name, jurisdiction_id) VALUES ($FIRM, '$CASE_NUM_SQL', '$CASE_NUM_SQL', '$CASE_NUM_SQL', '$FIRM_JUR_UUID'::uuid) RETURNING id::text;" 2>/dev/null | head -1 | tr -d ' ')
        if [ -z "$CASE_ID" ]; then
            echo "  ERROR: Failed to insert case"
            exit 1
        fi
        CASE_STATUS="CREATED"
        echo "  Status: CREATED"
        echo "  Case ID: $CASE_ID"
    fi
fi

# ========================================
# STEP 9: Validation
# ========================================
echo ""
echo "=== Step 9: Validation ==="

PASS=true

# Validate jurisdiction
V_JUR=$(run_psql "SELECT count(*) FROM public_v1.jurisdiction WHERE id = '$FIRM_JUR_UUID'::uuid AND firm_id = $FIRM;" 2>/dev/null | tr -d ' ')
if [ "$V_JUR" = "1" ]; then
    echo "  Jurisdiction in DB:  PASS"
else
    echo "  Jurisdiction in DB:  FAIL (count=$V_JUR)"
    PASS=false
fi

# Validate mapping
V_MAP=$(run_psql "SELECT count(*) FROM private.ecfx_jurisdiction_mapping WHERE firm_id = $FIRM AND ecfx_jurisdiction_id = '$ECFX_JUR_ID' AND firm_jurisdiction_id = '$FIRM_JUR_UUID'::uuid;" 2>/dev/null | tr -d ' ')
if [ "$V_MAP" = "1" ]; then
    echo "  Mapping in DB:       PASS"
else
    echo "  Mapping in DB:       FAIL (count=$V_MAP)"
    PASS=false
fi

# Validate case
if [ "$SKIP_CASE" != "yes" ] && [ -n "$CASE_ID" ]; then
    V_CASE=$(run_psql "SELECT count(*) FROM public_v1.\"case\" WHERE id = '$CASE_ID'::uuid AND firm_id = $FIRM AND jurisdiction_id = '$FIRM_JUR_UUID'::uuid;" 2>/dev/null | tr -d ' ')
    if [ "$V_CASE" = "1" ]; then
        echo "  Case in DB:          PASS"
        echo "  Case->Jur FK:        PASS"
    else
        echo "  Case in DB:          FAIL (count=$V_CASE)"
        PASS=false
    fi
fi

# ========================================
# SUMMARY
# ========================================
echo ""
echo "========================================================"
echo " JURISDICTION & CASE SETUP REPORT"
echo "========================================================"
echo ""
echo "--- Email ---"
echo "  File:        $(basename "$EML_FILE")"
echo "  Provider:    $PROVIDER"
echo "  Court Name:  $COURT_NAME"
echo "  Case Number: ${CASE_NUMBER:-N/A}"
echo ""
echo "--- Jurisdiction ---"
echo "  ECFX ID:     $ECFX_JUR_ID"
echo "  Name:        $JUR_CANONICAL_NAME"
echo "  Firm Jur ID: $FIRM_JUR_UUID"
echo "  Status:      $JUR_STATUS"
echo ""
echo "--- Mapping ---"
echo "  Firm $FIRM -> $ECFX_JUR_ID -> $FIRM_JUR_UUID"
echo "  Status:      $MAP_STATUS"
echo ""
echo "--- Case ---"
echo "  Case Number: ${CASE_NUMBER:-N/A}"
echo "  Case ID:     ${CASE_ID:-N/A}"
echo "  Status:      $CASE_STATUS"
echo ""
if [ "$PASS" = "true" ]; then
    echo "SETUP_COMPLETE"
else
    echo "SETUP_FAILED — see validation errors above"
fi
echo "========================================================"
```

---

## Presenting Results

After the script completes, read the output and present a summary table to the user:

| Field | Value |
|-------|-------|
| Provider | detected from email |
| Court Name | extracted court signature |
| Case Number | extracted case number |
| ECFX Jurisdiction ID | from CSV lookup |
| Jurisdiction Status | CREATED / ALREADY EXISTS |
| Mapping Status | CREATED / ALREADY EXISTS |
| Case Status | CREATED / ALREADY EXISTS / SKIPPED |
| Validation | PASS / FAIL |

If the skill reports `SETUP_COMPLETE`, inform the user they can now re-run `/process-email-notice` for the same email.

---

## Reference: Database Tables

| Table | Key Columns | Purpose |
|-------|-------------|---------|
| `public_v1.jurisdiction` | firm_id, id (UUID), reference_id, name | Firm-specific jurisdiction records |
| `private.ecfx_jurisdiction_mapping` | firm_id, ecfx_jurisdiction_id, firm_jurisdiction_id (UUID) | Maps firm jurisdiction to ECFX global jurisdiction |
| `private.ecfx_jurisdiction` | id (varchar, e.g., `us_ny_supreme_queens`), name | Global ECFX jurisdiction definitions |
| `private.ecfx_provider_jurisdiction` | provider_id, signature, ecfx_jurisdiction_id | Maps email court signatures to ECFX jurisdictions |
| `public_v1."case"` | firm_id, id (UUID), case_number, jurisdiction_id (UUID FK) | Case records |

## Reference: Provider CSV Files

All CSVs in `jurisdiction_metadata/Providers/` use format: `ecfx_jurisdiction_id,signature`

Major providers: NYSCEF.csv (500+ signatures), PACER.csv, Missouri.csv, Florida*.csv, Tylers_*.csv (per state), TrueFiling.csv, NJCourts.csv, Hawaii.csv, Ohio.csv, and 70+ more.
