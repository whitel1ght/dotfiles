# Repository Patterns Module

**Purpose**: Micronaut Data JPA repository patterns with real database testing

**When to Use**: Building data access layer components (repositories)

**Dependencies**: Loaded by `tdd-micronaut.md` base agent when repository work is detected

---

## JpaRepository Extension Pattern

**Core Pattern**: All repositories extend `JpaRepository<Entity, IdType>` interface.

```java
package com.goecfx.repositories;

import com.goecfx.data.entities.EmailInboxItem;
import io.micronaut.data.annotation.Repository;
import io.micronaut.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for EmailInboxItem persistence operations.
 *
 * Extends JpaRepository to inherit standard CRUD methods:
 * - save(entity), saveAll(entities)
 * - findById(id), findAll()
 * - deleteById(id), delete(entity)
 * - count(), existsById(id)
 */
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {

    /**
     * Finds inbox items by firm ID.
     * Micronaut Data generates implementation from method name.
     */
    List<EmailInboxItem> findByFirmId(Integer firmId);

    /**
     * Finds single inbox item by firm and email ID.
     * Returns Optional for null-safe handling.
     */
    Optional<EmailInboxItem> findByFirmIdAndEmailId(Integer firmId, String emailId);
}
```

**Key Points**:
- **Interface only** - Micronaut Data generates implementation
- **`@Repository` annotation** - Enables repository scanning
- **Generic parameters**: `JpaRepository<Entity, IdType>` where IdType is the primary key type
- **Methods are declarations** - no implementation needed for standard patterns

---

## Query Method Naming Conventions

Micronaut Data auto-generates query implementations from method names following specific patterns.

### Pattern: find{Property}

**Generates**: `SELECT * FROM table WHERE property = ?`

```java
// Single property
List<User> findByEmail(String email);
// SQL: SELECT * FROM user WHERE email = ?

// Multiple properties (AND)
List<Case> findByFirmIdAndStatus(Integer firmId, String status);
// SQL: SELECT * FROM case WHERE firm_id = ? AND status = ?

// Optional result (single or none)
Optional<Firm> findBySubdomain(String subdomain);
// SQL: SELECT * FROM firm WHERE subdomain = ? LIMIT 1
```

### Pattern: find{Property}OrderBy{Property}

**Generates**: Query with `ORDER BY` clause

```java
List<User> findByFirmIdOrderByCreatedAtDesc(Integer firmId);
// SQL: SELECT * FROM user WHERE firm_id = ? ORDER BY created_at DESC
```

### Pattern: find{Property}Before/After

**Generates**: Temporal comparison queries

```java
import java.time.LocalDateTime;

List<Event> findByCreatedAtBefore(LocalDateTime cutoff);
// SQL: SELECT * FROM event WHERE created_at < ?

List<Event> findByCreatedAtAfter(LocalDateTime start);
// SQL: SELECT * FROM event WHERE created_at > ?
```

### Pattern: find{Property}Like

**Generates**: `LIKE` query for partial matching

```java
List<User> findByNameLike(String pattern);
// Usage: repository.findByNameLike("%smith%")
// SQL: SELECT * FROM user WHERE name LIKE ?
```

### Pattern: count{Property}

**Generates**: `COUNT(*)` query

```java
long countByFirmId(Integer firmId);
// SQL: SELECT COUNT(*) FROM table WHERE firm_id = ?
```

### Pattern: exists{Property}

**Generates**: Boolean existence check

```java
boolean existsByEmail(String email);
// SQL: SELECT EXISTS(SELECT 1 FROM table WHERE email = ?)
```

**Complete Reference**:
- `findBy...` - SELECT query
- `countBy...` - COUNT query
- `existsBy...` - EXISTS check
- `deleteBy...` - DELETE query
- `And` - Logical AND
- `Or` - Logical OR
- `Like` - Pattern matching
- `Between` - Range query
- `LessThan`, `GreaterThan` - Comparison
- `Before`, `After` - Temporal comparison
- `OrderBy` - Sorting
- `Asc`, `Desc` - Sort direction

---

## Pagination Support

**Pattern**: Return `Page<Entity>` and accept `Pageable` parameter.

```java
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;

@Repository
public interface FirmRepository extends JpaRepository<Firm, Integer> {

    /**
     * Finds firms with pagination support.
     *
     * @param active Filter by active status
     * @param pageable Pagination parameters (page, size, sort)
     * @return Page of results with metadata (total count, page number, etc.)
     */
    Page<Firm> findByActive(Boolean active, Pageable pageable);
}
```

**Usage**:
```java
// In service or test
import io.micronaut.data.model.Pageable;
import io.micronaut.data.model.Sort;

// Page 0, size 20, sort by name ascending
Pageable pageable = Pageable.from(0, 20, Sort.of(Sort.Order.asc("name")));
Page<Firm> page = repository.findByActive(true, pageable);

// Access results
List<Firm> firms = page.getContent();
long totalCount = page.getTotalSize();
int totalPages = page.getTotalPages();
boolean hasNext = page.hasNext();
```

