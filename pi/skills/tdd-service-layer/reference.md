# Service Layer Reference

## External Documentation

- [Micronaut Dependency Injection](https://docs.micronaut.io/latest/guide/#ioc) — DI and bean management
- [Micronaut AOP / @Transactional](https://docs.micronaut.io/latest/guide/#aop) — AOP interceptors and transactions
- [Micronaut TestResources](https://micronaut-projects.github.io/micronaut-test-resources/latest/guide/) — Auto-provisioned test containers
- [Spock Framework](https://spockframework.org/spock/docs/2.3/all_in_one.html) — Spock testing reference
- [Spock Interaction Based Testing](https://spockframework.org/spock/docs/2.3/interaction_based_testing.html) — Mock/Stub/Spy patterns (for external service mocks)

## What to Mock vs What to Use Real

| Dependency Type | Approach | Example |
|----------------|----------|---------|
| Repository / DAO | **REAL** (TestContainers DB) | `@Inject FirmRepository` |
| Other service (DB-backed) | **REAL** | `@Inject UserService` |
| S3 storage | **REAL** (LocalStack TestResources) | `@Inject S3Client` — create buckets in setup |
| External HTTP API | **MOCK** | `@MockBean(PaymentGateway)` |
| Notification / Email | **MOCK** | `@MockBean(NotificationService)` |
| Message queue producer | **MOCK** | `@MockBean(EventPublisher)` |
| Encryption / credential encoding | **MOCK** | `@MockBean(CredentialEncodingService)` |

## Spock Mock Quick Reference (for External Service Mocks)

| Syntax | Meaning |
|--------|---------|
| `Mock(Type)` | Create mock (verifiable interactions) |
| `Stub(Type)` | Create stub (return values only, no verification) |
| `1 * method()` | Expect exactly 1 call |
| `0 * method()` | Expect no calls |
| `>> value` | Return value (stub) |
| `>> { throw new Ex() }` | Throw exception |
| `_` | Any argument |

## @Transactional Quick Reference

| Attribute | Default | Use |
|-----------|---------|-----|
| `readOnly` | `false` | Set `true` for read-only optimization |
| `rollbackFor` | `RuntimeException` | Specify exception types for rollback |
| `propagation` | `REQUIRED` | Transaction propagation behavior |
| `isolation` | `DEFAULT` | Transaction isolation level |

## @MicronautTest Options for Service Tests

| Option | Default | Use |
|--------|---------|-----|
| `transactional` | `true` | Set `false` to test real transaction boundaries |
| `rollback` | `true` | Set `false` to persist test data across methods |

## Tenant-Aware Services — `ServerRequestContext`

Tenant-aware service methods that read tenant from the HTTP request context require the test to wrap the call in `ServerRequestContext.with(httpRequest) { ... }`. Without it, tenant resolution fails silently or throws. Construct an `HttpRequest` with the host header (`subdomain.localhost.com`) the firm filter expects.

## `@Cacheable` Cross-Test Contamination

`@Cacheable` is a Micronaut singleton bean with cache state shared across all tests in a `@MicronautTest` context. Two tests using the same cache key will return the FIRST test's stubbed value, completely bypassing the second test's mock setup.

- **Use unique cache key values per test** (UUID-based subdomains, emails, identifiers)
- **`@Cacheable` does NOT cache `Optional.empty()` by default** — to test caching, insert data, cache a present result, delete from DB, verify cached value persists

## `@Scheduled` Cross-Context Interference

Multiple `@MicronautTest` specs with different `@Property` sets create SEPARATE Micronaut contexts that share the same TestResources DB. Any `@Scheduled` method that polls the DB (e.g., `processQueue()` at `fixedDelay = "10ms"`) will steal jobs/data from OTHER contexts' tests.

**Fix**: externalize all `@Scheduled` delays/cadences as property placeholders with sensible test defaults:
```java
@Scheduled(fixedDelay = "${ecfx.process-queue.fixed-delay:10ms}",
           initialDelay = "${ecfx.process-queue.initial-delay:0s}")
```
Then in `application-test.yml`:
```yaml
ecfx.process-queue.fixed-delay: 24h
ecfx.process-queue.initial-delay: 24h
```

`@Scheduled(fixedDelay = "24h")` still fires ONCE at context startup unless `initialDelay` is also set to a long value.

## Manually-Created EntityManagers in Test Context

Services that manage their own EntityManager lifecycle via `entityManagerFactory.createEntityManager()` produce EntityManagers (in `@MicronautTest` context) where `unwrap(Session.class)` returns `null` and `createNativeQuery()` returns `null`. Verification via these methods will NPE or silently misbehave.

**Fix**: use raw JDBC via `getRawDataSource().getConnection()` for direct pool-level testing. Unwrap `DelegatingDataSource`:
```groovy
def ds = dataSource
while (ds.hasProperty('targetDataSource')) { ds = ds.targetDataSource }
def conn = ds.connection
```

## Split `@Transactional + Publish` Flows

When a `@Transactional` method both writes to the DB AND publishes to a message broker (RabbitMQ, etc.), split into two phases:

1. **Phase 1** (`@Transactional`): does ALL database work, returns a result record describing what to publish (`DispatchIntent`, `EvaluationResult`, etc.).
2. **Phase 2** (non-transactional public method): calls phase 1, then publishes AFTER the transaction commits.

This prevents phantom dispatches where a message is sent but the DB record is rolled back. The non-transactional wrapper is also the ideal `OptimisticLockException` retry boundary — each retry gets a fresh transaction.

## WireMock-Backed HTTP Client Tests

For tests of `@Client(id = ...)` HTTP clients backed by WireMock, boot a dedicated `ApplicationContext.run([...])` in `setupSpec` rather than using `@MicronautTest`. The client's URL must be known at context-start time AND you need WireMock's port before the context starts:

```groovy
def wireMockServer = new WireMockServer(WireMockConfiguration.options().dynamicPort())
wireMockServer.start()
applicationContext = ApplicationContext.run([
    'micronaut.http.services.my-service.url': wireMockServer.baseUrl(),
    'aaa.retry.delay': '50ms',  // shorten retry delays
])
```

Use `@Retryable(delay = "${aaa.retry.delay:5s}")` placeholder pattern in production code so tests can shorten retries to keep total test time under a few seconds.
