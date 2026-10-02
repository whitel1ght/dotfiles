# Schema Drift Detector: Examples

## Example 1: Missing Column (Critical Drift)

### Scenario
Production schema added `created_at` column to `email_inbox_items` table, but test schema not updated.

### Detection
```bash
$ diff src/test/resources/db/schema.sql /tmp/prod-schema.sql

--- src/test/resources/db/schema.sql
+++ /tmp/prod-schema.sql
@@ -15,6 +15,7 @@
   raw_email TEXT NOT NULL,
   status VARCHAR(50) NOT NULL,
   firm_id BIGINT REFERENCES firms(id),
+  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
   PRIMARY KEY (id)
 );
```

### Impact
- Repository tests querying `created_at` fail with "column does not exist"
- Tests inserting without `created_at` may pass but production insert fails
- Entity mapping fails because JPA expects `created_at` field

### Report Section
```markdown
### Critical Drift

#### Missing Columns
- `email_inbox_items.created_at` - Type: TIMESTAMP, Constraints: NOT NULL, Default: CURRENT_TIMESTAMP
  - Impact: Repository queries selecting created_at will fail
  - Impact: JPA entity mapping expects this column
  - Action: Add column to test schema
```

### Synchronization
```sql
-- Add to test schema (src/test/resources/db/schema.sql)
ALTER TABLE email_inbox_items ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Or rebuild table definition with the column
CREATE TABLE email_inbox_items (
  id BIGSERIAL,
  raw_email TEXT NOT NULL,
  status VARCHAR(50) NOT NULL,
  firm_id BIGINT REFERENCES firms(id),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);
```

---

## Example 2: Missing Table (Critical Drift)

### Scenario
New `audit_logs` table added to production for tracking changes, test schema lacks it.

### Detection
```bash
$ diff -u test-normalized.sql prod-normalized.sql

--- test-normalized.sql
+++ prod-normalized.sql
@@ -50,6 +50,15 @@
   PRIMARY KEY (id)
 );

+CREATE TABLE audit_logs (
+  id BIGSERIAL PRIMARY KEY,
+  entity_type VARCHAR(100) NOT NULL,
+  entity_id BIGINT NOT NULL,
+  action VARCHAR(50) NOT NULL,
+  user_id BIGINT,
+  timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
+);
+
 CREATE TABLE inbox_item_process_jobs (
```

### Impact
- Any code using `AuditLog` entity fails in tests
- Repository tests for `AuditLogRepository` cannot run
- Integration tests verifying audit logging behavior don't test real schema

### Report Section
```markdown
### Critical Drift

#### Missing Tables in Test Schema
- `audit_logs` - Created in production (migration 2025-10-15)
  - Columns: id, entity_type, entity_id, action, user_id, timestamp
  - Impact: AuditLogRepository tests cannot run
  - Impact: Integration tests for audit logging fail
  - Action: Add complete table definition to test schema
```

### Synchronization
```bash
# Extract table definition from production schema
grep -A 10 "CREATE TABLE audit_logs" /tmp/prod-schema.sql >> src/test/resources/db/schema.sql

# Or manually add the definition
```

```sql
-- Add to test schema at appropriate location
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  entity_type VARCHAR(100) NOT NULL,
  entity_id BIGINT NOT NULL,
  action VARCHAR(50) NOT NULL,
  user_id BIGINT,
  timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes if present in production
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);
```

---

## Example 3: Type Mismatch (Critical Drift)

### Scenario
Production changed `status` column from `VARCHAR(50)` to ENUM type for better type safety.

### Detection
```bash
$ diff src/test/resources/db/schema.sql /tmp/prod-schema.sql

--- src/test/resources/db/schema.sql
+++ /tmp/prod-schema.sql
@@ -1,6 +1,11 @@
+-- Create ENUM type for status
+CREATE TYPE email_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED');
+
 CREATE TABLE email_inbox_items (
   id BIGSERIAL,
-  status VARCHAR(50) NOT NULL,
+  status email_status NOT NULL DEFAULT 'PENDING',
```

### Impact
- Tests insert invalid status values that would fail in production
- Application code expects ENUM type checking
- Default value behavior differs between VARCHAR and ENUM

### Report Section
```markdown
### Critical Drift

#### Type Mismatches
- `email_inbox_items.status` - Test: VARCHAR(50), Production: email_status ENUM
  - Values: Production restricts to: PENDING, PROCESSING, COMPLETED, FAILED
  - Impact: Tests may insert invalid status values
  - Impact: Default value handling differs
  - Action: Create ENUM type and alter column in test schema
```

