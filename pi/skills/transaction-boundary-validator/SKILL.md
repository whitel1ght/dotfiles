---
name: transaction-boundary-validator
description: >-
  Enforce architectural pattern that @Transactional annotation should only appear on service layer methods, never on controllers or repositories. Use when creating services, during code review, when transaction-related issues occur, or when user mentions transactions, database operations, or service layer implementation.
---


# Transaction Boundary Validator

Validate that `@Transactional` annotations follow the correct architectural pattern: service layer only. This prevents transaction mismanagement and ensures proper separation of concerns.

## Problem Solved

Improper placement of `@Transactional` annotations leads to:
- Controllers managing transactions (mixing HTTP and transaction concerns)
- Repositories with transaction annotations (redundant, repositories already operate in transactions)
- Unclear transaction boundaries
- Difficult testing and debugging
- Transaction leakage or premature commits

## Critical Architectural Pattern

**Micronaut Layered Architecture Transaction Rules**:
- **Controllers**: NEVER have `@Transactional` (thin HTTP layer, delegate to services)
- **Services**: ALWAYS have `@Transactional` on public methods that modify data (define transaction boundaries)
- **Repositories**: NEVER have `@Transactional` (Micronaut Data handles transactions automatically)

## Process

### 1. Identify Project Layers

Locate the three layers in the project:
```
src/main/java/[package]/
├── controllers/    # HTTP endpoints
├── services/       # Business logic
└── repositories/   # Data access
```

Use Glob to find all files:
```bash
# Find all Java files in each layer
src/main/java/**/controllers/**/*.java
src/main/java/**/services/**/*.java
src/main/java/**/repositories/**/*.java
```

### 2. Scan for @Transactional Annotations

Use Grep to find all `@Transactional` usage:
```bash
# Search for @Transactional in all Java files
pattern: @Transactional
path: src/main/java
output_mode: content
-n: true
```

### 3. Validate Each Occurrence

For each found `@Transactional` annotation, determine:

**File Path Analysis**:
- Extract layer from path: `controllers/`, `services/`, or `repositories/`
- If path contains `controllers/` → **VIOLATION**
- If path contains `repositories/` → **VIOLATION**
- If path contains `services/` → **VALID** (proceed to method-level validation)

**Class-Level Annotations**:
- `@Transactional` on class level applies to all public methods
- Valid only on service classes
- Controllers and repositories should NEVER have class-level `@Transactional`

**Method-Level Validation for Services**:
- Public methods that modify data should have `@Transactional`
- Read-only methods can optionally have `@Transactional(readOnly = true)`
- Private methods should NOT have `@Transactional` (use transaction on public entry point)

### 4. Check for Missing Annotations

Scan service layer for methods that SHOULD have `@Transactional`:

**Methods that require @Transactional**:
- Methods calling repository save/delete/update operations
- Methods performing multiple repository operations (atomic operations)
- Methods containing business logic that modifies state

**Pattern to grep for in services**:
```bash
# Find repository save/update/delete calls in services
pattern: \.(save|update|delete|persist|merge)\(
path: src/main/java/**/services/
output_mode: content
-n: true
```

Check if the containing method has `@Transactional`.

### 5. Validate Import Statements

Verify correct `@Transactional` import:

**Correct imports**:
```java
// Micronaut framework (preferred)
import io.micronaut.transaction.annotation.Transactional;

// Jakarta/JTA (also valid)
import jakarta.transaction.Transactional;
```

**Incorrect imports**:
```java
// Spring framework (wrong framework)
import org.springframework.transaction.annotation.Transactional;
```

Use Grep to find Spring imports:
```bash
pattern: import org\.springframework\.transaction
output_mode: files_with_matches
```

### 6. Generate Validation Report

Create a comprehensive report:

```markdown
## Transaction Boundary Validation Report

### Summary
- **Total @Transactional found**: [count]
- **Valid placements**: [count]
- **Violations**: [count]
- **Missing annotations**: [count]

### Violations Found

#### Controllers with @Transactional (VIOLATION)
**File**: `src/main/java/com/example/controllers/WebhookController.java`
**Line**: 45
**Code**:
```java
@Controller("/webhooks")
public class WebhookController {
    @Post("/inbound")
    @Transactional  // ❌ VIOLATION: Controller should not manage transactions
    public HttpResponse<Void> handleInbound(@Body Request request) {
        // ...
    }
}
```
**Issue**: Controllers should be thin HTTP handlers, delegate to services for transactional operations.

**Fix**: Remove `@Transactional` from controller, ensure service method has it.

#### Repositories with @Transactional (VIOLATION)
**File**: `src/main/java/com/example/repositories/ItemRepository.java`
**Line**: 12
**Code**:
```java
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    @Transactional  // ❌ VIOLATION: Repositories already operate in transactions
    List<Item> findByStatus(String status);
}
```
**Issue**: Micronaut Data repositories automatically operate within transactions.

**Fix**: Remove `@Transactional` from repository interface.

### Missing @Transactional Annotations

#### Service Methods Without @Transactional
**File**: `src/main/java/com/example/services/ProcessingService.java`
**Line**: 30
**Code**:
```java
@Singleton
public class ProcessingService {
    public void processItem(Item item) {  // ❌ MISSING: Should have @Transactional
        repository.save(item);
        jobRepository.save(createJob(item));
    }
}
```
**Issue**: Method performs multiple database operations that should be atomic.

**Fix**: Add `@Transactional` annotation to method.

### Valid Placements (Examples)

#### Correct Service Layer Transaction
**File**: `src/main/java/com/example/services/EmailProcessingService.java`
**Line**: 25
**Code**:
```java
@Singleton
public class EmailProcessingService {
    @Transactional  // ✅ CORRECT: Service method with transaction boundary
    public void processInboundEmail(EmailRequest request) {
        EmailInboxItem item = createInboxItem(request);
        emailRepository.save(item);

        InboxItemProcessJob job = createJob(item);
        jobRepository.save(job);
    }
}
```
**Status**: ✅ Correct placement - service defines transaction boundary.

### Import Validation
- [ ] All imports use Micronaut/Jakarta annotations
- [ ] No Spring framework imports found

### Overall Assessment
**Status**: ✅ COMPLIANT / ❌ VIOLATIONS FOUND

### Recommendations
[List specific fixes with file paths and line numbers]
```

### 7. Provide Remediation Guidance

For each violation, provide specific fix:

**Controller Violation Fix**:
```java
// BEFORE (wrong):
@Controller("/webhooks")
public class WebhookController {
    private final ProcessingService service;

    @Post("/inbound")
    @Transactional  // ❌ Remove this
    public HttpResponse<Void> handle(@Body Request request) {
        service.process(request);
        return HttpResponse.ok();
    }
}

// AFTER (correct):
@Controller("/webhooks")
public class WebhookController {
    private final ProcessingService service;

    @Post("/inbound")  // No @Transactional here
    public HttpResponse<Void> handle(@Body Request request) {
        service.process(request);  // Service handles transaction
        return HttpResponse.ok();
    }
}
```

**Service Missing Annotation Fix**:
```java
// BEFORE (wrong):
@Singleton
public class ProcessingService {
    // Missing @Transactional
    public void process(Request request) {
        repository.save(createItem(request));
        jobRepository.save(createJob());
    }
}

// AFTER (correct):
@Singleton
public class ProcessingService {
    @Transactional  // ✅ Add this
    public void process(Request request) {
        repository.save(createItem(request));
        jobRepository.save(createJob());
    }
}
```

**Repository Violation Fix**:
```java
// BEFORE (wrong):
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    @Transactional  // ❌ Remove this
    List<Item> findByFirmId(Long firmId);
}

// AFTER (correct):
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    List<Item> findByFirmId(Long firmId);  // No annotation needed
}
```

## Quality Checklist

