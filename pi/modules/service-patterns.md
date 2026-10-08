# Service Patterns Module

**Purpose**: Business logic service patterns with dependency injection and mocking

**When to Use**: Building service layer components with business logic

**Dependencies**: Loaded by `tdd-micronaut.md` base agent when service work is detected

---

## Constructor Dependency Injection Pattern

**Core Pattern**: ALWAYS use constructor injection with private final fields.

```java
package com.goecfx.services;

import com.goecfx.repositories.EmailInboxItemRepository;
import jakarta.inject.Singleton;
import jakarta.transaction.Transactional;

import java.util.Optional;

/**
 * Service for processing incoming emails and creating inbox items.
 *
 * Uses constructor injection for immutable dependencies.
 */
@Singleton
public class EmailProcessingService {

    private final EmailInboxItemRepository repository;  // final = immutable

    /**
     * Constructor injection.
     * Micronaut automatically provides dependencies at instantiation.
     *
     * @param repository Repository for inbox item persistence
     */
    public EmailProcessingService(EmailInboxItemRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public EmailInboxItem createInboxItem(Integer firmId, String rawEmail) {
        // Business logic implementation
        var item = new EmailInboxItem();
        item.setFirmId(firmId);
        item.setRawEmail(rawEmail);
        return repository.save(item);
    }
}
```

**Why This Pattern**:
- **Immutability**: `final` fields cannot be reassigned
- **Testability**: Easy to provide mock dependencies in tests
- **Clarity**: Dependencies explicit in constructor signature
- **Compile-time safety**: Micronaut validates dependencies exist at compile time
- **No reflection magic**: Constructor is just regular Java code

**Anti-Pattern** (Field Injection):
```java
// ❌ WRONG - mutable, harder to test, uses reflection
@Singleton
public class EmailProcessingService {
    @Inject
    private EmailInboxItemRepository repository;  // NOT final, uses @Inject
}
```

---

## @Transactional Granularity

**Pattern**: Apply `@Transactional` at **method level** for write operations ONLY.

### Correct Pattern

```java
@Singleton
public class FirmService {

    private final FirmRepository repository;

    public FirmService(FirmRepository repository) {
        this.repository = repository;
    }

    /**
     * Read-only operation - NO @Transactional needed.
     * More efficient without transaction overhead.
     */
    public Optional<Firm> findBySubdomain(String subdomain) {
        return repository.findBySubdomain(subdomain);
    }

    /**
     * Write operation - @Transactional REQUIRED.
     * Ensures atomic commit/rollback.
     */
    @Transactional
    public Firm createFirm(String name, String subdomain) {
        var firm = new Firm();
        firm.setName(name);
        firm.setSubdomain(subdomain);
        firm.setEncryptionKeyId(UUID.randomUUID());
        return repository.save(firm);
    }

    /**
     * Write operation - @Transactional REQUIRED.
     * Rollback if any operation fails.
     */
    @Transactional
    public Firm updateFirm(Integer id, String newName) {
        var firm = repository.findById(id)
            .orElseThrow(() -> new FirmNotFoundException(id));
        firm.setName(newName);
        return repository.save(firm);
    }
}
```

**When to Use @Transactional**:
- ✅ Methods that call `save()`, `update()`, `delete()`
- ✅ Methods that modify multiple entities (need atomicity)
- ✅ Methods that need rollback on exception
- ❌ Read-only methods (`findBy...`, `get...`)
- ❌ Methods that only call other services (let them handle transactions)

**Why Method-Level**:
- Read operations don't need transaction overhead
- Finer control over transaction boundaries
- Better performance (fewer database connections held)
- Clearer intent (transaction only where needed)

**Anti-Pattern** (Class-Level):
```java
// ❌ WRONG - ALL methods get transactions (including reads)
@Transactional
@Singleton
public class FirmService {
    // Every method now has transaction overhead
}
```

---

## @MockBean Pattern for Dependencies

**Pattern**: Use `@MockBean` to provide mocked dependencies in service tests.