### Synchronization
```sql
-- Add to beginning of test schema
CREATE TYPE email_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED');

-- Update table definition
-- Option 1: Alter existing table
ALTER TABLE email_inbox_items ALTER COLUMN status TYPE email_status USING status::email_status;

-- Option 2: Rebuild table with correct type
DROP TABLE IF EXISTS email_inbox_items CASCADE;
CREATE TABLE email_inbox_items (
  id BIGSERIAL,
  status email_status NOT NULL DEFAULT 'PENDING',
  -- ... other columns
);
```

---

## Example 4: Missing Index (Warning Drift)

### Scenario
Production added index on frequently queried column, test schema lacks it.

### Detection
```bash
$ grep "CREATE INDEX" src/test/resources/db/schema.sql | sort > /tmp/test-indexes.txt
$ grep "CREATE INDEX" /tmp/prod-schema.sql | sort > /tmp/prod-indexes.txt
$ diff /tmp/test-indexes.txt /tmp/prod-indexes.txt

> CREATE INDEX idx_email_inbox_items_firm_id ON email_inbox_items(firm_id);
```

### Impact
- Tests run but with different performance characteristics
- Query plans differ between test and production
- Tests may not catch performance regressions

### Report Section
```markdown
### Warning Drift

#### Missing Indexes
- `idx_email_inbox_items_firm_id` - Index on email_inbox_items(firm_id)
  - Impact: Test query performance differs from production
  - Impact: Query plan testing not accurate
  - Action: Add index to test schema (optional for fast test execution)
```

### Synchronization Decision
```sql
-- Option 1: Add for accuracy
CREATE INDEX idx_email_inbox_items_firm_id ON email_inbox_items(firm_id);

-- Option 2: Skip for test performance
-- Document in schema.sql header:
-- Note: Production index idx_email_inbox_items_firm_id intentionally
-- omitted from test schema for faster fixture loading
```

---

## Example 5: Test-Specific Table (Expected Difference)

### Scenario
Test schema has `test_fixtures` table for test data management, not in production.

### Detection
```bash
$ diff src/test/resources/db/schema.sql /tmp/prod-schema.sql

--- src/test/resources/db/schema.sql
+++ /tmp/prod-schema.sql
@@ -45,13 +45,6 @@
   PRIMARY KEY (id)
 );

-CREATE TABLE test_fixtures (
-  id BIGSERIAL PRIMARY KEY,
-  fixture_name VARCHAR(100) NOT NULL,
-  data JSONB NOT NULL
-);
-
 CREATE INDEX idx_firms_name ON firms(name);
```

### Report Section
```markdown
### Expected Differences (Documented)

#### Test-Specific Elements
- `test_fixtures` - Table for managing test data fixtures
  - Present in: Test schema only
  - Purpose: Stores reusable test data in JSON format
  - Assessment: Intentional test-only table
  - Action: No action needed, document in schema header
```

### Documentation
```sql
-- src/test/resources/db/schema.sql
-- =====================================================
-- TEST SCHEMA
-- =====================================================
-- This schema is synchronized with production schema
-- from db_migrator service with the following exceptions:
--
-- TEST-SPECIFIC TABLES (not in production):
--   - test_fixtures: For test data management
--
-- INTENTIONAL SIMPLIFICATIONS:
--   - Missing index idx_email_inbox_items_firm_id (performance)
-- =====================================================

-- Test-specific tables
CREATE TABLE test_fixtures (
  id BIGSERIAL PRIMARY KEY,
  fixture_name VARCHAR(100) NOT NULL,
  data JSONB NOT NULL
);

-- Production tables (synchronized)
CREATE TABLE firms (
  -- ...
);
```

---

## Example 6: Full Synchronization Workflow

### Scenario
Multiple drifts detected, performing comprehensive synchronization.

### Initial Drift Detection
```bash
$ cd /Users/traviscarter/ecfx/receipt_processing_web

# Run drift detection
$ diff src/test/resources/db/schema.sql /tmp/db-migrator-schema.sql

# Output shows:
# - Missing table: audit_logs
# - Missing column: email_inbox_items.created_at
# - Type mismatch: status VARCHAR vs ENUM
# - Extra test table: test_fixtures (expected)
```

