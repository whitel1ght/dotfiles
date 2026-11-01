# Transaction Boundary Validator - Reference

## Micronaut Transaction Documentation

### Official Documentation
- **Micronaut Data Transactions**: https://micronaut-projects.github.io/micronaut-data/latest/guide/#transactions
- **Micronaut Transaction Management**: https://docs.micronaut.io/latest/guide/index.html#dataAccess
- **Micronaut JPA**: https://micronaut-projects.github.io/micronaut-sql/latest/guide/#hibernate

### Key Concepts
- **Transaction Propagation**: How transactions behave when methods call other methods
- **Isolation Levels**: How transactions interact with each other
- **Rollback Rules**: When transactions rollback vs commit

---

## @Transactional Annotation Reference

### Package and Import

**Micronaut (Primary)**:
```java
import io.micronaut.transaction.annotation.Transactional;
```

**Jakarta/JTA (Also supported)**:
```java
import jakarta.transaction.Transactional;
```

**Spring (Do NOT use in Micronaut)**:
```java
import org.springframework.transaction.annotation.Transactional;  // WRONG
```

### Annotation Attributes

**readOnly**:
```java
@Transactional(readOnly = true)
```
- Optimizes for read-only operations
- Prevents flush and dirty checking
- Can route to read replicas
- Use for queries that don't modify data

**timeout**:
```java
@Transactional(timeout = 30)  // seconds
```
- Sets transaction timeout
- Throws exception if exceeded
- Prevents long-running transactions

**isolation** (Jakarta annotation only):
```java
@Transactional(isolation = Isolation.READ_COMMITTED)
```
- READ_UNCOMMITTED: Lowest isolation, highest concurrency
- READ_COMMITTED: Default for most databases
- REPEATABLE_READ: Prevents non-repeatable reads
- SERIALIZABLE: Highest isolation, lowest concurrency

**propagation** (Jakarta annotation only):
```java
@Transactional(propagation = Propagation.REQUIRED)
```
- REQUIRED: Use existing transaction or create new (default)
- REQUIRES_NEW: Always create new transaction
- SUPPORTS: Use existing transaction if present, non-transactional otherwise
- NOT_SUPPORTED: Execute non-transactionally
- NEVER: Throw exception if transaction exists
- MANDATORY: Require existing transaction, throw exception if none

---

## Transaction Propagation Behavior

### REQUIRED (Default)
```java
@Transactional
public void methodA() {
    // Starts transaction
    methodB();  // Uses same transaction
}

@Transactional
public void methodB() {
    // Participates in existing transaction
}
```
**Behavior**: If transaction exists, use it. Otherwise, create new one.

### REQUIRES_NEW
```java
@Transactional
public void methodA() {
    // Transaction 1
    methodB();  // Suspends Transaction 1, starts Transaction 2
    // Transaction 1 resumes
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
public void methodB() {
    // Transaction 2 (independent)
    // Can commit even if Transaction 1 rolls back
}
```
**Behavior**: Always creates new transaction, suspending existing one.

### SUPPORTS
```java
public void methodA() {
    // No transaction
    methodB();  // Runs without transaction
}

@Transactional
public void methodC() {
    // Transaction
    methodB();  // Uses transaction
}

@Transactional(propagation = Propagation.SUPPORTS)
public void methodB() {
    // Adapts to caller
}
```
**Behavior**: If transaction exists, use it. Otherwise, run without transaction.

---

## Rollback Behavior

### Default Rollback Rules

**Automatic Rollback**:
- RuntimeException and subclasses
- Error and subclasses
- Any unchecked exception

**No Rollback**:
- Checked exceptions (Exception and subclasses except RuntimeException)
- Successful completion

### Examples

**Rollback on RuntimeException**:
```java
@Transactional
public void process() {
    repository.save(item);
    throw new IllegalStateException();  // Rolls back
}
```

**No rollback on checked exception**:
```java
@Transactional
public void process() throws IOException {
    repository.save(item);
    throw new IOException();  // Does NOT rollback automatically
}
```

**Custom rollback rules** (Jakarta annotation):
```java
@Transactional(rollbackOn = {IOException.class})
public void process() throws IOException {
    repository.save(item);
    throw new IOException();  // Now rolls back
}

@Transactional(dontRollbackOn = {ValidationException.class})
public void process() {
    repository.save(item);
    throw new ValidationException();  // Does NOT rollback
}
```

---

## Layer-Specific Patterns

### Controller Layer: NO @Transactional

**Why**: Controllers are HTTP boundary, should not manage transactions

**Pattern**:
```java
@Controller("/api/items")
public class ItemController {
    private final ItemService service;

    @Post
    public HttpResponse<Item> create(@Body ItemRequest request) {
        // No @Transactional - delegate to service
        return HttpResponse.created(service.createItem(request));
    }
}
```

