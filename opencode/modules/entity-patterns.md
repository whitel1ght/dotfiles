# Entity Patterns Module

**Purpose**: Schema-first JPA entity patterns for PostgreSQL with Hibernate 6

**When to Use**: Creating or migrating JPA entities from PostgreSQL schema

**Dependencies**: Loaded by `tdd-micronaut.md` base agent when entity work is detected

---

## Schema-First Philosophy

**Core Principle**: The PostgreSQL schema is the **absolute source of truth**.

Entities are **mappings** of existing database tables, not designs for new tables. This approach:
- Ensures entity matches reality (production schema)
- Catches mapping errors at startup via schema validation
- Prevents drift between code and database
- Makes schema the authoritative documentation

**Critical Configuration**:
```yaml
# application-test.yml
jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: validate  # ⭐ NEVER "update" or "create" - ALWAYS "validate"
        default_schema: private
```

**What `validate` does**:
- Hibernate compares entity annotations against actual database schema
- Fails fast if mismatch (wrong type, missing column, incorrect nullable)
- Forces you to fix entity, not database
- Provides immediate feedback during test execution

**Result**: If tests pass with `validate`, your entity is 100% correct.

---

## PostgreSQL Type Mapping Reference Table

This is your complete guide to mapping PostgreSQL types to JPA annotations.

| PostgreSQL Type | Java Type | Annotations | Example |
|-----------------|-----------|-------------|---------|
| `uuid` | `UUID` | `@Column(columnDefinition = "uuid")` | `private UUID id;` |
| `text` | `String` | `@Column(columnDefinition = "text")` | `private String name;` |
| `character varying(N)` | `String` | `@Column(columnDefinition = "character varying(50)")` | `private String code;` |
| `character varying` | `String` | `@Column(columnDefinition = "character varying")` | `private String email;` |
| `integer` or `int4` | `Integer` | `@Column(columnDefinition = "integer")` | `private Integer firmId;` |
| `bigint` or `int8` | `Long` | `@Column(columnDefinition = "bigint")` | `private Long id;` |
| `boolean` or `bool` | `Boolean` | `@Column(columnDefinition = "boolean")` | `private Boolean active;` |
| `timestamp with time zone` | `LocalDateTime` | `@Column(columnDefinition = "timestamp with time zone")` | `private LocalDateTime createdAt;` |
| `timestamptz` | `LocalDateTime` | `@Column(columnDefinition = "timestamptz")` | `private LocalDateTime updatedAt;` |
| `timestamp` | `Instant` | `@Column(columnDefinition = "timestamp")` | `private Instant processedAt;` |
| `date` | `LocalDate` | `@Column(columnDefinition = "date")` | `private LocalDate birthDate;` |
| `time` | `LocalTime` | `@Column(columnDefinition = "time")` | `private LocalTime deliveryTime;` |
| `numeric(P,S)` | `BigDecimal` | `@Column(columnDefinition = "numeric(10,2)")` | `private BigDecimal amount;` |
| `jsonb` | `Map<String, Object>` | `@JdbcTypeCode(SqlTypes.JSON)` + `columnDefinition = "jsonb"` | `private Map<String, Object> metadata;` |
| `text[]` | `List<String>` | `@JdbcTypeCode(SqlTypes.ARRAY)` + `columnDefinition = "text[]"` | `private List<String> tags;` |
| `uuid[]` | `List<UUID>` | `@JdbcTypeCode(SqlTypes.ARRAY)` + `columnDefinition = "uuid[]"` | `private List<UUID> ids;` |
| `hstore` | `Map<String, String>` | `@Type(PostgreSQLHStoreType.class)` + `columnDefinition = "hstore"` | `private Map<String, String> props;` |
| `bytea` | `byte[]` | `@Column(columnDefinition = "bytea")` | `private byte[] logo;` |
| Custom enum | `EnumType` | `@Enumerated(STRING)` + `@JdbcTypeCode(NAMED_ENUM)` + `columnDefinition = "enum_name"` | `private StatusType status;` |
| Enum array | `List<String>` | `@JdbcTypeCode(SqlTypes.ARRAY)` + `columnDefinition = "text[]"` | `private List<String> features;` |

