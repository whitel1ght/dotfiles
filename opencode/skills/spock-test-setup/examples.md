# Spock Test Setup Examples

Complete examples of Spock tests for Micronaut projects, covering all three testing layers.

## Complete Repository Test Example

```groovy
package com.goecfx.repositories

import com.goecfx.infrastructure.SchemaLoader
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

import javax.sql.DataSource

/**
 * Test specification for FirmRepository with database integration.
 * Tests run against TestContainers PostgreSQL instance.
 */
@MicronautTest
class FirmRepositorySpec extends Specification {

    @Inject
    FirmRepository repository

    @Inject
    DataSource dataSource

    def setup() {
        // Load schema for testing (idempotent)
        def schemaFile = new File("src/test/resources/db/schema.sql")
        SchemaLoader.loadSchema(dataSource, schemaFile)

        // Insert encryption key (required FK, idempotent with ON CONFLICT)
        dataSource.connection.withCloseable { conn ->
            conn.createStatement().execute("""
                INSERT INTO private.encryption_key (id)
                VALUES ('00000000-0000-0000-0000-000000000001'::uuid)
                ON CONFLICT (id) DO NOTHING
            """)
        }

        // Insert test firms (idempotent with ON CONFLICT)
        dataSource.connection.withCloseable { conn ->
            conn.createStatement().execute("""
                INSERT INTO private.firm (id, subdomain, active, encryption_key_id, name)
                VALUES
                    (1, 'acme', true, '00000000-0000-0000-0000-000000000001'::uuid, 'ACME Corp'),
                    (2, 'TestFirm', true, '00000000-0000-0000-0000-000000000001'::uuid, 'Test Firm Inc'),
                    (3, 'inactive-firm', false, '00000000-0000-0000-0000-000000000001'::uuid, 'Inactive Firm')
                ON CONFLICT (id) DO NOTHING
            """)
        }
    }

    void "finds active firm by exact subdomain match"() {
        when: "querying for active firm by exact subdomain"
        def result = repository.findBySubdomainIgnoreCaseAndActiveTrue('acme')

        then: "returns the firm"
        result.isPresent()
        result.get().subdomain == 'acme'
        result.get().name == 'ACME Corp'
        result.get().active == true
    }

    void "finds active firm by case-insensitive subdomain"() {
        when: "querying with different case"
        def result = repository.findBySubdomainIgnoreCaseAndActiveTrue('testfirm')

        then: "returns the firm regardless of case"
        result.isPresent()
        result.get().subdomain == 'TestFirm'
        result.get().name == 'Test Firm Inc'
        result.get().active == true
    }

    void "returns empty Optional when firm exists but is inactive"() {
        when: "querying for inactive firm"
        def result = repository.findBySubdomainIgnoreCaseAndActiveTrue('inactive-firm')

        then: "returns empty Optional"
        !result.isPresent()
    }

    void "returns empty Optional when subdomain doesn't exist"() {
        when: "querying for non-existent subdomain"
        def result = repository.findBySubdomainIgnoreCaseAndActiveTrue('nonexistent')

        then: "returns empty Optional"
        !result.isPresent()
    }

    void "handles null subdomain gracefully"() {
        when: "querying with null subdomain"
        repository.findBySubdomainIgnoreCaseAndActiveTrue(null)

        then: "throws IllegalArgumentException"
        def ex = thrown(IllegalArgumentException)
        ex.message.contains("Argument [subdomain] value is null")
    }
}
```

**Key Features**:
- `@MicronautTest` with no additional configuration
- `setup()` method loads schema and inserts test data
- `ON CONFLICT DO NOTHING` ensures idempotency
- Tests actual database queries
- Verifies Optional return types
- Tests error conditions (null handling)

## Complete Service Test Example

