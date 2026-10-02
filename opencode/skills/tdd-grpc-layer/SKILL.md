---
name: tdd-grpc-layer
description: >-
  Micronaut gRPC server and client patterns with full @MicronautTest integration testing. Use when creating/modifying gRPC service implementations (extending *ImplBase), gRPC client wrappers, @GrpcChannel injections, @Factory classes for stub beans, grpc/ directories, or when working with PipelineArtifactService / any other gRPC service in this project. Also when test specs that exercise gRPC code bypass @MicronautTest.
---


# TDD gRPC Layer

gRPC has two roles in this codebase: **SERVERS** (orchestrator exposes services to workers) and **CLIENTS** (workers call orchestrator services). Both follow Micronaut's `@Singleton` + `@Factory` + `@MicronautTest` discipline. **Bypassing `@MicronautTest` is a defect** — it leaves DI wiring, factory bean ordering, and `@GrpcChannel` resolution untested.

Two principles drive everything below:
1. **Stubs are NOT auto-bean-managed.** You must expose every client stub via an `@Factory`.
2. **Server impls auto-register.** Anything `@Singleton` extending the generated `*ImplBase` is picked up automatically.

## Test File Organization

- ALWAYS search for existing `{ServiceName}GrpcServiceSpec.groovy` (server) or `{ServiceName}GrpcClientSpec.groovy` (client wrapper) before creating a new file.
- If found: ADD test cases to the existing spec — reuse its `@MicronautTest` setup, fixtures, and helpers.
- If NOT found: CREATE the spec named after the class, not the behavior.
- gRPC specs MUST use `@MicronautTest` and inject beans from the context — never construct stubs/clients in test setup unless you're testing pure proto wire format on a class with no DI dependencies.
- Reference patterns:
  - Server: `pipeline-orchestrator/src/test/groovy/com/goecfx/pipeline/grpc/PipelineArtifactGrpcServiceSpec.groovy` + `GrpcTestStubFactory`
  - Client: `pipeline-workers/src/test/groovy/com/goecfx/workers/grpc/PipelineArtifactGrpcClientSpec.groovy` + `InProcessGrpcServerFixture` + `TestStubFactory`

## Server Side: Implementing a gRPC Service

```java
@Singleton
public class {ServiceName}GrpcService
        extends {ServiceName}Grpc.{ServiceName}ImplBase {

    private final {DomainService} domainService;

    public {ServiceName}GrpcService({DomainService} domainService) {
        this.domainService = domainService;
    }

    @Override
    public void {rpcMethod}({Request} request, StreamObserver<{Response}> observer) {
        try {
            // 1. Validate inputs (UUID parsing, blank checks)
            // 2. Delegate to domain service (returns plain types)
            // 3. Build proto response, onNext + onCompleted
            observer.onNext({Response}.newBuilder()....build());
            observer.onCompleted();
        } catch (IllegalArgumentException e) {
            observer.onError(Status.INVALID_ARGUMENT
                .withDescription(e.getMessage()).asRuntimeException());
        } catch (NoSuchElementException e) {
            observer.onError(Status.NOT_FOUND
                .withDescription(e.getMessage()).asRuntimeException());
        } catch (RuntimeException e) {
            observer.onError(Status.INTERNAL
                .withDescription(e.getMessage()).asRuntimeException());
        }
    }
}
```

The gRPC service is a thin adapter: validate, parse, delegate, format. All business logic lives in an `@Singleton @Transactional` domain service that's also unit-testable on its own.

### Status Code Mapping

| Domain exception | gRPC Status |
|---|---|
| `IllegalArgumentException` (bad input, malformed UUID) | `INVALID_ARGUMENT` |
| `NoSuchElementException` (entity not found) | `NOT_FOUND` |
| `OptimisticLockException` / version conflict | `ABORTED` |
| Permission/auth | `PERMISSION_DENIED` / `UNAUTHENTICATED` |
| Anything else | `INTERNAL` |

### Server-Side Test Template

```groovy
@MicronautTest(transactional = false)  // gRPC handler runs in its own tx
class {ServiceName}GrpcServiceSpec extends Specification {

    @Inject {ServiceName}Grpc.{ServiceName}BlockingStub stub
    @Inject {DomainService} domainService   // for setup, not assertion

    void "RPC roundtrip persists the expected state"() {
        given:
        // arrange domain state via the domain service so commits land
        // before the stub call

        when:
        def response = stub.{rpcMethod}({Request}.newBuilder()....build())

        then:
        // assert returned proto fields + persisted state
    }

    void "returns INVALID_ARGUMENT for malformed UUID"() {
        when:
        stub.{rpcMethod}({Request}.newBuilder()
            .setSomeId("not-a-uuid").build())

        then:
        def e = thrown(StatusRuntimeException)
        e.status.code == Status.Code.INVALID_ARGUMENT
    }
}
```

`transactional = false` is critical: by default `@MicronautTest` wraps each spec method in a rolled-back transaction, but the gRPC handler runs on its own thread/connection and won't see un-flushed parent rows. FK constraint violations on entities created in `given:` blocks are the smoking-gun symptom.