**Critical Notes**:
1. **ALWAYS include `columnDefinition`** - without it, Hibernate guesses wrong types
2. **Enum arrays**: Use `List<String>`, NEVER `List<EnumType>` (PostgreSQL limitation)
3. **HSTORE**: Requires `hypersistence-utils` library and `PostgreSQLHStoreType`
4. **JSONB**: Requires `@JdbcTypeCode(SqlTypes.JSON)` for proper serialization
5. **Arrays**: Require `@JdbcTypeCode(SqlTypes.ARRAY)` for proper array handling

---

## Entity Template with All Annotations

Use this as your starting point for every entity:

```java
package com.goecfx.data.entities;

import io.hypersistence.utils.hibernate.type.basic.PostgreSQLHStoreType;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.annotations.Type;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.*;

/**
 * {Business description of this entity}.
 *
 * Mapped to table: private.{table_name}
 *
 * Schema-first approach: All fields explicitly declared to match PostgreSQL schema.
 * This entity uses:
 * - UUID primary key (manually assigned in constructor)
 * - [List any special types: JSONB, arrays, HSTORE, enums, etc.]
 * - [List any relationships: @ManyToOne to X, @OneToMany to Y]
 *
 * @see {Related entities if applicable}
 */
@Entity
@Table(name = "{table_name}", schema = "private")
@Getter
@Setter
public class {EntityName} {

    /**
     * Primary key - UUID identifier.
     *
     * NOTE: NO @GeneratedValue - IDs are assigned manually in constructor.
     * This is the standard pattern for UUID primary keys in this codebase.
     */
    @Id
    @Column(name = "id", nullable = false, columnDefinition = "uuid")
    private UUID id;

    /**
     * Foreign key to firm table - multi-tenant isolation.
     *
     * NOTE: Integer type because firm.id is Integer, not UUID.
     */
    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    /**
     * Standard text field example.
     */
    @Column(name = "name", nullable = false, columnDefinition = "text")
    private String name;

    /**
     * VARCHAR with specific length.
     */
    @Column(name = "code", columnDefinition = "character varying(50)")
    private String code;

    /**
     * PostgreSQL JSONB for flexible JSON storage.
     * Stores arbitrary JSON documents.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "metadata", columnDefinition = "jsonb")
    private Map<String, Object> metadata;

    /**
     * PostgreSQL text array for storing multiple values.
     */
    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "tags", columnDefinition = "text[]")
    private List<String> tags;

    /**
     * Boolean field with default value.
     */
    @Column(name = "active", nullable = false, columnDefinition = "boolean")
    private Boolean active = true;

    /**
     * Created timestamp - automatically managed by Hibernate.
     */
    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime createdAt;

    /**
     * Updated timestamp - automatically managed by Hibernate.
     */
    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime updatedAt;

    /**
     * Default constructor for JPA.
     *
     * CRITICAL: MUST initialize UUID primary key and any default values.
     *
     * For timestamps:
     * - If using @CreationTimestamp/@UpdateTimestamp: DON'T initialize here
     * - If using Instant without annotations: Initialize with Instant.now()
     */
    public {EntityName}() {
        this.id = UUID.randomUUID();  // ⭐ REQUIRED for UUID PKs
        this.active = true;            // Initialize defaults
        this.tags = new ArrayList<>(); // Initialize collections if non-null
    }

    /**
     * equals() based on ID only - safe for JPA entities.
     * Uses Hibernate.getClass() instead of getClass() for proxy safety.
     *
     * Why Hibernate.getClass(): In Hibernate 6, getClass() on a proxy returns the
     * proxy class (e.g., Entity$HibernateProxy$abc123), not the entity class.
     * This breaks equality between a proxy and a real instance of the same entity.
     */
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null) return false;
        if (!Hibernate.getClass(this).isAssignableFrom(Hibernate.getClass(o))) return false;
        {EntityName} that = ({EntityName}) o;
        return id != null && id.equals(that.id);
    }

    /**
     * hashCode() based on ID - safe for JPA entities.
     *
     * CRITICAL: NEVER access lazy @ManyToOne associations here.
     * Doing so triggers LazyInitializationException on detached entities
     * and NPE when the association is null. Use only the entity's own ID fields.
     */
    @Override
    public int hashCode() {
        if (id != null) return id.hashCode();
        return System.identityHashCode(this);
    }
}
```

