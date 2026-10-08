# Schema Drift Detector: Reference

## Schema Comparison Tools

### Database-Specific Tools

#### PostgreSQL
```bash
# Export schema only (no data)
pg_dump -h host -U user --schema-only --no-owner --no-acl database_name > schema.sql

# Export specific schema (not database)
pg_dump --schema=private --schema-only database_name > private_schema.sql

# Compare two databases
pg_dump --schema-only db1 > /tmp/db1.sql
pg_dump --schema-only db2 > /tmp/db2.sql
diff -u /tmp/db1.sql /tmp/db2.sql

# Extract just table definitions
pg_dump --schema-only --table='*' database_name

# Include/exclude specific objects
pg_dump --schema-only --exclude-table=test_* database_name
```

#### MySQL
```bash
# Export schema only
mysqldump -h host -u user -p --no-data database_name > schema.sql

# Export specific tables
mysqldump --no-data database_name table1 table2 > tables.sql

# Compare schemas
mysqldump --no-data db1 > /tmp/db1.sql
mysqldump --no-data db2 > /tmp/db2.sql
diff -u /tmp/db1.sql /tmp/db2.sql
```

#### SQL Server
```bash
# Using mssql-scripter
mssql-scripter -S server -d database -U user --schema-only > schema.sql

# Using sqlcmd with system queries
sqlcmd -S server -d database -Q "SELECT * FROM INFORMATION_SCHEMA.TABLES" > schema.txt
```

### Cross-Platform Tools

#### Liquibase
```bash
# Generate changelog from database
liquibase --changeLogFile=schema.xml generateChangeLog

# Compare two databases
liquibase --referenceUrl=jdbc:... --referenceUsername=... diff

# Generate diff changelog
liquibase --referenceUrl=jdbc:... diffChangeLog
```

#### Flyway
```bash
# Export schema using info command
flyway info -schemas=schema_name

# Validate schema matches migrations
flyway validate

# Generate schema from migrations
flyway migrate -target=version > schema.sql
```

#### SchemaCrawler
```bash
# Compare two databases
schemacrawler.sh \
  --server=postgresql \
  --database=db1 \
  --command=schema \
  --output-file=db1-schema.txt

schemacrawler.sh \
  --server=postgresql \
  --database=db2 \
  --command=schema \
  --output-file=db2-schema.txt

diff db1-schema.txt db2-schema.txt
```

#### Apgdiff (PostgreSQL-specific)
```bash
# Compare two PostgreSQL schema files
apgdiff schema1.sql schema2.sql > diff.sql

# Generates ALTER statements to migrate schema1 to schema2
```

---

## Diff Techniques

### Basic Diff
```bash
# Unified format (most readable)
diff -u file1.sql file2.sql

# Side-by-side comparison
diff -y file1.sql file2.sql

# Ignore whitespace
diff -w file1.sql file2.sql

# Ignore blank lines
diff -B file1.sql file2.sql

# Ignore case
diff -i file1.sql file2.sql

# Combined: ignore whitespace and blank lines
diff -wB file1.sql file2.sql
```

### Advanced Diff
```bash
# Show only differences, no context
diff --changed-group-format='%<' --unchanged-group-format='' file1.sql file2.sql

# HTML diff output
diff -u file1.sql file2.sql | diff2html -i stdin > diff.html

# Git-style diff (if files in git)
git diff --no-index file1.sql file2.sql

# Colored diff
diff -u file1.sql file2.sql | colordiff | less -R
```

### Structural Diff (Focus on Schema Objects)
```bash
# Extract and compare CREATE TABLE statements
grep -E "^CREATE TABLE" schema.sql | sort > tables.txt

# Extract and compare indexes
grep -E "^CREATE.*INDEX" schema.sql | sort > indexes.txt

# Extract and compare constraints
grep -E "CONSTRAINT|FOREIGN KEY|PRIMARY KEY" schema.sql | sort > constraints.txt

# Compare column definitions
awk '/CREATE TABLE/,/);/' schema.sql | grep -E "^\s+\w+\s+" | sort
```

---

## Normalization Techniques

### Remove Comments
```bash
# SQL comments (-- style)
grep -v "^--" schema.sql

# C-style comments (/* */ style)
sed 's/\/\*.*\*\///g' schema.sql

# Both types
sed -e 's/\/\*.*\*\///g' -e '/^--/d' schema.sql
```

### Normalize Whitespace
```bash
# Remove trailing whitespace
sed 's/[[:space:]]*$//' schema.sql

# Remove blank lines
grep -v "^[[:space:]]*$" schema.sql

# Normalize multiple spaces to single space
sed 's/[[:space:]]\+/ /g' schema.sql

# Trim leading whitespace
sed 's/^[[:space:]]*//' schema.sql

# Combined normalization
sed -e 's/[[:space:]]*$//' \
    -e '/^[[:space:]]*$/d' \
    -e 's/[[:space:]]\+/ /g' \
    schema.sql
```