Stubs are injected via a `GrpcTestStubFactory` — see `examples.md` for the full factory + `@GrpcChannel(GrpcServerChannel.NAME)` wiring.

## Client Side: Calling a Remote gRPC Service

Two classes — `@Factory` produces the stub bean, domain wrapper consumes it:

```java
// {Project}GrpcClientFactory.java
@Factory
public class {Project}GrpcClientFactory {

    @Singleton
    public {ServiceName}Grpc.{ServiceName}BlockingStub {serviceName}BlockingStub(
            @GrpcChannel("{channel-name}") ManagedChannel channel) {
        return {ServiceName}Grpc.newBlockingStub(channel);
    }
}
```

```java
// {ServiceName}GrpcClient.java  (domain wrapper)
@Singleton
public class {ServiceName}GrpcClient {
    private final {ServiceName}Grpc.{ServiceName}BlockingStub stub;

    public {ServiceName}GrpcClient({ServiceName}Grpc.{ServiceName}BlockingStub stub) {
        this.stub = stub;
    }

    public {DomainResult} doSomething({DomainArgs} args) {
        var request = {Request}.newBuilder()....build();
        var response = stub.someRpc(request);
        return parse(response);
    }
}
```

The wrapper converts between domain types (`UUID`, `Instant`) and proto string types, and gives callers a builder-free, Micronaut-injectable API. Application code injects `{ServiceName}GrpcClient`, **not** the raw stub.

### Client-Side Test Template

The spec must run under `@MicronautTest` so it exercises the production `@Factory` wiring, then a test-only `@Replaces` factory swaps the stub for one wired to an in-process server.

```groovy
@MicronautTest
class {ServiceName}GrpcClientSpec extends Specification {

    @Inject {ServiceName}GrpcClient client                       // production wrapper
    @Inject {ServiceName}Grpc.{ServiceName}BlockingStub stub     // replaced by TestStubFactory
    @Inject InProcessGrpcServerFixture fixture                   // recording fake server

    void setup() { fixture.reset() }

    void "DI wiring: client and stub are injected from the context"() {
        expect:
        client != null
        stub != null
    }

    void "wrapper serializes every field over the wire"() {
        given:
        fixture.nextArtifactId = UUID.randomUUID()

        when:
        def returned = client.doSomething(...)

        then:
        returned == fixture.nextArtifactId
        fixture.lastRequest.someField == "expected"
    }

    void "wrapper propagates server-side errors as StatusRuntimeException"() {
        given:
        fixture.failNextWith = Status.NOT_FOUND.withDescription("missing")

        when:
        client.doSomething(...)

        then:
        def e = thrown(StatusRuntimeException)
        e.status.code == Status.Code.NOT_FOUND
    }
}
```

Two test-side fixtures are required: `InProcessGrpcServerFixture` (a recording fake server) and `TestStubFactory` (a `@Replaces` factory wiring the stub to the in-process channel). See `examples.md` for the full implementations.

## Common Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| FK violation when test setup creates entities | `@MicronautTest` wraps spec in tx; gRPC handler runs in its own tx and doesn't see un-flushed rows | Add `@MicronautTest(transactional = false)` |
| `port out of range:-1` at server start in tests | `grpc.server.port: -1` — works for HTTP, fails for gRPC | Use `grpc.server.port: 0` |
| Spec passes but prod fails on first deploy | Stub constructed inline in spec setup → `@Factory` wiring untested | Inject the stub from the context, never `new {Stub}(channel)` in prod or non-prod-mirroring specs |
| `No bean of type [ObjectMapper]` | Used Jackson's `com.fasterxml...ObjectMapper` directly | Inject `io.micronaut.serde.ObjectMapper` |
| `${VAR:host:port}` defaults garbled | Micronaut treats inner `:` as another default delimiter | Split into `${HOST:host}:${PORT:port}` |
| Generated stub package mismatch | proto's `option java_package` differs from expected | Read the generated class location: `build/generated/sources/proto/main/grpc/...` |
| Replacement `@Factory` doesn't kick in | Missing `@Requires(env = "test")` or wrong `@Replaces(bean = ...)` target | Set both — and the `bean =` target must be the exact stub class, not the factory |

## Related Skills

- **tdd-context-loader** — load TDD context before starting
- **tdd-flow** — full TDD workflow (extend it to route gRPC tasks here)
- **tdd-service-layer** — for the `@Singleton @Transactional` domain service the gRPC handler delegates to
- **spock-test-setup** — ensure ByteBuddy + Spock dependencies are present
- **checkstyle-enforcer** — enforce code style on the new gRPC classes
- **verify-library-api** — confirm proto-generated method signatures via javap
- **tdd-retrospective** — after a gRPC TDD cycle, capture any new `Status` codes used or new fixture patterns

For verbose examples (full server + client fixtures, end-to-end roundtrip, `@Replaces` factory bodies), see `examples.md`.
For external documentation, dependencies, configuration reference, and edge cases, see `reference.md`.