**Template Notes**:
- Replace `{EntityName}` and `{table_name}` with actual names
- Remove examples you don't need (JSONB, arrays, etc.)
- Add fields specific to your entity
- Keep constructor, equals(), hashCode() as-is

---

## Constructor Patterns

### UUID Primary Key Initialization

**Pattern**: ALWAYS initialize UUID in no-arg constructor.

```java
public EntityName() {
    this.id = UUID.randomUUID();
}
```

**Why**:
- JPA requires IDs before `persist()` when using `@Id` without `@GeneratedValue`
- Prevents "ids for this class must be manually assigned" errors
- Allows setting relationships before persistence

**Anti-Pattern**:
```java
// ❌ WRONG - ID is null, persist() will fail
public EntityName() {
    // No ID initialization
}
```

### Integer Primary Key (Rare - Firm Entity Only)

**Pattern**: Use `@GeneratedValue` for auto-increment.

```java
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
@Column(name = "id", nullable = false, columnDefinition = "integer")
private Integer id;

public Firm() {
    // NO manual ID initialization - database generates it
}
```

**When to Use**: Only when schema uses `SERIAL` or `IDENTITY` (like `firm` table).

### Default Value Initialization

**Pattern**: Initialize non-null defaults in constructor.

```java
public EntityName() {
    this.id = UUID.randomUUID();
    this.active = true;                    // Boolean default
    this.status = StatusType.PENDING;      // Enum default
    this.tags = new ArrayList<>();         // Empty collection
    this.features = List.of();             // Immutable empty list
}
```

**What to Initialize**:
- UUID primary keys (always)
- Boolean defaults matching database
- Enum defaults matching database
- Empty collections (if column is NOT NULL)

**What NOT to Initialize**:
- `@CreationTimestamp` / `@UpdateTimestamp` fields (Hibernate manages)
- Nullable fields (leave as null)
- Fields with database defaults (let DB set them)

---

## Inheritance Strategies

### Strategy 1: @MappedSuperclass (No Table)

**Use When**: Sharing fields across entities that DON'T share a table.

```java
// Base class - NO table
@MappedSuperclass
@Getter
@Setter
public abstract class BaseFirmEntity {
    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime createdAt;
}

// Concrete entity - HAS table
@Entity
@Table(name = "user", schema = "private")
public class User extends BaseFirmEntity {
    @Id
    @Column(name = "id", columnDefinition = "uuid")
    private UUID id;

    @Column(name = "email", columnDefinition = "text")
    private String email;

    // Inherits firmId and createdAt
}
```

**Benefits**:
- Code reuse for common fields
- No performance overhead (no JOINs)
- Each entity has its own table

**Limitations**:
- Cannot query base class directly
- Cannot have relationships TO base class

### Strategy 2: JOINED Inheritance (Multiple Tables)

**Use When**: Entities share a base table and extend with additional tables.

```java
// Base entity - base table
@Entity
@Table(name = "dms_credential", schema = "private")
@Inheritance(strategy = InheritanceType.JOINED)
@Getter
@Setter
public class DMSCredential {
    @Id
    @Column(name = "id", columnDefinition = "uuid")
    private UUID id;

    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    @Column(name = "name", columnDefinition = "text")
    private String name;

    public DMSCredential() {
        this.id = UUID.randomUUID();
    }
}

// Subclass entity - extends with own table
@Entity
@Table(name = "dropbox_credential", schema = "private")
@Getter
@Setter
public class DropboxCredential extends DMSCredential {
    @Column(name = "access_token", columnDefinition = "text")
    private String accessToken;

    @Column(name = "refresh_token", columnDefinition = "text")
    private String refreshToken;

    // Inherits id, firmId, name from base
}
```

