---
name: cleanup-inbox-item
description: >-
  Delete a previously-processed test inbox item and everything derived from it (envelope, court documents, process jobs, notifications) from the local database so the same email can be reprocessed cleanly.
---


# Cleanup Inbox Item for Reprocessing

Delete a previously-processed test inbox item (and its derived envelope, court documents, process jobs, and notifications) from the local database so the same `.eml` can be re-run through the CLI without triggering duplicate / "envelope already exists" detection.

## Allowed Tools
Bash, Read, Write

## Description

Use this skill when you want to re-run `/process-email-notice` (or the `email-receipt` CLI) on a test email that has already been processed in the local DB. The ECFX processor's duplicate-detection (e.g. `hasEnvelope`, `court_envelope.court_envelope_id`, inbox_item rows keyed by message-id hash) will otherwise short-circuit the run and make it impossible to validate code changes end-to-end.

Common symptoms this resolves:
- CLI log shows `Replicating existing envelope. envelopeId=env_…` instead of processing fresh
- Duplicate `inbox_item_process_job` rows piling up across retries
- Processor short-circuits with `ProcessorResult.duplicate()` and persists nothing new

This skill preserves **case**, **jurisdiction**, **ecfx_jurisdiction_mapping**, and **credential** rows — only the per-run artifacts are removed. Re-running the CLI after this cleanup reproduces a fresh processing pass.

## User-Invocable

**If the user invokes the skill with NO arguments, do NOT prompt or proceed. Print the usage block below verbatim and stop.**

```
/cleanup-inbox-item — clean up a test inbox item so the same .eml can be reprocessed.

Identifier (provide ONE):
  EML_PATH           path to the .eml file — usually what you want
  CASE_NUMBER        e.g. 24SL-CC07907 — nukes every envelope/doc tied to that case
  ENVELOPE_ID        UUID or short court_envelope_id — for orphaned envelopes
  INBOX_ITEM_ID      UUID — most surgical

Optional flags:
  --firm <id>                      firm id (default: 1)
  --dry-run                        show counts, roll back the transaction
  --also-delete-case               also delete the case row (rarely wanted)
  --also-delete-jurisdiction       also delete firm jurisdiction + mapping (rarely wanted)

Always preserved unless explicitly requested: case, jurisdiction, ecfx_jurisdiction_mapping, credential.

Examples:
  /cleanup-inbox-item test-emails/ECFX-12504/inbox_t2tkwyrhwyi7dnm6wudkll6dwi.eml
  /cleanup-inbox-item test-emails/ECFX-12504/inbox_t2tkwyrhwyi7dnm6wudkll6dwi.eml --firm 1 --dry-run
  /cleanup-inbox-item --case-number 24SL-CC07907
  /cleanup-inbox-item --envelope-id env_f5c33wjydyi7dpc7xx5goagnje
  /cleanup-inbox-item --inbox-item-id 2e774a47-381e-11f1-bc5f-095b1d1732f5
```

After printing the usage, tell the user: *"Re-run with an identifier — the most common form is `/cleanup-inbox-item <path-to-your-.eml>`."* Do not attempt the cleanup until the user replies with an identifier.

**If the user DOES provide parameters**, gather them (the skill is flexible — you can identify the item to delete by **any one** of the IDs below).

**Identification (provide one; EML_PATH is preferred for test-emails reruns):**
- **EML_PATH** — Path to the `.eml` file (absolute or relative to project root or `test-emails/`). The skill derives the expected `raw_content` length as a selector.
- **CASE_NUMBER** — Case number (e.g. `24SL-CC07907`). Cleans up everything tied to that case's envelope(s).
- **ENVELOPE_ID** — `court_envelope.id` (UUID) or `court_envelope_id` (short string). Scopes deletion to that envelope only.
- **INBOX_ITEM_ID** — `inbox_item.id` (UUID). Scopes deletion to that one inbox item and any documents/jobs that reference it.

**Optional:**
- **FIRM** — Firm ID (default: `1`).
- **DRY_RUN** — `yes` to print counts of what *would* be deleted without mutating (default: `no`).
- **ALSO_DELETE_CASE** — `yes` to delete the `case` row too (default: `no`; rarely wanted — the case is typically reused across reruns).
- **ALSO_DELETE_JURISDICTION** — `yes` to delete the firm jurisdiction + mapping (default: `no`; almost never wanted).

If the user provides parameters inline (e.g. `/cleanup-inbox-item inbox_xxx.eml --firm 2 --dry-run`), parse them and proceed.

