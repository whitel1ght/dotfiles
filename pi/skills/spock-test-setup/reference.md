# Spock Test Setup Reference

Technical reference for Spock testing with Micronaut, including dependency versions, configuration details, and framework documentation links.

## Required Dependencies

### Core Testing Framework

```groovy
testImplementation("io.micronaut.test:micronaut-test-spock")
```
- Provides Micronaut integration for Spock
- Includes `@MicronautTest` annotation
- Handles dependency injection in tests
- Manages test context lifecycle

```groovy
testImplementation("org.spockframework:spock-core") {
    exclude group: "org.codehaus.groovy", module: "groovy-all"
}
```
- Spock BDD testing framework
- Exclude `groovy-all` to avoid version conflicts with Gradle's Groovy
- Provides Specification base class and Groovy DSL

### Critical Mocking Dependencies

**Without these, you cannot mock concrete classes:**

```groovy
testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'
```
- **Purpose**: Enables dynamic proxy creation for concrete classes
- **Without it**: Can only mock interfaces, not classes
- **Error without it**: "Cannot create mock for class [ClassName]"
- **Minimum version**: 1.17.8 (compatible with Java 17+)
- **Scope**: Must be `testRuntimeOnly` (not `testImplementation`)

```groovy
testRuntimeOnly "org.objenesis:objenesis:3.4"
```
- **Purpose**: Allows instantiating objects without calling constructors
- **Without it**: Cannot mock classes without no-arg constructors
- **Error without it**: "Unable to proxy instance" or "No suitable constructor"
- **Minimum version**: 3.4
- **Scope**: Must be `testRuntimeOnly`
- **Works with**: ByteBuddy or CGLIB for complete mocking support

### HTTP Testing

```groovy
testImplementation("io.micronaut:micronaut-http-client")
```
- Required for controller/HTTP integration tests
- Provides `HttpClient` for making test requests
- Handles serialization/deserialization
- Supports authentication and custom headers

## Version Compatibility Matrix

| Component | Version | Java | Notes |
|-----------|---------|------|-------|
| Micronaut | 4.10.0 | 17+ | LTS version |
| Spock | 2.x | 17+ | Requires Groovy 4.x |
| ByteBuddy | 1.17.8+ | 17+ | Earlier versions may not work with Java 17 |
| Objenesis | 3.4+ | 17+ | Required for constructor-less mocking |
| Groovy | 4.x | 17+ | Bundled with Gradle 8.x |

## Annotation Reference

### @MicronautTest

```groovy
@MicronautTest
```
**Default behavior**:
- Starts embedded application context
- Enables dependency injection in tests
- Wraps each test method in a transaction (rollback after test)
- Enables TestResources if configured

**Options**:
```groovy
@MicronautTest(transactional = false)
```
- Disable automatic transaction wrapping
- Useful for testing transaction boundaries in services

```groovy
@MicronautTest(rebuildContext = true)
```
- Rebuild application context for each test method
- Slower but ensures complete isolation
- Use when tests modify shared state

```groovy
@MicronautTest(environments = ["test", "custom"])
```
- Specify active environments
- Loads application-{env}.yml files

### @MockBean