### Generate Comprehensive Report
```markdown
## Schema Drift Detection Report

**Date**: 2025-10-27
**Test Schema**: src/test/resources/db/schema.sql
**Production Schema Source**: db_migrator repository (commit abc123)

### Summary
- **Status**: ❌ CRITICAL DRIFT
- **Total Differences**: 4
- **Critical Issues**: 3
- **Expected Differences**: 1

### Critical Drift (Action Required)

1. Missing table: `audit_logs`
2. Missing column: `email_inbox_items.created_at`
3. Type mismatch: `email_inbox_items.status`

### Expected Differences
1. Test-specific table: `test_fixtures`
```

### Synchronization Steps

**Step 1: Backup current schema**
```bash
cp src/test/resources/db/schema.sql src/test/resources/db/schema.sql.backup.2025-10-27
```

**Step 2: Create updated schema**
```bash
# Extract production schema sections
cat > /tmp/schema-updates.sql <<'EOF'
-- Add ENUM type
CREATE TYPE email_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED');

-- Update existing table
ALTER TABLE email_inbox_items
  ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ALTER COLUMN status TYPE email_status USING status::email_status;

-- Add new table
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  entity_type VARCHAR(100) NOT NULL,
  entity_id BIGINT NOT NULL,
  action VARCHAR(50) NOT NULL,
  user_id BIGINT,
  timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
EOF
```

**Step 3: Apply to test schema**
```bash
# Rebuild test schema with updates
cat src/test/resources/db/schema.sql.backup.2025-10-27 /tmp/schema-updates.sql > /tmp/new-schema.sql

# Review changes
diff src/test/resources/db/schema.sql /tmp/new-schema.sql

# Apply if approved
mv /tmp/new-schema.sql src/test/resources/db/schema.sql
```

**Step 4: Verify with tests**
```bash
# Run repository tests
./gradlew test --tests *Repository*

# Check for failures
# Expected: Tests may need updates for new columns/types
```

**Step 5: Update affected tests**
```java
// EmailInboxItemRepositorySpec.groovy
// Update fixture creation for new schema

def "should find items by firm"() {
    given: "an email inbox item with created_at"
    EmailInboxItem item = new EmailInboxItem()
    item.setStatus(InboxItem.Status.PENDING)  // Now ENUM
    item.setCreatedAt(Instant.now())          // New field
    // ...
}
```

**Step 6: Document synchronization**
```bash
# Add header comment to schema.sql
cat > src/test/resources/db/schema.sql <<'EOF'
-- =====================================================
-- TEST SCHEMA
-- Last synchronized: 2025-10-27
-- Source: db_migrator repository commit abc123
-- =====================================================
-- TEST-SPECIFIC ELEMENTS:
--   - test_fixtures table
-- =====================================================

-- [Rest of schema]
EOF
```

### Verification Results
```bash
$ ./gradlew test --tests *Repository*

BUILD SUCCESSFUL in 45s
12 actionable tasks: 12 executed

# All repository tests pass with synchronized schema
```

---

## Example 7: Continuous Drift Monitoring

### Setup Regular Drift Detection

**Create monitoring script** (`scripts/check-schema-drift.sh`):
```bash
#!/bin/bash
set -e

echo "Schema Drift Detection - $(date)"
echo "================================"

# Clone latest db_migrator schema
if [ ! -d "/tmp/db_migrator" ]; then
  git clone git@gitlab.com:ecfx/db_migrator.git /tmp/db_migrator
else
  cd /tmp/db_migrator && git pull
fi

# Compare schemas
diff -u src/test/resources/db/schema.sql /tmp/db_migrator/schema.sql > /tmp/schema-drift.diff || true

if [ -s /tmp/schema-drift.diff ]; then
  echo "⚠️  SCHEMA DRIFT DETECTED"
  echo ""
  cat /tmp/schema-drift.diff
  exit 1
else
  echo "✅ Schemas in sync"
  exit 0
fi
```

**Add to CI pipeline** (`.gitlab-ci.yml`):
```yaml
schema-drift-check:
  stage: test
  script:
    - bash scripts/check-schema-drift.sh
  allow_failure: true  # Warning only, doesn't block pipeline
  only:
    - schedules  # Run on scheduled pipelines (weekly)
```

**Schedule in GitLab**:
- CI/CD > Schedules > New Schedule
- Description: "Weekly Schema Drift Check"
- Interval: Every Monday at 9:00 AM
- Target Branch: main

### Results Over Time
```
Week 1: ✅ No drift detected
Week 2: ⚠️  1 new column detected (audit_logs.correlation_id)
        Action: Synchronized test schema
Week 3: ✅ No drift detected
Week 4: ⚠️  New table detected (notifications)
        Action: Evaluated, not needed for current tests yet
        Documented as known drift, will sync when needed
```
