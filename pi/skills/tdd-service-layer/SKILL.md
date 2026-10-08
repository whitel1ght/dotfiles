---
name: tdd-service-layer
description: >-
  Business logic service patterns with dependency injection and integration testing. Use when creating/modifying service classes, transaction issues, @Singleton, @Transactional, services/ directories, or when working with exception handling, input validation, or service-layer business logic.
---


# TDD Service Layer

Services contain business logic with constructor-injected dependencies. Test with `@MicronautTest` using **real repositories** backed by TestContainers PostgreSQL. Only mock external services (notifications, email APIs, third-party integrations) that are not database-backed.

## Why Integration Tests for Services

| Approach | Problem |
|----------|---------|
| Mocking repositories | Bypasses query derivation, hides SQL errors, doesn't test @Transactional boundaries, tests pass but production fails |
| Real DB (this approach) | Tests actual query execution, validates transaction commit/rollback, catches constraint violations, proves business logic works end-to-end |

**Rule**: If it touches the database, use the real thing. If it calls an external system, mock it.

## Service Template

```java
@Singleton
public class {ServiceName} {

    private final {Repository} repository;  // final = immutable

    public {ServiceName}({Repository} repository) {
        this.repository = repository;       // constructor injection
    }

    public Optional<{Entity}> findById(UUID id) {
        return repository.findById(id);     // no @Transactional for reads
    }

    @Transactional
    public {Entity} create(Integer firmId, String name) {
        var entity = new {Entity}();        // @Transactional for writes
        entity.setFirmId(firmId);
        entity.setName(name);
        return repository.save(entity);
    }
}
```

## @Transactional Rules

| Operation | @Transactional? | Reason |
|-----------|----------------|--------|
| `findBy...`, `get...` | No | Read-only, no transaction overhead |
| `save()`, `update()` | Yes | Needs atomic commit/rollback |
| Multi-entity writes | Yes | Atomicity across operations |
| Calls other services | No | Let called service manage its own |

**Anti-pattern**: `@Transactional` on class level — adds overhead to all reads.

## Test File Organization

- ALWAYS search for existing `{ServiceName}Spec.groovy` before creating a new file
- If found: ADD test cases to the existing spec — reuse its setup/cleanup/helpers
- If NOT found: CREATE `{ServiceName}Spec.groovy` — named after the class, not the behavior
- New behaviors/fixes = new test cases in the existing spec, NOT new spec files

## Test Template

### Standard Service Spec (most services)

Use default `transactional = true` for services that rely on the caller's transaction (controllers, other services). This covers **most** core_rest services.

```groovy
@MicronautTest(startApplication = false, packages = "com.goecfx.data")
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class {ServiceName}Spec extends Specification {

    @Inject {ServiceName} service
    @Inject DataSource dataSource
    @Inject EntityManager entityManager

    // Static constants — deterministic, unique per spec
    static final int TEST_FIRM_ID = {unique_id}

    def setup() {
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/db/schema.sql").toURI()))
        insertTestData()
    }

    def cleanup() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("DELETE FROM private.{table} WHERE firm_id = ${TEST_FIRM_ID}")
            conn.createStatement().execute("DELETE FROM private.firm WHERE id = ${TEST_FIRM_ID}")
        }
    }

    private void executeWithAutoCommit(Closure action) {
        def conn = dataSource.connection
        def originalAutoCommit = conn.autoCommit
        conn.autoCommit = true
        try { action(conn) }
        finally { conn.autoCommit = originalAutoCommit; conn.close() }
    }

    void "creates entity and persists to database"() {
        when: "calling service method"
        def result = service.create(TEST_FIRM_ID, "Test Entity")

        then: "entity is returned with generated ID"
        result != null
        result.id != null
    }
}
```

### When to use `transactional = false`

Only use `transactional = false` when the service under test has its **own `@Transactional`** methods:

| Service Type | `transactional` | Reason |
|-------------|----------------|--------|
| Most core_rest services | `true` (default) | Services rely on caller's transaction; `entityManager.find()` needs transaction context |
| Services with `@Transactional` methods | `false` | Service creates its own transaction; avoids deadlock with test transaction |
| Queue services (no `@Transactional`) | `false` + `TransactionOperations` | Mirrors consumer's transaction; see Queue Service Pattern below |

### S3 Service Spec (LocalStack TestResources)

