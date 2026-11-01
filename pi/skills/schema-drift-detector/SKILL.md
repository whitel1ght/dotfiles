---
name: schema-drift-detector
description: >-
  Compare test schema.sql with actual production schema from db_migrator service to detect divergence. Use when creating new entities, when repository tests fail mysteriously, periodically as maintenance, or when user mentions schema sync, test schema, or database schema issues.
---


# Schema Drift Detector

Detect when test schema diverges from production schema managed by the external db_migrator service. This prevents false positives/negatives in repository tests caused by schema mismatches.

## Problem Solved

In architectures where schema is managed externally (not by the application), test schemas can drift from production. This causes:
- Repository tests passing with outdated schema (false positives)
- Tests failing because schema is ahead/behind production (false negatives)
- Wasted debugging time tracking down schema-related issues
- Integration failures when deploying code that worked in tests

## Critical Concept

**External Schema Management Pattern**:
- Production schema is managed by a separate service (e.g., db_migrator)
- Application has NO schema migration tools (no Flyway, Liquibase)
- Test schema is a COPY stored in `src/test/resources/db/schema.sql`
- This copy can become stale and must be synchronized regularly

## Process

### 1. Locate Test Schema File

Find the test schema file in the project:

```bash
find . -path "*/test/resources/db/schema.sql" -o -path "*/test/resources/schema.sql"
```

**Common locations**:
- `src/test/resources/db/schema.sql`
- `test/resources/schema.sql`
- `src/test/resources/sql/schema.sql`

If not found, check project documentation for schema location.

### 2. Identify Production Schema Source

Determine where the canonical production schema is maintained:

**Option A: Separate Repository**
- Schema in dedicated repository (e.g., `db_migrator` service)
- Check project documentation or README for repository location
- Look for references like "schema managed by db_migrator service"

**Option B: Migration Files**
- Schema defined in migration files (Flyway/Liquibase in separate service)
- Migration directory typically: `db/migrations/` or `migrations/`

**Option C: Schema Export**
- Export current schema from production-like database
- Use `pg_dump` for PostgreSQL, `mysqldump` for MySQL

**Ask the user** if location is unclear:
- Where is the production schema maintained?
- Is there a db_migrator or schema service repository?
- Should we compare against a running database?

### 3. Obtain Production Schema

Based on source type, obtain the current production schema:

**For Separate Repository**:
```bash
# Clone or update the schema repository
git clone <schema-repo-url> /tmp/schema-repo
# Or if already cloned:
cd /tmp/schema-repo && git pull

# Locate schema file
find /tmp/schema-repo -name "schema.sql" -o -name "*.sql" | grep -v test
```

**For Migration-Based Schema**:
```bash
# If migrations are in separate repo, clone it
git clone <migrations-repo-url> /tmp/migrations

# Generate schema from migrations (tool-specific)
# Flyway:
flyway info -schemas=<schema-name>

# Liquibase:
liquibase updateSQL

# Or export from a database with migrations applied
```

**For Database Export**:
```bash
# PostgreSQL
pg_dump -h <host> -U <user> --schema-only --no-owner --no-acl <database> > /tmp/prod-schema.sql

# MySQL
mysqldump -h <host> -u <user> -p --no-data <database> > /tmp/prod-schema.sql
```

### 4. Normalize Schemas for Comparison

Before comparing, normalize both schemas to reduce false positives:

**Remove non-structural differences**:
- Comments (SQL comments, header comments)
- Whitespace variations (extra spaces, blank lines)
- Object creation order (if semantically equivalent)
- Environment-specific settings
- Auto-generated timestamps or version comments

**Create normalized copies**:
```bash
# Normalize test schema
grep -v "^--" src/test/resources/db/schema.sql | \
  sed 's/[[:space:]]*$//' | \
  grep -v "^[[:space:]]*$" > /tmp/test-schema-normalized.sql

# Normalize production schema (adjust path as needed)
grep -v "^--" /tmp/prod-schema.sql | \
  sed 's/[[:space:]]*$//' | \
  grep -v "^[[:space:]]*$" > /tmp/prod-schema-normalized.sql
```

