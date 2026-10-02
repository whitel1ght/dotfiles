# Micronaut Data Repository Validator - Examples

## Example 1: Valid Repository with Common Patterns

### Entity Class
```java
package com.goecfx.data.entities;

import javax.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "email_inbox_items", schema = "private")
public class EmailInboxItem {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "firm_id", nullable = false)
    private Firm firm;

    @Column(name = "raw_email", nullable = false, columnDefinition = "TEXT")
    private String rawEmail;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private InboxItem.Status status;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    // Getters and setters...
}
```

### Repository Interface
```java
package com.goecfx.repositories;

import com.goecfx.data.entities.EmailInboxItem;
import com.goecfx.data.entities.InboxItem;
import io.micronaut.data.annotation.Repository;
import io.micronaut.data.jpa.repository.JpaRepository;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {

    // Simple property match
    List<EmailInboxItem> findByFirmId(Long firmId);

    // Multiple criteria with And
    List<EmailInboxItem> findByFirmIdAndStatus(Long firmId, InboxItem.Status status);

    // With Like expression
    List<EmailInboxItem> findByRawEmailLike(String pattern);

    // With ordering
    List<EmailInboxItem> findByStatusOrderByCreatedAtDesc(InboxItem.Status status);

    // Count operation
    long countByFirmId(Long firmId);

    // Exists check
    boolean existsByFirmIdAndStatus(Long firmId, InboxItem.Status status);

    // Optional return for single result
    Optional<EmailInboxItem> findFirstByFirmIdOrderByCreatedAtDesc(Long firmId);

    // Pagination
    Page<EmailInboxItem> findByStatus(InboxItem.Status status, Pageable pageable);

    // Between expression
    List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);

    // IsNull expression
    List<EmailInboxItem> findByProcessedAtIsNull();

    // InList expression
    List<EmailInboxItem> findByStatusInList(List<InboxItem.Status> statuses);

    // Top N results
    List<EmailInboxItem> findTop10ByFirmIdOrderByCreatedAtDesc(Long firmId);

    // Nested property access
    List<EmailInboxItem> findByFirm_Name(String firmName);
}
```

### Validation Report
```markdown
## Micronaut Data Repository Validation: EmailInboxItemRepository

**Repository**: com.goecfx.repositories.EmailInboxItemRepository
**Entity**: com.goecfx.data.entities.EmailInboxItem
**Methods Validated**: 12

### Method Validation Results

#### Method 1: findByFirmId(Long firmId)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find` (query method)
- ✅ Property: `firmId` (exists on entity via Firm association)
- ✅ Parameter: `Long firmId` (matches type)
- ✅ Return type: `List<EmailInboxItem>` (appropriate for multiple results)

#### Method 2: findByFirmIdAndStatus(Long firmId, InboxItem.Status status)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Properties: `firmId`, `status` (both exist)
- ✅ Operator: `And` (supported)
- ✅ Parameters: Match property types
- ✅ Return type: `List<EmailInboxItem>`

#### Method 3: findByRawEmailLike(String pattern)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `rawEmail` (String type, supports Like)
- ✅ Expression: `Like` (supported)
- ✅ Parameter: `String pattern`
- ✅ Return type: `List<EmailInboxItem>`

#### Method 4: findByStatusOrderByCreatedAtDesc(InboxItem.Status status)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `status` (exists)
- ✅ Ordering: `OrderByCreatedAtDesc` (valid syntax)
- ✅ Parameter: `InboxItem.Status status`
- ✅ Return type: `List<EmailInboxItem>`

#### Method 5: countByFirmId(Long firmId)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `count` (counting operation)
- ✅ Property: `firmId` (exists)
- ✅ Parameter: `Long firmId`
- ✅ Return type: `long` (correct for count)

#### Method 6: existsByFirmIdAndStatus(Long firmId, InboxItem.Status status)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `exists` (existence check)
- ✅ Properties: `firmId`, `status`
- ✅ Operator: `And`
- ✅ Parameters: Match types
- ✅ Return type: `boolean` (correct for exists)