For services using `S3Client` or `S3AsyncClient`, use real LocalStack S3 via TestResources — do NOT mock S3:

```groovy
@MicronautTest(startApplication = false, packages = "com.goecfx.data")
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class {S3ServiceName}Spec extends Specification {

    @Inject {S3ServiceName} service
    @Inject S3Client s3Client  // real — provisioned by LocalStack TestResources
    @Inject DataSource dataSource

    @Shared boolean bucketsCreated = false

    def setup() {
        if (!bucketsCreated) {
            try { s3Client.createBucket(CreateBucketRequest.builder().bucket("test-request-bucket").build()) } catch (Exception ignored) {}
            try { s3Client.createBucket(CreateBucketRequest.builder().bucket("test-response-bucket").build()) } catch (Exception ignored) {}
            bucketsCreated = true
        }
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/db/schema.sql").toURI()))
    }
}
```

**Requires** in `build.gradle`:
```gradle
testResourcesService("io.micronaut.testresources:micronaut-test-resources-localstack-s3")
```

**Requires** in `application-test.yml`:
```yaml
test-resources:
  containers:
    localstack:
      services: s3
aws:
  region: us-east-1
  services:
    s3:
```

**Tip**: Even if the service uses `S3AsyncClient`, inject the sync `S3Client` in the test for verification — both point to the same LocalStack instance.

## Queue Service Pattern (Services Called from @Transactional Consumers)