**What controllers do**:
- Handle HTTP requests/responses
- Perform authentication/authorization
- Validate request format
- Delegate to services
- Format responses

**What controllers DON'T do**:
- Manage transactions
- Direct database access
- Business logic

---

### Service Layer: YES @Transactional

**Why**: Services define business logic boundaries, which map to transaction boundaries

**Pattern**:
```java
@Singleton
public class ItemService {
    private final ItemRepository repository;

    @Transactional
    public Item createItem(ItemRequest request) {
        // Transaction boundary matches business operation
        Item item = new Item();
        item.setName(request.getName());
        return repository.save(item);
    }
}
```

**When to use @Transactional**:
- Any method that saves/updates/deletes
- Methods with multiple repository calls (atomicity)
- Business operations that must be atomic

**When to use readOnly = true**:
- Query methods that only read data
- Report generation
- Search operations

---

### Repository Layer: NO @Transactional

**Why**: Micronaut Data repositories already operate within transactions

**Pattern**:
```java
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    // No @Transactional needed
    List<Item> findByName(String name);

    @Query("UPDATE Item i SET i.processed = true WHERE i.id = :id")
    void markAsProcessed(@Param("id") Long id);
}
```

**How it works**:
- Repository methods automatically join existing transaction
- If no transaction, creates one for the operation
- Service layer should define transaction boundaries

---

## Common Scenarios and Solutions

### Scenario 1: Multiple Repository Operations

**Problem**: Save to multiple repositories atomically

**Solution**:
```java
@Transactional
public void processOrder(OrderRequest request) {
    Order order = createOrder(request);
    orderRepository.save(order);

    Payment payment = createPayment(order);
    paymentRepository.save(payment);  // Same transaction

    // If payment save fails, order save also rolls back
}
```

### Scenario 2: Read-Only Optimization

**Problem**: Large read operations causing unnecessary overhead

**Solution**:
```java
@Transactional(readOnly = true)
public OrderReport generateReport(Long customerId) {
    // No flush, no dirty checking
    List<Order> orders = orderRepository.findByCustomerId(customerId);
    List<Item> items = itemRepository.findByOrderIds(extractIds(orders));
    return new OrderReport(orders, items);
}
```

### Scenario 3: Independent Operations

**Problem**: Some operations should commit independently

**Solution**:
```java
@Transactional
public void processBatch(List<ItemRequest> requests) {
    for (ItemRequest request : requests) {
        auditService.logAttempt(request);  // Independent transaction
        processItem(request);  // Main transaction
    }
}

// In AuditService:
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void logAttempt(ItemRequest request) {
    // Always commits, even if processBatch fails
    auditRepository.save(createAuditLog(request));
}
```

### Scenario 4: Conditional Rollback

**Problem**: Need to rollback based on business rules

**Solution**:
```java
@Transactional
public void processItem(Item item) {
    itemRepository.save(item);

    if (!isValid(item)) {
        throw new ValidationException("Item failed validation");
        // Automatic rollback
    }

    // Commits if validation passes
}
```

---

## Performance Considerations

### Transaction Overhead

**Problem**: Unnecessary transactions for read-only operations

**Impact**:
- Connection pool usage
- Database lock contention
- Memory overhead (dirty checking)

**Solution**:
```java
@Transactional(readOnly = true)  // Optimized
public List<Item> searchItems(String query) {
    return itemRepository.findByQuery(query);
}
```

### Long-Running Transactions

**Problem**: Holding database connections too long

**Impact**:
- Connection pool exhaustion
- Lock contention
- Timeout errors

**Solution**:
```java
// BAD: Long-running transaction
@Transactional
public void processAll() {
    List<Item> items = itemRepository.findAll();  // Large dataset
    for (Item item : items) {
        processItem(item);  // Slow processing
        Thread.sleep(1000);  // Holds transaction open
    }
}

// GOOD: Process in batches with separate transactions
public void processAll() {
    List<Long> ids = itemRepository.findAllIds();
    for (Long id : ids) {
        processSingleItem(id);  // Each has own transaction
    }
}

@Transactional
private void processSingleItem(Long id) {
    Item item = itemRepository.findById(id).orElseThrow();
    processItem(item);
}
```

### Nested Transaction Overhead

**Problem**: Too many nested REQUIRES_NEW transactions

**Impact**:
- Connection pool usage (each requires separate connection)
- Performance degradation

**Solution**: Use REQUIRED (default) for most cases, REQUIRES_NEW only when necessary

---

## Testing Transaction Behavior

### Unit Testing Services