#### Method 7: findFirstByFirmIdOrderByCreatedAtDesc(Long firmId)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Projection: `First` (limit to 1 result)
- ✅ Property: `firmId`
- ✅ Ordering: `OrderByCreatedAtDesc`
- ✅ Parameter: `Long firmId`
- ✅ Return type: `Optional<EmailInboxItem>` (appropriate for single result)

#### Method 8: findByStatus(InboxItem.Status status, Pageable pageable)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `status`
- ✅ Parameters: `status` and `Pageable`
- ✅ Return type: `Page<EmailInboxItem>` (requires Pageable parameter)

#### Method 9: findByCreatedAtBetween(LocalDateTime start, LocalDateTime end)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `createdAt`
- ✅ Expression: `Between` (supported)
- ✅ Parameters: Two LocalDateTime (correct for Between)
- ✅ Return type: `List<EmailInboxItem>`

#### Method 10: findByProcessedAtIsNull()
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `processedAt` (assuming it exists)
- ✅ Expression: `IsNull` (supported)
- ✅ Parameters: None (correct for IsNull)
- ✅ Return type: `List<EmailInboxItem>`

#### Method 11: findByStatusInList(List<InboxItem.Status> statuses)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `status`
- ✅ Expression: `InList` (supported)
- ✅ Parameter: `List<InboxItem.Status>` (correct for InList)
- ✅ Return type: `List<EmailInboxItem>`

#### Method 12: findTop10ByFirmIdOrderByCreatedAtDesc(Long firmId)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Projection: `Top10` (limit results)
- ✅ Property: `firmId`
- ✅ Ordering: `OrderByCreatedAtDesc`
- ✅ Parameter: `Long firmId`
- ✅ Return type: `List<EmailInboxItem>`

#### Method 13: findByFirm_Name(String firmName)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `firm.name` (nested property, underscore notation)
- ✅ Parameter: `String firmName`
- ✅ Return type: `List<EmailInboxItem>`

### Overall Assessment
**Result**: ✅ ALL METHODS VALID

All repository methods follow Micronaut Data conventions and will compile successfully.
```

---

## Example 2: Invalid Repository with Spring Data Syntax

### Repository with Common Mistakes
```java
package com.goecfx.repositories;

import com.goecfx.data.entities.EmailInboxItem;
import com.goecfx.data.entities.InboxItem;
import io.micronaut.data.annotation.Repository;
import io.micronaut.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {

    // ❌ MISTAKE 1: Using Spring Data 'Before' expression
    List<EmailInboxItem> findByCreatedBefore(LocalDateTime date);

    // ❌ MISTAKE 2: Wrong property casing
    List<EmailInboxItem> findByFirmID(Long id);

    // ❌ MISTAKE 3: Using 'After' expression
    List<EmailInboxItem> findByCreatedAfter(LocalDateTime date);

    // ❌ MISTAKE 4: Missing parameter for Between
    List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start);

    // ❌ MISTAKE 5: Like on non-String property
    List<EmailInboxItem> findByIdLike(Long id);

    // ❌ MISTAKE 6: Property doesn't exist
    List<EmailInboxItem> findByEmail(String email);

    // ❌ MISTAKE 7: Wrong return type for count
    List<EmailInboxItem> countByFirmId(Long firmId);
}
```

### Validation Report
```markdown
## Micronaut Data Repository Validation: EmailInboxItemRepository

**Repository**: com.goecfx.repositories.EmailInboxItemRepository
**Entity**: com.goecfx.data.entities.EmailInboxItem
**Methods Validated**: 7

### Method Validation Results

#### Method 1: findByCreatedBefore(LocalDateTime date)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ❌ Expression: `Before` (NOT supported in Micronaut Data)

**Issues**:
1. **Expression 'Before' not supported**
   - **Problem**: Spring Data syntax, Micronaut Data doesn't recognize it
   - **Impact**: Compilation will fail with "Unable to implement Repository method"
   - **Fix**: Change to `findByCreatedAtLessThan(LocalDateTime date)`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByCreatedBefore(LocalDateTime date);