Print a summary at the end of:
- which table had how many rows deleted
- any rows that were skipped because they were preserved (case, jurisdiction, credential) with their ids so the user can confirm state
- a suggested re-run command hint: `"Re-run your CLI now to reprocess the email."`

## CRITICAL: Execution Strategy

**This skill runs as a single Bash call** that drives `psql` through a SQL file inside a transaction. The SQL file is generated from the resolved parameters and copied into the `ecfx_postgres` container so multi-statement transactions and heredocs survive the docker boundary cleanly.

If `DRY_RUN=yes`, the generated SQL uses `SELECT count(*)` instead of `DELETE` and ends with `ROLLBACK`.

---

## Phase 1: Generate and run cleanup SQL

Run the entire workflow as a **single Bash call**. Substitute the resolved parameter values into the script below. The script:

1. Resolves the inbox-item identity via whatever selector was provided.
2. Writes a transactional SQL script to `/tmp/cleanup-inbox-item.sql`.
3. Copies it into the `ecfx_postgres` container and executes via `psql -f`.
4. Prints a concise summary.

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Users/levisiebens/gitlab/ecfx-backend-v4/ecfx-backend"
EML_INPUT="<USER_PROVIDED_OR_EMPTY>"
CASE_NUMBER="<USER_PROVIDED_OR_EMPTY>"
ENVELOPE_ID="<USER_PROVIDED_OR_EMPTY>"          # uuid OR court_envelope_id string
INBOX_ITEM_ID="<USER_PROVIDED_OR_EMPTY>"        # uuid
FIRM="<FIRM_ID>"
DRY_RUN="<yes|no>"
ALSO_DELETE_CASE="<yes|no>"
ALSO_DELETE_JURISDICTION="<yes|no>"

# ========================================
# STEP 1: Resolve selector
# ========================================
echo "=== Step 1: Resolve target selector ==="

SELECTOR_TYPE=""
SELECTOR_VALUE=""

if [ -n "$INBOX_ITEM_ID" ]; then
    SELECTOR_TYPE="inbox_item_id"
    SELECTOR_VALUE="$INBOX_ITEM_ID"
elif [ -n "$ENVELOPE_ID" ]; then
    SELECTOR_TYPE="envelope_id"
    SELECTOR_VALUE="$ENVELOPE_ID"
elif [ -n "$CASE_NUMBER" ]; then
    SELECTOR_TYPE="case_number"
    SELECTOR_VALUE="$CASE_NUMBER"
elif [ -n "$EML_INPUT" ]; then
    # Resolve .eml path and derive raw_content length
    if [ -f "$EML_INPUT" ]; then
        EML_FILE="$(cd "$(dirname "$EML_INPUT")" && pwd)/$(basename "$EML_INPUT")"
    elif [ -f "$PROJECT_ROOT/$EML_INPUT" ]; then
        EML_FILE="$PROJECT_ROOT/$EML_INPUT"
    elif [ -f "$PROJECT_ROOT/test-emails/$EML_INPUT" ]; then
        EML_FILE="$PROJECT_ROOT/test-emails/$EML_INPUT"
    else
        FOUND=$(find "$PROJECT_ROOT/test-emails" -name "*${EML_INPUT##*/}*" -name "*.eml" 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then EML_FILE="$FOUND"
        else echo "ERROR: .eml not found: $EML_INPUT"; exit 1; fi
    fi
    SELECTOR_TYPE="eml_length"
    SELECTOR_VALUE=$(wc -c < "$EML_FILE" | tr -d ' ')
    echo "  Resolved .eml: $EML_FILE (raw_content length ≈ $SELECTOR_VALUE)"
else
    echo "ERROR: provide one of EML_PATH, CASE_NUMBER, ENVELOPE_ID, INBOX_ITEM_ID"
    exit 1
fi
echo "  Selector: $SELECTOR_TYPE = $SELECTOR_VALUE"
echo "  Firm:     $FIRM"
echo "  Dry run:  $DRY_RUN"

# ========================================
# STEP 2: Build WHERE clause for inbox_item lookup
# ========================================
case "$SELECTOR_TYPE" in
  inbox_item_id)
    INBOX_WHERE="id = '$SELECTOR_VALUE'::uuid AND firm_id = $FIRM"
    ;;
  envelope_id)
    # Accept either a UUID or a short court_envelope_id string.
    if [[ "$SELECTOR_VALUE" =~ ^[0-9a-f-]{36}$ ]]; then
        ENV_WHERE="id = '$SELECTOR_VALUE'::uuid"
    else
        ENV_WHERE="court_envelope_id = '$SELECTOR_VALUE'"
    fi
    # No direct FK from inbox_item → envelope; use court_document.inbox_item_id as bridge.
    INBOX_WHERE="id IN (SELECT DISTINCT inbox_item_id FROM private.court_document WHERE inbox_item_id IS NOT NULL AND envelope_id IN (SELECT id FROM private.court_envelope WHERE $ENV_WHERE))"
    ;;
  case_number)
    # Normalize quoted table name; case_number lives on the case table (firm-scoped).
    INBOX_WHERE="id IN (SELECT DISTINCT inbox_item_id FROM private.court_document WHERE inbox_item_id IS NOT NULL AND envelope_id IN (SELECT id FROM private.court_envelope WHERE case_id = (SELECT id FROM public_v1.\"case\" WHERE firm_id = $FIRM AND case_number = '$SELECTOR_VALUE' LIMIT 1)))"
    ;;
  eml_length)
    # Raw-content size is a reasonable fingerprint when re-uploading the same .eml repeatedly.
    INBOX_WHERE="firm_id = $FIRM AND length(raw_content) = $SELECTOR_VALUE"
    ;;
