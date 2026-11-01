---
name: spock-test-setup
description: >-
  Automate Spock + Micronaut test setup with proper dependencies and patterns. Use when creating the first Spock test in a project, when "unable to proxy" or "cannot create mock" errors occur, when user mentions setting up tests, or when implementing repository/service/controller tests.
---


# Spock Test Setup for Micronaut

Automate the setup of Spock testing framework with Micronaut, ensuring all required dependencies for mocking concrete classes are present. Provides layer-specific test patterns for repository, service, and controller testing.

## Problem Solved

Missing ByteBuddy and Objenesis dependencies prevent Spock from mocking concrete classes (like JPA repositories), leading to "unable to proxy" or "cannot create mock for class" errors. This skill ensures correct test infrastructure setup and provides proven test patterns.

## Process

### 1. Verify Test Dependencies

Check if `build.gradle` contains the required testing dependencies:

**Required Dependencies**:
```groovy
dependencies {
    // Core Spock and Micronaut Test
    testImplementation("io.micronaut.test:micronaut-test-spock")
    testImplementation("org.spockframework:spock-core") {
        exclude group: "org.codehaus.groovy", module: "groovy-all"
    }

    // CRITICAL: Required for mocking concrete classes
    testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'  // Enables class mocking
    testRuntimeOnly "org.objenesis:objenesis:3.4"      // Enables mocking without default constructor

    // HTTP client for controller tests
    testImplementation("io.micronaut:micronaut-http-client")
}
```

**Validation Checks**:
- [ ] `micronaut-test-spock` present
- [ ] `spock-core` present with groovy-all exclusion
- [ ] `byte-buddy` present (version 1.17.8 or higher)
- [ ] `objenesis` present (version 3.4 or higher)
- [ ] `micronaut-http-client` present for controller tests

### 2. Check Test Resources Configuration

Verify TestResources is configured if database tests are needed:

**File**: `src/test/resources/application-test.yml`
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: your_test_db
      db-password: test_password
      db-username: test_user
```

**Validation**:
- [ ] `application-test.yml` exists
- [ ] `test-resources.enabled: true` is set
- [ ] Container configuration matches database type
- [ ] Base `application.yml` has NO datasource connection properties

### 3. Determine Test Layer

Identify which layer is being tested to apply the correct pattern:

**Repository Tests**:
- Test data access layer with real database
- Use TestContainers via TestResources
- Load schema with SchemaLoader utility
- Test actual SQL queries and constraints

**Service Tests**:
- Test business logic in isolation
- Mock all repository dependencies
- Focus on transaction boundaries
- Verify interaction counts

**Controller Tests**:
- Test HTTP request/response handling
- Use real HTTP client
- Mock service layer
- Test authentication and validation

### 4. Create SchemaLoader Utility (If Missing)

For repository tests, a SchemaLoader utility is needed to load test schema:

**File**: `src/test/groovy/com/[your-package]/infrastructure/SchemaLoader.groovy`

Check if SchemaLoader exists. If not, create it following the pattern in `examples.md`.

**Key features**:
- Handles PostgreSQL dollar-quoted functions (`$$`)
- Splits statements properly at semicolons
- Auto-commit mode for idempotent execution
- Ignores "already exists" errors for multiple test runs

### 5. Provide Layer-Specific Template

Based on the test layer, provide the appropriate template:

#### Repository Test Template

```groovy
package com.yourpackage.repositories

import com.yourpackage.infrastructure.SchemaLoader
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

import javax.sql.DataSource

@MicronautTest
class YourRepositorySpec extends Specification {

    @Inject
    YourRepository repository

    @Inject
    DataSource dataSource

    def setup() {
        // Load schema (idempotent)
        def schemaFile = new File("src/test/resources/db/schema.sql")
        SchemaLoader.loadSchema(dataSource, schemaFile)

        // Insert test data (use ON CONFLICT DO NOTHING for idempotency)
        dataSource.connection.withCloseable { conn ->
            conn.createStatement().execute("""
                INSERT INTO your_table (id, field1, field2)
                VALUES (1, 'value1', 'value2')
                ON CONFLICT (id) DO NOTHING
            """)
        }
    }

    void "test case description"() {
        when: "action occurs"
        def result = repository.yourMethod()

        then: "expected outcome"
        result != null
    }
}
```

**Key Points**:
- `@MicronautTest` annotation (no additional annotations needed)
- Inject `DataSource` for schema loading and test data
- Use `setup()` method (runs before each test)
- Load schema via SchemaLoader
- Insert test data with `ON CONFLICT DO NOTHING` for idempotency
- Test actual database operations

#### Service Test Template

```groovy
package com.yourpackage.services