// After (correct):
List<EmailInboxItem> findByCreatedAtLessThan(LocalDateTime date);
```

#### Method 2: findByFirmID(Long id)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ❌ Property: `FirmID` (property is `firmId` not `FirmID`)

**Issues**:
1. **Property name case mismatch**
   - **Problem**: Property is `firmId` (camelCase), not `FirmID` (uppercase)
   - **Impact**: Compilation fails with "Cannot query entity on non-existent property 'firmID'"
   - **Fix**: Change to `findByFirmId(Long id)`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByFirmID(Long id);

// After (correct):
List<EmailInboxItem> findByFirmId(Long id);
```

#### Method 3: findByCreatedAfter(LocalDateTime date)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ❌ Expression: `After` (NOT supported)

**Issues**:
1. **Expression 'After' not supported**
   - **Problem**: Spring Data syntax
   - **Impact**: Compilation failure
   - **Fix**: Change to `findByCreatedAtGreaterThan(LocalDateTime date)`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByCreatedAfter(LocalDateTime date);

// After (correct):
List<EmailInboxItem> findByCreatedAtGreaterThan(LocalDateTime date);
```

#### Method 4: findByCreatedAtBetween(LocalDateTime start)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `createdAt`
- ✅ Expression: `Between` (supported)
- ❌ Parameters: Only 1 parameter, Between requires 2

**Issues**:
1. **Missing parameter**
   - **Problem**: Between expression requires start and end parameters
   - **Impact**: Compilation fails due to parameter count mismatch
   - **Fix**: Add second parameter `LocalDateTime end`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start);

// After (correct):
List<EmailInboxItem> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);
```

#### Method 5: findByIdLike(Long id)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `id` (exists)
- ❌ Expression: `Like` on non-String type

**Issues**:
1. **Expression incompatible with property type**
   - **Problem**: Like expression only works with String properties, not Long
   - **Impact**: Compilation fails or runtime error
   - **Fix**: Remove Like, use simple equality: `findById(Long id)` or use built-in method

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByIdLike(Long id);

// After (correct - simple equality):
List<EmailInboxItem> findById(Long id);
// OR use built-in method:
Optional<EmailInboxItem> findById(Long id);  // inherited from JpaRepository
```

#### Method 6: findByEmail(String email)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ❌ Property: `email` (does NOT exist on entity)

**Issues**:
1. **Property doesn't exist**
   - **Problem**: Entity has `rawEmail` property, not `email`
   - **Impact**: Compilation fails with "Cannot query entity on non-existent property 'email'"
   - **Fix**: Change to `findByRawEmail(String email)`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> findByEmail(String email);

// After (correct):
List<EmailInboxItem> findByRawEmail(String email);
```

#### Method 7: countByFirmId(Long firmId)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `count`
- ✅ Property: `firmId`
- ✅ Parameter: `Long firmId`
- ❌ Return type: `List<EmailInboxItem>` (should be `long` or `Long`)

**Issues**:
1. **Wrong return type for count operation**
   - **Problem**: Count operations must return numeric type (long, Long, int, Integer)
   - **Impact**: Type mismatch, compilation fails
   - **Fix**: Change return type to `long`

**Corrective Action**:
```java
// Before (wrong):
List<EmailInboxItem> countByFirmId(Long firmId);

// After (correct):
long countByFirmId(Long firmId);
```

### Overall Assessment
**Result**: ❌ ERRORS FOUND - 7 method(s) need correction

### Summary of Corrections Needed

1. **Replace Spring Data expressions**: Use Micronaut Data equivalents
   - `Before` → `LessThan`
   - `After` → `GreaterThan`

2. **Fix property name casing**: Match entity property names exactly
   - `FirmID` → `FirmId`
   - `email` → `rawEmail`

3. **Fix parameter counts**: Ensure expressions have required parameters
   - `Between` needs 2 parameters

4. **Fix type incompatibilities**: Expressions must match property types
   - Don't use `Like` with numeric types

5. **Fix return types**: Return types must match operation
   - `count` methods return numeric types, not Lists
