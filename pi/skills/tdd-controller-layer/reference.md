# Controller Layer Reference

## External Documentation

- [Micronaut HTTP Server](https://docs.micronaut.io/latest/guide/#httpServer) — Controller and routing
- [Micronaut HTTP Client](https://docs.micronaut.io/latest/guide/#httpClient) — Client for testing
- [Micronaut Security](https://micronaut-projects.github.io/micronaut-security/latest/guide/) — Authentication and authorization
- [Jakarta Bean Validation](https://jakarta.ee/specifications/bean-validation/3.0/) — DTO validation annotations

## HTTP Annotation Cheat Sheet

| Annotation | Purpose |
|-----------|---------|
| `@Controller("/path")` | Declare controller with base path |
| `@Get` / `@Post` / `@Put` / `@Delete` | HTTP method binding |
| `@Get("/{id}")` | Path with variable |
| `@Body` | Bind request body |
| `@Valid` | Trigger validation on body |
| `@PathVariable` | Bind path parameter |
| `@QueryValue` | Bind query parameter |
| `@Header` | Bind request header |
| `@Secured(SecurityRule.IS_AUTHENTICATED)` | Require authentication |
| `@Secured(SecurityRule.IS_ANONYMOUS)` | Allow anonymous access |

## Status Code Quick Reference

| Code | Constant | Typical Use |
|------|----------|------------|
| 200 | `OK` | Successful read/update |
| 201 | `CREATED` | Resource created |
| 202 | `ACCEPTED` | Async processing |
| 204 | `NO_CONTENT` | Successful delete |
| 400 | `BAD_REQUEST` | Validation error |
| 401 | `UNAUTHORIZED` | Auth required |
| 403 | `FORBIDDEN` | Insufficient permissions |
| 404 | `NOT_FOUND` | Resource missing |
| 409 | `CONFLICT` | Duplicate resource |
| 422 | `UNPROCESSABLE_ENTITY` | Business rule violation |
| 500 | `INTERNAL_SERVER_ERROR` | Unexpected error |

## Authentication Filter Routing

| Path prefix | Filter | Auth mechanism | Tenant context |
|-------------|--------|----------------|----------------|
| `/api/v1/admin/**` | `AdminApiKeyFilter` (order `SECURITY - 10`) | `X-API-Key` header matching `ecfx.admin.api-key` | NONE — `FirmHttpRequestFilter` skips admin paths via `requestPath.startsWith(ADMIN_PATH_PREFIX)`. Use `@Secured(IS_ANONYMOUS)` on the controller method. |
| `/api/v1/**` (non-admin) | `FirmHttpRequestFilter` + Micronaut Security | JWT bearer token | Host header `subdomain.localhost.com` resolves the tenant |
| Public banner-style endpoints | Add path to `FirmHttpRequestFilter.allowedPaths` (exact match) OR use `ADMIN_PATH_PREFIX` for `startsWith()` semantics | `@Secured(IS_ANONYMOUS)` is NOT enough alone — the filter runs independently of Micronaut Security |

When debugging unexpected 401s, list ALL HTTP filters: `applicationContext.getBeansOfType(HttpServerFilter)` — custom security filters frequently coexist with `@Secured` annotations.

## `BaseRestController` 404 Behavior (post 2026-03-16)

`BaseRestController.getSingularObject() / updateObject() / deleteObject()` and `BaseUpdatableRestController` peers now null-check the entity and return HTTP 404. Subclasses with their own `getById()` calls (e.g., `DocumentController.getCourtDocument()`) need their own null checks — the base-class fix doesn't reach them.

## HTTP Test Behavior — 5xx Responses

Default `HttpClient.exchange(req, Type)` throws `HttpClientResponseException` on ANY 5xx status, even a deliberate business-logic 503 (e.g., gated-feature "DISABLED" response). Spec assertions for an INTENTIONAL 5xx happy path must use:

```groovy
when:
client.toBlocking().exchange(req, ResponseType)

then:
def ex = thrown(HttpClientResponseException)
ex.response.status == HttpStatus.SERVICE_UNAVAILABLE
def body = ex.response.getBody(ResponseType).orElseThrow()
body.code == 'DISABLED'
```

Don't use `response.body()` for these — the response variable was never assigned.

## Test Data and Connection Hygiene

| Concern | Pattern |
|---------|---------|
| HTTP integration test data | `autoCommit = true` for inserts. HTTP requests run in separate threads/transactions — test-tx data is invisible to them. Implement explicit `cleanup()` because autoCommit data won't roll back. |
| `executeWithAutoCommit` finally clause | MUST restore `conn.autoCommit` in `finally`. Micronaut may return the transactional connection; failing to restore breaks Hibernate rollback for the rest of the test. |
| `@MockBean` addition + hardcoded port | Adding a new `@MockBean` changes the Micronaut context fingerprint, preventing context reuse between specs. If `micronaut.server.port` is hardcoded (e.g., 8080), previously-shared specs now create separate contexts and get `BindException: Address already in use`. Always set `micronaut.server.port: -1` in `application-test.yml` for random port assignment. |
| Heavyweight controller setup | Stub `@Property` values for config-gated beans (e.g., `ecfx.document-bucket`, `ecfx.encryption-service.*`) and `@MockBean` for interface-only beans whose implementations have `@Requires` annotations (e.g., `EmailDeliveryService`). Walk the constructor dependency chain BEFORE writing the first test — iterative trial-and-error is expensive. |
| Conditional endpoints | Inject `Optional<GatedBean>`, let `@Requires(property = ...)` decide bean presence, and branch on `provisioningTrigger.isPresent()` in the method. Returns deterministic 503 when disabled with a body for ops diagnostics; peer non-gated endpoints on the same controller stay untouched. |

## `micronaut { runtime + testRuntime }` Block (CRITICAL for `@Client`)

The `io.micronaut.application` Gradle plugin (4.6.x) does NOT pull in an embedded HTTP server unless the build.gradle declares:

```groovy
micronaut {
    runtime("netty")
    testRuntime("spock2")
}
```

Without that block, `micronaut-http-server-netty` is missing, no `EmbeddedServer` bean is created, and `@MicronautTest(startApplication = true)` fails to inject `@Client("/")` with the misleading message `Invalid service reference [/] specified to @Client`. Both halves are load-bearing — `testRuntime("spock2")` is also required for some Spock-Micronaut wiring. Always grep the build for a `micronaut {}` block BEFORE writing the first controller spec.