```groovy
package com.goecfx.services

import com.goecfx.data.entities.documents.EmailInboxItem
import com.goecfx.data.entities.Firm
import com.goecfx.data.entities.workflow.InboxItemProcessJob
import com.goecfx.repositories.InboxItemRepository
import com.goecfx.repositories.InboxItemProcessJobRepository
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * Test specification for EmailProcessingService with mocked dependencies.
 * Tests business logic for email inbox item creation and job setup.
 */
@MicronautTest
class EmailProcessingServiceSpec extends Specification {

    @Inject
    EmailProcessingService service

    @Inject
    InboxItemRepository inboxItemRepository

    @Inject
    InboxItemProcessJobRepository jobRepository

    @MockBean(InboxItemRepository)
    InboxItemRepository mockInboxItemRepository() {
        Mock(InboxItemRepository)
    }

    @MockBean(InboxItemProcessJobRepository)
    InboxItemProcessJobRepository mockJobRepository() {
        Mock(InboxItemProcessJobRepository)
    }

    void "processes email and creates job successfully"() {
        given: "a firm and raw email content"
        def firm = createTestFirm()
        def rawEmail = """From: sender@example.com
To: recipient@example.com
Subject: Test Email
Content-Type: text/plain

Test email body content"""

        and: "mocks for saved entities"
        def mockSavedInboxItem = Mock(EmailInboxItem) {
            getId() >> UUID.randomUUID()
        }
        def mockJob = Mock(InboxItemProcessJob)

        when: "processing the email"
        def result = service.processEmail(firm, rawEmail)

        then: "inbox item is saved with correct data"
        1 * inboxItemRepository.save(_ as EmailInboxItem) >> { EmailInboxItem item ->
            assert item.firmId == firm.id
            assert item.rawContent == rawEmail
            return mockSavedInboxItem
        }

        and: "job is created and saved"
        1 * jobRepository.save(_ as InboxItemProcessJob) >> { InboxItemProcessJob job ->
            assert job.parent == mockSavedInboxItem
            assert job.firmId == firm.id
            return mockJob
        }

        and: "returns the saved inbox item"
        result == mockSavedInboxItem
    }

    void "handles null firm gracefully"() {
        given: "null firm"
        def rawEmail = "From: test@example.com\n\nTest"

        when: "processing with null firm"
        service.processEmail(null, rawEmail)

        then: "exception is thrown"
        def exception = thrown(Exception)
        exception instanceof IllegalArgumentException || exception instanceof NullPointerException

        and: "no repository calls are made"
        0 * inboxItemRepository.save(_)
        0 * jobRepository.save(_)
    }

    void "ensures transactional behavior - rollback on job save failure"() {
        given: "a firm and raw email content"
        def firm = createTestFirm()
        def rawEmail = """From: sender@example.com
To: recipient@example.com
Subject: Test Email

Test email body content"""

        and: "mock saved inbox item"
        def mockSavedInboxItem = Mock(EmailInboxItem) {
            getId() >> UUID.randomUUID()
        }

        when: "processing email but job save fails"
        service.processEmail(firm, rawEmail)

        then: "inbox item is saved"
        1 * inboxItemRepository.save(_ as EmailInboxItem) >> mockSavedInboxItem

        and: "job save throws exception"
        1 * jobRepository.save(_) >> { throw new RuntimeException("Database error") }

        and: "exception propagates"
        thrown(RuntimeException)
    }

    void "handles empty string raw email"() {
        given: "a firm and empty string email"
        def firm = createTestFirm()
        def emptyEmail = ""

        when: "processing with empty email"
        service.processEmail(firm, emptyEmail)

        then: "IllegalArgumentException is thrown"
        def exception = thrown(IllegalArgumentException)
        exception.message.contains("cannot be null or empty")

        and: "no repository calls are made"
        0 * inboxItemRepository.save(_)
        0 * jobRepository.save(_)
    }

    void "preserves exact raw email content including special characters"() {
        given: "a firm and email with special characters"
        def firm = createTestFirm()
        def specialEmail = """From: test@example.com
Subject: Test with special chars
Content: <html><body>Special: & < > " ' % \$ # @</body></html>"""

        and: "mock saved item"
        def mockSavedInboxItem = Mock(EmailInboxItem)

        when: "processing email with special characters"
        def result = service.processEmail(firm, specialEmail)

        then: "inbox item preserves exact content"
        1 * inboxItemRepository.save(_ as EmailInboxItem) >> { EmailInboxItem item ->
            assert item.rawContent == specialEmail
            return mockSavedInboxItem
        }

        and: "job is saved"
        1 * jobRepository.save(_ as InboxItemProcessJob) >> Mock(InboxItemProcessJob)

        and: "processing succeeds"
        result == mockSavedInboxItem
    }

    // Helper methods

    private Firm createTestFirm() {
        def firm = new Firm()
        firm.setId(1)
        firm.setName("Test Firm")
        return firm
    }
}
```

**Key Features**:
- Mock factory methods for both repositories
- Interaction verification with exact counts
- Argument capture for assertion (`_ as Type`)
- Transaction boundary testing
- Error condition testing
- Helper method for test data creation

