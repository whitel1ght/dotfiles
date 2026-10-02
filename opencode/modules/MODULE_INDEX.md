# Module Index - Quick Reference Guide

**Purpose**: Fast pattern lookup across all TDD agent modules

**Last Updated**: 2025-11-05

---

## When to Use Which Module

| What You're Building | Module to Load | Why |
|----------------------|----------------|-----|
| JPA entity from PostgreSQL schema | `entity-patterns.md` | Schema-first mapping, PostgreSQL types |
| Data access layer (repository) | `repository-patterns.md` | Micronaut Data, query methods |
| Business logic (service) | `service-patterns.md` | Mocking, transactions, validation |
| HTTP endpoint (controller) | `controller-patterns.md` | REST API, status codes, validation |

**Base Agent**: Always loaded first, provides 7-step TDD workflow and cross-cutting patterns.

---

## Common Workflows

### Workflow 1: Building Complete New Entity

**Layers Involved**: Entity → Repository → Service (optional)

1. **Start**: Load `entity-patterns.md`
   - Extract PostgreSQL schema
   - Map to JPA annotations
   - Write entity test with schema validation
   - Implement entity with constructor UUID initialization

2. **Next**: Load `repository-patterns.md`
   - Create JpaRepository interface
   - Define query methods using naming conventions
   - Write repository test with real database
   - Verify queries work against TestContainers

3. **Optional**: Load `service-patterns.md` if business logic needed
   - Create service with constructor injection
   - Mock repository in tests
   - Implement business rules

**Total Time**: 60-120 minutes depending on complexity

### Workflow 2: Building Service with Existing Repository

**Layers Involved**: Service only (references Repository)

1. **Start**: Load `service-patterns.md`
   - Review repository interface (reference `repository-patterns.md`)
   - Design service with mocked repository
   - Write service tests with `@MockBean`
   - Implement business logic
   - Add `@Transactional` to write operations

**Cross-Reference**: Repository patterns for interface structure

**Total Time**: 30-60 minutes

### Workflow 3: Building REST API Endpoint

**Layers Involved**: Controller → Service (optional)

1. **Start**: Load `controller-patterns.md`
   - Define HTTP endpoints and DTOs
   - Write HTTP integration tests with `@Client`
   - Test all status codes (200, 201, 400, 401, 404, 500)
   - Implement controller with service injection
   - Add DTO validation with Jakarta Validation

2. **Optional**: If service doesn't exist, load `service-patterns.md`
   - Build service layer first
   - Then connect controller to service

**Total Time**: 45-75 minutes

### Workflow 4: Full Stack Feature (All Layers)

**Layers Involved**: Entity → Repository → Service → Controller

1. **Entity** (`entity-patterns.md`): 30-45 min
2. **Repository** (`repository-patterns.md`): 20-30 min
3. **Service** (`service-patterns.md`): 30-45 min
4. **Controller** (`controller-patterns.md`): 30-45 min

**Total Time**: 2-3 hours for complete feature

---

## Cross-Module Pattern Reference

### Pattern: UUID Primary Key Initialization

- **Defined In**: `entity-patterns.md` § "Constructor Patterns"
- **Used In**: `repository-patterns.md` (entity creation in tests)
- **Pattern**:
  ```java
  public EntityName() {
      this.id = UUID.randomUUID();
  }
  ```
- **Why**: JPA requires IDs before `persist()` when no `@GeneratedValue`

### Pattern: SchemaLoader with @Shared Boolean

- **Defined In**: `entity-patterns.md` § "Testing Patterns"
- **Used In**: `repository-patterns.md` (database setup)
- **Pattern**:
  ```groovy
  @Shared
  static boolean schemaLoaded = false

  def setup() {
      if (!schemaLoaded) {
          SchemaLoader.loadSchema(dataSource, schemaFile)
          schemaLoaded = true
      }
  }
  ```
- **Why**: Load schema once per test class, not per method

### Pattern: TestResources Three-File Configuration

- **Defined In**: Base agent § "TestResources Configuration"
- **Used In**: All modules (testing setup)
- **Files**: `application.yml` (no connection), `application-prod.yml` (env vars), `application-test.yml` (TestResources enabled)
- **Why**: Auto-provisions TestContainers when connection values missing

### Pattern: ByteBuddy/Objenesis for Mocking

- **Defined In**: Base agent § "ByteBuddy & Objenesis for Mocking"
- **Used In**: `service-patterns.md`, `controller-patterns.md`
- **Dependencies**:
  ```groovy
  testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'
  testRuntimeOnly 'org.objenesis:objenesis:3.4'
  ```
- **Why**: Required to mock concrete classes (repositories, services)

### Pattern: Constructor Dependency Injection

- **Defined In**: `service-patterns.md` § "Constructor Dependency Injection"
- **Used In**: `controller-patterns.md` (controllers inject services)
- **Pattern**:
  ```java
  private final Dependency dependency;  // final = immutable

  public Service(Dependency dependency) {
      this.dependency = dependency;
  }
  ```
- **Why**: Testability, immutability, clarity

### Pattern: @Transactional Granularity