```

---

## Example 3: Complex Query Requiring @Query Annotation

### Attempting Complex Query with Method Name
```java
package com.goecfx.repositories;

import com.goecfx.data.entities.EmailInboxItem;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.annotation.Repository;
import io.micronaut.data.jpa.repository.JpaRepository;
import io.micronaut.data.repository.query.QueryMethod;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {

    // ❌ TOO COMPLEX - readability suffers
    List<EmailInboxItem> findByStatusAndFirmIdAndCreatedAtBetweenAndRawEmailLikeOrderByCreatedAtDesc(
        InboxItem.Status status,
        Long firmId,
        LocalDateTime start,
        LocalDateTime end,
        String emailPattern
    );

    // ✅ BETTER - use @Query for complex queries
    @Query("SELECT e FROM EmailInboxItem e WHERE e.status = :status " +
           "AND e.firm.id = :firmId " +
           "AND e.createdAt BETWEEN :start AND :end " +
           "AND e.rawEmail LIKE :emailPattern " +
           "ORDER BY e.createdAt DESC")
    List<EmailInboxItem> findByComplexCriteria(
        String status,
        Long firmId,
        LocalDateTime start,
        LocalDateTime end,
        String emailPattern
    );
}
```

### Validation Report
```markdown
## Micronaut Data Repository Validation: EmailInboxItemRepository

**Repository**: com.goecfx.repositories.EmailInboxItemRepository
**Entity**: com.goecfx.data.entities.EmailInboxItem
**Methods Validated**: 2

#### Method 1: findByStatusAndFirmIdAndCreatedAtBetweenAndRawEmailLikeOrderByCreatedAtDesc(...)
**Status**: ⚠️ VALID BUT NOT RECOMMENDED

**Analysis**:
- ✅ Prefix: `find`
- ✅ Properties: All exist and types match
- ✅ Expressions: All supported
- ✅ Parameters: Correct count and types
- ✅ Return type: Appropriate
- ⚠️  **Complexity**: Method name is too long and hard to read

**Recommendation**:
While this method is technically valid and will compile, it's not recommended due to poor readability. For queries with 4+ criteria or complex logic, use `@Query` annotation instead.

#### Method 2: findByComplexCriteria(...)
**Status**: ✅ VALID (using @Query)

**Analysis**:
- ✅ Uses `@Query` annotation
- ✅ Parameter names match placeholders (`:status`, `:firmId`, etc.)
- ✅ Return type: Appropriate
- ✅ Readability: Excellent

**Note**: Methods with `@Query` skip method name validation since query is explicitly defined.

### Overall Assessment
**Result**: ✅ VALID (with recommendation to prefer method 2)

### Recommendation
Use `@Query` annotation when:
- Query has 4+ criteria
- Query involves joins beyond simple associations
- Query uses database-specific functions
- Method name would be excessively long
- Complex ordering or grouping is needed
```

---

## Example 4: Validation Workflow

### Step-by-Step Validation Process

**Step 1: Locate Repository and Entity**
```bash
# Find repository files
$ find src/main/java -name "*Repository.java"
src/main/java/com/goecfx/repositories/EmailInboxItemRepository.java
src/main/java/com/goecfx/repositories/InboxItemProcessJobRepository.java

# Find entity (if in project)
$ find src/main/java -name "EmailInboxItem.java"
# (not found - external library)
```

**Step 2: Inspect Entity from External Library**
```bash
# Use verify-library-api skill
$ find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"
~/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123/data-0.2.1.jar