### Sort Elements
```bash
# Sort all lines (loses structure but good for exact comparison)
sort schema.sql

# Sort CREATE statements while preserving table definitions
awk '/^CREATE TABLE/,/^);$/ {print; if (/^);$/) print ""}' schema.sql | \
  awk 'BEGIN{RS="\n\n"; ORS="\n\n"} {print | "sort"}'

# Sort column definitions within tables
awk '/CREATE TABLE/,/);/ {
  if (/CREATE TABLE/) { table=$0; next }
  if (/);/) { print table; for(i in cols) print cols[i]; delete cols; print $0; next }
  cols[NR]=$0
}' schema.sql
```

### Handle Database-Specific Syntax
```bash
# Remove PostgreSQL-specific extensions
sed '/CREATE EXTENSION/d' schema.sql

# Remove MySQL engine specifications
sed 's/ENGINE=[^ ;]*//' schema.sql

# Remove AUTO_INCREMENT values (MySQL)
sed 's/AUTO_INCREMENT=[0-9]*//' schema.sql

# Normalize sequences (PostgreSQL)
sed '/CREATE SEQUENCE/,/;/d' schema.sql

# Remove schema qualifications
sed 's/public\.//g' schema.sql
```

---

## Drift Categories and Severity

### Critical Drift (Immediate Action)
- **Missing Tables**: New tables in production not in test
- **Missing Columns**: Columns added to production tables
- **Type Changes**: Column types differ (VARCHAR(50) → TEXT)
- **Missing NOT NULL**: Production has NOT NULL, test doesn't
- **Missing Primary Keys**: PK exists in prod, not in test
- **Missing Foreign Keys**: FK constraint exists in prod, not in test
- **Missing Unique Constraints**: Unique constraint in prod, not in test

**Detection Pattern**:
```bash
# Missing tables
diff <(grep "CREATE TABLE" test.sql | awk '{print $3}' | sort) \
     <(grep "CREATE TABLE" prod.sql | awk '{print $3}' | sort)

# Missing columns in specific table
diff <(awk '/CREATE TABLE target_table/,/);/' test.sql | grep -E "^\s+\w+") \
     <(awk '/CREATE TABLE target_table/,/);/' prod.sql | grep -E "^\s+\w+")
```

### Warning Drift (Review Needed)
- **Extra Tables in Test**: Tables in test not in production
- **Default Value Differences**: Different defaults for columns
- **Index Differences**: Indexes present in one but not other
- **Check Constraints**: Different CHECK constraints
- **Column Order**: Columns in different order (usually harmless)

**Detection Pattern**:
```bash
# Extra tables in test
comm -23 <(grep "CREATE TABLE" test.sql | awk '{print $3}' | sort) \
         <(grep "CREATE TABLE" prod.sql | awk '{print $3}' | sort)

# Index differences
diff <(grep "CREATE INDEX" test.sql | sort) \
     <(grep "CREATE INDEX" prod.sql | sort)
```

### Informational Drift (Low Priority)
- **Comment Differences**: Different or missing comments
- **Whitespace**: Formatting differences
- **Statement Order**: Objects defined in different order
- **Alias Differences**: Table/column aliases differ

**Detection Pattern**:
```bash
# After normalization, no differences
diff -wB test-normalized.sql prod-normalized.sql
# vs
diff test.sql prod.sql
# If first shows no diff but second does, it's informational
```

### Expected Differences (Document)
- **Test Fixtures**: Test-specific tables for fixtures
- **Test Schemas**: Separate test schema namespace
- **Performance Optimizations**: Simplified indexes for test speed
- **Mock Tables**: Tables for mocking external services

**Documentation Pattern**:
```sql
-- src/test/resources/db/schema.sql
-- =====================================================
-- EXPECTED DIFFERENCES FROM PRODUCTION
-- =====================================================
-- 1. test_fixtures table: Manages test data (test-only)
-- 2. Indexes: Fewer indexes for faster test execution
-- 3. mock_external_api table: Mocks external service (test-only)
-- =====================================================
```

---

## Schema Synchronization Strategies

### Strategy 1: Full Replacement
**When**: Comprehensive drift, multiple changes
```bash
# Backup test schema
cp src/test/resources/db/schema.sql{,.backup}

# Replace with production schema
cp /tmp/prod-schema.sql src/test/resources/db/schema.sql

# Re-add test-specific elements
cat >> src/test/resources/db/schema.sql <<'EOF'
-- Test-specific tables
CREATE TABLE test_fixtures (...);
EOF
```

**Pros**: Complete sync, no missed changes
**Cons**: Loses test-specific customizations

### Strategy 2: Incremental Updates
**When**: Few specific changes identified
```bash
# Apply specific changes to test schema
cat >> src/test/resources/db/schema.sql <<'EOF'
-- Sync changes from 2025-10-27
ALTER TABLE email_inbox_items ADD COLUMN created_at TIMESTAMP;
CREATE TABLE audit_logs (...);
EOF
```

**Pros**: Preserves test-specific elements
**Cons**: Manual process, error-prone

