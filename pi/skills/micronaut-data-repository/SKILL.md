---
name: micronaut-data-repository
description: >-
  Validate repository interfaces follow Micronaut Data conventions for query derivation. Use when creating or modifying repository interfaces, when query derivation compilation fails, when user mentions Micronaut Data repositories, or when "unable to implement" errors occur.
---


# Micronaut Data Repository Validator

Validate that repository interfaces follow Micronaut Data query derivation conventions. This prevents compilation errors caused by invalid method names, unsupported expressions, or property mismatches.

## Problem Solved

Micronaut Data uses compile-time query derivation with different rules than Spring Data. Invalid method names, unsupported expressions, or property name mismatches cause compilation failures. This skill validates repository methods before compilation to catch errors early.

## Critical Concept

**Compile-Time Validation**:
- Micronaut Data generates queries at compile-time (not runtime)
- Property names in method names must exactly match entity properties (case-sensitive)
- Unsupported expressions cause immediate compilation failure
- No query translation happens at runtime like in Spring Data

## Process

### 1. Identify Repository Interface and Entity

Extract from context:
- **Repository interface**: e.g., `EmailInboxItemRepository`
- **Entity class**: e.g., `EmailInboxItem`
- **Repository location**: e.g., `src/main/java/com/goecfx/repositories/`
- **Entity location**: e.g., External library or `src/main/java/com/goecfx/entities/`

### 2. Locate and Read Files

Read the repository interface:
```bash
# Find repository
find src/main/java -name "*Repository.java"
```

Read the entity class (if in project):
```bash
# Find entity
find src/main/java -name "EmailInboxItem.java"
```

For external library entities, use the verify-library-api skill to inspect available properties.

### 3. Extract Entity Properties

From the entity class, identify all valid property names:

**Field-based properties**:
```java
@Entity
public class EmailInboxItem {
    private Long id;
    private String rawEmail;
    private InboxItem.Status status;
    private Firm firm;  // Association
}
```

**Valid property names**: `id`, `rawEmail`, `status`, `firm`
**Nested properties** (via associations): `firm.id`, `firm.name`

### 4. Validate Each Repository Method

For each method in the repository interface, check:

#### Method Name Structure

Valid structure: `[prefix][projection][By][criteria][OrderBy][sorting]`

**Example**: `findDistinctByFirmIdOrderByCreatedAtDesc`
- Prefix: `find`
- Projection: `Distinct`
- By: `By`
- Criteria: `FirmId`
- OrderBy: `OrderByCreatedAtDesc`

#### Supported Prefixes

**Query methods**: `find`, `get`, `query`, `retrieve`, `read`, `search`
**Count methods**: `count`
**Existence methods**: `exists`
**Delete methods**: `delete`, `remove`, `erase`, `eliminate`
**Update methods**: `update`

**Validation check**:
- [ ] Method starts with supported prefix
- [ ] Prefix matches method purpose (e.g., `count` returns Number)

#### Property Name Validation

**Extract property names from method name**:
- `findByFirmId` → property: `firmId`
- `findByFirm_Id` → nested property: `firm.id` (underscore indicates nesting)
- `findByStatusAndRawEmailLike` → properties: `status`, `rawEmail`

**Validation checks**:
- [ ] Property name exactly matches entity property (case-sensitive)
- [ ] Property type supports the expression (e.g., `Like` requires String)
- [ ] Nested properties use valid association paths

**Common mistakes**:
- `findByFirmID` (wrong case, should be `FirmId`)
- `findByEmail` (wrong property name, should be `RawEmail`)
- `findByFirmName` (should be `Firm_Name` for nested property)

#### Expression Validation

**Supported expressions**: `GreaterThan`, `LessThan`, `Between`, `Like`, `Ilike`, `Contains`, `StartsWith`, `EndsWith`, `InList`, `IsNull`, `IsNotNull`, `True`, `False`

**Negation**: Prefix with `Not` (e.g., `NotInList`, `NotContains`)

**Validation checks**:
- [ ] Expression is supported by Micronaut Data
- [ ] Expression matches property type (e.g., `Like` only for String)
- [ ] Method parameters match expression requirements

