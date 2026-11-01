---
name: flyway-migration-preflight
description: >-
  Validate a new or modified Flyway migration in ecfx-backend before commit — version collision against master AND open MRs, no CREATE INDEX CONCURRENTLY (repo convention), partial-index predicates preserved when rewriting indexes, and the commons_test master schema.sql mirror updated. Use when creating or reviewing a SQL migration in projects/db_migrator, when the user mentions Flyway, a V### migration, migration version conflicts, or when repository tests fail after a schema change.
---


# Flyway Migration Preflight

Pre-commit validation for Flyway migrations in **ecfx-backend** (`~/gitlab/ecfx-backend-v4/ecfx-backend` or wherever the clone lives). There is **no CI check for version collisions** — two MRs can both claim `V821` and the second one to merge breaks the migrator job. This skill is the guard.

Migrations live at:

```
projects/db_migrator/src/main/resources/db/migration/V<number>__<snake_case_description>.sql
```

Example: `V819__document_categorization_retry_state.sql`. Version numbers may have gaps (no V814/V816/V818 exist) — gaps are fine; **collisions are not**.

## Process

### 1. Identify the migration(s) under review

```bash
git -C <checkout> status --porcelain projects/db_migrator/src/main/resources/db/migration/
git -C <checkout> diff --name-only origin/master...HEAD -- projects/db_migrator/src/main/resources/db/migration/
```

### 2. Version-collision check — three surfaces

**a) Local vs master.** The new version must be strictly greater than the highest on `origin/master`:

```bash
git -C <checkout> fetch origin master --quiet
git -C <checkout> ls-tree -r --name-only origin/master -- projects/db_migrator/src/main/resources/db/migration/ \
  | sed -E 's#.*/V([0-9]+)__.*#\1#' | sort -n | tail -1
```

**b) Open MRs.** Check every open MR that touches the migration directory for the same version number:

```bash
for iid in $(glab mr list -R ecfx/ecfx-backend --state opened --output json | jq -r '.[].iid'); do
  glab api "projects/:id/merge_requests/$iid/changes" \
    | jq -r --arg iid "$iid" '.changes[].new_path | select(test("db/migration/V")) | "\($iid)\t\(.)"'
done
```

If any open MR claims the same `V<number>`, **renumber yours to highest+1 and say which MR you're avoiding.** (This exact collision happened: a V809 claimed by another MR forced a rename to V810.)

**c) Duplicate within the branch.** Two files with the same version prefix in the directory is an immediate failure:

```bash
ls projects/db_migrator/src/main/resources/db/migration/ | sed -E 's/^(V[0-9]+)__.*/\1/' | sort | uniq -d
```

### 3. CONCURRENTLY check — repo convention is to keep it OUT

Flyway runs each migration inside a transaction, and `CREATE INDEX CONCURRENTLY` cannot run inside a transaction. The established repo convention (stated verbatim in `V819`, applied in `V758`, `V778`, `V810`, `V817`) is:

- **Never put `CREATE INDEX CONCURRENTLY` in a migration.** Ship the plain `CREATE INDEX` form; if the table is hot enough to need a concurrent build, the index is built manually out-of-band first and the migration's plain form becomes a no-op via `IF NOT EXISTS`.
- A commented-out CONCURRENTLY form as documentation is fine; an active one is a blocker.

```bash
grep -in "CONCURRENTLY" <new-migration.sql>   # active (uncommented) hits are blockers
```

### 4. Index-rewrite predicate check

When a migration **replaces or rewrites an existing index**, verify the new definition preserves any partial-index `WHERE` predicate from the old one. Dropping a partial predicate silently turns a small hot index into a full-table index — this caused a production post-processing throughput collapse (ECFX-15618, regression from the V819 work). Compare against the current definition:

```bash
grep -n -A3 "CREATE .*INDEX.*<index_name>" projects/db_migrator/src/main/resources/db/migration/*.sql
grep -n -B2 -A4 "<index_name>" projects/commons_test/src/main/resources/db/schema.sql
```

### 5. Test-schema mirror

Integration tests do **not** run Flyway. They load a hand-maintained master schema via `SchemaLoader.loadMasterSchema(dataSource)`:

```
projects/commons_test/src/main/resources/db/schema.sql
```

Every DDL change in the migration must be manually mirrored into that file, or repository Specs will pass against a stale schema (or fail mysteriously). Verify the same tables/columns/indexes/constraints appear in both. For a deeper structural comparison, use the `schema-drift-detector` skill.

### 6. Content safety checklist

- [ ] Version strictly greater than master's highest AND not claimed by any open MR
- [ ] No active `CREATE INDEX CONCURRENTLY`
- [ ] Rewritten indexes preserve partial predicates and column order
- [ ] `commons_test/src/main/resources/db/schema.sql` updated to match
- [ ] Destructive ops (`DROP`, `ALTER ... TYPE`, `NOT NULL` on existing column) called out explicitly with a rollback note
- [ ] New columns on large/hot tables avoid table-rewriting defaults where possible
- [ ] File name is `V<number>__<snake_case_description>.sql` (double underscore)

## Output

Report a short verdict: **PASS** or the specific failures with the fix (e.g. "V821 also claimed by open MR !5432 — renumber to V822"). If everything passes, say so in one line; don't pad.

## Scope

This skill is specific to the ecfx-backend repo layout. For other repos with Flyway, apply steps 2–4 generically but skip the `commons_test` mirror step.
