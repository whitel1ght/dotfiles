# Controller Patterns Module

**Purpose**: HTTP controller patterns with integration testing

**When to Use**: Building HTTP endpoints and REST controllers

**Dependencies**: Loaded by `tdd-micronaut.md` base agent when controller work is detected

---

## @Client Injection for HTTP Testing

**Core Pattern**: Use `@Client` to inject HTTP client for integration testing.

```groovy
package com.goecfx.controllers

import io.micronaut.http.HttpRequest
import io.micronaut.http.HttpStatus
import io.micronaut.http.client.HttpClient
import io.micronaut.http.client.annotation.Client
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * HTTP integration test for PostmarkController.
 * Tests full request/response cycle through actual HTTP.
 */
@MicronautTest
class PostmarkControllerSpec extends Specification {

    @Inject
    @Client("/")  // ⭐ Inject HTTP client pointing to root path
    HttpClient client

    void "POST endpoint accepts valid request"() {
        given: "valid request payload"
        def payload = [
            email: "test@example.com",
            subject: "Test Subject"
        ]
        def request = HttpRequest.POST("/api/webhook", payload)

        when: "making HTTP request"
        def response = client.toBlocking().exchange(request, Void)

        then: "returns success status"
        response.status == HttpStatus.ACCEPTED
    }
}
```

**Key Points**:
- **`@Client("/")`**: Injects client for testing local server
- **`client.toBlocking()`**: Synchronous HTTP calls (easier for tests)
- **`.exchange(request, ResponseType)`**: Execute request, return full response
- **Tests real HTTP stack**: Serialization, routing, security, validation

---

## HttpRequest Building Patterns

### Basic Requests

```groovy
// POST with JSON body
def request = HttpRequest.POST("/api/endpoint", payload)

// GET with path parameter
def request = HttpRequest.GET("/api/firms/123")

// PUT with JSON body
def request = HttpRequest.PUT("/api/firms/123", updatePayload)

// DELETE
def request = HttpRequest.DELETE("/api/firms/123")

// GET with query parameters
def request = HttpRequest.GET("/api/firms?active=true&page=0")
```

### Authentication Headers

```groovy
// Basic Auth
def request = HttpRequest.POST("/api/webhook", payload)
    .basicAuth("username", "password")

// Bearer Token
def request = HttpRequest.GET("/api/firms")
    .bearerAuth("token-value")

// Custom Header
def request = HttpRequest.POST("/api/webhook", payload)
    .header("X-Custom-Header", "value")
```

### Subdomain Extraction

```groovy
// Extract subdomain from Host header
def request = HttpRequest.POST("/api/endpoint", payload)
    .header("Host", "testfirm.example.com")

// Controller can extract: testfirm.example.com → "testfirm"
```

---

## Status Code Testing

**Pattern**: Test all relevant HTTP status codes for each endpoint.

### Success Scenarios

```groovy
void "returns 200 OK for successful GET"() {
    given:
    def request = HttpRequest.GET("/api/firms/1")

    when:
    def response = client.toBlocking().exchange(request, Firm)

    then:
    response.status == HttpStatus.OK
    response.body().id == 1
}

void "returns 201 CREATED for successful POST"() {
    given:
    def payload = [name: "New Firm", subdomain: "newfirm"]
    def request = HttpRequest.POST("/api/firms", payload)

    when:
    def response = client.toBlocking().exchange(request, Firm)

    then:
    response.status == HttpStatus.CREATED
    response.body().name == "New Firm"
}

void "returns 202 ACCEPTED for async operations"() {
    given:
    def request = HttpRequest.POST("/api/webhooks", payload)

    when:
    def response = client.toBlocking().exchange(request, Void)

    then:
    response.status == HttpStatus.ACCEPTED
}

void "returns 204 NO_CONTENT for successful DELETE"() {
    given:
    def request = HttpRequest.DELETE("/api/firms/1")

    when:
    def response = client.toBlocking().exchange(request, Void)

    then:
    response.status == HttpStatus.NO_CONTENT
}
```

### Client Error Scenarios

```groovy
void "returns 400 BAD_REQUEST for invalid payload"() {
    given: "payload missing required fields"
    def invalidPayload = [name: null]  // Missing required field
    def request = HttpRequest.POST("/api/firms", invalidPayload)

    when:
    client.toBlocking().exchange(request, Void)

    then: "validation error thrown"
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.BAD_REQUEST
}

void "returns 401 UNAUTHORIZED for missing auth"() {
    given: "request without authentication"
    def request = HttpRequest.POST("/api/webhook", payload)
    // No .basicAuth() call

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.UNAUTHORIZED
}

void "returns 404 NOT_FOUND for non-existent resource"() {
    given:
    def request = HttpRequest.GET("/api/firms/99999")

    when:
    client.toBlocking().exchange(request, Firm)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.NOT_FOUND
}

void "returns 422 UNPROCESSABLE_ENTITY for business rule violations"() {
    given: "payload violates business rule"
    def payload = [subdomain: "duplicate"]  // Already exists
    def request = HttpRequest.POST("/api/firms", payload)

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.UNPROCESSABLE_ENTITY
}
```