- **Defined In**: `service-patterns.md` § "@Transactional Granularity"
- **Applied To**: Service write operations only
- **Rule**: Method-level, write operations only (not reads)
- **Why**: Performance (reads don't need transaction overhead)

### Pattern: javap External Library Verification

- **Defined In**: Base agent § "External Library API Verification"
- **Used In**: `service-patterns.md` § "javap Verification"
- **Command**: `javap -public -cp /path/to/library.jar com.example.Class`
- **When**: Before implementing code calling external library methods
- **Why**: Documentation may be wrong/outdated

### Pattern: Optional<T> Return Types

- **Defined In**: `repository-patterns.md` § "Optional<T> Return Types"
- **Used In**: Service layer (when wrapping repository calls)
- **Why**: Forces explicit null handling, prevents NullPointerException

### Pattern: Spock Mock Verification + Stubbing

- **Defined In**: `service-patterns.md` § "Spock Verification Syntax"
- **Syntax**: `1 * repository.method(args) >> returnValue`
- **Where**: `then:` block (not `given:`)
- **Why**: Combines interaction count and return value

### Pattern: entityManager.clear() for Test Isolation

- **Defined In**: `entity-patterns.md` § "Testing Patterns"
- **Used In**: Entity and repository tests
- **Pattern**:
  ```groovy
  entityManager.persist(entity)
  entityManager.flush()
  entityManager.clear()  // Clear cache
  def retrieved = entityManager.find(Entity, id)
  ```
- **Why**: Proves database round-trip worked (not from cache)

---

## Quick Pattern Lookup

### PostgreSQL Type Mappings

See `entity-patterns.md` § "PostgreSQL Type Mapping Reference Table"

- UUID → `@Column(columnDefinition = "uuid")`
- Text → `@Column(columnDefinition = "text")`
- JSONB → `@JdbcTypeCode(SqlTypes.JSON)` + `columnDefinition = "jsonb"`
- Arrays → `@JdbcTypeCode(SqlTypes.ARRAY)` + `columnDefinition = "text[]"`
- HSTORE → `@Type(PostgreSQLHStoreType.class)` + `columnDefinition = "hstore"`
- Enum Arrays → `List<String>` (NOT `List<EnumType>`)

### Micronaut Data Query Methods

See `repository-patterns.md` § "Query Method Naming Conventions"

- `findBy{Property}` → SELECT WHERE
- `findBy{Property}OrderBy{Property}` → SELECT with ORDER BY
- `countBy{Property}` → COUNT(*)
- `existsBy{Property}` → Boolean existence check
- `And` / `Or` → Logical operators
- Pagination → `Page<Entity> findBy...(Pageable)`

### HTTP Status Codes

See `controller-patterns.md` § "Status Code Testing"

- 200 OK → Successful GET
- 201 CREATED → Successful POST
- 202 ACCEPTED → Async operation
- 204 NO_CONTENT → Successful DELETE
- 400 BAD_REQUEST → Validation error
- 401 UNAUTHORIZED → Missing/invalid auth
- 404 NOT_FOUND → Resource doesn't exist
- 422 UNPROCESSABLE_ENTITY → Business rule violation
- 500 INTERNAL_SERVER_ERROR → Unexpected exception

### Jakarta Validation Annotations

See `controller-patterns.md` § "DTO Validation Patterns"

- `@NotNull` → Field cannot be null
- `@NotBlank` → String cannot be null/empty/whitespace
- `@Size(min, max)` → String/Collection size constraints
- `@Email` → Valid email format
- `@Pattern(regexp)` → Regex validation
- `@Valid` → Triggers validation in controller

---

## Pattern Categories

### Database Patterns
- Schema-first validation: `entity-patterns.md`
- SchemaLoader setup: `entity-patterns.md`, `repository-patterns.md`
- entityManager.clear(): `entity-patterns.md`
- FK setup with ON CONFLICT: `entity-patterns.md`

### Testing Patterns
- Test templates: All modules
- @MockBean setup: `service-patterns.md`, `controller-patterns.md`
- Spock verification: `service-patterns.md`
- HTTP client testing: `controller-patterns.md`
- Real database testing: `entity-patterns.md`, `repository-patterns.md`

### Injection Patterns
- Constructor injection: `service-patterns.md`, `controller-patterns.md`
- @Client injection: `controller-patterns.md`
- MockBean injection: `service-patterns.md`

### Transaction Patterns
- @Transactional granularity: `service-patterns.md`
- Transaction rollback testing: `service-patterns.md`

### Validation Patterns
- Jakarta Validation: `controller-patterns.md`
- Business exceptions: `service-patterns.md`
- Null handling: `service-patterns.md`

### Security Patterns
- Authentication testing: `controller-patterns.md`
- BasicAuth: `controller-patterns.md`
- Security disabled in tests: `controller-patterns.md`

---

## Finding Patterns

**By Layer**:
- Entity → `entity-patterns.md`
- Repository → `repository-patterns.md`
- Service → `service-patterns.md`
- Controller → `controller-patterns.md`

**By Technology**:
- PostgreSQL → `entity-patterns.md`
- JPA/Hibernate → `entity-patterns.md`
- Micronaut Data → `repository-patterns.md`
- Spock → All modules
- TestContainers → Base agent, `entity-patterns.md`, `repository-patterns.md`
- HTTP/REST → `controller-patterns.md`

**By Concept**:
- TDD Workflow → Base agent
- Testing → All modules
- Mocking → `service-patterns.md`, `controller-patterns.md`
- Transactions → `service-patterns.md`
- Validation → `controller-patterns.md`
- Security → `controller-patterns.md`

---

**Quick Navigation Tips**:
1. Know your layer → Load appropriate module
2. Cross-layer work → Load multiple modules (entity + repository, service + controller)
3. Pattern lookup → Use this index
4. Full workflow → Follow "Common Workflows" section above

**Remember**: Base agent (`tdd-micronaut.md`) always loads first, provides TDD workflow and cross-cutting patterns.