- [ ] All three layers (controllers, services, repositories) scanned
- [ ] Every `@Transactional` occurrence validated
- [ ] Controller violations identified and reported
- [ ] Repository violations identified and reported
- [ ] Service methods performing saves/updates checked for `@Transactional`
- [ ] Import statements validated (Micronaut/Jakarta, not Spring)
- [ ] Report clearly categorizes violations vs valid usage
- [ ] Specific remediation provided for each violation
- [ ] Code examples show before/after for fixes

## When to Use This Skill

**Always use when**:
- Creating new service classes
- Adding transactional methods to existing services
- Code review before committing
- Troubleshooting transaction-related issues

**Warning signs that indicate need**:
- "Transaction not active" errors
- Data inconsistency (partial saves)
- "Could not open JPA EntityManager" exceptions
- Unexpected commits or rollbacks
- Tests failing with transaction-related errors

**Preventative use**:
- Before creating pull requests
- After implementing new features
- During architectural reviews
- When onboarding new developers

## Expected Patterns When Correct

**Correct three-layer pattern**:

```java
// Controllers: No @Transactional
@Controller("/api/items")
public class ItemController {
    private final ItemService service;

    @Post
    public HttpResponse<Item> create(@Body ItemRequest request) {
        Item item = service.createItem(request);
        return HttpResponse.created(item);
    }
}

// Services: @Transactional on public methods
@Singleton
public class ItemService {
    private final ItemRepository repository;

    @Transactional
    public Item createItem(ItemRequest request) {
        Item item = new Item();
        item.setName(request.getName());
        return repository.save(item);
    }

    @Transactional(readOnly = true)
    public Item findById(Long id) {
        return repository.findById(id)
            .orElseThrow(() -> new NotFoundException());
    }
}

// Repositories: No @Transactional
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    List<Item> findByName(String name);
}
```

## Special Cases

**Read-Only Transactions**: Use `@Transactional(readOnly = true)` for service methods that only read data:
```java
@Transactional(readOnly = true)
public List<Item> searchItems(String query) {
    return repository.findByNameContaining(query);
}
```

**Transaction Propagation**: Micronaut supports transaction propagation. Service methods can call other service methods:
```java
@Transactional
public void processItem(Item item) {
    // This method starts transaction
    itemService.validate(item);  // Uses same transaction
    repository.save(item);
}
```

**Class-Level Annotation**: Can apply `@Transactional` at class level for all public methods:
```java
@Singleton
@Transactional  // Applies to all public methods
public class ItemService {
    public void create(Item item) { /* transactional */ }
    public void update(Item item) { /* transactional */ }
}
```

**Exception Handling**: Transactions rollback on unchecked exceptions (RuntimeException):
```java
@Transactional
public void processItem(Item item) {
    repository.save(item);
    if (item.isInvalid()) {
        throw new ValidationException();  // Triggers rollback
    }
}
```

**Non-Transactional Methods**: Private helper methods don't need `@Transactional`:
```java
@Singleton
public class ItemService {
    @Transactional
    public void process(Item item) {
        validateItem(item);  // Private, uses transaction from public method
        repository.save(item);
    }

    private void validateItem(Item item) {  // No @Transactional needed
        // Validation logic
    }
}
```

## Common Mistakes

**Mistake 1**: Putting `@Transactional` on controller
- **Problem**: Mixes HTTP concerns with transaction management
- **Fix**: Move to service layer

**Mistake 2**: Forgetting `@Transactional` on service method with multiple saves
- **Problem**: Partial saves if one fails (no atomicity)
- **Fix**: Add `@Transactional` to ensure atomic operations

**Mistake 3**: Using Spring's `@Transactional` in Micronaut project
- **Problem**: Wrong framework, won't work
- **Fix**: Use `io.micronaut.transaction.annotation.Transactional`

**Mistake 4**: Transactional annotation on repository interface
- **Problem**: Redundant, can cause confusion
- **Fix**: Remove, repositories already transactional

---

For detailed examples of each layer pattern, see `examples.md`
For Micronaut transaction documentation links, see `reference.md`