```groovy
@MockBean(RepositoryClass)
RepositoryClass mockRepository() {
    Mock(RepositoryClass)
}
```
**How it works**:
- Replaces real bean with mock in application context
- Factory method pattern (REQUIRED, field injection won't work)
- Must return `Mock(ClassName)` from method
- Method name doesn't matter (convention: `mock{BeanName}()`)

**Multiple mock beans**:
```groovy
@Inject FirstRepository first
@Inject SecondRepository second

@MockBean(FirstRepository)
FirstRepository mockFirst() { Mock(FirstRepository) }

@MockBean(SecondRepository)
SecondRepository mockSecond() { Mock(SecondRepository) }
```

### @Client

```groovy
@Inject
@Client("/")
HttpClient client
```
**Purpose**: Inject HTTP client for controller tests
**Path options**:
- `@Client("/")` - Root path (most common)
- `@Client("/api")` - Base path for all requests
- `@Client("http://localhost:8080")` - Full URL

### @Property

```groovy
@Property(name = "webhook.postmark.password", value = "test-secret")
```
**Purpose**: Override configuration properties for specific test
**Scope**: Applied to test class or method
**Use cases**:
- Test-specific configuration
- Override default values
- Test different property scenarios

## Spock Interaction Syntax

### Cardinality

```groovy
1 * repository.method()        // Exactly once
0 * repository.method()        // Never called
2 * repository.method()        // Exactly twice
(1..3) * repository.method()   // 1 to 3 times
(1.._) * repository.method()   // At least once
(_..3) * repository.method()   // At most 3 times
_ * repository.method()        // Any number of times (including zero)
```

### Argument Matching

```groovy
1 * repository.save(_)                    // Any argument
1 * repository.save(null)                 // Null argument
1 * repository.save(!null)                // Non-null argument
1 * repository.save(_ as Entity)          // Argument of specific type
1 * repository.findById(123)              // Specific value
1 * repository.findByName("test")         // Specific string
1 * repository.method(_, !null)           // Multiple arguments
1 * repository.method({ it.id == 1 })     // Closure constraint
```

### Return Values

```groovy
repository.findById(1) >> entity                    // Return value
repository.findById(1) >> Optional.of(entity)       // Return Optional
repository.findById(1) >> Optional.empty()          // Return empty Optional
repository.save(_) >> { Entity e -> e }             // Return argument
repository.save(_) >> { Entity e ->                 // Closure with assertions
    assert e.field == "expected"
    return e
}
repository.method() >> [item1, item2]               // Return collection
repository.method() >>> [result1, result2, result3] // Sequence of returns
repository.method() >> { throw new Exception() }    // Throw exception
```

### Multiple Interactions

```groovy
then:
1 * repository.findById(1) >> Optional.of(entity)
1 * repository.save(_) >> entity
0 * repository.delete(_)
```

### Ordered Interactions

```groovy
then: "first operation"
1 * firstRepository.method()

then: "second operation (after first)"
1 * secondRepository.method()
```

## Test Block Structure

### Standard Test Structure

```groovy
void "test description"() {
    given: "setup description"
    def variable = setupValue

    when: "action description"
    def result = service.method(variable)

    then: "verification description"
    result == expectedValue
}
```

### With And Blocks

```groovy
void "test with multiple verifications"() {
    given: "first setup"
    def setup1 = value1

    and: "additional setup"
    def setup2 = value2

    when: "action occurs"
    def result = service.method(setup1, setup2)

    then: "first verification"
    result != null

    and: "second verification"
    result.field == "expected"
}
```

### With Where Block (Data-Driven)

```groovy
void "test multiple scenarios"() {
    expect:
    service.calculate(input) == output

    where:
    input | output
    0     | 0
    1     | 10
    5     | 50
}
```

### Setup and Cleanup

```groovy
def setup() {
    // Runs before each test method
}

def cleanup() {
    // Runs after each test method
}

def setupSpec() {
    // Runs once before all tests
}

def cleanupSpec() {
    // Runs once after all tests
}
```

## TestResources Configuration

### application-test.yml Structure

```yaml
test-resources:
  enabled: true  # REQUIRED to enable TestResources
  containers:
    postgres:
      image: postgres:16  # Optional: specify version
      db-name: test_db    # Required: database name
      db-username: test   # Required: username
      db-password: test   # Required: password
```

### Supported Databases

**PostgreSQL**:
```yaml
test-resources:
  containers:
    postgres:
      image: postgres:16
      db-name: test_db
      db-username: test
      db-password: test
```

**MySQL**:
```yaml
test-resources:
  containers:
    mysql:
      image: mysql:8.0
      db-name: test_db
      db-username: test
      db-password: test
```

**MariaDB**:
```yaml
test-resources:
  containers:
    mariadb:
      image: mariadb:11
      db-name: test_db
      db-username: test
      db-password: test
```

## HttpClient API Reference

### Making Requests

```groovy
// GET request
def request = HttpRequest.GET("/api/resource")
def response = client.toBlocking().exchange(request, ResponseType)

// POST request
def payload = [field: "value"]
def request = HttpRequest.POST("/api/resource", payload)
def response = client.toBlocking().exchange(request, ResponseType)

// PUT request
def request = HttpRequest.PUT("/api/resource/1", payload)
def response = client.toBlocking().exchange(request, ResponseType)

// DELETE request
def request = HttpRequest.DELETE("/api/resource/1")
def response = client.toBlocking().exchange(request, Void)
```

### Authentication

```groovy
// Basic authentication
def request = HttpRequest.POST("/api/resource", payload)
    .basicAuth("username", "password")

// Bearer token
def request = HttpRequest.GET("/api/resource")
    .bearerAuth("token-value")

// Custom header
def request = HttpRequest.GET("/api/resource")
    .header("X-Custom-Header", "value")
```

### Response Handling

```groovy
// Get response with body
def response = client.toBlocking().exchange(request, String)
def body = response.body()
def status = response.status

// No response body expected
def response = client.toBlocking().exchange(request, Void)
def status = response.status

// Retrieve as specific type
def response = client.toBlocking().exchange(request, EntityClass)
def entity = response.body()
```

### Error Handling

```groovy
try {
    client.toBlocking().exchange(request, Void)
} catch (HttpClientResponseException ex) {
    ex.status == HttpStatus.NOT_FOUND
    ex.response.body() // Error response body if present
}
```

## PostgreSQL Schema Loading

### ON CONFLICT Pattern for Idempotency

```sql
-- Insert with idempotency (won't fail if record exists)
INSERT INTO table_name (id, field1, field2)
VALUES (1, 'value1', 'value2')
ON CONFLICT (id) DO NOTHING;

-- Update on conflict
INSERT INTO table_name (id, field1, field2)
VALUES (1, 'value1', 'value2')
ON CONFLICT (id) DO UPDATE
SET field1 = EXCLUDED.field1,
    field2 = EXCLUDED.field2;
```

### Dollar-Quoted Functions

```sql
-- PostgreSQL function with dollar quotes
CREATE OR REPLACE FUNCTION my_function()
RETURNS void AS $$
BEGIN
    -- Function body
    -- Can contain semicolons without ending statement
    INSERT INTO table VALUES (1, 'test');
    UPDATE table SET field = 'value';
END;
$$ LANGUAGE plpgsql;
```

## Common Errors and Solutions

### Error: "Cannot create mock for class X"

**Cause**: Missing ByteBuddy dependency
**Solution**:
```groovy
testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'
```

### Error: "Unable to proxy instance of X"

**Cause**: Missing Objenesis dependency or wrong scope
**Solution**:
```groovy
testRuntimeOnly "org.objenesis:objenesis:3.4"
```

### Error: "No bean of type [Repository] exists"

**Cause**: Incorrect @MockBean usage (field injection instead of factory method)
**Solution**:
```groovy
// ❌ WRONG
@MockBean(Repository)
Repository repository = Mock()

// ✅ CORRECT
@Inject
Repository repository

@MockBean(Repository)
Repository mockRepository() {
    Mock(Repository)
}
```

### Error: "Too few invocations" or "Too many invocations"

**Cause**: Interaction count mismatch
**Solution**: Verify expected call count matches actual calls
```groovy
// Check what was actually called
then:
(0..1) * repository.method()  // Allow 0 or 1 call instead of exact count
```

### Error: "TestContainers not starting"

**Cause**: Configuration has datasource connection properties
**Solution**: Remove `url`, `username`, `password` from `application.yml` (keep only in `application-prod.yml`)

## Documentation Links

### Official Documentation

- **Micronaut Test**: https://micronaut-projects.github.io/micronaut-test/latest/guide/
- **Spock Framework**: https://spockframework.org/spock/docs/2.3/all_in_one.html
- **Micronaut TestResources**: https://micronaut-projects.github.io/micronaut-test-resources/latest/guide/
- **ByteBuddy**: https://bytebuddy.net/
- **Objenesis**: http://objenesis.org/

### Related Skills

- **test-resources-validator**: Validate TestResources configuration
- **verify-library-api**: Verify external library methods before mocking
- **transaction-boundary-validator**: Ensure @Transactional only on services

## Gradle Plugin Configuration

### Required Plugins

```groovy
plugins {
    id("groovy")
    id("io.micronaut.application") version "4.6.0"
    id("io.micronaut.test-resources") version "4.6.0"
}
```

### `micronaut { runtime + testRuntime }` Block (Mandatory for `@Client` Specs)

The `io.micronaut.application` plugin (4.6.x) does NOT pull in an embedded HTTP server unless build.gradle declares this block:

```groovy
micronaut {
    runtime("netty")
    testRuntime("spock2")
}
```

Without it, `micronaut-http-server-netty` is missing, no `EmbeddedServer` bean is created, and `@MicronautTest(startApplication = true)` fails to inject `@Client("/")` with the misleading message: `Invalid service reference [/] specified to @Client`. The `testRuntime("spock2")` half is also load-bearing — without it some Spock-Micronaut wiring is missing. Always grep the build for a `micronaut {}` block before writing the first controller spec.

## `@MicronautTest(startApplication = ...)` Default

`@MicronautTest` defaults to `startApplication = false`. For controller specs that use `@Client("/")`, `startApplication = true` is mandatory — the implicit "client triggers server" behavior from older Micronaut versions does not apply in Micronaut 4. Setting it on the test class:

```groovy
@MicronautTest(startApplication = true)
class MyControllerSpec extends Specification { ... }
```

For service-only specs that don't need the HTTP server, leave the default `false` (faster context startup).

## Mocking Repositories with Conflicting Erased Return Types

When a repository extends multiple parent interfaces declaring the same method with different return types after erasure (e.g., `DocumentRepository extends BaseTenantModelRepository<CourtDocument>, StoredDocumentModelRepository<CourtDocument>` — both declare `getById(Firm, PublicId)` with different bounds), Spock `Mock()`, `Stub()`, and `GroovyMock()` ALL fail because JDK dynamic proxies cannot reconcile conflicting return types.

**Fix inside `@MicronautTest`**: use a concrete `@Singleton @Replaces(Repo)` static inner stub class.

```groovy
@MicronautTest(startApplication = false)
class IManageCloudProviderSpec extends Specification {

    @Inject ApplicationContext applicationContext
    @Inject StubDocumentRepository stubDocumentRepository

    void "test method"() {
        given:
        stubDocumentRepository.forInboxItemResult = [doc1, doc2]
        // ...
    }

    @Singleton
    @Replaces(DocumentRepository)
    static class StubDocumentRepository implements DocumentRepository {
        List<CourtDocument> forInboxItemResult = []
        // implement methods, mutate fields per-test
    }
}
```

**Outside `@MicronautTest`**: use a plain concrete stub class — no `@Replaces` annotation needed.

## Spock Mocks with Reactor Schedulers — Don't Mix

Spock mocks return DEFAULT values (null/empty) instead of stubbed responses when the mocked service method is invoked from a Reactor scheduler thread (`Schedulers.single()`, `Schedulers.parallel()`). The mock invocation succeeds but the stub doesn't fire.

**Fix**: for thread-safety tests with mocked dependencies, use plain `Thread + join()` instead of Reactor schedulers:

```groovy
def thread = new Thread({ service.method() })
thread.start()
thread.join()
```

## Spock Interaction Block Placement

Stubs and interaction expectations MUST live in the `then:` (or `setup:`) block, NOT in `when:`. Spock processes `then:` interaction declarations BEFORE executing `when:`, so:

```groovy
when:
service.method()        // Stub already active here

then:
1 * mock.dependency() >> stubbedResult     // ← stub IS set up before when: runs
```

Putting the stub in `when:` causes the stub never to be applied — the call hits the un-stubbed mock and gets default values.

## `HttpClientResponseException` Constructor — Mock Carefully

`HttpClientResponseException` constructor calls `initResponse()`, which calls `getErrorType()`, which accesses `response.getContentType()`. If you pass a mock response that returns `null` for `getStatus()` or `getContentType()`, the constructor itself NPEs during construction.

**Fix**: for edge cases like null status, mock the exception ITSELF instead of trying to construct one with a partially-mocked response:

```groovy
def ex = Mock(HttpClientResponseException) {
    getStatus() >> null
    response.getBody(_) >> Optional.empty()
}
service.httpClient.exchange(_, _) >> { throw ex }
```

For "real" exceptions, use `HttpResponse.status(HttpStatus.valueOf(code))` as the response argument — this satisfies the internal chain.

### Source Sets

Gradle automatically configures:
- `src/test/groovy` - Spock specifications
- `src/test/java` - Java test code
- `src/test/resources` - Test configuration and schema files

## Performance Considerations

### Test Execution Speed

**Fast** (milliseconds):
- Unit tests with mocked dependencies
- Service tests with mocked repositories
- Tests without database or HTTP

**Medium** (1-2 seconds):
- Repository tests with TestContainers
- First test in suite (container startup)
- HTTP integration tests

**Slow** (multiple seconds):
- Tests with `rebuildContext = true`
- Tests that modify application context
- Multiple TestContainer databases

### Optimization Tips

1. **Reuse TestContainers**: TestResources shares containers across tests
2. **Use `@MicronautTest` default**: Transactional tests roll back automatically
3. **Group similar tests**: Keep tests in same class to share context
4. **Mock aggressively**: Service tests should mock all repositories
5. **Parallel execution**: Gradle can run test classes in parallel

```groovy
// In build.gradle
test {
    maxParallelForks = Runtime.runtime.availableProcessors().intdiv(2) ?: 1
}
```