esac

# ========================================
# STEP 3: Write SQL script
# ========================================
SQL_FILE="/tmp/cleanup-inbox-item.sql"
END_KEYWORD="COMMIT"
DELETE_KEYWORD="DELETE"
if [ "$DRY_RUN" = "yes" ]; then
    END_KEYWORD="ROLLBACK"
    # We still issue DELETEs so we can count cascaded removals; ROLLBACK undoes everything.
fi

cat > "$SQL_FILE" <<SQL
BEGIN;

-- 1. Capture the set of inbox items we're cleaning up.
CREATE TEMP TABLE _cleanup AS
SELECT id FROM private.inbox_item WHERE $INBOX_WHERE;

-- 2. Capture envelopes tied to those inbox items (via court_document bridge).
CREATE TEMP TABLE _cleanup_envelopes AS
SELECT DISTINCT envelope_id AS id
FROM private.court_document
WHERE inbox_item_id IN (SELECT id FROM _cleanup);

SELECT 'inbox_items_targeted'   AS what, count(*) FROM _cleanup
UNION ALL SELECT 'envelopes_targeted', count(*) FROM _cleanup_envelopes;

-- 3. Child tables referencing inbox_item or court_document.
$DELETE_KEYWORD FROM private.inbox_item_process_job  WHERE parent_id     IN (SELECT id FROM _cleanup);
$DELETE_KEYWORD FROM private.inbox_item_notification WHERE inbox_item_id IN (SELECT id FROM _cleanup);

-- 4. dms_job references court_document.
$DELETE_KEYWORD FROM private.dms_job
 WHERE parent_id IN (SELECT id FROM private.court_document WHERE inbox_item_id IN (SELECT id FROM _cleanup)
                                                              OR envelope_id   IN (SELECT id FROM _cleanup_envelopes));

-- 5. Court documents — tied to either the inbox items OR their envelopes.
$DELETE_KEYWORD FROM private.court_document
 WHERE inbox_item_id IN (SELECT id FROM _cleanup)
    OR envelope_id   IN (SELECT id FROM _cleanup_envelopes);

-- 6. Envelopes (only those with no remaining documents).
$DELETE_KEYWORD FROM private.court_envelope
 WHERE id IN (SELECT id FROM _cleanup_envelopes)
   AND NOT EXISTS (SELECT 1 FROM private.court_document d WHERE d.envelope_id = private.court_envelope.id);

-- 7. Inbox items themselves. Clear self-FKs first so deletion is ordering-safe.
UPDATE private.inbox_item SET parent_id = NULL, linked_item_id = NULL
 WHERE id IN (SELECT id FROM _cleanup)
    OR parent_id IN (SELECT id FROM _cleanup)
    OR linked_item_id IN (SELECT id FROM _cleanup);
$DELETE_KEYWORD FROM private.inbox_item WHERE id IN (SELECT id FROM _cleanup);

SQL

# Optional destructive extras — OFF by default.
if [ "$ALSO_DELETE_CASE" = "yes" ] && [ -n "$CASE_NUMBER" ]; then
    cat >> "$SQL_FILE" <<SQL