Some services have NO `@Transactional` on their methods — they rely on the caller (e.g., a RabbitMQ consumer's `@Transactional realHandle()`) to provide the transaction. Without an outer transaction, each repository call commits independently and in-memory entity modifications (like `case_.assignTimekeeper()` after `caseRepository.save()`) are lost.

### Test Setup

```groovy
@MicronautTest(transactional = false)  // Avoids deadlock between test transaction and repo @Transactional
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class QueueServiceSpec extends Specification {

    @Inject DataSource dataSource
    @Inject MyService service
    @Inject EntityManager entityManager
    @Inject io.micronaut.transaction.TransactionOperations transactionOperations  // NO generic type!

    // Mirrors the consumer's @Transactional
    private void inTransaction(Closure action) {
        transactionOperations.executeWrite(status -> { action(); return null })
    }

    def setup() {
        SchemaLoader.loadSchema(getRawDataSource(), new File(getClass().getResource("/db/schema.sql").toURI()))
        insertBaseTestData()
        // Load entities in read transaction (EntityManager needs transaction context)
        transactionOperations.executeRead(status -> {
            firm = entityManager.find(Firm.class, TEST_FIRM_ID)
            return null
        })
    }

    def "should create entity"() {
        when:
        inTransaction { service.create(firm, ...) }

        then: "verify via raw JDBC (separate connection, committed data)"
        def results = findByFirm()
        results.size() == 1
    }
}
```

**CRITICAL**: `TransactionOperations<java.sql.Connection>` → WRONG. Gives JDBC DataSourceTransactionManager, conflicts with Hibernate. Use raw `TransactionOperations` (no generic type).

### Queue Service Test Checklist
- `startApplication = true` — queue services need RabbitMQ consumers, scheduled tasks, health checks
- `maximum-pool-size: 10` in application-test.yml — background tasks compete for connections
- Schema.sql: **copy core_rest's schema.sql** as base, add project-specific tables (never build from scratch)
- Abstract entities as method params: mock is OK, but load from DB via `entityManager.find(ConcreteSubclass.class, ...)` when passed to Hibernate Criteria queries

### Why `transactional = false` for Queue Services
| Approach | Result |
|----------|--------|
| `transactional = true` | Deadlock — test's transaction + repository's `@Transactional` compete for connections |
| `transactional = true` + EntityManager verification | Hangs — two transaction managers (JDBC vs Hibernate) conflict |
| `transactional = false` + `TransactionOperations` | Works — explicit write transaction mirrors production consumer behavior |

## When to Mock: External Services Only

Mock only non-DB dependencies — external APIs, notification services, email senders:

```groovy
@MicronautTest
class OrderServiceSpec extends Specification {

    @Inject OrderService service
    @Inject OrderRepository orderRepository     // REAL — backed by TestContainers
    @Inject FirmRepository firmRepository        // REAL — backed by TestContainers
    @Inject NotificationService notificationService  // MOCKED — external system

    @MockBean(NotificationService)
    NotificationService mockNotification() {
        Mock(NotificationService)
    }

    // ... schema loading setup ...

    void "creates order and sends notification"() {
        given: "a firm exists in the database"
        def firm = firmRepository.save(new Firm(name: "Test Firm", subdomain: "test-${UUID.randomUUID().toString().substring(0,8)}"))

        when: "creating an order"
        def result = service.createOrder(firm.id, new CreateOrderRequest(description: "Test"))

        then: "order is persisted"
        result.id != null
        orderRepository.findById(result.id).present

        and: "notification was sent"
        1 * notificationService.notifyOrderCreated(_)
    }
}
```

## Exception Pattern

```java
public class {Entity}NotFoundException extends RuntimeException {
    public {Entity}NotFoundException(UUID id) {
        super(String.format("{Entity} not found with ID: %s", id));
    }
}
```

## Testing Transaction Rollback

With real databases, you can verify actual rollback behavior:

```groovy
@MicronautTest(transactional = false)  // disable test-level transaction wrapper
class TransactionalServiceSpec extends Specification {

    void "rolls back all changes when exception occurs mid-transaction"() {
        given: "initial count"
        def initialCount = repository.count()

        when: "service method throws partway through"
        service.createMultipleOrFail(firmId, items)

        then: "exception propagates"
        thrown(RuntimeException)

        and: "no new records persisted (rolled back)"
        repository.count() == initialCount
    }
}
```

## NEVER DO THIS — Service Test Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|-------------|---------------|-----------------|
| Writing a Spock spec without `@MicronautTest` for a `@Singleton` service | Bypasses DI, transactions, AOP interceptors. Tests pass but production fails | Always `@MicronautTest` with `@Inject` for the service under test |
| Using `new MyService(mockRepo)` to instantiate a service | No transaction management, no AOP, no bean lifecycle. Proves nothing about real behavior | Let Micronaut create the bean via `@Inject`. Use `@MockBean` for external deps only |
| Mocking repositories instead of using real database | Hides SQL errors, skips query derivation validation, misses constraint violations | Real repositories with TestContainers PostgreSQL. Only mock external services (email, S3, etc.) |
| Using reflection to set private fields on services | Fragile, bypasses DI, breaks when fields change | Constructor injection + `@MockBean` for dependencies |

## Common Pitfalls

| Error | Cause | Fix |
|-------|-------|-----|
| FK violation in test | Parent entity not created before child | Insert parent via its repository in `setup()` or `given:` block |
| Test data leaking between tests | Shared mutable state | Use unique values (UUID suffixes), or clean up in `cleanup()` |
| Transaction not rolling back | Missing `@Transactional` on write method | Add `@Transactional` to methods with save/update/delete |
| Field injection used | Using `@Inject` on field | Use constructor injection with `private final` |
| `Cannot mock final class` | Mocking a DB repository instead of using real one | Use real repository; only mock external services. If external service is concrete, add ByteBuddy/Objenesis |
| Schema not loaded | Missing SchemaLoader in setup | Add `SchemaLoader.loadSchema()` in `setup()` — it's idempotent, no guards needed |
| `TransactionOperations<Connection>` errors | JDBC manager conflicts with Hibernate session | Use raw `TransactionOperations` (no generic type) |
| Service hangs in test | No outer `@Transactional`, each repo call gets own transaction | Wrap in `TransactionOperations.executeWrite()` via `inTransaction {}` helper |
| `TransientObjectException` for entity param | Mock entity passed to Hibernate Criteria query | Load real entity from DB: `entityManager.find(ConcreteSubclass.class, id)` |
| `Connection is not available` in test | Background tasks (scheduled cache refresh, health checks) exhaust small pool | Set `maximum-pool-size: 10` in application-test.yml |

## Related Skills

- **test-resources-validator** — verify TestResources three-file configuration for auto-provisioned PostgreSQL
- **verify-library-api** — verify external library methods with javap before implementing
- **transaction-boundary-validator** — validate @Transactional placement
- **spock-test-setup** — ensure test dependencies (ByteBuddy/Objenesis only needed for mocking external services)
- **schema-drift-detector** — detect entity-schema drift
- **checkstyle-enforcer** — enforce code style

For verbose examples (multi-dependency services, transaction rollback, mixed real/mock), see `examples.md`.
For external documentation links, see `reference.md`.
