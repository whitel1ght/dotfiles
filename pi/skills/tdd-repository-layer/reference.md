# Repository Layer Reference

## External Documentation

- [Micronaut Data JPA Repositories](https://micronaut-projects.github.io/micronaut-data/latest/guide/#dbc-repositories) — Repository interface patterns
- [Micronaut Data Query Methods](https://micronaut-projects.github.io/micronaut-data/latest/guide/#querying) — Query derivation conventions
- [Micronaut TestResources](https://micronaut-projects.github.io/micronaut-test-resources/latest/guide/) — Auto-provisioned test containers

## Query Derivation Keywords

| Keyword | SQL Equivalent |
|---------|---------------|
| `findBy` | `SELECT ... WHERE` |
| `countBy` | `SELECT COUNT(*) WHERE` |
| `existsBy` | `SELECT EXISTS(...)` |
| `deleteBy` | `DELETE WHERE` |
| `And` | `AND` |
| `Or` | `OR` |
| `Like` | `LIKE` |
| `Between` | `BETWEEN ... AND ...` |
| `LessThan` / `GreaterThan` | `<` / `>` |
| `LessThanEquals` / `GreaterThanEquals` | `<=` / `>=` |
| `Before` / `After` | `<` / `>` (temporal) |
| `IsNull` / `IsNotNull` | `IS NULL` / `IS NOT NULL` |
| `In` | `IN (...)` |
| `OrderBy...Asc` / `...Desc` | `ORDER BY ... ASC/DESC` |

## Supported Return Types

| Return Type | Use Case |
|-------------|----------|
| `List<T>` | Multiple results |
| `Optional<T>` | Zero or one result |
| `Page<T>` | Paginated results (with `Pageable` param) |
| `Slice<T>` | Paginated without total count |
| `long` | Count queries |
| `boolean` | Existence checks |
| `void` | Delete operations |

## Version Notes

| Component | Version |
|-----------|---------|
| Micronaut Data | 4.x |
| JPA API | Jakarta Persistence 3.1 |
| TestResources | Matches Micronaut version |

## Repository Choice — Composite-PK and Read-Only

Composite-PK read-only repositories should extend `GenericRepository<E, IdType>`, NOT `JpaRepository`. `JpaRepository` requires a single-typed PK and exposes persistence methods you don't need for a lookup-only repo. Example: `ECFXProviderJurisdiction` uses `@IdClass` (composite PK) and only needs `findBySignature` — `GenericRepository<ECFXProviderJurisdiction, String>` is correct.

## Projections — JPQL vs Native

| Projection style | When it works |
|------------------|---------------|
| `@Introspected interface Projection { String getX(); }` + `@Query("SELECT x AS xField ...")` | NATIVE queries only. With JPQL it compiles but explodes at first call: `InstantiationException: No default constructor exists` (Micronaut's `BeanIntrospectionMapper` tries to instantiate the interface). |
| `@Introspected @Serdeable record Projection(String x, String y)` + `@Query("SELECT new fully.qualified.Record(x, y) FROM ...")` | Works for both JPQL and native. JPQL `SELECT new` calls the record's canonical constructor. **Default for new code.** |

## Cross-Entity Joins Without `@ManyToOne`

When two entities share a logical join key but are NOT linked by a JPA association, use JPQL theta-join syntax rather than inventing fake `@ManyToOne`:

```java
@Query("SELECT new com.x.CaseProvisioning(c.caseNumber, c.name) " +
       "FROM Case c, FirmJurisdictionMapping m " +
       "WHERE m.firmJurisdictionId = c.jurisdictionId " +
       "AND m.firmId = c.firmId AND c.firmId = :firmId")
List<CaseProvisioning> findProvisionable(Integer firmId);
```

## Bulk Update Cache Bypass

`@Query` bulk `UPDATE` bypasses the Hibernate first-level cache. Subsequent reads return stale data unless you call `entityManager.clear()` between the bulk update and the re-fetch. In tests:

```groovy
repository.bulkUpdateStatus(...)
entityManager.clear()    // mandatory — drop cached entities
def fresh = repository.findById(id)
```

## Transactional Rollback Characterization

`@MicronautTest` defaults to `transactional = true`, wrapping each test in an OUTER transaction that rolls back at method end. With `Propagation.REQUIRED`, an inner `@Transactional` (or `@TransactionalAdvice`) method JOINS the outer test tx instead of opening a new one. So when the inner method throws, it merely marks the outer tx rollback-only — a subsequent same-test-method read STILL sees the uncommitted insert (same tx, still visible). Rollback assertions silently pass on a false premise.

**Fix**: `@MicronautTest(transactional = false)` for any spec that asserts rollback behavior. The inner-method tx becomes the only tx, its rollback is real, and subsequent reads run in a fresh connection that sees post-rollback DB state. Foundational pattern for ALL transaction-boundary tests.

## Pagination Without COUNT — limit+1 Pattern

For repository methods that return paginated results without needing the true total, use the `limit + 1` pattern to eliminate the COUNT round-trip:

```java
query.setMaxResults(limit + 1);
List<T> dtos = query.getResultList();
boolean hasMore = dtos.size() > limit;
if (hasMore) { dtos = dtos.subList(0, limit); }
long approxCount = offset + dtos.size() + (hasMore ? limit : 0);
```

`PaginatedStream.hasNextPage()` only needs `hasMore`, not the exact total. Add `query.setHint("org.hibernate.timeout", 30)` as a safety net for long-running FTS queries. Verify COUNT elimination via Hibernate SQL output in test logs (look for absence of `Hibernate: SELECT count(*)`).

## Dynamic WHERE Filter Binding — Double Cast

When building dynamic WHERE clauses with mixed PostgreSQL column types (enums like `inbox_item_status`, booleans like `hidden`, varchars), cast BOTH the column AND the parameter to text:

```sql
cast(column as text) = cast(:filter_param as text)
```

Single-side casting (`cast(column as text) = :filter_param`) fails for booleans because the JDBC driver sends Java `boolean` as PostgreSQL `boolean` (not `text`), producing `operator does not exist: text = boolean`. Double-cast is type-agnostic across enums, booleans, and varchars. Prefix dynamic filter parameter names (e.g., `:filter_status`) to avoid collisions with existing named parameters.

## Query Timeout Hints

| Hint | Unit | Source |
|------|------|--------|
| `jakarta.persistence.query.timeout` | milliseconds | JPA-standard (Jakarta Persistence 3.1) |
| `org.hibernate.timeout` | seconds | Hibernate-specific |

Both work in Hibernate 6. Catch `jakarta.persistence.QueryTimeoutException` (extends `PersistenceException`) and log SLOW_QUERY context (firm_id, filter dimensions, offset, limit) before re-throwing. Extract timeout values to `private static final int QUERY_TIMEOUT_MS` constants.