**Critical Requirement**: ByteBuddy + Objenesis dependencies for mocking concrete classes.

```groovy
// build.gradle
dependencies {
    testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'
    testRuntimeOnly 'org.objenesis:objenesis:3.4'
}
```

**Test Template**:
```groovy
package com.goecfx.services

import com.goecfx.repositories.EmailInboxItemRepository
import com.goecfx.data.entities.EmailInboxItem
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * Test specification for EmailProcessingService with mocked dependencies.
 * Service tests use mocks, NOT real database.
 */
@MicronautTest
class EmailProcessingServiceSpec extends Specification {

    @Inject
    EmailProcessingService service

    @Inject
    EmailInboxItemRepository repository  // This gets replaced by mock below

    /**
     * Provides mock implementation of repository.
     * Micronaut injects this instead of real repository.
     */
    @MockBean(EmailInboxItemRepository)
    EmailInboxItemRepository mockRepository() {
        Mock(EmailInboxItemRepository)  // Spock mock creation
    }

    void "creates inbox item successfully"() {
        given: "mocked repository returns saved item"
        def savedItem = new EmailInboxItem(id: 123L, firmId: 1, rawEmail: "test")

        when: "calling service method"
        def result = service.createInboxItem(1, "test")

        then: "repository.save() is called once and returns mock object"
        1 * repository.save(_) >> savedItem  // ⭐ Verification + Stubbing combined

        and: "result matches mock"
        result.id == 123L
        result.firmId == 1
    }
}
```

**Key Points**:
- **`@MockBean(RepositoryClass)`**: Annotation tells Micronaut to use mock
- **Method returns `Mock(RepositoryClass)`**: Spock creates the mock
- **`@Inject` both service and repository**: Service gets mock repository injected
- **Without ByteBuddy/Objenesis**: Cannot mock concrete repository classes

**See**: `tdd-micronaut.md` section "ByteBuddy & Objenesis for Mocking" for details.

---

## Spock Verification Syntax

**Pattern**: Combine stubbing (return value) and verification (interaction count) in `then:` block.

### Correct Pattern

```groovy
void "processes entity correctly"() {
    given: "test data"
    def entity = new Entity(id: 1)

    when: "calling service method"
    def result = service.processEntity(1)

    then: "repository called exactly once and returns entity"
    1 * repository.findById(1) >> Optional.of(entity)  // Count + Return value
    1 * repository.save(_) >> entity
    result.id == 1
}
```

**Syntax Breakdown**:
- `1 *` = Expect exactly 1 call
- `repository.findById(1)` = Method and argument matcher
- `>>` = Return value (stubbing)
- `Optional.of(entity)` = What to return
- `_` = Any argument matcher

**Multiple Interactions**:
```groovy
then: "multiple repository interactions"
1 * repository.findById(1) >> Optional.of(entity)  // First call
1 * repository.findById(2) >> Optional.empty()     // Second call
2 * repository.save(_) >> { args -> args[0] }      // Called twice, return argument
```

**Argument Matchers**:
```groovy
1 * repository.save(_)                    // Any argument
1 * repository.save({ it.id == 1 })       // Closure matcher
1 * repository.findById(1)                // Exact match
0 * repository.delete(_)                  // Never called
_ * repository.findAll()                  // Any number of calls
```

**Anti-Pattern** (Separate given and then):
```groovy
// ❌ WRONG - stubbing in given, verification in then
given:
repository.findById(_) >> Optional.of(entity)  // Stub

then:
1 * repository.findById(_)  // Verify (but returns null!)
result == null  // Stubbing doesn't work this way
```

**Correct**: Combine in `then:` block for both stubbing and verification.

---

## Business Exception Handling

**Pattern**: Throw domain-specific exceptions with clear messages.

### Exception Definition

```java
package com.goecfx.exceptions;

/**
 * Thrown when a firm is not found by ID or subdomain.
 */
public class FirmNotFoundException extends RuntimeException {

    private final Object identifier;

    public FirmNotFoundException(Integer firmId) {
        super(String.format("Firm not found with ID: %d", firmId));
        this.identifier = firmId;
    }

    public FirmNotFoundException(String subdomain) {
        super(String.format("Firm not found with subdomain: %s", subdomain));
        this.identifier = subdomain;
    }

    public Object getIdentifier() {
        return identifier;
    }
}
```

