# gRPC Layer Reference

## External Documentation

- [Micronaut gRPC 4.12 Guide](https://micronaut-projects.github.io/micronaut-grpc/4.12.0/guide/) — source of truth for `@GrpcChannel`, `@Factory` stubs, server auto-registration, channel config
- [gRPC Java Status Codes](https://grpc.github.io/grpc-java/javadoc/io/grpc/Status.html) — canonical mapping of `Status` codes and their semantics
- [gRPC Java In-Process Transport](https://grpc.github.io/grpc-java/javadoc/io/grpc/inprocess/package-summary.html) — `InProcessServerBuilder` / `InProcessChannelBuilder` used in client-side test fixtures
- [Micronaut Test](https://micronaut-projects.github.io/micronaut-test/latest/guide/) — `@MicronautTest`, `transactional`, `@Replaces`, `@MockBean`

Two principles from the guide to remember:
1. **Stubs are NOT auto-bean-managed.** "Micronaut for gRPC does not create client beans automatically for you. Instead, you must expose which client stubs your application needs using a `@Factory`."
2. **Server impls auto-register.** "Any services declared as beans" (annotated `@Singleton`, extending the generated `*ImplBase`) are picked up automatically — no separate registry config.

## Required Dependencies

Server (`build.gradle`):
```gradle
implementation("io.micronaut.grpc:micronaut-grpc-server-runtime")
implementation("com.goecfx.backend:protos_java:${protosJavaVersion}")
```

Client (`build.gradle`):
```gradle
implementation("io.micronaut.grpc:micronaut-grpc-client-runtime")
implementation("com.goecfx.backend:protos_java:${protosJavaVersion}")
testImplementation("io.grpc:grpc-inprocess")  // for InProcessChannel/Server in specs
```

For server tests, `grpc-inprocess` is NOT needed — `@GrpcChannel(GrpcServerChannel.NAME)` reaches the embedded test server through the framework.

## Configuration Quick Reference

| Key | When | Value |
|---|---|---|
| `grpc.server.port` | Server, prod | `${GRPC_SERVER_PORT:50051}` |
| `grpc.server.port` | Server, test (`application-test.yml`) | `0` (random — `-1` does NOT work, gRPC's NettyServerBuilder rejects it) |
| `grpc.server.keep-alive-time` | Server | `3h` |
| `grpc.server.max-inbound-message-size` | Server | `4194304` (4 MiB), bump for large proto bodies |
| `grpc.channels.{name}.address` | Client | Split: `"${HOST:localhost}:${PORT:50051}"` (avoids colon-default escape) |
| `grpc.channels.{name}.plaintext` | Client, cluster-internal | `true` |
| `grpc.channels.{name}.max-retry-attempts` | Client | `3` |

## Status Code Mapping (Extended)

| Domain exception | gRPC Status | Notes |
|---|---|---|
| `IllegalArgumentException` | `INVALID_ARGUMENT` | Bad input, malformed UUID, blank required field |
| `NoSuchElementException` | `NOT_FOUND` | Entity not found in DB |
| `OptimisticLockException` / `StaleStateException` | `ABORTED` | Version conflict — caller may retry |
| `SecurityException` / unauthenticated | `PERMISSION_DENIED` / `UNAUTHENTICATED` | Authz vs authn — pick deliberately |
| `TimeoutException` | `DEADLINE_EXCEEDED` | Upstream deadline hit |
| `UnsupportedOperationException` | `UNIMPLEMENTED` | RPC not implemented for this code path |
| Anything else | `INTERNAL` | Default for unexpected `RuntimeException` |

## When to Skip `@MicronautTest`

Only one valid case: testing a class that is a pure delegate over an already-injected stub, with no other DI dependencies. Even then, prefer `@MicronautTest` because it costs almost nothing once `ContextSmokeSpec` has paid the startup. Exceptions:

- Pure proto wire-format tests on a hand-built request — covered by the protos repo's own tests.
- Library-level shims that aren't bean-managed.

If unsure, use `@MicronautTest`.

## Channel Names: Prod vs In-Process

| Channel | Where it points | Use in |
|---|---|---|
| `GrpcServerChannel.NAME` | The embedded test gRPC server Micronaut auto-creates | Server-side specs only — never wire this in production |
| `{configured-name}` (e.g., `pipeline-orchestrator`) | Whatever `grpc.channels.{name}.address` resolves to | Production code + client-side specs (replaced by `TestStubFactory`) |
| `InProcessGrpcServerFixture.IN_PROCESS_NAME` | The fixture's in-process gRPC server | `TestStubFactory` only, never in production |

Mixing these up is the most common cause of "spec passes, prod fails."

## Generated Stub Locations

Generated proto/gRPC stubs land under:

```
build/generated/sources/proto/main/java/...      // message classes
build/generated/sources/proto/main/grpc/...      // *Grpc.java services + stubs
```

If a stub import fails to resolve, check the actual `option java_package` in the `.proto` and read the generated tree — don't assume the package from the proto's directory layout.

## Proto Enum Authoring

When adding or editing enums in the `protos_java` repo (`ecfx-protobufs`):

- Proto enum values use **C++ scoping** — a value is a sibling of the enclosing *package*,
  not a child of its enum. Two top-level enums in the same package (e.g. `ecfx.services`)
  cannot share a value name; `protoc` fails `:generateProto` with `"<value>" is already
  defined in file ...`.
- **Always prefix every top-level enum value with the enum name** — `JOB_STATUS_FAILED`,
  not `FAILED`. This is what bit `JobStatus.FAILED` vs `EvaluationRunStatus.FAILED`.
- Renaming a value changes the generated Java constant name (`JobStatus.JOB_STATUS_FAILED`)
  but not its integer/wire value, so it's wire-compatible — update consumer code to the new
  constant name.

## Retrospective Hooks

After finishing a gRPC TDD cycle, capture lessons via `tdd-retrospective`. Worth flagging:

- Any new gRPC `Status` codes used → update the Status Code Mapping table above.
- Any test fixture pattern that didn't exist (e.g. async streaming RPC, bidi streaming, deadline propagation) → add to `examples.md`.
- New `@GrpcChannel` configuration patterns (mTLS, retry policy, load balancing) → add a row to Configuration Quick Reference.