**Database Schema**:
```sql
-- Base table
CREATE TABLE private.dms_credential (
    id uuid PRIMARY KEY,
    firm_id integer NOT NULL,
    name text
);

-- Subclass table (FK to base)
CREATE TABLE private.dropbox_credential (
    id uuid PRIMARY KEY REFERENCES private.dms_credential(id) ON DELETE CASCADE,
    access_token text,
    refresh_token text
);
```

**Benefits**:
- Can query base class (gets all subclasses)
- Normalized schema (no duplication)
- Supports polymorphic relationships

**Limitations**:
- JOIN overhead (Hibernate joins tables)
- More complex queries

### Strategy 3: Mixed 4-Level Hierarchy

**Use When**: Complex hierarchy mixes @Entity and @MappedSuperclass.

```java
// Level 1: @Entity with JOINED - HAS TABLE
@Entity
@Table(name = "dms_credential", schema = "private")
@Inheritance(strategy = InheritanceType.JOINED)
public class DMSCredential {
    @Id private UUID id;
    @Column(name = "firm_id") private Integer firmId;
    // Constructor initializes UUID
}

// Level 2: @MappedSuperclass - NO TABLE (adds HTTP fields)
@MappedSuperclass
public abstract class DMSHTTPCredential extends DMSCredential {
    @Column(name = "base_url") private String baseUrl;
    @Column(name = "use_agent") private Boolean useAgent;
}

// Level 3: @MappedSuperclass - NO TABLE (adds vendor fields)
@MappedSuperclass
public abstract class IManageCredential extends DMSHTTPCredential {
    @Column(name = "client_id") private String clientId;

    @Type(PostgreSQLHStoreType.class)
    @Column(name = "custom_properties", columnDefinition = "hstore")
    private Map<String, String> customProperties;
}

// Level 4: @Entity - HAS TABLE (final implementation)
@Entity
@Table(name = "imanage_cloud", schema = "private")
public class IManageCloudCredential extends IManageCredential {
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "cloud_environment", columnDefinition = "imanage_cloud_environment")
    private IManageCloudEnvironment cloudEnvironment;

    // Inherits ALL fields from 3 parent classes
}
```

**When to Use**:
- Deep domain hierarchies (authentication credentials, document types)
- Mix shared fields (@MappedSuperclass) with polymorphic queries (@Entity)

**Complexity**: HIGH - only use when domain truly requires it.

---

## Testing Patterns

### Test Template

```groovy
package com.goecfx.data.entities

import com.goecfx.data.infrastructure.SchemaLoader
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import jakarta.persistence.EntityManager
import spock.lang.Shared
import spock.lang.Specification

import javax.sql.DataSource

/**
 * Test specification for {EntityName} entity with schema validation.
 * Tests run with hbm2ddl.auto=validate to ensure entity matches PostgreSQL schema.
 */
@MicronautTest(transactional = true, rollback = true)
class {EntityName}Spec extends Specification {

    @Inject
    EntityManager entityManager

    @Inject
    @Shared
    DataSource dataSource

    @Shared
    static boolean schemaLoaded = false

    def setup() {
        if (!schemaLoaded) {
            // Load schema once for all tests
            def schemaFile = new File("src/test/resources/db/schema-minimal.sql")
            SchemaLoader.loadSchema(dataSource, schemaFile)
            schemaLoaded = true
        }
    }

    void "test entity persistence with all fields"() {
        given: "a fully populated entity"
        def entity = new {EntityName}()
        // entity.id is auto-initialized in constructor
        entity.firmId = 1010
        entity.name = "Test Entity"
        // ... set all fields

        when: "persisting the entity"
        entityManager.persist(entity)  // ⭐ NO transaction wrapper!
        entityManager.flush()           // @MicronautTest handles transactions

        then: "entity is saved and retrievable"
        def retrieved = entityManager.find({EntityName}.class, entity.id)
        retrieved != null
        retrieved.id == entity.id
        retrieved.name == "Test Entity"
        // ... assert all fields
    }

    void "test minimal required fields"() {
        given: "entity with only required NOT NULL fields"
        def entity = new {EntityName}()
        entity.firmId = 1010  // Required
        // Don't set optional fields

        when:
        entityManager.persist(entity)
        entityManager.flush()

        then:
        def retrieved = entityManager.find({EntityName}.class, entity.id)
        retrieved != null
    }

    void "test schema validation passes"() {
        expect: "Hibernate validation succeeds (no exceptions thrown)"
        true  // If we get here, validation passed
    }
}
```