**Alternative: Focus on structure only**
```bash
# Extract CREATE statements only (tables, indexes, constraints)
grep -E "^CREATE (TABLE|INDEX|UNIQUE INDEX|SEQUENCE)" schema.sql | sort
```

### 5. Compare Schemas

Use `diff` to identify differences:

```bash
diff -u /tmp/test-schema-normalized.sql /tmp/prod-schema-normalized.sql
```

**Analyze diff output**:
- Lines starting with `-` exist in test but not production (removed or test-only)
- Lines starting with `+` exist in production but not test (missing updates)
- Context lines show where differences occur

**For structure-only comparison**:
```bash
# Compare table definitions
diff <(grep -E "^CREATE TABLE" /tmp/test-schema-normalized.sql | sort) \
     <(grep -E "^CREATE TABLE" /tmp/prod-schema-normalized.sql | sort)

# Compare indexes
diff <(grep -E "^CREATE.*INDEX" /tmp/test-schema-normalized.sql | sort) \
     <(grep -E "^CREATE.*INDEX" /tmp/prod-schema-normalized.sql | sort)
```

### 6. Categorize Drift

Classify detected differences by severity and type:

**Critical Drift** (Immediate action required):
- Missing tables in test schema
- Missing columns in test schema
- Different column types (e.g., VARCHAR(100) vs TEXT)
- Missing constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL)
- Missing indexes used by queries in tests

**Warning Drift** (Review needed):
- Extra tables in test schema (test-specific fixtures)
- Extra columns in test schema (future features)
- Different default values
- Different index types or properties

**Informational Drift** (Low priority):
- Comment differences
- Column order differences (if not affecting tests)
- Whitespace or formatting differences