**Common mistakes**:
- `findByNameEquals` (unnecessary, should be `findByName`)
- `findByIdLike` (Like doesn't make sense for Long)
- `findByCreatedBefore` (should be `CreatedLessThan` or use @Query)

#### Projection Validation

**Supported projections**: `Distinct`, `Count`, `CountDistinct`, `Max`, `Min`, `Sum`, `Avg`, `Top`, `First`

**Validation checks**:
- [ ] Projection placement is correct (before `By`)
- [ ] Return type matches projection (e.g., `count` returns Number)
- [ ] Property supports aggregation

**Examples**:
- `countByStatus()` → returns `long`
- `findMaxIdByStatus()` → returns `Long` or `Optional<Long>`
- `findTop10ByOrderByCreatedAtDesc()` → returns `List<Entity>`

#### Logical Operators

**Supported**: `And`, `Or`

**Validation checks**:
- [ ] Operators combine valid expressions
- [ ] Parameter count matches criteria count
- [ ] Operator precedence is clear (use parentheses in complex queries)

**Example**: `findByStatusAndFirmIdOrRawEmailLike`
- Parameters: `(Status status, Long firmId, String rawEmail)`

#### Parameter Validation

**Validation checks**:
- [ ] Parameter count matches criteria count
- [ ] Parameter types match property types
- [ ] Parameter names are meaningful (not required but recommended)
- [ ] Special types handled correctly (`Pageable`, `Sort`)

**Common mistakes**:
- Wrong parameter count: `findByStatusAndFirmId(Status status)` (missing firmId)
- Wrong parameter type: `findByFirmId(String id)` (should be Long)
- Missing Pageable: `findAll()` returning `Page<T>` (needs `Pageable` parameter)

#### Return Type Validation

**Validation checks**:
- [ ] Return type matches method purpose
- [ ] Collection types appropriate (`List`, `Set`, `Stream`)
- [ ] Optional used for single results that might not exist
- [ ] Pagination types (`Page`, `Slice`) require `Pageable` parameter

**Common return types**:
- `List<Entity>` - multiple results
- `Optional<Entity>` - single result that might not exist
- `Entity` - single result that must exist (throws if not found)
- `long` / `Long` - count operations
- `boolean` - existence checks
- `void` - delete/update operations
- `Page<Entity>` - paginated results (requires Pageable)

### 5. Check for Anti-Patterns

**Anti-Pattern 1**: Using Spring Data expressions
```java
// ❌ WRONG - Spring Data syntax
List<EmailInboxItem> findByCreatedAtBefore(LocalDateTime date);

// ✅ CORRECT - Micronaut Data syntax
List<EmailInboxItem> findByCreatedAtLessThan(LocalDateTime date);
```

**Anti-Pattern 2**: Complex queries in method names
```java
// ❌ WRONG - too complex for method name
List<EmailInboxItem> findByStatusAndFirmIdAndCreatedAtBetweenAndRawEmailLikeOrderByCreatedAtDesc(...);

// ✅ CORRECT - use @Query for complex queries
@Query("SELECT e FROM EmailInboxItem e WHERE ...")
List<EmailInboxItem> findComplexQuery(...);
```

**Anti-Pattern 3**: Incorrect property casing
```java
// ❌ WRONG - property is 'firmId' not 'FirmID'
List<EmailInboxItem> findByFirmID(Long id);

// ✅ CORRECT
List<EmailInboxItem> findByFirmId(Long id);
```

**Anti-Pattern 4**: Missing parameters
```java
// ❌ WRONG - Between requires two parameters
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start);

// ✅ CORRECT
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);
```

**Anti-Pattern 5**: Using @Transactional on repository
```java
// ❌ WRONG - @Transactional belongs on service methods
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    @Transactional
    List<EmailInboxItem> findByFirmId(Long firmId);
}

// ✅ CORRECT - no @Transactional on repository
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    List<EmailInboxItem> findByFirmId(Long firmId);
}
```

### 6. Generate Validation Report

Create a comprehensive report:

```markdown
## Micronaut Data Repository Validation: [RepositoryName]

**Repository**: [RepositoryInterface]
**Entity**: [EntityClass]
**Methods Validated**: [count]

### Method Validation Results

#### Method: findByFirmId(Long firmId)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find` (supported)
- ✅ Property: `firmId` (exists on entity, type: Long)
- ✅ Parameter: `Long firmId` (matches property type)
- ✅ Return type: `List<EmailInboxItem>` (appropriate)

#### Method: findByCreatedBefore(LocalDateTime date)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find` (supported)
- ❌ Expression: `Before` (NOT supported in Micronaut Data)
- ❌ Should use: `CreatedLessThan` or `CreatedAtLessThan`

**Issues**:
1. **Line 15**: Expression `Before` is not supported
   - **Problem**: Spring Data syntax, not Micronaut Data
   - **Impact**: Compilation will fail
   - **Fix**: Change to `findByCreatedAtLessThan(LocalDateTime date)`

### Overall Assessment
**Result**: ❌ ERRORS FOUND - [X] method(s) need correction

### Recommendations
[List specific fixes needed for each invalid method]
```

### 7. Provide Corrective Actions

For each invalid method, provide specific fix:

**For unsupported expressions**:
```java
// Before (wrong):
List<EmailInboxItem> findByCreatedBefore(LocalDateTime date);

// After (correct):
List<EmailInboxItem> findByCreatedAtLessThan(LocalDateTime date);
```

**For property name mismatches**:
```java
// Before (wrong):
List<EmailInboxItem> findByFirmID(Long id);

// After (correct):
List<EmailInboxItem> findByFirmId(Long id);
```

**For complex queries**:
```java
// Before (wrong - too complex):
List<EmailInboxItem> findByStatusAndFirmIdAndCreatedAtBetween...(...);

// After (correct - use @Query):
@Query("SELECT e FROM EmailInboxItem e WHERE e.status = :status " +
       "AND e.firmId = :firmId AND e.createdAt BETWEEN :start AND :end " +
       "ORDER BY e.createdAt DESC")
List<EmailInboxItem> findByComplexCriteria(
    @Param("status") Status status,
    @Param("firmId") Long firmId,
    @Param("start") LocalDateTime start,
    @Param("end") LocalDateTime end
);
```

## Quality Checklist

- [ ] Repository interface located and read
- [ ] Entity class properties identified
- [ ] All repository methods extracted
- [ ] Each method prefix validated
- [ ] Property names verified against entity
- [ ] Expressions checked for support
- [ ] Parameter counts and types validated
- [ ] Return types verified
- [ ] Anti-patterns identified
- [ ] Specific corrective actions provided
- [ ] Report clearly identifies all issues

## When to Use This Skill

**Always use when**:
- Creating new repository interfaces
- Adding methods to existing repositories
- Compilation fails with "unable to implement" errors
- Migrating from Spring Data to Micronaut Data

**Warning signs that indicate need**:
- Error: "Unable to implement Repository method"
- Error: "Cannot query entity ... on non-existent property"
- Method compiles but throws runtime errors
- Uncertain about Micronaut Data expression support

**Preventative use**:
- Before first compilation after adding repository methods
- During code review of repository changes
- When onboarding developers new to Micronaut Data

## Expected Behavior When Correct

When repository is valid:

1. **Compilation succeeds**: No errors from annotation processor
2. **Query generation**: Micronaut generates SQL at compile-time
3. **Runtime execution**: Methods work as expected
4. **Type safety**: Parameters and return types enforced

## Special Cases

**External Library Entities**: Use verify-library-api skill to inspect properties before validating repository

**Custom Queries**: Methods with `@Query` don't need method name validation, but parameter names must match

**Multiple Datasources**: Verify repository extends correct base for the datasource

**DTO Projections**: Return type DTOs must be `@Introspected` and property names must match entity

## Composite-PK Read-Only Repositories

For repositories that only need to LOOK UP entities with composite primary keys (`@IdClass`), extend `GenericRepository<E, IdType>`, NOT `JpaRepository`. `JpaRepository` requires a single-typed PK and exposes persistence methods (save, delete) you don't need.

```java
// Composite PK via @IdClass — only needs lookups
@Repository
public interface ECFXProviderJurisdictionRepository
        extends GenericRepository<ECFXProviderJurisdiction, String> {

    Optional<ECFXProviderJurisdiction> findBySignature(String signature);
}
```

Trying to extend `JpaRepository<ECFXProviderJurisdiction, IdClass>` will fail because the IdClass is not a single typed value.

## Projections — JPQL vs Native (Records vs Interfaces)

Projection style choice depends on query type:

| Projection style | When it works | When it fails |
|------------------|---------------|---------------|
| `@Introspected interface Projection { String getX(); }` + `@Query("SELECT x AS xField ...")` | NATIVE queries (`nativeQuery = true`) and Micronaut Data JDBC runtime | JPQL queries: compiles fine, explodes at first call with `InstantiationException: No default constructor exists` (Micronaut's `BeanIntrospectionMapper` tries to instantiate the interface) |
| `@Introspected @Serdeable record Projection(String x, String y)` + `@Query("SELECT new fully.qualified.Record(x, y) FROM ...")` | Both JPQL and native (canonical record constructor satisfies `SELECT new`) | — |

**Recommendation**: default to record projections with `SELECT new` — they work in both JPQL and native queries and are immutable by design. Switch the property accessors from `getX()` to `x()` (record accessor syntax).

---

For detailed examples, see `examples.md`
For Micronaut Data reference documentation links, see `reference.md`
