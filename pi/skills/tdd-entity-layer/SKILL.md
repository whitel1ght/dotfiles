---
name: tdd-entity-layer
description: >-
  Schema-first JPA entity patterns for PostgreSQL with Hibernate 6. Use when creating/modifying JPA entities, PostgreSQL mappings, @Entity, @Table, entities/ directories, or when working with column type mappings, inheritance strategies, or entity testing.
---


# TDD Entity Layer

Schema-first JPA entity development where PostgreSQL schema is the absolute source of truth. Entities are mappings of existing tables, not designs for new ones.

## Critical Configuration

```yaml
# application-test.yml — ALWAYS validate, NEVER update/create
jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: validate
        default_schema: private
```

## Entity Template

```java
@Entity
@Table(name = "{table_name}", schema = "private")
@Getter
@Setter
public class {EntityName} {

    @Id
    @Column(name = "id", nullable = false, columnDefinition = "uuid")
    private UUID id;

    @Column(name = "firm_id", nullable = false, columnDefinition = "integer")
    private Integer firmId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false,
            columnDefinition = "timestamp with time zone")
    private LocalDateTime updatedAt;

    public {EntityName}() {
        this.id = UUID.randomUUID();  // REQUIRED for UUID PKs
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null) return false;
        // Use Hibernate.getClass() for proxy safety — getClass() returns the proxy class in Hibernate 6
        if (!Hibernate.getClass(this).isAssignableFrom(Hibernate.getClass(o))) return false;
        {EntityName} that = ({EntityName}) o;
        return id != null && id.equals(that.id);
    }

    @Override
    public int hashCode() {
        // Use id.hashCode() when available, identity hash otherwise.
        // NEVER access lazy @ManyToOne associations here — causes LazyInitializationException.
        if (id != null) return id.hashCode();
        return System.identityHashCode(this);
    }
}
```

## PostgreSQL Type Mapping Reference

| PostgreSQL Type | Java Type | Annotations |
|-----------------|-----------|-------------|
| `uuid` | `UUID` | `@Column(columnDefinition = "uuid")` |
| `text` | `String` | `@Column(columnDefinition = "text")` |
| `character varying(N)` | `String` | `@Column(columnDefinition = "character varying(50)")` |
| `integer` / `int4` | `Integer` | `@Column(columnDefinition = "integer")` |
| `bigint` / `int8` | `Long` | `@Column(columnDefinition = "bigint")` |
| `boolean` | `Boolean` | `@Column(columnDefinition = "boolean")` |
| `timestamp with time zone` | `LocalDateTime` | `@Column(columnDefinition = "timestamp with time zone")` |
| `date` | `LocalDate` | `@Column(columnDefinition = "date")` |
| `numeric(P,S)` | `BigDecimal` | `@Column(columnDefinition = "numeric(10,2)")` |
| `jsonb` | `Map<String, Object>` | `@JdbcTypeCode(SqlTypes.JSON)` + `columnDefinition = "jsonb"` |
| `text[]` | `List<String>` | `@JdbcTypeCode(SqlTypes.ARRAY)` + `columnDefinition = "text[]"` |
| `hstore` | `Map<String, String>` | `@Type(PostgreSQLHStoreType.class)` + `columnDefinition = "hstore"` |
| `bytea` | `byte[]` | `@Column(columnDefinition = "bytea")` |
| Custom enum | `EnumType` | `@Enumerated(STRING)` + `@JdbcTypeCode(NAMED_ENUM)` + `columnDefinition = "enum_name"` |

**Rules**: Always include `columnDefinition`. Enum arrays use `List<String>`, never `List<EnumType>`.

## Test File Organization

- Test file MUST be named `{EntityName}Spec.groovy` — covers ALL entity behaviors (persistence, equals, hashCode, helpers, proxy behavior)
- hashCode/equals tests are test cases WITHIN the entity spec, NOT standalone classes like `{EntityName}HashCodeSpec`
- ALWAYS search for an existing `{EntityName}Spec.groovy` before creating a new file. If found, ADD test cases to it.
- Use the module's `SchemaLoader` + `schema.sql` for DB setup — NEVER inline custom schema handling. If the module lacks a SchemaLoader, create one following `core_rest/infrastructure/SchemaLoader.groovy`.

## Test Template