### SchemaLoader Pattern

**Purpose**: Load PostgreSQL schema once before all tests.

**Pattern**:
```groovy
@Shared
static boolean schemaLoaded = false

def setup() {
    if (!schemaLoaded) {
        def schemaFile = new File("src/test/resources/db/schema-minimal.sql")
        SchemaLoader.loadSchema(dataSource, schemaFile)
        schemaLoaded = true
    }
}
```

**Why `@Shared static boolean`**:
- Loads schema once per test class (not per test method)
- Prevents redundant schema loads (faster tests)
- Thread-safe for parallel test execution

### Test Isolation with entityManager.clear()

**Problem**: Hibernate caches entities, subsequent queries may return cached objects.

**Solution**: Clear EntityManager after persist/flush.

```groovy
when: "persisting entity"
entityManager.persist(entity)
entityManager.flush()
def entityId = entity.id
entityManager.clear()  // ⭐ Clear cache

then: "retrieving from database (not cache)"
def retrieved = entityManager.find(EntityName, entityId)
retrieved != null  // Proves database round-trip worked
```

### Native Query for FK Dependencies

**Problem**: Entity has FK to firm, must insert firm first.

**Solution**: Use native SQL with `ON CONFLICT DO NOTHING`.

```groovy
def setup() {
    // ... schema loading ...

    // Insert firm for FK relationship
    entityManager.createNativeQuery("""
        INSERT INTO private.firm (id, name, subdomain, encryption_key_id)
        VALUES (?, ?, ?, ?::uuid)
        ON CONFLICT (id) DO NOTHING
    """).setParameter(1, 1010)
      .setParameter(2, "Test Firm")
      .setParameter(3, "test-firm")
      .setParameter(4, UUID.randomUUID().toString())
      .executeUpdate()

    entityManager.flush()
}
```

**Why `ON CONFLICT DO NOTHING`**:
- Multiple tests may try to insert same firm_id
- Prevents "duplicate key" errors
- Idempotent (safe to run multiple times)

---

## Common Pitfalls and Fixes

### Issue: Schema Validation Fails - Wrong Column Type

**Error**: `wrong column type encountered in column [X]; found [Y], but expecting [Z]`

**Cause**: Missing or incorrect `columnDefinition`

**Fix**: Add exact PostgreSQL type to `columnDefinition`

```java
// ❌ WRONG - Hibernate guesses type
@Column(name = "metadata")
private Map<String, Object> metadata;

// ✅ CORRECT - Explicit columnDefinition
@JdbcTypeCode(SqlTypes.JSON)
@Column(name = "metadata", columnDefinition = "jsonb")
private Map<String, Object> metadata;
```

### Issue: Missing Column in Table

**Error**: `missing column [X] in table [Y]`

**Cause**: Column name doesn't match schema (typo or wrong snake_case)

**Fix**: Check schema and match exactly

```java
// ❌ WRONG - camelCase
@Column(name = "createdAt")

// ✅ CORRECT - snake_case matching schema
@Column(name = "created_at")
```

### Issue: Wrong Nullable Constraint

**Error**: `wrong column definition; expected NOT NULL but found nullable`

**Cause**: `nullable` attribute doesn't match schema

**Fix**: Check schema `NOT NULL` constraint

```java
// ❌ WRONG - schema has NOT NULL but entity allows null
@Column(name = "name")

// ✅ CORRECT - match schema constraint
@Column(name = "name", nullable = false)
```

### Issue: Null ID Errors on Persist

**Error**: `ids for this class must be manually assigned before calling save()`

**Cause**: Forgot to initialize UUID in constructor

**Fix**: Add constructor with UUID initialization

```java
public EntityName() {
    this.id = UUID.randomUUID();  // ⭐ Required!
}
```

### Issue: Enum Arrays Don't Work

**Error**: Type mapping issues with `List<EnumType>`

