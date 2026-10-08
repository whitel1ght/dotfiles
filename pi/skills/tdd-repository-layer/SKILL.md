---
name: tdd-repository-layer
description: >-
  Micronaut Data JPA repository patterns with real database testing. Use when creating/modifying repository interfaces, query derivation, @Repository, JpaRepository, repositories/ directories, or when working with query methods, pagination, or database integration tests.
---


# TDD Repository Layer

Repository interfaces extend `JpaRepository<Entity, IdType>`. Micronaut Data generates implementations from method names. Test against real PostgreSQL via TestContainers, never mocks.

## Repository Template

```java
@Repository
public interface {EntityName}Repository extends JpaRepository<{EntityName}, UUID> {

    List<{EntityName}> findByFirmId(Integer firmId);

    Optional<{EntityName}> findByFirmIdAndEmailId(Integer firmId, String emailId);
}
```

## Query Derivation Reference

| Keyword | Example | Generated SQL |
|---------|---------|---------------|
| `findBy` | `findByEmail(String)` | `WHERE email = ?` |
| `And` | `findByFirmIdAndStatus(Integer, String)` | `WHERE firm_id = ? AND status = ?` |
| `Or` | `findByNameOrEmail(String, String)` | `WHERE name = ? OR email = ?` |
| `OrderBy...Desc` | `findByFirmIdOrderByCreatedAtDesc(Integer)` | `WHERE firm_id = ? ORDER BY created_at DESC` |
| `Before` / `After` | `findByCreatedAtBefore(LocalDateTime)` | `WHERE created_at < ?` |
| `Like` | `findByNameLike(String)` | `WHERE name LIKE ?` |
| `Between` | `findByAgeBetween(int, int)` | `WHERE age BETWEEN ? AND ?` |
| `LessThan` / `GreaterThan` | `findByAmountGreaterThan(BigDecimal)` | `WHERE amount > ?` |
| `countBy` | `countByFirmId(Integer)` | `SELECT COUNT(*) WHERE firm_id = ?` |
| `existsBy` | `existsByEmail(String)` | `SELECT EXISTS(... WHERE email = ?)` |
| `deleteBy` | `deleteByFirmId(Integer)` | `DELETE WHERE firm_id = ?` |

**Return types**: `List<T>`, `Optional<T>`, `Page<T>` (with `Pageable`), `long` (count), `boolean` (exists).

## Test Template

```groovy
@MicronautTest
class {EntityName}RepositorySpec extends Specification {

    @Inject {EntityName}Repository repository
    @Inject @Shared DataSource dataSource
    @Shared static boolean schemaLoaded = false

    def setup() {
        if (!schemaLoaded) {
            SchemaLoader.loadSchema(dataSource, new File("src/test/resources/db/schema.sql"))
            schemaLoaded = true
        }
    }

    void "saves and retrieves entity"() {
        given: "a new entity"
        def entity = new {EntityName}()
        entity.firmId = 1010

        when: "saving"
        def saved = repository.save(entity)

        then: "entity has ID"
        saved.id != null

        when: "retrieving"
        def retrieved = repository.findById(saved.id)

        then: "found"
        retrieved.present
        retrieved.get().id == saved.id
    }

    void "returns empty when not found"() {
        when:
        def result = repository.findById(UUID.randomUUID())

        then:
        !result.present
    }
}
```

## Custom Queries

Use `@Query` when method naming is insufficient:

```java
@Query("SELECT f FROM Firm f WHERE f.active = true AND f.createdAt > :cutoff")
List<Firm> findRecentActiveFirms(LocalDateTime cutoff);

@Query(value = "SELECT * FROM private.firm WHERE metadata @> :json::jsonb", nativeQuery = true)
List<Firm> findByJsonbContains(String json);
```

## NEVER DO THIS — Repository Test Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|-------------|---------------|-----------------|
| Writing a Spock spec without `@MicronautTest` for a `@Repository` | Cannot test query derivation, schema validation, or actual SQL execution | Always `@MicronautTest` with real database via TestContainers |
| Mocking the repository in repository tests | You're testing Micronaut Data's code generation — mocking it tests nothing | Real repository + real database. Mocking is for service tests mocking external deps |
| Testing repository behavior with `new Entity()` + manual field setting only | Proves entity construction, not persistence behavior | Persist via repository, then read back and assert |

## Common Pitfalls

| Error | Cause | Fix |
|-------|-------|-----|
| Query method not generating | Method name doesn't match conventions | Check property names match entity fields exactly |
| `No bean of type [Repository]` | Missing `@Repository` annotation | Add `@Repository` to interface |
| FK violation in test | Parent entity not inserted | Insert parent first with `ON CONFLICT DO NOTHING` |
| Flaky test data | Shared state between tests | Use unique values (e.g., `UUID.randomUUID()` in subdomains) |

## Related Skills

- **micronaut-data-repository** — Micronaut Data-specific patterns and conventions
- **test-resources-validator** — verify TestResources three-file configuration
- **spock-test-setup** — ensure test dependencies present
- **schema-drift-detector** — detect entity-schema drift
- **checkstyle-enforcer** — enforce code style

For verbose examples (pagination, batch ops, relationships, custom queries), see `examples.md`.
For external documentation links, see `reference.md`.
