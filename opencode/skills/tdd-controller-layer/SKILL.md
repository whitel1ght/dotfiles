---
name: tdd-controller-layer
description: >-
  HTTP controller patterns with integration testing via HttpClient. Use when creating/modifying HTTP controllers, REST endpoints, HTTP testing, @Controller, @Get, @Post, controllers/ directories, or when working with status codes, authentication testing, DTO validation, or error responses.
---


# TDD Controller Layer

Controllers handle HTTP request/response with injected services. Test with `@MicronautTest` using `@Client("/")` HttpClient for real HTTP integration tests. Mock service layer with `@MockBean`.

## Test File Organization

- ALWAYS search for existing `{ControllerName}Spec.groovy` before creating a new file
- If found: ADD test cases to the existing spec — reuse its setup/cleanup/helpers
- If NOT found: CREATE `{ControllerName}Spec.groovy` — named after the class, not the behavior
- Controller specs MUST use `@Client` HttpClient to call real endpoints — never test controller logic in isolation
- Reference pattern: `ECFXTrackControllerSpec` (SchemaLoader, JwtUtil, @Client, @MockBean for security)

## Controller Template

```java
@Controller("/api/{resources}")
@Secured(SecurityRule.IS_AUTHENTICATED)
public class {ControllerName} {

    private final {Service} service;

    public {ControllerName}({Service} service) {
        this.service = service;
    }

    @Post
    public HttpResponse<{Entity}> create(@Body @Valid Create{Entity}Request request) {
        var entity = service.create(request.getName());
        return HttpResponse.created(entity);
    }

    @Get("/{id}")
    public HttpResponse<{Entity}> getById(@PathVariable UUID id) {
        return service.findById(id)
            .map(HttpResponse::ok)
            .orElse(HttpResponse.notFound());
    }

    @Delete("/{id}")
    public HttpResponse<Void> delete(@PathVariable UUID id) {
        service.delete(id);
        return HttpResponse.noContent();
    }
}
```

## HTTP Status Code Reference

| Status | Constant | When to Use |
|--------|----------|-------------|
| 200 | `HttpStatus.OK` | Successful GET/PUT |
| 201 | `HttpStatus.CREATED` | Successful POST (resource created) |
| 202 | `HttpStatus.ACCEPTED` | Async operation accepted |
| 204 | `HttpStatus.NO_CONTENT` | Successful DELETE |
| 400 | `HttpStatus.BAD_REQUEST` | Validation failure, malformed input |
| 401 | `HttpStatus.UNAUTHORIZED` | Missing/invalid authentication |
| 404 | `HttpStatus.NOT_FOUND` | Resource doesn't exist |
| 422 | `HttpStatus.UNPROCESSABLE_ENTITY` | Business rule violation |
| 500 | `HttpStatus.INTERNAL_SERVER_ERROR` | Unexpected server error |

## HttpRequest Building

```groovy
// POST with JSON body
HttpRequest.POST("/api/endpoint", payload)

// GET, PUT, DELETE
HttpRequest.GET("/api/endpoint/1")
HttpRequest.PUT("/api/endpoint/1", payload)
HttpRequest.DELETE("/api/endpoint/1")

// Authentication
request.basicAuth("user", "pass")
request.bearerAuth("token")

// Custom headers
request.header("X-Custom", "value")
```

## Test Template

```groovy
@MicronautTest
class {ControllerName}Spec extends Specification {

    @Inject @Client("/") HttpClient client
    @Inject {Service} service

    @MockBean({Service})
    {Service} mockService() {
        Mock({Service})
    }

    void "POST creates resource successfully"() {
        given:
        def payload = [name: "Test"]
        def entity = new {Entity}(name: "Test")

        when:
        def response = client.toBlocking().exchange(
            HttpRequest.POST("/api/resources", payload), {Entity}
        )

        then:
        1 * service.create("Test") >> entity
        response.status == HttpStatus.CREATED
    }

    void "returns 400 for invalid input"() {
        when:
        client.toBlocking().exchange(
            HttpRequest.POST("/api/resources", [name: null]), Void
        )

        then:
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.BAD_REQUEST
    }

    void "returns 401 without authentication"() {
        when:
        client.toBlocking().exchange(
            HttpRequest.POST("/api/resources", payload), Void
        )

        then:
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.UNAUTHORIZED
    }

    void "returns 404 for non-existent resource"() {
        when:
        client.toBlocking().exchange(
            HttpRequest.GET("/api/resources/" + UUID.randomUUID()), {Entity}
        )

        then:
        1 * service.findById(_) >> Optional.empty()
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.NOT_FOUND
    }
}
```

## DTO Validation

```java
public class Create{Entity}Request {
    @NotNull @NotBlank
    private String name;

    @Email
    private String contactEmail;

    @Pattern(regexp = "^[a-z0-9-]+$")
    private String subdomain;
}
```

Validation runs automatically with `@Valid` on controller parameter. Returns 400 on failure.

## Common Pitfalls

| Error | Cause | Fix |
|-------|-------|-----|
| Test gets 401 unexpectedly | Security enabled, no auth in request | Add `.basicAuth()` or disable security in test config |
| Response body is null | Wrong response type in `.exchange()` | Match type to actual response (e.g., `Map`, `Entity`) |
| `Cannot mock final class` | Missing ByteBuddy for service mock | Add ByteBuddy + Objenesis to test dependencies |
| Exception not caught in then | Using wrong exception class | Use `HttpClientResponseException` for HTTP errors |
| Validation not triggering | Missing `@Valid` on `@Body` parameter | Add `@Valid` annotation alongside `@Body` |

## Related Skills

- **spock-test-setup** — ensure test dependencies and mock infrastructure
- **checkstyle-enforcer** — enforce code style
- **test-resources-validator** — verify TestResources configuration
- **verify-library-api** — verify external library methods with javap

For verbose examples (CRUD controllers, file uploads, error handlers, auth patterns), see `examples.md`.
For external documentation links, see `reference.md`.