### Service Usage

```java
@Singleton
public class FirmService {

    private final FirmRepository repository;

    public FirmService(FirmRepository repository) {
        this.repository = repository;
    }

    /**
     * Finds firm by subdomain or throws exception.
     *
     * @throws FirmNotFoundException if subdomain doesn't exist
     */
    public Firm getBySubdomain(String subdomain) {
        return repository.findBySubdomain(subdomain)
            .orElseThrow(() -> new FirmNotFoundException(subdomain));
    }

    /**
     * Updates firm name.
     *
     * @throws FirmNotFoundException if firm doesn't exist
     */
    @Transactional
    public Firm updateName(Integer firmId, String newName) {
        var firm = repository.findById(firmId)
            .orElseThrow(() -> new FirmNotFoundException(firmId));
        firm.setName(newName);
        return repository.save(firm);
    }
}
```

### Testing Exceptions

```groovy
void "throws FirmNotFoundException when firm doesn't exist"() {
    given: "repository returns empty"
    repository.findById(999) >> Optional.empty()

    when: "calling service with non-existent ID"
    service.updateName(999, "New Name")

    then: "FirmNotFoundException is thrown"
    thrown(FirmNotFoundException)
}

void "exception contains correct firm ID"() {
    given:
    repository.findById(123) >> Optional.empty()

    when:
    service.updateName(123, "Name")

    then:
    def ex = thrown(FirmNotFoundException)
    ex.message.contains("123")
}
```

**Benefits**:
- Clear error semantics for controller layer
- Easier exception handling in controllers
- Better error messages for debugging
- Type-safe exception catching

---

## javap Verification for External Libraries (⭐ CRITICAL)

**Problem**: Documentation may be wrong, outdated, or aspirational. Methods you expect may not exist.

**Solution**: ALWAYS verify external library APIs with `javap` before implementing.

### Verification Process

```bash
# Step 1: Find the library JAR in Gradle cache
find ~/.gradle/caches -name "data-*.jar"

# Example output:
# /Users/you/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123/data-0.2.1.jar

# Step 2: Inspect actual public methods with javap
javap -public -cp /Users/you/.gradle/caches/.../data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem

# Example output:
# public class com.goecfx.data.entities.EmailInboxItem {
#   public com.goecfx.data.entities.EmailInboxItem();
#   public void setFirmId(java.lang.Integer);
#   public void setRawEmail(java.lang.String);
#   public java.lang.Integer getFirmId();
#   public java.lang.String getRawEmail();
# }
```

### Real Example from Learnings

**Documentation Said**: `EmailInboxItem.create(firm, rawEmail)` exists
**Reality (via javap)**: No static `create()` method
**Fix**: Use constructor and setters instead

```java
// ❌ WRONG - method doesn't exist
var item = EmailInboxItem.create(firm, rawEmail);

// ✅ CORRECT - verified with javap
var item = new EmailInboxItem();
item.setFirmId(firm.getId());
item.setRawEmail(rawEmail);
```

**When to Use javap**:
- Before implementing code calling external library methods
- When compilation fails with "cannot find symbol"
- When working with internal/custom libraries (like your data library)
- When documentation seems unclear or contradictory
- Anytime you're unsure if a method exists

**Why This Matters**: Prevents wasted time implementing against APIs that don't exist. Saves 15-30 minutes per occurrence.

**Reference**: See `tdd-learnings.md` section "External Library Patterns" for real-world examples.

---

## Service Test Template

Complete test template for service testing:

```groovy
package com.goecfx.services

import com.goecfx.repositories.EntityRepository
import com.goecfx.data.entities.Entity
import com.goecfx.exceptions.EntityNotFoundException
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * Test specification for {Service} with mocked dependencies.
 * Business logic tested in isolation from database.
 */
@MicronautTest
class {Service}Spec extends Specification {

    @Inject
    {Service} service

    @Inject
    {Repository} repository

    @MockBean({Repository})
    {Repository} mockRepository() {
        Mock({Repository})
    }

    void "processes entity successfully"() {
        given: "repository returns entity"
        def entity = new Entity(id: 1, name: "Test")

        when: "calling service method"
        def result = service.processEntity(1)

        then: "repository interactions verified"
        1 * repository.findById(1) >> Optional.of(entity)
        1 * repository.save(_) >> entity
        result.id == 1
    }

    void "throws exception when entity not found"() {
        given: "repository returns empty"
        repository.findById(999) >> Optional.empty()

        when: "calling service"
        service.processEntity(999)

        then: "exception thrown"
        thrown(EntityNotFoundException)
    }

    void "handles null inputs gracefully"() {
        when: "calling with null"
        service.processEntity(null)

        then: "appropriate exception thrown"
        thrown(IllegalArgumentException)
    }

    void "validates business rules"() {
        given: "invalid entity state"
        def entity = new Entity(status: "INVALID")

        when: "attempting business operation"
        service.performBusinessOperation(entity)

        then: "validation exception thrown"
        thrown(BusinessRuleViolationException)
    }
}
```

---

## Transaction Rollback Testing

**Pattern**: Test that transactions roll back on exceptions.

```groovy
void "rolls back transaction on exception"() {
    given: "repository save will throw exception"
    def entity = new Entity(id: 1)

    when: "service method throws exception"
    service.processEntity(1)

    then: "transaction is rolled back (no save completed)"
    1 * repository.findById(1) >> Optional.of(entity)
    1 * repository.save(_) >> { throw new RuntimeException("Database error") }
    thrown(RuntimeException)

    and: "verify rollback happened (subsequent operations don't see changes)"
    // In real scenario, query database to verify no changes persisted
}
```

**Testing @Transactional Behavior**:
- Mock can verify method was called (interaction)
- Cannot verify actual transaction rollback (requires real DB)
- For full transaction testing, use repository tests with real database

---

## Null Handling and Validation

**Pattern**: Validate inputs early, fail fast with clear exceptions.

```java
@Singleton
public class EmailProcessingService {

    private final EmailInboxItemRepository repository;

    public EmailProcessingService(EmailInboxItemRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public EmailInboxItem createInboxItem(Integer firmId, String rawEmail) {
        // Validate inputs
        if (firmId == null) {
            throw new IllegalArgumentException("Firm ID cannot be null");
        }
        if (rawEmail == null || rawEmail.isBlank()) {
            throw new IllegalArgumentException("Raw email cannot be null or blank");
        }

        // Business logic
        var item = new EmailInboxItem();
        item.setFirmId(firmId);
        item.setRawEmail(rawEmail);
        return repository.save(item);
    }
}
```

**Testing Validation**:
```groovy
void "rejects null firm ID"() {
    when:
    service.createInboxItem(null, "email")

    then:
    def ex = thrown(IllegalArgumentException)
    ex.message.contains("Firm ID")
}

void "rejects blank email"() {
    when:
    service.createInboxItem(1, "")

    then:
    thrown(IllegalArgumentException)
}
```

---

## Cross-References

**To Base Agent**:
- For TDD workflow, see `tdd-micronaut.md` section "The Sacred TDD Cycle"
- For ByteBuddy/Objenesis setup, see `tdd-micronaut.md` section "ByteBuddy & Objenesis for Mocking"
- For javap details, see `tdd-micronaut.md` section "External Library API Verification"

**To Repository Module**:
- For repository interfaces being mocked, see `repository-patterns.md` section "JpaRepository Extension Pattern"
- For repository method patterns, see `repository-patterns.md` section "Query Method Naming Conventions"

**From Other Modules**:
- `controller-patterns.md` will mock these services in controller tests
- `entity-patterns.md` may be needed for creating test fixtures

---

**Key Takeaway**: Services contain business logic, use constructor injection, mock dependencies in tests, verify with javap before implementing external APIs.