import com.yourpackage.repositories.YourRepository
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

@MicronautTest
class YourServiceSpec extends Specification {

    @Inject
    YourService service

    @Inject
    YourRepository repository

    @MockBean(YourRepository)
    YourRepository mockRepository() {
        Mock(YourRepository)
    }

    void "test business logic with mocked repository"() {
        given: "repository returns expected data"
        def entity = Mock(YourEntity)
        repository.findById(1) >> Optional.of(entity)

        when: "service method is called"
        def result = service.yourMethod(1)

        then: "correct interaction with repository"
        1 * repository.findById(1)

        and: "business logic result is correct"
        result != null
    }

    void "test transaction rollback on error"() {
        given: "repository throws exception"
        repository.save(_) >> { throw new RuntimeException("DB error") }

        when: "service method is called"
        service.yourTransactionalMethod(data)

        then: "exception propagates"
        thrown(RuntimeException)
    }
}
```

**Key Points**:
- `@MicronautTest` annotation
- Inject both service (real) and repository (to be mocked)
- Use `@MockBean` factory method pattern (NOT `@MockBean` on field)
- Return `Mock(RepositoryClass)` from factory method
- Specify interaction counts (`1 * repository.method()`)
- Test transaction boundaries and error handling

#### Controller Test Template

```groovy
package com.yourpackage.controllers

import com.yourpackage.services.YourService
import io.micronaut.http.HttpRequest
import io.micronaut.http.HttpStatus
import io.micronaut.http.client.HttpClient
import io.micronaut.http.client.annotation.Client
import io.micronaut.http.client.exceptions.HttpClientResponseException
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

@MicronautTest
class YourControllerSpec extends Specification {

    @Inject
    @Client("/")
    HttpClient client

    @Inject
    YourService service

    @MockBean(YourService)
    YourService mockService() {
        Mock(YourService)
    }

    void "POST /endpoint accepts valid request"() {
        given: "a valid payload"
        def payload = [field1: "value1", field2: "value2"]

        and: "service processes successfully"
        service.process(payload) >> { /* mock response */ }

        and: "authenticated request"
        def request = HttpRequest.POST("/endpoint", payload)
            .basicAuth("username", "password")

        when: "making HTTP request"
        def response = client.toBlocking().exchange(request, Void)

        then: "returns expected status"
        response.status == HttpStatus.ACCEPTED

        and: "service was called"
        1 * service.process(payload)
    }

    void "returns 400 for invalid request"() {
        given: "invalid payload (missing required field)"
        def payload = [field1: "value1"]  // field2 missing

        and: "request"
        def request = HttpRequest.POST("/endpoint", payload)
            .basicAuth("username", "password")

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 400 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.BAD_REQUEST
    }

    void "returns 401 for unauthenticated request"() {
        given: "payload without authentication"
        def payload = [field1: "value1", field2: "value2"]
        def request = HttpRequest.POST("/endpoint", payload)

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 401 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.UNAUTHORIZED
    }
}
```

**Key Points**:
- `@MicronautTest` annotation
- Inject `@Client("/")` HttpClient for HTTP testing
- Mock service layer (NOT repository)
- Use `HttpRequest.POST()` or `.GET()` with `.basicAuth()` for authentication
- Use `client.toBlocking().exchange()` for synchronous requests
- Catch `HttpClientResponseException` for error status verification
- Test HTTP status codes, authentication, validation

### 6. Common Patterns and Best Practices

**Mock Factory Method Pattern** (REQUIRED):
```groovy
@Inject
YourRepository repository  // Inject to get reference

@MockBean(YourRepository)
YourRepository mockRepository() {
    Mock(YourRepository)  // Return mock from factory method
}
```

**DO NOT use field injection for mocks**:
```groovy
// ❌ WRONG - This doesn't work with Micronaut
@MockBean(YourRepository)
YourRepository repository = Mock()
```

**Interaction Verification**:
```groovy
// Verify exact call count
1 * repository.save(_)

// Verify with specific argument
1 * repository.findById(123)

// Verify no calls
0 * repository.delete(_)