**Test with mocked repositories**:
```groovy
@MicronautTest
class ItemServiceSpec extends Specification {
    @Inject ItemService service

    @MockBean(ItemRepository)
    ItemRepository repository = Mock()

    void "should call repository within transaction"() {
        given:
        ItemRequest request = new ItemRequest(name: "Test")

        when:
        service.createItem(request)

        then:
        1 * repository.save(_)
    }
}
```

### Integration Testing Transactions

**Test with real database**:
```groovy
@MicronautTest
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ItemServiceIntegrationSpec extends Specification {
    @Inject DataSource dataSource
    @Inject ItemService service
    @Inject ItemRepository repository

    void setupSpec() {
        SchemaLoader.loadSchema(dataSource, "db/schema.sql")
    }

    void "should commit transaction on success"() {
        given:
        ItemRequest request = new ItemRequest(name: "Test")

        when:
        service.createItem(request)

        then:
        repository.findByName("Test").isPresent()
    }

    void "should rollback transaction on exception"() {
        given:
        ItemRequest request = new ItemRequest(name: "")

        when:
        service.createItem(request)

        then:
        thrown(ValidationException)
        repository.count() == 0  // Verify rollback
    }
}
```

---

## Common Errors and Solutions

### Error: "No transaction is in progress"

**Cause**: Method trying to access transaction outside transactional method

**Solution**: Add `@Transactional` to service method
```java
// Before (error):
public void processItem(Item item) {
    repository.save(item);  // Error: no transaction
}

// After (fixed):
@Transactional
public void processItem(Item item) {
    repository.save(item);
}
```

### Error: "Transaction marked for rollback only"

**Cause**: Exception occurred earlier in transaction, transaction cannot commit

**Solution**: Check for uncaught exceptions in transactional methods
```java
@Transactional
public void process() {
    try {
        riskyOperation();
    } catch (Exception e) {
        log.error("Error", e);
        // Transaction marked for rollback
    }
    // Trying to save here will fail
}
```

### Error: "Could not open JPA EntityManager"

**Cause**: Database connection issues or configuration problems

**Solution**: Check datasource configuration, connection pool settings

### Error: "Transaction timeout expired"

**Cause**: Transaction took longer than timeout setting

**Solution**: Increase timeout or optimize query
```java
@Transactional(timeout = 60)  // Increase timeout
public void longRunningOperation() {
    // ...
}
```

---

## Comparison: Micronaut vs Spring

### Annotation Packages

**Micronaut**:
```java
import io.micronaut.transaction.annotation.Transactional;
```

**Spring**:
```java
import org.springframework.transaction.annotation.Transactional;
```

### Feature Parity

| Feature | Micronaut | Spring |
|---------|-----------|--------|
| @Transactional | ✅ | ✅ |
| readOnly | ✅ | ✅ |
| timeout | ✅ | ✅ |
| propagation | ✅ (via Jakarta) | ✅ |
| isolation | ✅ (via Jakarta) | ✅ |
| rollbackFor | ✅ (via Jakarta) | ✅ |

### Key Differences

**Micronaut**:
- Compile-time AOP (no runtime proxies)
- Works with final classes and methods
- Better performance (no reflection)

**Spring**:
- Runtime proxies
- Cannot work with final classes/methods
- Uses reflection

---

## Gradle Dependencies

### Required Dependencies

```groovy
// Micronaut Data JPA
implementation("io.micronaut.data:micronaut-data-hibernate-jpa")

// Micronaut Transaction
implementation("io.micronaut.sql:micronaut-jdbc-hikari")

// Hibernate
implementation("io.micronaut.sql:micronaut-hibernate-jpa")

// Database driver
runtimeOnly("org.postgresql:postgresql")
```

### Optional: Jakarta Annotations

```groovy
// For propagation and isolation control
implementation("jakarta.transaction:jakarta.transaction-api:2.0.1")
```

---

## Configuration Reference

### Application Configuration

**application.yml**:
```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    dialect: POSTGRES

jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: none  # Schema managed externally
        show_sql: false
```

**application-test.yml**:
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: test

jpa:
  default:
    properties:
      hibernate:
        show_sql: true  # Debug SQL in tests
```

---

## Additional Resources

### Micronaut Guides
- Getting Started with Data JPA: https://guides.micronaut.io/latest/micronaut-data-jpa-repository.html
- Transaction Management: https://guides.micronaut.io/latest/micronaut-data-jdbc-repository.html

### Jakarta Transaction API
- Specification: https://jakarta.ee/specifications/transactions/2.0/
- API Docs: https://javadoc.io/doc/jakarta.transaction/jakarta.transaction-api/latest/index.html

### Hibernate Documentation
- Transaction Management: https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#transactions