**Cause**: PostgreSQL doesn't support Java enum arrays directly

**Fix**: Use `List<String>` instead

```java
// ❌ WRONG - doesn't work with PostgreSQL
@Column(name = "features", columnDefinition = "text[]")
private List<FeatureType> features;

// ✅ CORRECT - use String list
@JdbcTypeCode(SqlTypes.ARRAY)
@Column(name = "features", columnDefinition = "text[]")
private List<String> features;  // Store enum names as strings
```

---

## Advanced Patterns

### HSTORE for Flexible Key-Value Storage

**Use Case**: Storing credentials or configuration with varying fields.

```java
import io.hypersistence.utils.hibernate.type.basic.PostgreSQLHStoreType;
import org.hibernate.annotations.Type;

@MappedSuperclass
public abstract class BaseFirmCredential {

    /**
     * Flexible credential storage using PostgreSQL HSTORE.
     * Supports various authentication patterns:
     * - OAuth2: "client_id", "client_secret", "redirect_uri"
     * - API Key: "api_key", "api_secret", "endpoint"
     * - Basic Auth: "username", "password"
     */
    @Type(PostgreSQLHStoreType.class)
    @Column(name = "credentials", nullable = false, columnDefinition = "hstore")
    private Map<String, String> credentials = new HashMap<>();

    public BaseFirmCredential() {
        this.id = UUID.randomUUID();
        this.credentials = new HashMap<>();  // Initialize for NOT NULL
    }
}
```

**Testing HSTORE**:
```groovy
void "test HSTORE credentials with OAuth2 fields"() {
    given:
    def entity = new FirmCredential()
    entity.firmId = 1010
    entity.credentials = [
        "client_id": "abc123",
        "client_secret": "secret456",
        "redirect_uri": "https://example.com/callback"
    ]

    when:
    entityManager.persist(entity)
    entityManager.flush()

    then:
    def retrieved = entityManager.find(FirmCredential, entity.id)
    retrieved.credentials.size() == 3
    retrieved.credentials["client_id"] == "abc123"
}
```

### OAuth2 Credential Patterns

**Authorization Code Flow** (user-based):
```java
@Entity
@Table(name = "netdocuments_cloud", schema = "private")
public class NetDocumentsCloudCredential {
    @Column(name = "basic_auth", columnDefinition = "text")
    private String basicAuth;  // Base64 for token refresh

    @Column(name = "refresh_token", columnDefinition = "text")
    private String refreshToken;  // 90-day expiry

    @Column(name = "recent_access_token", columnDefinition = "text")
    private String recentAccessToken;  // 1-hour expiry

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "cloud_environment", columnDefinition = "netdocuments_cloud_environment")
    private NetDocumentsCloudEnvironment cloudEnvironment;  // SANDBOX or PROD
}
```

**Client Credentials Grant** (service-to-service):
```java
@Entity
@Table(name = "box_client_credential", schema = "private")
public class BoxClientCredential {
    @Column(name = "client_key", columnDefinition = "text")
    private String clientKey;

    @Column(name = "client_secret", columnDefinition = "text")
    private String clientSecret;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "box_subject_type", columnDefinition = "box_subject_type")
    private BoxSubjectType boxSubjectType;  // ENTERPRISE or USER

    @Column(name = "box_subject_id", columnDefinition = "bigint")
    private Long boxSubjectId;
}
```

---

## Cross-References

**To Base Agent**:
- For TDD workflow, see `tdd-micronaut.md` section "The Sacred TDD Cycle"
- For TestResources config, see `tdd-micronaut.md` section "TestResources Configuration"

**To Other Modules**:
- Repository tests use these entity patterns, see `repository-patterns.md` section "Real Database Testing"
- Service tests may need to create entities for fixtures, see `service-patterns.md` section "Test Data Setup"

**From Other Modules**:
- `repository-patterns.md` references entity structure for query methods
- `service-patterns.md` may reference entity creation patterns

---

**Total Patterns**: 50+ PostgreSQL type mappings, 3 inheritance strategies, complete testing approach

**Key Takeaway**: Schema is truth, entities are mappings. Always validate with `hbm2ddl.auto: validate`.
