# Micronaut Data Repository Validator - Reference

## Micronaut Data Documentation

### Official Resources
- [Micronaut Data Guide](https://micronaut-projects.github.io/micronaut-data/latest/guide/)
- [Query Methods Reference](https://micronaut-projects.github.io/micronaut-data/latest/guide/#querying)
- [Repository Interfaces](https://micronaut-projects.github.io/micronaut-data/latest/guide/#repositories)
- [GitHub Repository](https://github.com/micronaut-projects/micronaut-data)

---

## Query Method Structure

### Complete Method Name Pattern

```
[prefix] + [projection] + [By] + [criteria] + [OrderBy] + [sorting]
```

### Component Breakdown

**Prefix** (required):
- Query: `find`, `get`, `query`, `retrieve`, `read`, `search`
- Count: `count`
- Exists: `exists`
- Delete: `delete`, `remove`, `erase`, `eliminate`
- Update: `update`

**Projection** (optional):
- `Distinct` - unique results
- `Top[N]` / `First[N]` - limit results
- `Count` - count values
- `Max` / `Min` / `Sum` / `Avg` - aggregations

**By** (required for criteria):
- Keyword separating prefix from criteria
- Omitted for methods like `findAll()`, `count()`

**Criteria** (optional):
- Property names from entity
- Expressions (`Like`, `GreaterThan`, etc.)
- Logical operators (`And`, `Or`)

**OrderBy** (optional):
- `OrderBy[Property][Direction]`
- Direction: `Asc` (ascending) or `Desc` (descending)
- Multiple: `OrderByNameAscCreatedAtDesc`

**Examples**:
```java
findDistinctByStatusOrderByCreatedAtDesc
│    │       │  │      │       │        │
│    │       │  │      │       │        └─ Direction: Desc
│    │       │  │      │       └────────── OrderBy property: CreatedAt
│    │       │  │      └────────────────── Criteria property: Status
│    │       │  └───────────────────────── Keyword: By
│    │       └──────────────────────────── Projection: Distinct
│    └──────────────────────────────────── Prefix: find

countByFirmIdAndStatus
│     │ │      │   │
│     │ │      │   └─ Property: Status
│     │ │      └───── Operator: And
│     │ └──────────── Property: FirmId
│     └────────────── Keyword: By
└──────────────────── Prefix: count
```

---

## Supported Query Prefixes

### Query Operations

| Prefix | Purpose | Return Type |
|--------|---------|-------------|
| `find` | Find entities | Entity, List, Optional, Stream, Page, Slice |
| `get` | Alias for find | Same as find |
| `query` | Alias for find | Same as find |
| `retrieve` | Alias for find | Same as find |
| `read` | Alias for find | Same as find |
| `search` | Alias for find | Same as find |

**Examples**:
```java
List<EmailInboxItem> findByStatus(Status status);
Optional<EmailInboxItem> getById(Long id);
Stream<EmailInboxItem> searchByFirmId(Long firmId);
```

### Count Operations

| Prefix | Purpose | Return Type |
|--------|---------|-------------|
| `count` | Count matching entities | long, Long, int, Integer |

**Examples**:
```java
long countByFirmId(Long firmId);
Long countByStatusAndFirmId(Status status, Long firmId);
```

### Existence Checks

| Prefix | Purpose | Return Type |
|--------|---------|-------------|
| `exists` | Check if entities exist | boolean, Boolean |

**Examples**:
```java
boolean existsByFirmId(Long firmId);
Boolean existsByStatusAndFirmId(Status status, Long firmId);
```

### Delete Operations

| Prefix | Purpose | Return Type |
|--------|---------|-------------|
| `delete` | Delete entities | void, long, Long, int, Integer |
| `remove` | Alias for delete | Same as delete |
| `erase` | Alias for delete | Same as delete |
| `eliminate` | Alias for delete | Same as delete |

**Examples**:
```java
void deleteByFirmId(Long firmId);
long removeByStatus(Status status);  // Returns count of deleted
```

### Update Operations

| Prefix | Purpose | Return Type |
|--------|---------|-------------|
| `update` | Update entities | void, long, Long, int, Integer |

**Note**: Update methods require `@Query` annotation or method parameters matching entity properties.

**Examples**:
```java
@Query("UPDATE EmailInboxItem e SET e.status = :status WHERE e.id = :id")
void updateStatus(Long id, Status status);
```

---

## Supported Expressions

### Comparison Expressions

| Expression | SQL Equivalent | Applicable Types | Example |
|-----------|---------------|------------------|---------|
| `GreaterThan` | `>` | Numeric, Date, Comparable | `findByCreatedAtGreaterThan(LocalDateTime date)` |
| `GreaterThanEquals` | `>=` | Numeric, Date, Comparable | `findByPagesGreaterThanEquals(int pages)` |
| `LessThan` | `<` | Numeric, Date, Comparable | `findByCreatedAtLessThan(LocalDateTime date)` |
| `LessThanEquals` | `<=` | Numeric, Date, Comparable | `findByPagesLessThanEquals(int pages)` |
| `Between` | `BETWEEN` | Numeric, Date, Comparable | `findByCreatedAtBetween(LocalDateTime start, LocalDateTime end)` |

**Parameter Requirements**:
- `Between` requires **2 parameters** (start and end values)

### String Expressions

| Expression | SQL Equivalent | Case-Sensitive | Example |
|-----------|---------------|----------------|---------|
| `Like` | `LIKE` | Yes | `findByRawEmailLike(String pattern)` |
| `Ilike` | `ILIKE` | No | `findByRawEmailIlike(String pattern)` |
| `Contains` | `LIKE %value%` | Yes | `findByRawEmailContains(String text)` |
| `StartsWith` | `LIKE value%` | Yes | `findByRawEmailStartsWith(String prefix)` |
| `StartingWith` | `LIKE value%` | Yes | `findByRawEmailStartingWith(String prefix)` |
| `EndsWith` | `LIKE %value` | Yes | `findByRawEmailEndsWith(String suffix)` |
| `EndingWith` | `LIKE %value` | Yes | `findByRawEmailEndingWith(String suffix)` |

**Notes**:
- Pattern wildcards for `Like` must be included in parameter: `"%pattern%"`
- `Contains`, `StartsWith`, `EndsWith` add wildcards automatically
- Only applicable to String properties

### Null Expressions

| Expression | SQL Equivalent | Example |
|-----------|---------------|---------|
| `IsNull` | `IS NULL` | `findByProcessedAtIsNull()` |
| `IsNotNull` | `IS NOT NULL` | `findByProcessedAtIsNotNull()` |

**Parameter Requirements**:
- No parameters required (checks for null/not null)

### Boolean Expressions

| Expression | SQL Equivalent | Example |
|-----------|---------------|---------|
| `True` | `= true` | `findByActiveTrue()` |
| `False` | `= false` | `findByActiveFalse()` |

**Applicable Types**:
- Only boolean/Boolean properties

### Collection Expressions

| Expression | SQL Equivalent | Example |
|-----------|---------------|---------|
| `InList` | `IN (...)` | `findByStatusInList(List<Status> statuses)` |
| `In` | `IN (...)` | `findByStatusIn(List<Status> statuses)` |
| `NotInList` | `NOT IN (...)` | `findByStatusNotInList(List<Status> statuses)` |
| `NotIn` | `NOT IN (...)` | `findByStatusNotIn(List<Status> statuses)` |

**Parameter Requirements**:
- Parameter must be `List`, `Collection`, `Iterable`, or array

### Negation

All expressions can be negated by prefixing with `Not`:

| Original | Negated | SQL Equivalent |
|---------|---------|---------------|
| `GreaterThan` | `NotGreaterThan` | `NOT >` or `<=` |
| `Like` | `NotLike` | `NOT LIKE` |
| `Contains` | `NotContains` | `NOT LIKE %value%` |
| `InList` | `NotInList` | `NOT IN (...)` |

**Examples**:
```java
List<EmailInboxItem> findByStatusNotInList(List<Status> excludedStatuses);
List<EmailInboxItem> findByRawEmailNotContains(String text);
```

---

## Logical Operators

### And Operator

Combines criteria with logical AND (all must match):

```java
List<EmailInboxItem> findByFirmIdAndStatus(Long firmId, Status status);
// SQL: WHERE firm_id = ? AND status = ?
```

### Or Operator

Combines criteria with logical OR (any must match):

```java
List<EmailInboxItem> findByStatusOrFirmId(Status status, Long firmId);
// SQL: WHERE status = ? OR firm_id = ?
```

### Combining And/Or

```java
// (status = ? AND firmId = ?) OR rawEmail LIKE ?
List<EmailInboxItem> findByStatusAndFirmIdOrRawEmailLike(
    Status status,
    Long firmId,
    String pattern
);
```

**Note**: For complex logical expressions, use `@Query` for clarity:
```java
@Query("SELECT e FROM EmailInboxItem e WHERE (e.status = :status OR e.firmId = :firmId) AND e.rawEmail LIKE :pattern")
List<EmailInboxItem> findByComplexCriteria(Status status, Long firmId, String pattern);
```

---

## Projection Expressions

### Distinct

Remove duplicate results:

```java
List<String> findDistinctStatusByFirmId(Long firmId);
// Returns unique status values for firmId
```

### Top/First

Limit number of results:

```java
List<EmailInboxItem> findTop10ByOrderByCreatedAtDesc();
List<EmailInboxItem> findFirst5ByFirmIdOrderByCreatedAtDesc(Long firmId);
EmailInboxItem findFirstByFirmIdOrderByCreatedAtDesc(Long firmId);
Optional<EmailInboxItem> findFirstByStatus(Status status);
```

**Notes**:
- `Top` and `First` are aliases
- Number is optional: `findFirst()` returns 1 result
- Return single entity or List
- Use `Optional` if result might not exist

### Aggregations

| Expression | SQL Function | Return Type | Example |
|-----------|-------------|-------------|---------|
| `Count` | `COUNT(*)` | long, Long | `countByFirmId(Long firmId)` |
| `CountDistinct` | `COUNT(DISTINCT ...)` | long, Long | `countDistinctStatusByFirmId(Long firmId)` |
| `Max` | `MAX(...)` | Property type | `findMaxIdByFirmId(Long firmId)` |
| `Min` | `MIN(...)` | Property type | `findMinIdByFirmId(Long firmId)` |
| `Sum` | `SUM(...)` | Numeric | `findSumAmountByFirmId(Long firmId)` |
| `Avg` | `AVG(...)` | Double | `findAvgAmountByFirmId(Long firmId)` |

**Examples**:
```java
Long findMaxIdByFirmId(Long firmId);
Integer findSumPagesBy();
Double findAvgPagesByAuthor(String author);
```

---

## Nested Property Access

Access properties through associations using underscore (`_`) notation:

### Syntax

```
findBy[Association]_[Property]
```

### Examples

**Entity structure**:
```java
@Entity
public class EmailInboxItem {
    @ManyToOne
    private Firm firm;  // Firm has: id, name, externalId
}
```

**Repository methods**:
```java
// Access firm.id
List<EmailInboxItem> findByFirm_Id(Long firmId);

// Access firm.name
List<EmailInboxItem> findByFirm_Name(String firmName);

// Access firm.name with expression
List<EmailInboxItem> findByFirm_NameLike(String pattern);

// Multiple levels (if Firm had address.city)
List<EmailInboxItem> findByFirm_Address_City(String city);
```

### Alternative: Direct Property Name

If entity has direct property (e.g., `firmId` column):
```java
// If EmailInboxItem has firmId property
List<EmailInboxItem> findByFirmId(Long firmId);

// Both work if both exist, but access different things:
findByFirmId(Long id)        // Direct property: firmId column
findByFirm_Id(Long id)       // Nested property: firm.id
```

---

## Ordering

### Simple Ordering

```java
List<EmailInboxItem> findByStatusOrderByCreatedAtDesc(Status status);
List<EmailInboxItem> findByStatusOrderByCreatedAtAsc(Status status);
```

### Multiple Properties

```java
// Order by status ASC, then createdAt DESC
List<EmailInboxItem> findByFirmIdOrderByStatusAscCreatedAtDesc(Long firmId);
```

### Nested Property Ordering

```java
List<EmailInboxItem> findByStatusOrderByFirm_NameAsc(Status status);
```

### Dynamic Ordering with Sort

```java
import io.micronaut.data.model.Sort;

List<EmailInboxItem> findByStatus(Status status, Sort sort);

// Usage:
repository.findByStatus(Status.PENDING, Sort.of(Sort.Order.desc("createdAt")));
```

---

## Return Types

### Single Results

| Return Type | Behavior if Not Found | Behavior if Multiple Found |
|-------------|----------------------|---------------------------|
| `Entity` | Exception | Returns first or exception (implementation-dependent) |
| `Optional<Entity>` | Empty Optional | Returns first wrapped in Optional |

**Examples**:
```java
EmailInboxItem findById(Long id);  // Exception if not found
Optional<EmailInboxItem> findByFirmId(Long firmId);  // Empty if not found
```

### Multiple Results

| Return Type | Description |
|-------------|-------------|
| `List<Entity>` | Standard list of results |
| `Stream<Entity>` | Lazy stream of results |
| `Iterable<Entity>` | Generic iterable |
| `Set<Entity>` | Unique results |

**Examples**:
```java
List<EmailInboxItem> findByStatus(Status status);
Stream<EmailInboxItem> streamByFirmId(Long firmId);
```

### Pagination

| Return Type | Description |
|-------------|-------------|
| `Page<Entity>` | Paginated results with total count |
| `Slice<Entity>` | Paginated results without total count (faster) |

**Requirements**:
- Method must have `Pageable` parameter
- `Page` executes count query (slower but provides total)
- `Slice` skips count query (faster)

**Examples**:
```java
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;
import io.micronaut.data.model.Slice;

Page<EmailInboxItem> findByStatus(Status status, Pageable pageable);
Slice<EmailInboxItem> findByFirmId(Long firmId, Pageable pageable);

// Usage:
Pageable pageable = Pageable.from(0, 20);  // Page 0, size 20
Page<EmailInboxItem> page = repository.findByStatus(Status.PENDING, pageable);
```

### Primitive Types

| Return Type | Use Case |
|-------------|----------|
| `long` / `Long` | Count operations |
| `int` / `Integer` | Count operations, update/delete counts |
| `boolean` / `Boolean` | Existence checks |

**Examples**:
```java
long countByFirmId(Long firmId);
boolean existsByFirmId(Long firmId);
int deleteByStatus(Status status);
```

### Aggregation Return Types

```java
Long findMaxIdByFirmId(Long firmId);
Integer findMinPagesBy();
Double findAvgPagesBy();
BigDecimal findSumAmountBy();
```

---

## Common Anti-Patterns

### Anti-Pattern 1: Spring Data Syntax

**Problem**: Micronaut Data doesn't support all Spring Data expressions

| Spring Data | Micronaut Data | Notes |
|------------|---------------|-------|
| `Before` | `LessThan` | Different expression names |
| `After` | `GreaterThan` | Different expression names |
| `Equals` | (omit) | Equality is default, no expression needed |

**Wrong**:
```java
List<EmailInboxItem> findByCreatedBefore(LocalDateTime date);
List<EmailInboxItem> findByCreatedAfter(LocalDateTime date);
List<EmailInboxItem> findByNameEquals(String name);
```

**Correct**:
```java
List<EmailInboxItem> findByCreatedAtLessThan(LocalDateTime date);
List<EmailInboxItem> findByCreatedAtGreaterThan(LocalDateTime date);
List<EmailInboxItem> findByName(String name);  // No 'Equals' needed
```

### Anti-Pattern 2: Case Sensitivity

**Problem**: Property names are case-sensitive and must match entity exactly

**Wrong**:
```java
// Entity has 'firmId' not 'FirmID'
List<EmailInboxItem> findByFirmID(Long id);

// Entity has 'rawEmail' not 'RawEMail'
List<EmailInboxItem> findByRawEMail(String email);
```

**Correct**:
```java
List<EmailInboxItem> findByFirmId(Long id);
List<EmailInboxItem> findByRawEmail(String email);
```

### Anti-Pattern 3: Missing Parameters

**Problem**: Expressions have parameter requirements

**Wrong**:
```java
// Between needs 2 parameters
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start);

// InList needs collection parameter
List<EmailInboxItem> findByStatusInList();
```

**Correct**:
```java
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);
List<EmailInboxItem> findByStatusInList(List<Status> statuses);
```

### Anti-Pattern 4: Type Mismatches

**Problem**: Expressions must match property types

**Wrong**:
```java
// Like only works with String
List<EmailInboxItem> findByIdLike(Long id);

// Between doesn't work well with boolean
List<EmailInboxItem> findByActiveBetween(boolean start, boolean end);
```

**Correct**:
```java
List<EmailInboxItem> findById(Long id);
List<EmailInboxItem> findByActiveTrue();
```

### Anti-Pattern 5: Over-Complex Method Names

**Problem**: Readability suffers with 4+ criteria

**Wrong** (valid but hard to read):
```java
List<EmailInboxItem> findByStatusAndFirmIdAndCreatedAtBetweenAndRawEmailLikeOrderByCreatedAtDesc(
    Status status,
    Long firmId,
    LocalDateTime start,
    LocalDateTime end,
    String pattern
);
```

**Correct** (use @Query):
```java
@Query("SELECT e FROM EmailInboxItem e WHERE e.status = :status " +
       "AND e.firmId = :firmId " +
       "AND e.createdAt BETWEEN :start AND :end " +
       "AND e.rawEmail LIKE :pattern " +
       "ORDER BY e.createdAt DESC")
List<EmailInboxItem> findByComplexCriteria(
    Status status,
    Long firmId,
    LocalDateTime start,
    LocalDateTime end,
    String pattern
);
```

### Anti-Pattern 6: Wrong Return Types

**Problem**: Return type doesn't match operation

**Wrong**:
```java
// Count should return numeric, not List
List<EmailInboxItem> countByFirmId(Long firmId);

// Exists should return boolean, not List
List<EmailInboxItem> existsByFirmId(Long firmId);

// Page requires Pageable parameter
Page<EmailInboxItem> findByStatus(Status status);
```

**Correct**:
```java
long countByFirmId(Long firmId);
boolean existsByFirmId(Long firmId);
Page<EmailInboxItem> findByStatus(Status status, Pageable pageable);
```

### Anti-Pattern 7: @Transactional on Repository

**Problem**: Transaction boundaries belong in service layer

**Wrong**:
```java
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    @Transactional  // ❌ Wrong layer
    List<EmailInboxItem> findByFirmId(Long firmId);
}
```

**Correct**:
```java
// Repository (no @Transactional)
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    List<EmailInboxItem> findByFirmId(Long firmId);
}

// Service (with @Transactional)
@Singleton
public class EmailProcessingService {
    private final EmailInboxItemRepository repository;

    @Transactional
    public void processEmails(Long firmId) {
        List<EmailInboxItem> items = repository.findByFirmId(firmId);
        // Business logic...
    }
}
```

---

## Validation Commands

### Find All Repository Files
```bash
find src/main/java -name "*Repository.java"
```

### Find Entity Classes
```bash
find src/main/java -name "*.java" -path "*/entities/*"
```

### Check for External Library Entities
```bash
# Find library JAR
find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"

# Inspect entity
javap -public -cp ~/.gradle/caches/.../data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
```

### Search for Potential Spring Data Syntax
```bash
# Look for 'Before' or 'After' (Spring Data syntax)
grep -r "findBy.*Before\|findBy.*After" src/main/java

# Look for 'Equals' (unnecessary in Micronaut Data)
grep -r "findBy.*Equals" src/main/java
```

---

## Compilation Error Messages

### Common Errors and Solutions

**Error**: `Unable to implement Repository method`
- **Cause**: Invalid method name, unsupported expression, or property mismatch
- **Solution**: Validate method name follows Micronaut Data conventions

**Error**: `Cannot query entity [Entity] on non-existent property [property]`
- **Cause**: Property name doesn't exist on entity or case mismatch
- **Solution**: Verify property name matches entity exactly (case-sensitive)

**Error**: `Method [method] requires [N] arguments but found [M]`
- **Cause**: Parameter count doesn't match criteria count
- **Solution**: Ensure each criterion in method name has corresponding parameter

**Error**: `Type mismatch: cannot convert from [Type1] to [Type2]`
- **Cause**: Parameter type doesn't match property type
- **Solution**: Verify parameter types match entity property types

---

## Best Practices

1. **Keep Method Names Readable**: Use `@Query` for 4+ criteria
2. **Match Property Names Exactly**: Case-sensitive, include 'At' suffixes (`createdAt` not `created`)
3. **Use Micronaut Data Expressions**: Not Spring Data equivalents
4. **Validate Property Existence**: Check entity before creating methods
5. **Use Optional for Nullable Results**: Single results that might not exist
6. **Use Appropriate Return Types**: Match operation (count → long, exists → boolean)
7. **Place @Transactional in Service**: Not on repository methods
8. **Prefer Explicit Over Implicit**: `findByStatusIsNull()` clearer than `findByStatus(null)`
9. **Use Nested Property Notation**: `firm_id` for associations
10. **Test After Creation**: Compile immediately to catch errors early

---

## Additional Resources

- [Micronaut Data JPA](https://micronaut-projects.github.io/micronaut-data/latest/guide/#sql)
- [Query Methods](https://micronaut-projects.github.io/micronaut-data/latest/guide/#querying)
- [Custom Queries with @Query](https://micronaut-projects.github.io/micronaut-data/latest/guide/#jdbcQueries)
- [Pagination and Sorting](https://micronaut-projects.github.io/micronaut-data/latest/guide/#pagination)
- [DTO Projections](https://micronaut-projects.github.io/micronaut-data/latest/guide/#dto)