**Benefits**:
- Efficient for large datasets (only loads requested page)
- Includes total count without separate query
- Supports sorting on any field
- Standard pattern across all repositories

---

## SchemaLoader Setup

**Pattern**: Load schema once before all tests using `@Shared` flag.

```groovy
package com.goecfx.repositories

import com.goecfx.data.infrastructure.SchemaLoader
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Shared
import spock.lang.Specification

import javax.sql.DataSource

@MicronautTest
class FirmRepositorySpec extends Specification {

    @Inject
    FirmRepository repository

    @Inject
    @Shared
    DataSource dataSource

    @Shared
    static boolean schemaLoaded = false

    def setup() {
        if (!schemaLoaded) {
            // Load PostgreSQL schema from file
            def schemaFile = new File("src/test/resources/db/schema.sql")
            SchemaLoader.loadSchema(dataSource, schemaFile)
            schemaLoaded = true
        }
    }

    void "test repository method"() {
        // Test implementation
    }
}
```

**Key Points**:
- **`@Shared static boolean`**: Ensures schema loads once per test class
- **SchemaLoader**: Utility class that executes SQL file against datasource
- **File location**: `src/test/resources/db/schema.sql` or `schema-minimal.sql`
- **Thread-safe**: Works with parallel test execution

**Cross-Reference**: For schema file structure and entity setup, see `entity-patterns.md` section "Testing Patterns".

---

## Real Database Testing Approach

**Core Principle**: Repository tests use **real PostgreSQL via TestContainers**, NOT mocks.

**Why Real Database**:
- Tests actual query generation by Micronaut Data
- Catches SQL syntax errors
- Validates schema compatibility
- Tests database constraints (FK, unique, NOT NULL)
- Provides confidence in production behavior

**TestResources Configuration**:
See `tdd-micronaut.md` section "TestResources Configuration" for three-file setup. Key point: TestResources auto-provisions PostgreSQL TestContainer when connection values are missing.

**Test Pattern**:
```groovy
@MicronautTest
class FirmRepositorySpec extends Specification {

    @Inject
    FirmRepository repository

    // ... schema loading setup ...

    void "finds firm by subdomain"() {
        given: "a firm exists in database"
        def firm = new Firm()
        firm.name = "Test Firm"
        firm.subdomain = "test-firm-" + UUID.randomUUID().toString().substring(0, 8)
        firm.encryptionKeyId = UUID.randomUUID()
        repository.save(firm)

        when: "querying by subdomain"
        def result = repository.findBySubdomain(firm.subdomain)

        then: "firm is found"
        result.present
        result.get().name == "Test Firm"
    }

    void "returns empty when firm not found"() {
        when: "querying for non-existent subdomain"
        def result = repository.findBySubdomain("does-not-exist")

        then: "returns empty Optional"
        !result.present
    }
}
```

---

## Relationship Testing

**Pattern**: Test `@ManyToOne` and `@OneToMany` relationships with real foreign keys.

### Testing @ManyToOne (Entity References Parent)

```groovy
void "finds inbox items by firm ID"() {
    given: "a firm exists"
    def firm = new Firm(name: "Test Firm", subdomain: "test", encryptionKeyId: UUID.randomUUID())
    def savedFirm = firmRepository.save(firm)

    and: "inbox items belong to that firm"
    def item1 = new EmailInboxItem(firmId: savedFirm.id, emailId: "email1")
    def item2 = new EmailInboxItem(firmId: savedFirm.id, emailId: "email2")
    inboxRepository.saveAll([item1, item2])

    when: "querying by firm ID"
    def results = inboxRepository.findByFirmId(savedFirm.id)

    then: "both items returned"
    results.size() == 2
    results.every { it.firmId == savedFirm.id }
}
```

### Testing Foreign Key Constraints

```groovy
void "enforces foreign key constraint"() {
    given: "inbox item with non-existent firm ID"
    def item = new EmailInboxItem(firmId: 99999, emailId: "test")

    when: "attempting to save"
    inboxRepository.save(item)

    then: "FK violation thrown"
    thrown(Exception)  // Specific exception depends on DB
}
```

---

## Optional<T> Return Types

**Pattern**: Use `Optional<T>` for query methods that may return zero or one result.

```java
@Repository
public interface FirmRepository extends JpaRepository<Firm, Integer> {

    /**
     * Finds firm by subdomain (unique constraint).
     * Returns Optional because subdomain may not exist.
     */
    Optional<Firm> findBySubdomain(String subdomain);

    /**
     * Finds firm by ID.
     * Returns Optional because ID may not exist.
     *
     * Note: findById() is inherited from JpaRepository and already returns Optional<Firm>.
     */
}
```