### Strategy 3: Patch-Based Sync
**When**: Regular synchronization workflow
```bash
# Generate patch from production to test
diff -u src/test/resources/db/schema.sql /tmp/prod-schema.sql > /tmp/schema.patch

# Review and edit patch (remove test-specific diffs)
vim /tmp/schema.patch

# Apply patch
patch src/test/resources/db/schema.sql < /tmp/schema.patch
```

**Pros**: Granular control, reviewable
**Cons**: Requires manual patch editing

### Strategy 4: Migration-Based Sync
**When**: Production uses migrations (Flyway/Liquibase)
```bash
# Identify which migrations are missing
flyway info -schemas=test_db > /tmp/test-migrations.txt
flyway info -schemas=prod_db > /tmp/prod-migrations.txt
diff /tmp/test-migrations.txt /tmp/prod-migrations.txt

# Apply missing migrations to test schema
flyway migrate -schemas=test_db -target=<latest_prod_version>
```

**Pros**: Leverages existing migration tooling
**Cons**: Requires migration files, may not fit all architectures

### Strategy 5: Automated Sync with Validation
**When**: Continuous integration setup
```bash
#!/bin/bash
# scripts/sync-test-schema.sh

set -e

# Fetch production schema
pg_dump --schema-only prod_db > /tmp/prod-schema.sql

# Backup current test schema
cp src/test/resources/db/schema.sql{,.auto-backup}

# Generate sync commands
diff -u src/test/resources/db/schema.sql /tmp/prod-schema.sql | \
  grep "^+" | grep -v "^+++" | \
  sed 's/^+//' > /tmp/sync-commands.sql

# Review sync commands
echo "Proposed changes:"
cat /tmp/sync-commands.sql

# Prompt for confirmation
read -p "Apply changes? (y/n) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Apply changes
  cat /tmp/sync-commands.sql >> src/test/resources/db/schema.sql
  echo "Schema synchronized"
else
  echo "Sync cancelled"
fi
```

**Pros**: Fast, reviewable, automated
**Cons**: May need manual adjustment for complex changes

---

## Best Practices

### Documentation
1. **Header Comments**: Document sync status in schema file
   ```sql
   -- Last synchronized: 2025-10-27
   -- Source: db_migrator commit abc123
   -- Known differences: test_fixtures table (test-only)
   ```

2. **Changelog**: Maintain sync history
   ```markdown
   # Test Schema Sync History

   ## 2025-10-27
   - Added: audit_logs table
   - Added: email_inbox_items.created_at column
   - Changed: status column from VARCHAR to ENUM

   ## 2025-09-15
   - Initial sync with db_migrator v2.5.0
   ```

3. **Diff Documentation**: Save diffs for reference
   ```bash
   mkdir -p docs/schema-diffs
   diff -u test.sql prod.sql > docs/schema-diffs/2025-10-27.diff
   ```

### Testing After Sync
1. **Repository Tests**: Verify all repository tests pass
   ```bash
   ./gradlew test --tests *Repository*
   ```

2. **Integration Tests**: Check full integration test suite
   ```bash
   ./gradlew integrationTest
   ```

3. **Schema Validation**: Verify schema loads without errors
   ```bash
   psql test_db < src/test/resources/db/schema.sql
   ```

4. **Entity Mapping**: Ensure JPA entities map correctly
   ```bash
   ./gradlew test --tests *EntityMappingTest
   ```

### Regular Maintenance
1. **Scheduled Checks**: Weekly or monthly drift detection
2. **Pre-Release Sync**: Before major releases, sync schemas
3. **CI Integration**: Add drift detection to CI pipeline
4. **Alert Thresholds**: Alert when drift exceeds threshold (e.g., >5 differences)

### Version Control
1. **Commit Syncs**: Each sync gets its own commit
   ```bash
   git add src/test/resources/db/schema.sql
   git commit -m "test(schema): sync with db_migrator abc123"
   ```

2. **Branch Protection**: Review schema changes in MRs
3. **Schema Tags**: Tag significant schema versions
   ```bash
   git tag -a schema-v2.0 -m "Schema version 2.0 sync"
   ```

---

## Related Documentation

### Micronaut Resources
- [Micronaut TestResources](https://micronaut-projects.github.io/micronaut-test-resources/latest/guide/)
- [Micronaut Data JPA](https://micronaut-projects.github.io/micronaut-data/latest/guide/#jdbc)
- [Micronaut Testing](https://docs.micronaut.io/latest/guide/#testing)

### Schema Management
- [Flyway Documentation](https://flywaydb.org/documentation/)
- [Liquibase Documentation](https://docs.liquibase.com/)
- [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
- [MySQL mysqldump](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)

### Diff Tools
- [GNU Diffutils](https://www.gnu.org/software/diffutils/)
- [diff2html](https://diff2html.xyz/)
- [Meld Visual Diff](https://meldmerge.org/)
- [Beyond Compare](https://www.scootersoftware.com/)

### Testing Best Practices
- [TestContainers](https://www.testcontainers.org/)
- [Database Testing Patterns](https://martinfowler.com/articles/evodb.html)
- [Test Data Builders](https://wiki.c2.com/?TestDataBuilder)