```groovy
@MicronautTest(transactional = false)
class {EntityName}Spec extends Specification {

    @Inject EntityManagerFactory entityManagerFactory
    @Inject DataSource dataSource

    // Static constants — deterministic, unique per spec to avoid cross-spec interference
    static final int FIRM_ID = {unique_id}  // e.g. 9900, 9901, etc.
    static final String CASE_UUID = 'aaaaaaaa-0001-0001-0001-aaaaaaaaaaaa'
    static final String ENTITY_UUID = 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb'

    def setup() {
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/schema.sql").toURI()))
        insertTestData()
    }

    def cleanup() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("DELETE FROM public.{table} WHERE firm_id = ${FIRM_ID}")
            conn.createStatement().execute("DELETE FROM public.firm WHERE id = ${FIRM_ID}")
        }
    }

    void "test entity persistence and retrieval"() {
        when: "loading the entity from the database"
        def em = entityManagerFactory.createEntityManager()
        em.getTransaction().begin()
        def entity = em.find({EntityName}.class, new PublicId("{prefix}", UUID.fromString(ENTITY_UUID)))
        em.getTransaction().commit()
        em.close()

        then: "entity is loaded with correct values"
        entity != null
        entity.name == "Test Entity"
    }

    // --- Test Data Helpers ---

    private void insertTestData() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("""
                INSERT INTO public.firm (id, name, subdomain)
                VALUES (${FIRM_ID}, 'Test Firm', 'test-{entity}')
                ON CONFLICT DO NOTHING
            """)
            conn.createStatement().execute("""
                INSERT INTO public.{table} (id, firm_id, name)
                VALUES ('${ENTITY_UUID}', ${FIRM_ID}, 'Test Entity')
                ON CONFLICT DO NOTHING
            """)
        }
    }

    private void executeWithAutoCommit(Closure action) {
        // Unwrap DelegatingDataSource to get raw connection outside transactional context
        def rawDs = dataSource
        while (rawDs.hasProperty('targetDataSource')) {
            rawDs = rawDs.targetDataSource
        }
        def conn = rawDs.getConnection()
        def originalAutoCommit = conn.autoCommit
        conn.autoCommit = true
        try {
            action(conn)
        } finally {
            conn.autoCommit = originalAutoCommit
            conn.close()
        }
    }
}
```

### Key rules for test data:
- **Static constants** for all IDs — never `UUID.randomUUID()`
- **Unique firm ID per spec** — prevents cross-spec interference
- **Single `insertTestData()` method** — NOT one method per table
- **`ON CONFLICT DO NOTHING`** — idempotent inserts
- **`executeWithAutoCommit`** with DataSource — NOT EntityManager → Session wrapping
- **Unwrap DelegatingDataSource** — required when `transactional = false`
- **No `@Shared static boolean` guards** — SchemaLoader is already idempotent

## NEVER DO THIS — Entity Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|-------------|---------------|-----------------|
| Writing a Spock spec without `@MicronautTest` for any entity test | Bypasses Hibernate entirely — cannot test proxy behavior, lazy loading, schema validation, or persistence lifecycle | Always use `@MicronautTest` with `EntityManager` or `EntityManagerFactory` |
| Using `new CourtDocument()` + reflection to set fields in tests | Tests a POJO in a vacuum, not a Hibernate-managed entity. Proves nothing about real behavior | Persist via `EntityManager` or raw SQL, load via `em.find()` or `em.getReference()` |
| Using `getClass()` in equals/hashCode on entities | Hibernate 6 proxies return the proxy class, not the entity class. Breaks equality checks silently | Use `Hibernate.getClass()` for type checks, or `instanceof` (which is proxy-safe) |
| Accessing lazy `@ManyToOne` associations in `hashCode()` | Triggers `LazyInitializationException` on detached entities, NPE when association is null | Use only the entity's own ID fields in `hashCode()` |
| Using `instanceof` on concrete entity classes without `Hibernate.unproxy()` | Hibernate proxies fail `instanceof` against concrete classes | Call `Hibernate.unproxy(entity)` before `instanceof`, OR check against interfaces (which are proxy-safe) |

## Common Pitfalls

| Error | Cause | Fix |
|-------|-------|-----|
| `wrong column type encountered` | Missing/incorrect `columnDefinition` | Add exact PostgreSQL type to `columnDefinition` |
| `missing column [X] in table [Y]` | Column name mismatch (camelCase vs snake_case) | Use exact `snake_case` from schema |
| `expected NOT NULL but found nullable` | `nullable` doesn't match schema | Set `nullable = false` matching schema |
| `ids must be manually assigned` | UUID not initialized in constructor | Add `this.id = UUID.randomUUID()` to constructor |
| Enum array type mapping fails | Using `List<EnumType>` | Use `List<String>` with `@JdbcTypeCode(SqlTypes.ARRAY)` |

## Constructor Rules

- **Always initialize**: UUID primary keys, boolean defaults, enum defaults, non-null collections
- **Never initialize**: `@CreationTimestamp`/`@UpdateTimestamp` fields, nullable fields

## Related Skills

- **test-resources-validator** — verify TestResources three-file configuration
- **spock-test-setup** — ensure ByteBuddy/Objenesis dependencies present
- **schema-drift-detector** — detect entity-schema drift
- **checkstyle-enforcer** — enforce code style

For verbose examples (inheritance strategies, relationships, HSTORE, OAuth2 patterns), see `examples.md`.
For external documentation links, see `reference.md`.
