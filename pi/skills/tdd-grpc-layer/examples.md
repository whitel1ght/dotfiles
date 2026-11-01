# gRPC Layer Examples

## Server-Side Test Stub Factory

Ship one `GrpcTestStubFactory` per project under `src/test`. Every server-side spec injects stubs from the context — no inline stub construction.

```groovy
@Factory
@Requires(env = "test")
class GrpcTestStubFactory {

    @Singleton
    {ServiceName}Grpc.{ServiceName}BlockingStub blockingStub(
            @GrpcChannel(GrpcServerChannel.NAME) ManagedChannel channel) {
        return {ServiceName}Grpc.newBlockingStub(channel)
    }
}
```

`GrpcServerChannel.NAME` is the in-process channel Micronaut auto-creates pointing at the embedded test gRPC server. No `grpc-inprocess` dependency needed on the server side — the framework wires it for you.

## End-to-End Server Spec with Domain Setup

```groovy
@MicronautTest(transactional = false, packages = "com.goecfx.data")
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class PipelineArtifactGrpcServiceSpec extends Specification {

    @Inject PipelineArtifactServiceGrpc.PipelineArtifactServiceBlockingStub stub
    @Inject PipelineArtifactService domainService
    @Inject DataSource dataSource

    static final int TEST_FIRM_ID = 9_001

    def setup() {
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/db/schema.sql").toURI()))
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("""
                INSERT INTO private.firm (id, name, subdomain, encryption_key_id)
                VALUES (${TEST_FIRM_ID}, 'gRPC Test Firm', 'grpc-test',
                        '00000000-0000-0000-0000-000000000001')
                ON CONFLICT DO NOTHING
            """)
        }
    }

    def cleanup() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("DELETE FROM private.pipeline_artifact WHERE firm_id = ${TEST_FIRM_ID}")
            conn.createStatement().execute("DELETE FROM private.firm WHERE id = ${TEST_FIRM_ID}")
        }
    }

    void "creates artifact via RPC and persists with the expected payload"() {
        given:
        def request = CreateArtifactRequest.newBuilder()
            .setFirmId(String.valueOf(TEST_FIRM_ID))
            .setPayload("hello world")
            .build()

        when:
        def response = stub.createArtifact(request)

        then:
        UUID.fromString(response.artifactId) != null

        and:
        def stored = domainService.findById(UUID.fromString(response.artifactId)).orElseThrow()
        stored.payload == "hello world"
    }

    void "returns NOT_FOUND for missing artifact"() {
        when:
        stub.getArtifact(GetArtifactRequest.newBuilder()
            .setArtifactId(UUID.randomUUID().toString())
            .build())

        then:
        def e = thrown(StatusRuntimeException)
        e.status.code == Status.Code.NOT_FOUND
    }

    void "returns INVALID_ARGUMENT for malformed UUID"() {
        when:
        stub.getArtifact(GetArtifactRequest.newBuilder()
            .setArtifactId("not-a-uuid")
            .build())

        then:
        def e = thrown(StatusRuntimeException)
        e.status.code == Status.Code.INVALID_ARGUMENT
    }

    private void executeWithAutoCommit(Closure action) {
        def ds = dataSource
        while (ds.hasProperty('targetDataSource')) { ds = ds.targetDataSource }
        def conn = ds.connection
        def originalAutoCommit = conn.autoCommit
        conn.autoCommit = true
        try { action(conn) }
        finally { conn.autoCommit = originalAutoCommit; conn.close() }
    }
}
```

## Client-Side Fixture: `InProcessGrpcServerFixture`

A recording fake server. Boots an in-process gRPC server on `@PostConstruct`, captures `lastRequest`, and can be configured to fail the next call with a specific `Status`.