## Complete Controller Test Example

```groovy
package com.goecfx.controllers

import com.goecfx.data.entities.Firm
import com.goecfx.repositories.FirmRepository
import com.goecfx.services.EmailProcessingService
import io.micronaut.http.HttpRequest
import io.micronaut.http.HttpStatus
import io.micronaut.http.client.HttpClient
import io.micronaut.http.client.annotation.Client
import io.micronaut.http.client.exceptions.HttpClientResponseException
import io.micronaut.test.annotation.MockBean
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * HTTP integration test specification for PostmarkController.
 *
 * Tests the complete HTTP request/response cycle for Postmark webhook endpoints,
 * including authentication, subdomain extraction, firm lookup, and service delegation.
 */
@MicronautTest
class PostmarkControllerSpec extends Specification {

    @Inject
    @Client("/")
    HttpClient client

    @Inject
    FirmRepository firmRepository

    @Inject
    EmailProcessingService emailProcessingService

    @MockBean(FirmRepository)
    FirmRepository mockFirmRepository() {
        Mock(FirmRepository)
    }

    @MockBean(EmailProcessingService)
    EmailProcessingService mockEmailProcessingService() {
        Mock(EmailProcessingService)
    }

    void "POST /api/postmark/receipts accepts valid webhook"() {
        given: "a valid Postmark inbound email payload"
        def payload = [
            From: "sender@example.com",
            To: "receipts@acme.goecfx.com",
            Subject: "Receipt from Store",
            RawEmail: "MIME-Version: 1.0\r\nFrom: sender@example.com\r\n..."
        ]

        and: "firm exists for subdomain"
        def firm = new Firm()
        firm.id = 1
        firm.subdomain = "acme"
        firm.active = true
        firmRepository.findBySubdomainIgnoreCaseAndActiveTrue("acme") >> Optional.of(firm)

        and: "service processes successfully"
        emailProcessingService.processEmail(firm, payload.RawEmail) >> { }

        and: "authenticated request"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "test-postmark-secret")

        when: "making HTTP request"
        def response = client.toBlocking().exchange(request, Void)

        then: "returns 202 Accepted"
        response.status == HttpStatus.ACCEPTED

        and: "service was called with correct parameters"
        1 * emailProcessingService.processEmail(firm, payload.RawEmail)
    }

    void "POST /api/postmark/receipts returns 404 when firm subdomain not found"() {
        given: "a valid payload but firm does not exist"
        def payload = [
            From: "sender@example.com",
            To: "receipts@nonexistent.goecfx.com",
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "firm not found"
        firmRepository.findBySubdomainIgnoreCaseAndActiveTrue("nonexistent") >> Optional.empty()

        and: "authenticated request"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "test-postmark-secret")

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 404 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.NOT_FOUND

        and: "service was not called"
        0 * emailProcessingService.processEmail(_, _)
    }

    void "handles uppercase subdomain in email address"() {
        given: "payload with uppercase subdomain"
        def payload = [
            From: "sender@example.com",
            To: "receipts@ACME.goecfx.com",
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "firm exists (case-insensitive match)"
        def firm = new Firm()
        firm.id = 1
        firm.subdomain = "acme"
        firm.active = true

        and: "authenticated request"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "test-postmark-secret")

        when: "making HTTP request"
        def response = client.toBlocking().exchange(request, Void)

        then: "case-insensitive lookup works"
        response.status == HttpStatus.ACCEPTED
        1 * firmRepository.findBySubdomainIgnoreCaseAndActiveTrue("ACME") >> Optional.of(firm)
        1 * emailProcessingService.processEmail(firm, payload.RawEmail)
    }

    void "returns 400 Bad Request when To field is missing"() {
        given: "payload with missing To field"
        def payload = [
            From: "sender@example.com",
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "authenticated request"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "test-postmark-secret")

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 400 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.BAD_REQUEST
    }

    void "returns 401 Unauthorized when credentials are invalid"() {
        given: "valid payload"
        def payload = [
            From: "sender@example.com",
            To: "receipts@acme.goecfx.com",
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "request with wrong credentials"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "wrong-password")

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 401 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.UNAUTHORIZED
    }

    void "returns 401 Unauthorized when no authentication provided"() {
        given: "valid payload without authentication"
        def payload = [
            From: "sender@example.com",
            To: "receipts@acme.goecfx.com",
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "request without authentication"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 401 status"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.UNAUTHORIZED
    }

    void "returns 500 when email address format is invalid"() {
        given: "payload with invalid email format (missing @)"
        def payload = [
            From: "sender@example.com",
            To: "receipts-acme.goecfx.com",  // Missing @
            Subject: "Receipt",
            RawEmail: "MIME-Version: 1.0\r\n..."
        ]

        and: "authenticated request"
        def request = HttpRequest.POST("/api/postmark/receipts", payload)
            .basicAuth("postmark", "test-postmark-secret")

        when: "making HTTP request"
        client.toBlocking().exchange(request, Void)

        then: "throws exception with 500 status (IllegalArgumentException)"
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.INTERNAL_SERVER_ERROR
    }
}
```