$ javap -public -cp ~/.gradle/caches/.../data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
public class com.goecfx.data.entities.EmailInboxItem {
  public EmailInboxItem();
  public java.lang.Long getId();
  public void setId(java.lang.Long);
  public com.goecfx.data.entities.Firm getFirm();
  public void setFirm(com.goecfx.data.entities.Firm);
  public java.lang.String getRawEmail();
  public void setRawEmail(java.lang.String);
  public com.goecfx.data.entities.InboxItem$Status getStatus();
  public void setStatus(com.goecfx.data.entities.InboxItem$Status);
  public java.time.LocalDateTime getCreatedAt();
  public void setCreatedAt(java.time.LocalDateTime);
}
```

**Step 3: Extract Valid Properties**
From javap output, valid properties are:
- `id` (Long)
- `firm` (Firm) - allows nested access via `firm.id`, `firm.name`, etc.
- `rawEmail` (String)
- `status` (InboxItem.Status)
- `createdAt` (LocalDateTime)

**Step 4: Read Repository Interface**
```java
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    List<EmailInboxItem> findByFirmId(Long firmId);
    List<EmailInboxItem> findByEmail(String email);  // ❌ Property 'email' doesn't exist
}
```

**Step 5: Validate Each Method**

**Method 1**: `findByFirmId(Long firmId)`
- Prefix: `find` ✅
- Property: `firmId` - checking entity... `firm` exists (Firm type), can access `id` ✅
- Parameter: `Long firmId` - matches Long type ✅
- Return: `List<EmailInboxItem>` ✅
- **Result**: ✅ VALID

**Method 2**: `findByEmail(String email)`
- Prefix: `find` ✅
- Property: `email` - checking entity... NOT FOUND ❌
- Valid property is `rawEmail`, not `email` ❌
- **Result**: ❌ INVALID - property doesn't exist

**Step 6: Generate Report and Recommendations**
[See validation report format above]

---

## Example 5: Nested Property Access

### Entity with Associations
```java
@Entity
public class EmailInboxItem {
    @Id
    private Long id;

    @ManyToOne
    @JoinColumn(name = "firm_id")
    private Firm firm;  // Association to Firm entity

    // Other fields...
}

@Entity
public class Firm {
    @Id
    private Long id;

    @Column(name = "name")
    private String name;

    @Column(name = "external_id")
    private String externalId;

    // Other fields...
}
```

### Repository with Nested Property Access
```java
@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {

    // ✅ CORRECT - using underscore for nested property
    List<EmailInboxItem> findByFirm_Name(String firmName);

    // ✅ CORRECT - accessing nested id
    List<EmailInboxItem> findByFirm_Id(Long firmId);

    // ✅ CORRECT - nested property with expression
    List<EmailInboxItem> findByFirm_NameLike(String pattern);

    // ✅ CORRECT - multiple levels (if Firm had address.city)
    // List<EmailInboxItem> findByFirm_Address_City(String city);

    // ❌ WRONG - missing underscore
    List<EmailInboxItem> findByFirmName(String firmName);

    // ❌ WRONG - property doesn't exist on Firm
    List<EmailInboxItem> findByFirm_CompanyName(String name);
}
```

### Validation Report
```markdown
#### Method: findByFirm_Name(String firmName)
**Status**: ✅ VALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Property: `firm.name` (nested access via underscore)
- ✅ Verification: `firm` exists on EmailInboxItem (Firm type)
- ✅ Verification: `name` exists on Firm entity
- ✅ Parameter: `String firmName` (matches Firm.name type)
- ✅ Return type: `List<EmailInboxItem>`

#### Method: findByFirmName(String firmName)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ❌ Property: `firmName` (doesn't exist on EmailInboxItem)
- **Problem**: Missing underscore for nested property access

**Fix**:
```java
// Before (wrong):
List<EmailInboxItem> findByFirmName(String firmName);

// After (correct):
List<EmailInboxItem> findByFirm_Name(String firmName);
```

#### Method: findByFirm_CompanyName(String name)
**Status**: ❌ INVALID

**Analysis**:
- ✅ Prefix: `find`
- ✅ Nested access syntax (underscore)
- ✅ Property: `firm` exists on EmailInboxItem
- ❌ Property: `companyName` does NOT exist on Firm entity
- **Available properties on Firm**: id, name, externalId

**Fix**:
```java
// Before (wrong):
List<EmailInboxItem> findByFirm_CompanyName(String name);

// After (correct - use actual property):
List<EmailInboxItem> findByFirm_Name(String name);
```
```