```groovy
@Singleton
@Requires(env = "test")
class InProcessGrpcServerFixture {
    static final String IN_PROCESS_NAME = "pipeline-artifact-test"

    Server server
    final RecordingService recordingService = new RecordingService()

    @PostConstruct
    void start() {
        server = InProcessServerBuilder.forName(IN_PROCESS_NAME)
            .directExecutor()
            .addService(recordingService)
            .build()
            .start()
    }

    @PreDestroy
    void stop() {
        if (server) {
            server.shutdownNow()
        }
    }

    void reset() {
        recordingService.lastRequest = null
        recordingService.nextArtifactId = null
        recordingService.failNextWith = null
    }

    // Convenience pass-throughs so tests read fluently
    CreateArtifactRequest getLastRequest() { recordingService.lastRequest }
    void setNextArtifactId(UUID id) { recordingService.nextArtifactId = id }
    void setFailNextWith(Status status) { recordingService.failNextWith = status }

    static class RecordingService
            extends PipelineArtifactServiceGrpc.PipelineArtifactServiceImplBase {

        CreateArtifactRequest lastRequest
        UUID nextArtifactId
        Status failNextWith

        @Override
        void createArtifact(CreateArtifactRequest request,
                            StreamObserver<CreateArtifactResponse> observer) {
            lastRequest = request

            if (failNextWith != null) {
                observer.onError(failNextWith.asRuntimeException())
                return
            }

            def id = nextArtifactId ?: UUID.randomUUID()
            observer.onNext(CreateArtifactResponse.newBuilder()
                .setArtifactId(id.toString())
                .build())
            observer.onCompleted()
        }
    }
}
```

## Client-Side Fixture: `TestStubFactory`

A `@Replaces` factory that swaps the production stub bean for one wired to the in-process channel. The fixture parameter forces server start before the stub is constructed.

```groovy
@Factory
@Requires(env = "test")
class TestStubFactory {

    @Singleton
    @Replaces(bean = PipelineArtifactServiceGrpc.PipelineArtifactServiceBlockingStub.class)
    PipelineArtifactServiceGrpc.PipelineArtifactServiceBlockingStub testBlockingStub(
            InProcessGrpcServerFixture fixture) {
        // Fixture parameter forces server start before stub is used.
        def channel = InProcessChannelBuilder
            .forName(InProcessGrpcServerFixture.IN_PROCESS_NAME)
            .directExecutor()
            .build()
        return PipelineArtifactServiceGrpc.newBlockingStub(channel)
    }
}
```

`@Replaces(bean = ...)` swaps just the stub bean; the production `@Factory` is otherwise active and the `@GrpcChannel` config still parses (so a typo in production config still fails this spec).

## Full Client Spec with Roundtrip + Error Path

```groovy
@MicronautTest
class PipelineArtifactGrpcClientSpec extends Specification {

    @Inject PipelineArtifactGrpcClient client
    @Inject PipelineArtifactServiceGrpc.PipelineArtifactServiceBlockingStub stub
    @Inject InProcessGrpcServerFixture fixture

    void setup() {
        fixture.reset()
    }

    void "DI wiring smoke: client, stub, fixture all injected from the context"() {
        expect:
        client != null
        stub != null
        fixture != null
    }

    void "wrapper serializes every domain field across the wire"() {
        given:
        def expectedId = UUID.randomUUID()
        fixture.nextArtifactId = expectedId

        when:
        def returned = client.createArtifact(42, "hello world")

        then: "wrapper returns the parsed domain type"
        returned == expectedId

        and: "server received exactly what the wrapper sent"
        fixture.lastRequest.firmId == "42"
        fixture.lastRequest.payload == "hello world"
    }

    void "wrapper propagates server-side errors as StatusRuntimeException"() {
        given:
        fixture.failNextWith = Status.NOT_FOUND.withDescription("missing")

        when:
        client.createArtifact(42, "ignored")

        then:
        def e = thrown(StatusRuntimeException)
        e.status.code == Status.Code.NOT_FOUND
        e.status.description == "missing"
    }
}
```

## Channel Configuration (Production)

`application.yml`:
```yaml
grpc:
  channels:
    pipeline-orchestrator:
      # Split host/port avoids escaping a colon-bearing default value.
      address: "${UPSTREAM_GRPC_HOST:localhost}:${UPSTREAM_GRPC_PORT:50051}"
      plaintext: true
      max-retry-attempts: 3
```

`application-prod.yml`:
```yaml
grpc:
  channels:
    pipeline-orchestrator:
      address: "${UPSTREAM_GRPC_HOST}:${UPSTREAM_GRPC_PORT}"
      plaintext: true
      max-retry-attempts: 3
```

`plaintext: true` is correct only when the channel stays inside the cluster's private network. Anything crossing a trust boundary needs TLS — see `grpc.channels.{name}.transport-security` and `ssl-context`.