**Key Features**:
- `@Client("/")` injection for HTTP client
- Mock both repository and service layers
- Use `HttpRequest.POST()` with `.basicAuth()`
- Use `client.toBlocking().exchange()` for requests
- Catch `HttpClientResponseException` for error status codes
- Test authentication (401), validation (400), not found (404)
- Verify service interaction counts

## SchemaLoader Utility (Complete Implementation)

```groovy
package com.goecfx.infrastructure

import io.micronaut.context.ApplicationContext
import javax.sql.DataSource
import java.sql.Connection

/**
 * Utility for loading PostgreSQL schema files that may contain
 * dollar-quoted functions and multiple statements.
 */
class SchemaLoader {

    private static DataSource cachedDataSource

    /**
     * Convenience method that loads schema from classpath resource path.
     * Uses the shared BeanContext to get DataSource.
     */
    static void loadSchema(String resourcePath) {
        // Get DataSource from shared context (Micronaut Test creates this)
        if (cachedDataSource == null) {
            def contexts = ApplicationContext.getContexts()
            if (contexts.isEmpty()) {
                throw new IllegalStateException("No ApplicationContext running")
            }
            cachedDataSource = contexts[0].getBean(DataSource)
        }

        def schemaFile = new File(SchemaLoader.class.getResource(resourcePath).toURI())
        loadSchema(cachedDataSource, schemaFile)
    }

    /**
     * Executes a SQL file statement-by-statement.
     * Properly handles dollar quotes ($$) used in PostgreSQL functions.
     */
    static void loadSchema(DataSource dataSource, File schemaFile) {
        def connection = dataSource.connection
        def originalAutoCommit = connection.autoCommit
        connection.autoCommit = true  // Auto-commit for idempotent execution

        try {
            def statements = splitSqlStatements(schemaFile.text)
            statements.each { sql ->
                try {
                    connection.createStatement().execute(sql)
                } catch (Exception e) {
                    // Ignore idempotency errors
                    def ignorableErrors = [
                        "already exists",
                        "multiple primary keys",
                        "multiple unique keys",
                        "constraint .* already exists",
                        "relation .* already exists"
                    ]
                    def shouldIgnore = ignorableErrors.any { pattern ->
                        e.message ==~ /.*${pattern}.*/
                    }

                    if (!shouldIgnore) {
                        println "Error executing SQL: ${sql.take(100)}..."
                        throw e
                    }
                }
            }
        } finally {
            connection.autoCommit = originalAutoCommit
            connection.close()
        }
    }

    /**
     * Splits SQL file into individual statements, properly handling:
     * - Dollar quotes ($$)
     * - Comments (-- and /* */)
     * - Multi-line statements
     */
    private static List<String> splitSqlStatements(String sql) {
        def statements = []
        def currentStatement = new StringBuilder()
        def inDollarQuote = false
        def lines = sql.split('\n')

        for (line in lines) {
            def trimmed = line.trim()

            // Skip empty lines and comments
            if (!trimmed || trimmed.startsWith('--')) continue

            // Track dollar quotes
            if (trimmed.contains('$$')) {
                inDollarQuote = !inDollarQuote
            }

            currentStatement.append(line).append('\n')

            // Statement ends with semicolon (but not inside dollar quote)
            if (trimmed.endsWith(';') && !inDollarQuote) {
                def stmt = currentStatement.toString().trim()
                if (stmt) {
                    statements.add(stmt)
                }
                currentStatement = new StringBuilder()
            }
        }

        // Add any remaining statement
        def remaining = currentStatement.toString().trim()
        if (remaining) {
            statements.add(remaining)
        }

        return statements
    }
}
```

