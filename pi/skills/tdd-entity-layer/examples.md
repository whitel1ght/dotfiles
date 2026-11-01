# Entity Layer Examples

## Inheritance Strategy: @MappedSuperclass (No Table)

```java
@MappedSuperclass
@Getter @Setter
public abstract class BaseFirmEntity {
    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime createdAt;
}

@Entity
@Table(name = "user", schema = "private")
public class User extends BaseFirmEntity {
    @Id
    @Column(name = "id", columnDefinition = "uuid")
    private UUID id;

    @Column(name = "email", columnDefinition = "text")
    private String email;

    public User() { this.id = UUID.randomUUID(); }
}
```

## Inheritance Strategy: JOINED (Multiple Tables)

```java
@Entity
@Table(name = "dms_credential", schema = "private")
@Inheritance(strategy = InheritanceType.JOINED)
@Getter @Setter
public class DMSCredential {
    @Id
    @Column(name = "id", columnDefinition = "uuid")
    private UUID id;

    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    public DMSCredential() { this.id = UUID.randomUUID(); }
}

@Entity
@Table(name = "dropbox_credential", schema = "private")
@Getter @Setter
public class DropboxCredential extends DMSCredential {
    @Column(name = "access_token", columnDefinition = "text")
    private String accessToken;

    @Column(name = "refresh_token", columnDefinition = "text")
    private String refreshToken;
}
```

Database schema for JOINED:
```sql
CREATE TABLE private.dms_credential (
    id uuid PRIMARY KEY,
    firm_id integer NOT NULL,
    name text
);
CREATE TABLE private.dropbox_credential (
    id uuid PRIMARY KEY REFERENCES private.dms_credential(id) ON DELETE CASCADE,
    access_token text,
    refresh_token text
);
```

## Mixed 4-Level Hierarchy

```java
// Level 1: @Entity JOINED — HAS TABLE
@Entity @Table(name = "dms_credential", schema = "private")
@Inheritance(strategy = InheritanceType.JOINED)
public class DMSCredential { ... }

// Level 2: @MappedSuperclass — NO TABLE
@MappedSuperclass
public abstract class DMSHTTPCredential extends DMSCredential {
    @Column(name = "base_url") private String baseUrl;
}

// Level 3: @MappedSuperclass — NO TABLE
@MappedSuperclass
public abstract class IManageCredential extends DMSHTTPCredential {
    @Column(name = "client_id") private String clientId;
    @Type(PostgreSQLHStoreType.class)
    @Column(name = "custom_properties", columnDefinition = "hstore")
    private Map<String, String> customProperties;
}

// Level 4: @Entity — HAS TABLE
@Entity @Table(name = "imanage_cloud", schema = "private")
public class IManageCloudCredential extends IManageCredential {
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "cloud_environment", columnDefinition = "imanage_cloud_environment")
    private IManageCloudEnvironment cloudEnvironment;
}
```

## JSONB Field

```java
@JdbcTypeCode(SqlTypes.JSON)
@Column(name = "metadata", columnDefinition = "jsonb")
private Map<String, Object> metadata;
```

## Array Field

```java
@JdbcTypeCode(SqlTypes.ARRAY)
@Column(name = "tags", columnDefinition = "text[]")
private List<String> tags;
```

## HSTORE Field

```java
@Type(PostgreSQLHStoreType.class)
@Column(name = "credentials", nullable = false, columnDefinition = "hstore")
private Map<String, String> credentials = new HashMap<>();
```

## Custom Enum

```java
@Enumerated(EnumType.STRING)
@JdbcTypeCode(SqlTypes.NAMED_ENUM)
@Column(name = "status", columnDefinition = "status_type")
private StatusType status;
```

## Testing: Schema Validation

```groovy
@MicronautTest(transactional = true, rollback = true)
class EntitySpec extends Specification {
    @Inject EntityManager entityManager
    @Inject @Shared DataSource dataSource
    @Shared static boolean schemaLoaded = false

    def setup() {
        if (!schemaLoaded) {
            SchemaLoader.loadSchema(dataSource, new File("src/test/resources/db/schema-minimal.sql"))
            schemaLoaded = true
        }
    }

    void "test HSTORE credentials"() {
        given:
        def entity = new FirmCredential()
        entity.firmId = 1010
        entity.credentials = ["client_id": "abc123", "client_secret": "secret"]

        when:
        entityManager.persist(entity)
        entityManager.flush()

        then:
        def retrieved = entityManager.find(FirmCredential, entity.id)
        retrieved.credentials["client_id"] == "abc123"
    }
}
```

## Testing: FK Dependencies with Native Query

```groovy
def setup() {
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

## Testing: Cache Isolation

```groovy
when:
entityManager.persist(entity)
entityManager.flush()
def entityId = entity.id
entityManager.clear()  // Clear cache — forces DB round-trip

then:
def retrieved = entityManager.find(EntityName, entityId)
retrieved != null  // Proves database round-trip worked
```