**Usage in Tests**:
```groovy
void "handles missing entity with Optional"() {
    when:
    def result = repository.findBySubdomain("does-not-exist")

    then:
    !result.present  // Cleaner than null check

    when: "accessing value safely"
    def firm = result.orElse(null)

    then:
    firm == null
}

void "unwraps Optional when present"() {
    given:
    def saved = repository.save(new Firm(...))

    when:
    def result = repository.findById(saved.id)

    then:
    result.present
    result.get().id == saved.id
}
```

**Benefits**:
- Forces explicit null handling
- Clearer API (presence vs absence)
- Prevents NullPointerException

---

## Repository Test Template

Complete test template for repository testing:

```groovy
package com.goecfx.repositories

import com.goecfx.data.entities.Firm
import com.goecfx.data.infrastructure.SchemaLoader
import io.micronaut.data.model.Pageable
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Shared
import spock.lang.Specification

import javax.sql.DataSource

/**
 * Test specification for {Repository} with real database integration.
 * Uses TestContainers PostgreSQL provisioned by Micronaut TestResources.
 */
@MicronautTest
class {Repository}Spec extends Specification {

    @Inject
    {Repository} repository

    @Inject
    @Shared
    DataSource dataSource

    @Shared
    static boolean schemaLoaded = false

    def setup() {
        if (!schemaLoaded) {
            def schemaFile = new File("src/test/resources/db/schema.sql")
            SchemaLoader.loadSchema(dataSource, schemaFile)
            schemaLoaded = true
        }
    }

    void "saves and retrieves entity"() {
        given: "a new entity"
        def entity = new Entity(...)

        when: "saving entity"
        def saved = repository.save(entity)

        then: "entity has ID assigned"
        saved.id != null

        when: "retrieving by ID"
        def retrieved = repository.findById(saved.id)

        then: "entity is found"
        retrieved.present
        retrieved.get().id == saved.id
    }

    void "finds entities by property"() {
        given: "entities exist"
        repository.saveAll([entity1, entity2])

        when: "querying by property"
        def results = repository.findByProperty(value)

        then: "matching entities returned"
        results.size() == expectedCount
    }

    void "returns empty when not found"() {
        when: "querying for non-existent entity"
        def result = repository.findByProperty(nonExistentValue)

        then: "returns empty result"
        result.isEmpty()  // For List
        // OR
        !result.present   // For Optional
    }

    void "supports pagination"() {
        given: "multiple entities exist"
        repository.saveAll([...])

        when: "querying first page"
        def page = repository.findAll(Pageable.from(0, 10))

        then: "page contains results"
        page.content.size() <= 10
        page.totalSize >= 0
    }

    void "handles relationships correctly"() {
        given: "parent and child entities"
        def parent = parentRepository.save(new Parent(...))
        def child = new Child(parentId: parent.id)

        when: "saving child"
        def saved = repository.save(child)

        then: "relationship maintained"
        saved.parentId == parent.id
    }
}
```

---

## Common Patterns

### Batch Operations

```java
// Save multiple entities efficiently
List<Entity> entities = List.of(entity1, entity2, entity3);
repository.saveAll(entities);  // Single transaction

// Delete multiple entities
repository.deleteAll(entities);
```

### Custom Queries (When Naming Convention Isn't Enough)

```java
import io.micronaut.data.annotation.Query;

@Repository
public interface FirmRepository extends JpaRepository<Firm, Integer> {

    /**
     * Custom JPQL query for complex logic.
     */
    @Query("SELECT f FROM Firm f WHERE f.active = true AND f.createdAt > :cutoff")
    List<Firm> findRecentActiveFirms(LocalDateTime cutoff);

    /**
     * Native SQL query for PostgreSQL-specific features.
     */
    @Query(value = "SELECT * FROM private.firm WHERE metadata @> :json::jsonb",
           nativeQuery = true)
    List<Firm> findByJsonbContains(String json);
}
```

**Use Custom Queries When**:
- Query method name becomes too complex
- Need PostgreSQL-specific features (JSONB operators, full-text search)
- Performance optimization requires specific SQL

---

## Cross-References

**To Base Agent**:
- For TDD workflow, see `tdd-micronaut.md` section "The Sacred TDD Cycle"
- For TestResources setup, see `tdd-micronaut.md` section "TestResources Configuration"

**To Entity Module**:
- For entity structure and field mappings, see `entity-patterns.md` section "Entity Template"
- For SchemaLoader details, see `entity-patterns.md` section "Testing Patterns"

**From Other Modules**:
- `service-patterns.md` will mock these repositories in service tests
- `controller-patterns.md` uses repositories indirectly through services

---

**Key Takeaway**: Repositories are interfaces, Micronaut Data generates implementations. Test against real database, not mocks.