$DELETE_KEYWORD FROM public_v1."case" WHERE firm_id = $FIRM AND case_number = '$CASE_NUMBER';
SQL
fi

if [ "$ALSO_DELETE_JURISDICTION" = "yes" ]; then
    cat >> "$SQL_FILE" <<SQL
-- Deleting jurisdiction + mapping only explicitly requested; normally preserved.
$DELETE_KEYWORD FROM private.ecfx_jurisdiction_mapping WHERE firm_id = $FIRM;
$DELETE_KEYWORD FROM public_v1.jurisdiction WHERE firm_id = $FIRM;
SQL
fi

# Verification tail.
cat >> "$SQL_FILE" <<SQL

-- Verify.
SELECT 'remaining_inbox_items'  AS what, count(*) FROM private.inbox_item  WHERE $INBOX_WHERE
UNION ALL SELECT 'remaining_envelopes', count(*) FROM private.court_envelope WHERE id IN (SELECT id FROM _cleanup_envelopes)
UNION ALL SELECT 'remaining_documents', count(*) FROM private.court_document WHERE envelope_id IN (SELECT id FROM _cleanup_envelopes) OR inbox_item_id IN (SELECT id FROM _cleanup);

$END_KEYWORD;
SQL

echo ""
echo "=== Step 2: Executing cleanup ($([ "$DRY_RUN" = "yes" ] && echo "DRY RUN" || echo "DELETE"))"
docker cp "$SQL_FILE" ecfx_postgres:/tmp/cleanup.sql >/dev/null
docker exec ecfx_postgres psql -U ecfx -d ecfx -f /tmp/cleanup.sql

echo ""
echo "========================================================"
if [ "$DRY_RUN" = "yes" ]; then
    echo " DRY RUN COMPLETE (transaction rolled back)"
else
    echo " CLEANUP COMPLETE"
    echo " Re-run your CLI now to reprocess the email."
fi
echo "========================================================"
```

---

## Presenting Results

After the script completes, present a summary table to the user:

| Field | Value |
|-------|-------|
| Selector | which identifier was used |
| Selector value | the resolved value |
| Firm | firm id |
| Mode | DRY_RUN or DELETE |
| inbox_items deleted | n |
| envelopes deleted | n |
| court_documents deleted | n |
| process jobs deleted | n |
| notifications deleted | n |
| dms jobs deleted | n |
| case preserved | yes/no (yes unless ALSO_DELETE_CASE) |
| jurisdiction preserved | yes/no |
| credentials preserved | always yes |

If the skill succeeds, tell the user they can now re-run the CLI / `/process-email-notice` for the same email.

---

## Reference: Tables touched

| Table | How it's tied to the inbox item | Preservation |
|-------|--------------------------------|--------------|
| `private.inbox_item` | the row itself | deleted |
| `private.inbox_item_process_job` | FK `parent_id → inbox_item.id` | deleted |
| `private.inbox_item_notification` | FK `inbox_item_id` | deleted |
| `private.court_document` | FK `inbox_item_id` and/or FK `envelope_id` | deleted |
| `private.court_envelope` | `case_id` on case; tied via `court_document.envelope_id` | deleted (only if no docs remain) |
| `private.dms_job` | FK `parent_id → court_document.id` | deleted |
| `public_v1."case"` | referenced by envelope | **preserved** unless `ALSO_DELETE_CASE=yes` |
| `public_v1.jurisdiction` | referenced by case | **preserved** unless `ALSO_DELETE_JURISDICTION=yes` |
| `private.ecfx_jurisdiction_mapping` | `firm_id → ecfx_jurisdiction_id` | **preserved** unless `ALSO_DELETE_JURISDICTION=yes` |
| `private.credential` | firm-level credential | **always preserved** |

## Tips for broader use

- The `eml_length` selector is a cheap fingerprint that works when the user uploads the same `.eml` repeatedly. If you need surgical scope across jurisdictions, use `INBOX_ITEM_ID` (most precise).
- Use `ENVELOPE_ID` when the inbox item has already been deleted but the envelope + documents linger (can happen if a prior partial cleanup ran).
- Start with `DRY_RUN=yes` if the user is cleaning up a case they still care about (real data) — the rolled-back counts show blast radius before commit.
- If the user also wants to re-exercise jurisdiction/case setup (e.g. to test `/setup-jurisdiction-and-case`), pass `ALSO_DELETE_CASE=yes`. Pair with `ALSO_DELETE_JURISDICTION=yes` only when explicitly testing the mapping-creation path from scratch.