**Key Features**:
- Handles PostgreSQL dollar-quoted functions (`$$`)
- Splits statements at semicolons (respecting dollar quotes)
- Ignores "already exists" errors for idempotency
- Auto-commit mode prevents transaction abortion
- Can be used with classpath resources or File objects

## build.gradle Dependencies Section

```groovy
dependencies {
    // ECFX Data Library (if using CodeArtifact)
    implementation("com.goecfx:data:0.2.1")

    // Annotation processors
    annotationProcessor("org.projectlombok:lombok")
    annotationProcessor("io.micronaut.data:micronaut-data-processor")
    annotationProcessor("io.micronaut:micronaut-http-validation")
    annotationProcessor("io.micronaut.serde:micronaut-serde-processor")
    annotationProcessor("io.micronaut.security:micronaut-security-annotations")
    annotationProcessor("io.micronaut.validation:micronaut-validation-processor")

    // Core dependencies
    implementation("io.micronaut:micronaut-management")
    implementation("io.micronaut.data:micronaut-data-hibernate-jpa")
    implementation("io.micronaut.data:micronaut-data-tx-hibernate")
    implementation("io.micronaut.security:micronaut-security")
    implementation("io.micronaut.serde:micronaut-serde-jackson")
    implementation("io.micronaut.sql:micronaut-hibernate-jpa")
    implementation("io.micronaut.sql:micronaut-jdbc-hikari")
    implementation("io.micronaut.validation:micronaut-validation")
    implementation("jakarta.validation:jakarta.validation-api")

    compileOnly("org.projectlombok:lombok")

    runtimeOnly("ch.qos.logback:logback-classic")
    runtimeOnly("org.postgresql:postgresql")

    // TEST DEPENDENCIES - CRITICAL FOR SPOCK
    testImplementation("io.micronaut:micronaut-http-client")
    testImplementation("io.micronaut.test:micronaut-test-spock")
    testImplementation("org.spockframework:spock-core") {
        exclude group: "org.codehaus.groovy", module: "groovy-all"
    }

    // REQUIRED: Enables mocking of concrete classes (not just interfaces)
    testRuntimeOnly 'net.bytebuddy:byte-buddy:1.17.8'

    // REQUIRED: Enables mocking of classes without default constructor
    testRuntimeOnly "org.objenesis:objenesis:3.4"
}
```

## application-test.yml Configuration

```yaml
# Test-specific configuration overlay
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: ecfx
      db-password: ecfx
      db-username: ecfx

# Test authentication credentials
webhook:
  postmark:
    password: test-postmark-secret
  sendgrid:
    password: test-sendgrid-secret

# JPA test configuration
jpa:
  default:
    properties:
      hibernate:
        default_schema: private  # If using schemas
        show_sql: false
        format_sql: false
```

## Common Test Patterns

### Testing Optional Returns

```groovy
void "returns Optional with result when found"() {
    when:
    def result = repository.findById(1)

    then:
    result.isPresent()
    result.get().id == 1
}

void "returns empty Optional when not found"() {
    when:
    def result = repository.findById(999)

    then:
    !result.isPresent()
}
```

### Testing Collections

```groovy
void "returns list of entities"() {
    when:
    def results = repository.findByFirmId(1)

    then:
    results.size() == 3
    results.every { it.firmId == 1 }
}

void "returns empty list when no matches"() {
    when:
    def results = repository.findByFirmId(999)

    then:
    results.isEmpty()
}
```

### Testing Exception Handling

```groovy
void "throws specific exception type"() {
    when:
    service.methodThatThrows(null)

    then:
    thrown(IllegalArgumentException)
}

void "throws exception with specific message"() {
    when:
    service.methodThatThrows(null)

    then:
    def ex = thrown(IllegalArgumentException)
    ex.message.contains("cannot be null")
}
```

### Complex Interaction Verification

```groovy
void "verifies method call sequence"() {
    when:
    service.complexOperation()

    then: "first operation"
    1 * firstRepository.findById(1) >> Optional.of(entity1)

    then: "second operation depends on first"
    1 * secondRepository.save(_ as Entity2) >> { Entity2 e ->
        assert e.relatedId == entity1.id
        return e
    }

    then: "third operation"
    1 * thirdRepository.update(_)
}
```

### Using Data Tables (Where Blocks)

```groovy
void "tests multiple scenarios"() {
    expect:
    service.calculate(input) == expected

    where:
    input | expected
    0     | 0
    1     | 10
    5     | 50
    10    | 100
}
```