### Server Error Scenarios

```groovy
void "returns 500 INTERNAL_SERVER_ERROR on unexpected exception"() {
    given: "request that triggers server error"
    def request = HttpRequest.POST("/api/endpoint", triggerErrorPayload)

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.INTERNAL_SERVER_ERROR
}
```

---

## Authentication Testing

### Pattern 1: Security Disabled in Tests

**Use When**: Focusing on business logic, not authentication.

```yaml
# src/test/resources/application-test.yml
micronaut:
  security:
    enabled: false  # ⭐ Disable security for tests
```

```groovy
@MicronautTest
class FirmControllerSpec extends Specification {
    // No authentication needed in tests
    void "creates firm without auth (security disabled)"() {
        given:
        def request = HttpRequest.POST("/api/firms", payload)
        // No .basicAuth() needed

        when:
        def response = client.toBlocking().exchange(request, Firm)

        then:
        response.status == HttpStatus.CREATED
    }
}
```

### Pattern 2: Testing Authentication

**Use When**: Validating authentication/authorization logic.

```groovy
@MicronautTest  // Security enabled (default)
class SecureEndpointSpec extends Specification {

    @Inject
    @Client("/")
    HttpClient client

    void "accepts request with valid credentials"() {
        given:
        def request = HttpRequest.POST("/api/webhook", payload)
            .basicAuth("valid-user", "valid-password")

        when:
        def response = client.toBlocking().exchange(request, Void)

        then:
        response.status == HttpStatus.ACCEPTED
    }

    void "rejects request with invalid credentials"() {
        given:
        def request = HttpRequest.POST("/api/webhook", payload)
            .basicAuth("invalid-user", "wrong-password")

        when:
        client.toBlocking().exchange(request, Void)

        then:
        def ex = thrown(Exception)
        ex.response.status == HttpStatus.UNAUTHORIZED
    }

    void "rejects request without credentials"() {
        given: "no authentication"
        def request = HttpRequest.POST("/api/webhook", payload)

        when:
        client.toBlocking().exchange(request, Void)

        then:
        def ex = thrown(Exception)
        ex.response.status == HttpStatus.UNAUTHORIZED
    }
}
```

---

## DTO Validation Patterns

**Pattern**: Jakarta Validation annotations automatically validate DTOs.

### DTO Definition

```java
package com.goecfx.dtos;

import jakarta.validation.constraints.*;

/**
 * DTO for creating a new firm.
 * Validation happens automatically in controller.
 */
public class CreateFirmRequest {

    @NotNull(message = "Name is required")
    @NotBlank(message = "Name cannot be blank")
    @Size(min = 2, max = 100, message = "Name must be between 2 and 100 characters")
    private String name;

    @NotNull(message = "Subdomain is required")
    @Pattern(regexp = "^[a-z0-9-]+$", message = "Subdomain must be lowercase alphanumeric with hyphens")
    private String subdomain;

    @Email(message = "Invalid email format")
    private String contactEmail;

    // Getters and setters
}
```

### Controller Usage

```java
@Controller("/api/firms")
public class FirmController {

    private final FirmService service;

    public FirmController(FirmService service) {
        this.service = service;
    }

    @Post
    public HttpResponse<Firm> createFirm(@Body @Valid CreateFirmRequest request) {
        // Validation happens BEFORE this method executes
        // If validation fails, 400 BAD_REQUEST returned automatically
        var firm = service.createFirm(request.getName(), request.getSubdomain());
        return HttpResponse.created(firm);
    }
}
```

### Testing Validation

```groovy
void "rejects request with missing required field"() {
    given: "payload missing name"
    def payload = [subdomain: "test"]  // No name

    when:
    def request = HttpRequest.POST("/api/firms", payload)
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.BAD_REQUEST
}

void "rejects request with invalid email"() {
    given: "payload with malformed email"
    def payload = [
        name: "Test Firm",
        subdomain: "test",
        contactEmail: "not-an-email"
    ]

    when:
    def request = HttpRequest.POST("/api/firms", payload)
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.BAD_REQUEST
}

void "accepts request with valid payload"() {
    given: "fully valid payload"
    def payload = [
        name: "Test Firm",
        subdomain: "test-firm",
        contactEmail: "contact@test.com"
    ]

    when:
    def request = HttpRequest.POST("/api/firms", payload)
    def response = client.toBlocking().exchange(request, Firm)

    then:
    response.status == HttpStatus.CREATED
}
```

---

## Error Response Verification

**Pattern**: Test error response bodies contain useful information.

```groovy
void "error response includes message and details"() {
    given:
    def request = HttpRequest.POST("/api/firms", invalidPayload)

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(Exception)
    ex.response.status == HttpStatus.BAD_REQUEST

    and: "response body contains error details"
    def errorBody = ex.response.getBody(Map).get()
    errorBody.message != null
    errorBody.message.contains("validation")
}
```

---

## Controller Template

Complete controller implementation template:

```java
package com.goecfx.controllers;

import com.goecfx.dtos.CreateFirmRequest;
import com.goecfx.services.FirmService;
import com.goecfx.data.entities.Firm;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.*;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.rules.SecurityRule;

import jakarta.validation.Valid;
import java.net.URI;

/**
 * HTTP controller for firm operations.
 *
 * Handles REST endpoints for firm CRUD operations.
 */
@Controller("/api/firms")
@Secured(SecurityRule.IS_AUTHENTICATED)  // Require authentication
public class FirmController {

    private final FirmService service;

    public FirmController(FirmService service) {
        this.service = service;
    }

    /**
     * Creates a new firm.
     *
     * @param request Validated firm creation request
     * @return 201 CREATED with firm details
     */
    @Post
    public HttpResponse<Firm> createFirm(@Body @Valid CreateFirmRequest request) {
        var firm = service.createFirm(request.getName(), request.getSubdomain());
        return HttpResponse.created(firm)
            .headers(headers -> headers.location(URI.create("/api/firms/" + firm.getId())));
    }

    /**
     * Retrieves firm by ID.
     *
     * @param id Firm ID
     * @return 200 OK with firm details, or 404 NOT_FOUND
     */
    @Get("/{id}")
    public HttpResponse<Firm> getFirm(@PathVariable Integer id) {
        return service.findById(id)
            .map(HttpResponse::ok)
            .orElse(HttpResponse.notFound());
    }

    /**
     * Updates firm name.
     *
     * @param id Firm ID
     * @param request Update request
     * @return 200 OK with updated firm, or 404 NOT_FOUND
     */
    @Put("/{id}")
    public HttpResponse<Firm> updateFirm(@PathVariable Integer id,
                                          @Body @Valid UpdateFirmRequest request) {
        var firm = service.updateName(id, request.getName());
        return HttpResponse.ok(firm);
    }

    /**
     * Deletes firm by ID.
     *
     * @param id Firm ID
     * @return 204 NO_CONTENT
     */
    @Delete("/{id}")
    public HttpResponse<Void> deleteFirm(@PathVariable Integer id) {
        service.delete(id);
        return HttpResponse.noContent();
    }
}
```

---

## Controller Test Template

Complete test template:

```groovy
package com.goecfx.controllers

import com.goecfx.data.entities.Firm
import io.micronaut.http.HttpRequest
import io.micronaut.http.HttpStatus
import io.micronaut.http.client.HttpClient
import io.micronaut.http.client.annotation.Client
import io.micronaut.test.extensions.spock.annotation.MicronautTest
import jakarta.inject.Inject
import spock.lang.Specification

/**
 * HTTP integration test for {Controller}.
 * Tests full request/response cycle including serialization and validation.
 */
@MicronautTest
class {Controller}Spec extends Specification {

    @Inject
    @Client("/")
    HttpClient client

    void "POST endpoint accepts valid request"() {
        given: "valid request payload"
        def payload = [field: "value"]
        def request = HttpRequest.POST("/api/endpoint", payload)

        when: "making HTTP request"
        def response = client.toBlocking().exchange(request, ResponseType)

        then: "returns success status"
        response.status == HttpStatus.CREATED
        response.body().field == "value"
    }

    void "GET endpoint returns resource"() {
        given:
        def request = HttpRequest.GET("/api/endpoint/1")

        when:
        def response = client.toBlocking().exchange(request, ResponseType)

        then:
        response.status == HttpStatus.OK
        response.body().id == 1
    }

    void "returns 400 for invalid input"() {
        given: "invalid payload"
        def payload = [field: null]  // Validation error
        def request = HttpRequest.POST("/api/endpoint", payload)

        when:
        client.toBlocking().exchange(request, Void)

        then:
        def ex = thrown(Exception)
        ex.response.status == HttpStatus.BAD_REQUEST
    }

    void "returns 401 for missing authentication"() {
        given: "request without auth"
        def request = HttpRequest.POST("/api/endpoint", payload)

        when:
        client.toBlocking().exchange(request, Void)

        then:
        def ex = thrown(Exception)
        ex.response.status == HttpStatus.UNAUTHORIZED
    }

    void "returns 404 for non-existent resource"() {
        given:
        def request = HttpRequest.GET("/api/endpoint/99999")

        when:
        client.toBlocking().exchange(request, ResponseType)

        then:
        def ex = thrown(Exception)
        ex.response.status == HttpStatus.NOT_FOUND
    }
}
```

---

## Cross-References

**To Base Agent**:
- For TDD workflow, see `tdd-micronaut.md` section "The Sacred TDD Cycle"
- For TestResources config, see `tdd-micronaut.md` section "TestResources Configuration"

**To Service Module**:
- Controllers inject services, see `service-patterns.md` section "Constructor Dependency Injection Pattern"
- Business exceptions map to HTTP status codes, see `service-patterns.md` section "Business Exception Handling"

**From Other Modules**:
- Controller tests may mock services (same as `service-patterns.md` mocks repositories)
- DTOs may contain entities from `entity-patterns.md`

---

**Key Takeaway**: Controllers handle HTTP, use `@Client` for integration tests, test all status codes, validate DTOs automatically.
