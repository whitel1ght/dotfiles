# Entity Layer Reference

## External Documentation

- [Micronaut Data JPA](https://micronaut-projects.github.io/micronaut-data/latest/guide/#hibernateJpa) — Micronaut's JPA integration
- [Jakarta Persistence (JPA) Spec](https://jakarta.ee/specifications/persistence/3.1/) — JPA 3.1 specification
- [Hibernate 6 User Guide](https://docs.jboss.org/hibernate/orm/6.4/userguide/html_single/Hibernate_User_Guide.html) — Hibernate ORM reference
- [Hypersistence Utils](https://github.com/vladmihalcea/hypersistence-utils) — PostgreSQL types (HSTORE, JSONB, arrays)

## JPA Annotation Cheat Sheet

| Annotation | Purpose |
|-----------|---------|
| `@Entity` | Marks class as JPA entity |
| `@Table(name, schema)` | Maps to database table |
| `@Id` | Primary key field |
| `@GeneratedValue` | Auto-generated ID (rare — only for SERIAL/IDENTITY) |
| `@Column(name, nullable, columnDefinition)` | Column mapping |
| `@MappedSuperclass` | Shared fields, no table |
| `@Inheritance(strategy)` | Entity inheritance |
| `@Enumerated(EnumType.STRING)` | Enum as string |
| `@JdbcTypeCode(SqlTypes.JSON)` | JSONB mapping |
| `@JdbcTypeCode(SqlTypes.ARRAY)` | Array mapping |
| `@JdbcTypeCode(SqlTypes.NAMED_ENUM)` | PostgreSQL named enum |
| `@Type(PostgreSQLHStoreType.class)` | HSTORE mapping |
| `@CreationTimestamp` | Auto-set on insert |
| `@UpdateTimestamp` | Auto-set on update |
| `@ManyToOne` / `@OneToMany` | Relationship mappings |

## PostgreSQL Type Quick Reference

| Category | Types |
|----------|-------|
| Text | `text`, `character varying(N)`, `char(N)` |
| Numeric | `integer`, `bigint`, `smallint`, `numeric(P,S)`, `real`, `double precision` |
| Boolean | `boolean` |
| Date/Time | `timestamp with time zone`, `timestamp`, `date`, `time`, `interval` |
| UUID | `uuid` |
| JSON | `json`, `jsonb` |
| Arrays | `text[]`, `integer[]`, `uuid[]` |
| Binary | `bytea` |
| Key-Value | `hstore` |

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Micronaut | 4.x | Current framework version |
| Hibernate | 6.x | JPA provider |
| Jakarta Persistence | 3.1 | JPA API |
| Hypersistence Utils | 3.x | Required for HSTORE |
| ByteBuddy | 1.17.8+ | Required for mocking concrete classes |

## Hibernate Proxy Behavior — Subtleties

| Behavior | Detail |
|----------|--------|
| `instanceof` asymmetry | Calling `equals()` ON a proxy works (interceptor delegates); passing a proxy AS argument fails `instanceof` against the concrete entity class. Use `Hibernate.unproxy(arg)` first, OR check against an interface (proxy-safe). |
| Hibernate 6 FK caching | Lazy `@ManyToOne` proxies cache the FK value. `detachedProxy.getId()` does NOT throw `LazyInitializationException`. The real bug is NPE when the association is `null` (`getCase()` returns `null`, then `null.getId()` NPE). Test the null-association case for RED, not just detached-proxy. |
| Serde `SerdeRegistrar<T>` priority | Built-in temporal Serde beans (e.g., `ZonedDateTimeSerde`) cannot be overridden by a `@Singleton @Primary Serde<T>` bean — `SerdeRegistrar` has special priority in the registry. For entities using `ObjectMapper.getDefault()` needing custom temporal handling (e.g., epoch-millis vs epoch-seconds), switch to Jackson `ObjectMapper` instead of fighting the Serde stack. |

## DB-Default Columns and `@Transient` Fields — Lifecycle Gotchas

DB-default columns (e.g., `created_at timestamptz DEFAULT current_timestamp` in `schema.sql`) are NOT populated on the entity returned from `entityManager.persist()` — only the `@GeneratedValue` id is assigned. The DB-default value becomes visible ONLY after `flush() + clear() + reload`. Pin both halves in characterization tests:

```groovy
def saved = repo.create(...)
assert saved.createdAt == null            // not yet populated

entityManager.flush()
entityManager.clear()
def reloaded = repo.getById(saved.id)
assert reloaded.createdAt != null          // DB default visible
```

`@Transient` fields (e.g., `BaseKeyModel.plaintextKeyBytes`) cannot be characterized by "set-it-then-read-same-entity" patterns: `entityManager.find(Class, id)` returns the SAME managed instance from the session cache, preserving the in-memory value and giving a false green. Always `flush() + clear()` before reload to force a fresh read.

## Inheritance Strategies — Test Schema Implications

**`@Inheritance(strategy = JOINED)`**: Hibernate generates LEFT JOINs to ALL subtables in every polymorphic query, even when the FK is null. Test schemas MUST include stub tables for every concrete subclass with all its mapped columns. Estimate EAGER `@ManyToOne` dependency depth BEFORE writing tests — `DMSCredential` (JOINED, 16 subclasses) requires 16 subtable stubs to load any entity that reaches `StoragePolicy.dmsCredential`.

**`@Inheritance(strategy = SINGLE_TABLE)`**: All columns from all subtypes live in one table. Hibernate SELECTs every mapped column regardless of the discriminator value. Missing subtype columns (e.g., `WebhookInboxItem.parsed_content` on `inbox_item`) cause `column does not exist` at runtime. Also: `@PostLoad` hooks on specific subtypes (e.g., `EmailInboxItem.onPostLoad()`) trigger during query result loading and can mark entities dirty, causing auto-flush during subsequent COUNT queries — use a discriminator value WITHOUT `@PostLoad` side effects (e.g., `WEBHOOK` instead of `EMAIL`) for filter/pagination test fixtures.