**Expected Differences** (Document, don't fix):
- Test-specific tables for fixtures
- Test-specific schemas
- Simplified constraints for test performance

### 7. Generate Drift Report

Create a comprehensive report:

```markdown
## Schema Drift Detection Report

**Date**: [timestamp]
**Test Schema**: src/test/resources/db/schema.sql
**Production Schema Source**: [location/repo/database]

### Summary
- **Status**: ✅ NO DRIFT / ⚠️ MINOR DRIFT / ❌ CRITICAL DRIFT
- **Total Differences**: [count]
- **Critical Issues**: [count]
- **Warnings**: [count]
- **Informational**: [count]

### Critical Drift (Action Required)

#### Missing Tables in Test Schema
- `table_name` - Created in production [date/migration]
  - Impact: Tests cannot use this table
  - Action: Add table definition to test schema

#### Missing Columns
- `table.column_name` - Type: [type], Constraints: [constraints]
  - Impact: Repository queries may fail or return incomplete data
  - Action: Add column to test schema table definition

#### Type Mismatches
- `table.column_name` - Test: [type1], Production: [type2]
  - Impact: Different behavior in tests vs production
  - Action: Update column type in test schema

#### Missing Constraints
- `table` - Missing [FOREIGN KEY/UNIQUE/NOT NULL] on [column]
  - Impact: Tests may pass invalid data that fails in production
  - Action: Add constraint to test schema

### Warning Drift (Review Needed)

#### Extra Tables in Test Schema
- `test_fixtures_table` - Present in test, not in production
  - Assessment: [Test-specific fixture / Stale table / Future feature]
  - Action: [Document as test-only / Remove / Synchronize]

#### Default Value Differences
- `table.column_name` - Test: [default1], Production: [default2]
  - Impact: Different behavior for omitted values
  - Action: Align default values

### Informational Drift

#### Whitespace/Formatting
- [List formatting differences]
- Action: Optional formatting cleanup

### Expected Differences (Documented)

#### Test-Specific Elements
- `test_schema.fixtures` - Test-only schema for fixtures
- Assessment: Intentional, no action needed

### Synchronization Recommendations

1. **Immediate Actions** (Critical):
   - [Specific SQL statements to add/modify]

2. **Recommended Actions** (Warnings):
   - [Specific recommendations with rationale]

3. **Optional Actions** (Informational):
   - [Formatting or documentation improvements]

### Synchronization Commands

```sql
-- Add missing table
CREATE TABLE table_name (
  -- [definition from production schema]
);

-- Add missing column
ALTER TABLE table_name ADD COLUMN column_name TYPE;

-- Fix type mismatch
ALTER TABLE table_name ALTER COLUMN column_name TYPE new_type;

-- Add missing constraint
ALTER TABLE table_name ADD CONSTRAINT constraint_name [constraint_definition];
```

### Next Steps

1. Review and approve recommended changes
2. Update `src/test/resources/db/schema.sql` with approved changes
3. Re-run repository tests to verify compatibility
4. Document any intentional test-specific differences
5. Schedule regular drift detection (e.g., monthly or before major releases)
```

### 8. Provide Synchronization Guidance

Offer specific guidance for updating the test schema:

**For simple additions**:
```bash
# Extract specific table definition from production
grep -A 20 "CREATE TABLE new_table" /tmp/prod-schema.sql

# Add to test schema at appropriate location
# (Maintain alphabetical order or logical grouping)
```

**For comprehensive sync**:
```bash
# Backup current test schema
cp src/test/resources/db/schema.sql src/test/resources/db/schema.sql.backup

# Replace with normalized production schema
cp /tmp/prod-schema-normalized.sql src/test/resources/db/schema.sql

# Re-add test-specific elements (if any)
# [Document which elements are test-specific]
```

**After synchronization**:
```bash
# Run repository tests to verify compatibility
./gradlew test --tests *Repository*

# Check for any test failures
# Update tests if schema changes require query modifications
```

## Quality Checklist

- [ ] Test schema file located
- [ ] Production schema source identified
- [ ] Production schema obtained successfully
- [ ] Both schemas normalized for comparison
- [ ] Diff executed without errors
- [ ] Differences categorized by severity
- [ ] Critical issues clearly identified
- [ ] Impact assessment provided for each difference
- [ ] Synchronization commands provided
- [ ] Next steps documented
- [ ] Report easy to understand and actionable

## When to Use This Skill

**Proactive Use**:
- Before creating new entities in the application
- **When adding/changing an entity in a JOINED or SINGLE_TABLE inheritance hierarchy** — additional polymorphic-loading checks apply (see Inheritance Strategies below)
- Before major feature development touching the database
- Monthly or quarterly as preventative maintenance
- After known schema changes in db_migrator service
- During onboarding to verify test environment setup

**Reactive Use**:
- When repository tests fail mysteriously
- After entity-related compilation errors
- When tests pass but integration/production fails
- When new developers report schema issues
- After "table does not exist" or "column not found" errors in tests

**Red Flags Indicating Drift**:
- Repository test failures: "relation does not exist"
- Type mismatch errors in tests
- Constraint violation differences between test and production
- Tests passing locally but failing in CI with schema errors
- New entity code compiles but repository queries fail

## Inheritance Strategies — Additional Schema Checks

JPA inheritance changes how Hibernate generates SQL, and the test schema must accommodate the FULL polymorphic shape — not just the entity you're testing.

### `@Inheritance(strategy = JOINED)`

Hibernate generates LEFT JOINs to ALL subtables in every polymorphic query, even when the FK is null. **Estimate EAGER `@ManyToOne` dependency depth BEFORE writing tests.**

**Example**: `StoragePolicy.dmsCredential` is `@ManyToOne` (default EAGER) to `DMSCredential`, which has `@Inheritance(strategy=JOINED)` with 16 concrete subclasses. Loading ANY entity that reaches `StoragePolicy` triggers LEFT JOINs to all 16 credential subtables. The test schema MUST include 16 stub tables with all their mapped columns.

**Checklist for JOINED hierarchies**:
- [ ] List every concrete subclass (`grep -l 'extends ParentClass'`)
- [ ] Each subclass has a stub table in `schema.sql` with ALL its `@Column`-annotated fields
- [ ] Stub tables include the discriminator column type and FK back to parent

### `@Inheritance(strategy = SINGLE_TABLE)`

All columns from all subtypes live in one table. Hibernate SELECTs every mapped column regardless of the discriminator value. Missing subtype columns (e.g., `WebhookInboxItem.parsed_content` on `inbox_item`) cause `column does not exist` at runtime.

**Checklist for SINGLE_TABLE hierarchies**:
- [ ] Every subtype's `@Column` fields exist in the single table
- [ ] Pay attention to subtype `@PostLoad` hooks — they trigger during query result loading and can mark entities dirty, causing auto-flush during subsequent COUNT queries (use a discriminator value WITHOUT `@PostLoad` side effects for filter/pagination test fixtures)

## Master Schema vs. Local Schema — Diff Checklist

When migrating a project from a local `schema.sql` to a shared master schema (e.g., `commons_test`), several common drift sources hit at once:

- [ ] **NOT NULL columns without defaults**: master schema may add `firm.encryption_key_id uuid NOT NULL` (no DEFAULT). Local schema had `DEFAULT '00000000-...'::uuid`. Every `INSERT INTO firm` that omits this column now fails — grep for all firm INSERTs and add the column.
- [ ] **Enum domains vs varchar**: master schema may use `private.email` (citext domain) where local schema had `varchar`. Test data inserts may need explicit casts: `?::private.inbox_item_status`.
- [ ] **PostgreSQL `search_path`**: extensions like `hstore`, `citext` live in their own schema (typically `extensions`). When switching `default_schema: public` → `default_schema: public_v1`, you also need `connection-init-sql: "SET search_path TO extensions, public_v1"` in `application-test.yml`. The `@Property(name = "datasource.default.schema")` annotation alone does NOT set PostgreSQL's `search_path` for extensions.
- [ ] **Table location moves**: `public.tablename` → `private.tablename` (with views in `public_v1`). Grep `public\.` across all SQL test files and rewrite. Also check escaped variants (`public.\"user\"`).
- [ ] **Missing tables/views/enums**: master schema may not include project-specific tables (e.g., `inbox_item_notification`, `inbox_item_notification_cadence` enum). Check ALL entity classes in the project against master schema before declaring migration complete.
- [ ] **Inline schema specs**: some specs build their own tables directly via `CREATE TABLE` in `setup()` — grep for `CREATE TABLE` across test sources to find them; they need migrating too.

## Special Cases

**Multiple Schemas**: If using database schemas (e.g., `public`, `private`):
```bash
# Compare specific schema
pg_dump --schema=private --schema-only > /tmp/private-schema.sql
diff src/test/resources/db/private-schema.sql /tmp/private-schema.sql
```

**Incremental Migrations**: If production uses migrations:
```bash
# Identify which migrations are missing from test schema
# Compare migration version numbers or checksums
flyway info -schemas=test_schema
flyway info -schemas=prod_schema
```

**Cross-Database Compatibility**: If test uses different DB than production:
```sql
-- PostgreSQL-specific
CREATE TABLE ... WITH (fillfactor=90);

-- Generic (for test compatibility)
CREATE TABLE ... ;
```
Document these intentional differences in `schema-differences.md`.

**Test-Specific Optimizations**: Tests may intentionally simplify:
- Fewer indexes (faster test data setup)
- Relaxed constraints (easier fixture creation)
- Smaller VARCHAR limits (test data smaller)

Document these in test schema header comments.

## Output Format

Present drift report in markdown format with:
1. Executive summary (status and counts)
2. Critical issues with specific impact and actions
3. Warning issues with recommendations
4. Informational differences
5. Synchronization SQL commands ready to execute
6. Next steps checklist

Offer to:
- Execute synchronization if approved
- Re-run tests after synchronization
- Document intentional differences
- Schedule regular drift checks

---

For detailed examples of drift patterns, see `examples.md`
For schema comparison tools and techniques, see `reference.md`