// Capture argument for assertion
1 * repository.save(_ as Entity) >> { Entity entity ->
    assert entity.field == "expected"
    return entity
}
```

**Idempotent Test Data**:
```groovy
// Use ON CONFLICT DO NOTHING for repeatable tests
conn.createStatement().execute("""
    INSERT INTO table_name (id, name)
    VALUES (1, 'Test')
    ON CONFLICT (id) DO NOTHING
""")
```

**When Clause with And**:
```groovy
void "descriptive test name"() {
    when: "action description"
    def result = service.method()

    then: "first verification"
    result != null

    and: "second verification"
    result.field == "expected"
}
```

### 7. Two rules a green spec does not prove

- **A guard must be shown to fail.** For any spec written to pin a regression, revert the fix once
  and record which feature method went red; if none did, the assertion cannot express the failure
  (single-element fixture, status-only assertion, stub that never fires — see the repo `AGENTS.md`).
- **Fixtures for API payloads come from the contract, not the code.** Serialise the real DTO or
  capture a real response; never put a value for a `secret` field in a `fields` map, and use the
  serialised key names (snake_case under Micronaut Serde). Details: the `api-contract-fixtures`
  skill.

## Quality Checklist

**Dependencies**:
- [ ] `micronaut-test-spock` dependency present
- [ ] `spock-core` dependency present
- [ ] `byte-buddy` version 1.17.8+ present
- [ ] `objenesis` version 3.4+ present

**Test Configuration**:
- [ ] `application-test.yml` configured for TestResources (if using database)
- [ ] Base `application.yml` has NO connection properties
- [ ] Test resources enabled and container configured

**Test Structure**:
- [ ] Correct `@MicronautTest` annotation
- [ ] Proper injection pattern for dependencies
- [ ] Mock factory methods (NOT field injection)
- [ ] Layer-appropriate test strategy

**Repository Tests**:
- [ ] SchemaLoader utility exists
- [ ] Schema loaded in `setup()` method
- [ ] Test data inserted with idempotency
- [ ] Real database operations tested

**Service Tests**:
- [ ] Repository dependencies mocked
- [ ] Interaction counts verified
- [ ] Transaction boundaries tested
- [ ] Error handling tested

**Controller Tests**:
- [ ] HttpClient injected with `@Client("/")`
- [ ] Service layer mocked
- [ ] HTTP status codes verified
- [ ] Authentication tested

## When to Use This Skill

**Always use when**:
- Creating first Spock test in a new Micronaut project
- "Unable to proxy" or "cannot create mock" errors occur
- Setting up test infrastructure
- Team members unfamiliar with Micronaut test patterns

**Warning signs that indicate need**:
- Error: "Cannot create mock for class [RepositoryClass]"
- Error: "Unable to proxy instance of [RepositoryClass]"
- Error: "No suitable constructor found"
- Tests compile but fail at runtime with mocking errors
- TestContainers don't start for repository tests

**Preventative use**:
- Before writing first test
- During project setup
- When onboarding new developers
- After adding new test layer (repository/service/controller)

## Special Cases

**Multiple Mock Beans**:
```groovy
@Inject
FirstRepository firstRepository

@Inject
SecondRepository secondRepository

@MockBean(FirstRepository)
FirstRepository mockFirstRepository() {
    Mock(FirstRepository)
}

@MockBean(SecondRepository)
SecondRepository mockSecondRepository() {
    Mock(SecondRepository)
}
```

**Mixed Real and Mock Dependencies**:
```groovy
// Use real service, mock repositories
@Inject
YourService service  // Real implementation

@Inject
FirstRepository firstRepository

@Inject
SecondRepository secondRepository

@MockBean(FirstRepository)
FirstRepository mockFirst() { Mock(FirstRepository) }

@MockBean(SecondRepository)
SecondRepository mockSecond() { Mock(SecondRepository) }
```

**Custom Test Configuration**:
```groovy
@MicronautTest
@Property(name = "custom.property", value = "test-value")
class CustomConfigSpec extends Specification {
    // Tests with custom property override
}
```

**Transactional Test Context** (when needed):
```groovy
@MicronautTest(transactional = false)  // Disable test transaction wrapper
class NonTransactionalSpec extends Specification {
    // Useful for testing @Transactional boundaries
}
```

## Troubleshooting

**Issue**: "Cannot create mock for class X"
**Solution**: Verify `byte-buddy` and `objenesis` are in `testRuntimeOnly` dependencies

**Issue**: "No bean of type [Repository] exists"
**Solution**: Check `@MockBean` factory method returns `Mock(RepositoryClass)`, not `Mock()`

**Issue**: TestContainers don't start
**Solution**: Run test-resources-validator skill to check configuration

**Issue**: Schema not loading or "relation does not exist"
**Solution**: Verify SchemaLoader is called in `setup()` method before test data insertion

**Issue**: Tests fail intermittently
**Solution**: Ensure test data uses `ON CONFLICT DO NOTHING` for idempotency

---

For complete test examples, see `examples.md`
For dependency version reference, see `reference.md`
