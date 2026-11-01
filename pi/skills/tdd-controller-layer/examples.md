# Controller Layer Examples

## Full CRUD Controller

```java
@Controller("/api/firms")
@Secured(SecurityRule.IS_AUTHENTICATED)
public class FirmController {

    private final FirmService service;

    public FirmController(FirmService service) {
        this.service = service;
    }

    @Post
    public HttpResponse<Firm> create(@Body @Valid CreateFirmRequest request) {
        var firm = service.createFirm(request.getName(), request.getSubdomain());
        return HttpResponse.created(firm)
            .headers(h -> h.location(URI.create("/api/firms/" + firm.getId())));
    }

    @Get("/{id}")
    public HttpResponse<Firm> getById(@PathVariable Integer id) {
        return service.findById(id)
            .map(HttpResponse::ok)
            .orElse(HttpResponse.notFound());
    }

    @Put("/{id}")
    public HttpResponse<Firm> update(@PathVariable Integer id,
                                      @Body @Valid UpdateFirmRequest request) {
        var firm = service.updateName(id, request.getName());
        return HttpResponse.ok(firm);
    }

    @Delete("/{id}")
    public HttpResponse<Void> delete(@PathVariable Integer id) {
        service.delete(id);
        return HttpResponse.noContent();
    }
}
```

## Authentication Testing

```groovy
void "accepts valid basic auth"() {
    given:
    def request = HttpRequest.POST("/api/webhook", payload)
        .basicAuth("valid-user", "valid-password")

    when:
    def response = client.toBlocking().exchange(request, Void)

    then:
    response.status == HttpStatus.ACCEPTED
}

void "rejects invalid credentials"() {
    given:
    def request = HttpRequest.POST("/api/webhook", payload)
        .basicAuth("invalid-user", "wrong-password")

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.status == HttpStatus.UNAUTHORIZED
}

void "rejects unauthenticated request"() {
    given:
    def request = HttpRequest.POST("/api/webhook", payload)

    when:
    client.toBlocking().exchange(request, Void)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.status == HttpStatus.UNAUTHORIZED
}
```

## Disabling Security in Tests

```yaml
# src/test/resources/application-test.yml
micronaut:
  security:
    enabled: false
```

## DTO Validation

```java
public class CreateFirmRequest {
    @NotNull(message = "Name is required")
    @NotBlank(message = "Name cannot be blank")
    @Size(min = 2, max = 100)
    private String name;

    @NotNull @Pattern(regexp = "^[a-z0-9-]+$")
    private String subdomain;

    @Email
    private String contactEmail;
}
```

```groovy
void "rejects missing required field"() {
    given:
    def payload = [subdomain: "test"]  // no name

    when:
    client.toBlocking().exchange(HttpRequest.POST("/api/firms", payload), Void)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.status == HttpStatus.BAD_REQUEST
}
```

## Error Response Body Verification

```groovy
void "error response includes details"() {
    when:
    client.toBlocking().exchange(HttpRequest.POST("/api/firms", invalidPayload), Void)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.status == HttpStatus.BAD_REQUEST
    def errorBody = ex.response.getBody(Map).get()
    errorBody.message != null
}
```

## Subdomain Extraction from Host Header

```groovy
void "extracts subdomain from Host header"() {
    given:
    def request = HttpRequest.POST("/api/endpoint", payload)
        .header("Host", "testfirm.example.com")

    when:
    def response = client.toBlocking().exchange(request, Map)

    then:
    response.status == HttpStatus.OK
}
```

## Query Parameters

```groovy
void "supports query parameters"() {
    given:
    def request = HttpRequest.GET("/api/firms?active=true&page=0&size=10")

    when:
    def response = client.toBlocking().exchange(request, Map)

    then:
    response.status == HttpStatus.OK
}
```

## All Status Code Tests

```groovy
// 200 OK
response.status == HttpStatus.OK

// 201 CREATED
response.status == HttpStatus.CREATED

// 202 ACCEPTED
response.status == HttpStatus.ACCEPTED

// 204 NO_CONTENT
response.status == HttpStatus.NO_CONTENT

// Error codes — caught via HttpClientResponseException
def ex = thrown(HttpClientResponseException)
ex.status == HttpStatus.BAD_REQUEST          // 400
ex.status == HttpStatus.UNAUTHORIZED         // 401
ex.status == HttpStatus.NOT_FOUND            // 404
ex.status == HttpStatus.UNPROCESSABLE_ENTITY // 422
ex.status == HttpStatus.INTERNAL_SERVER_ERROR // 500
```

## Full HTTP Stack Template (BaseUpdatableRestController + Protobuf + JWT)

For controllers extending `BaseUpdatableRestController` with protobuf endpoints, use the full HTTP stack pattern. Confirmed with: DepartmentController, JudgeController, NotificationRuleController.

```groovy
@MicronautTest(packages = "com.goecfx.data")  // startApplication = true is the default for this pattern
class {ControllerName}Spec extends Specification {

    @Inject @Client('/api/v1/{resource}') HttpClient client
    @Inject DataSource dataSource
    @Inject JwtUtil jwtUtil

    static final int FIRM_ID = {unique_per_spec}   // unique to avoid cross-spec interference
    static final String SUBDOMAIN = "test-{resource}"
    static final String FK_TARGET_UUID = "deadbeef-0001-0001-0001-deadbeefcafe"

    @MockBean(SecurityUserRepository)
    SecurityUserRepository mockSecurityUserRepository() { Mock(SecurityUserRepository) }

    @MockBean(TokenBlacklistService)
    TokenBlacklistService mockTokenBlacklistService() { Mock(TokenBlacklistService) }

    def setup() {
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/schema.sql").toURI()))
        insertTestData()
    }

    def cleanup() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("DELETE FROM private.{table} WHERE firm_id = ${FIRM_ID}")
            conn.createStatement().execute("DELETE FROM private.firm WHERE id = ${FIRM_ID}")
        }
    }

    void "POST creates entity, returns proto with PublicId"() {
        given:
        def proto = {Resource}Proto.newBuilder()
            .setName("Test")
            .setJurisdictionId(new PublicId("jur", UUID.fromString(FK_TARGET_UUID)).toString())
            .build()

        when:
        def request = HttpRequest.POST('/', proto.toByteArray())
            .header("Host", "${SUBDOMAIN}.localhost.com")
            .bearerAuth(jwtUtil.generateToken("test-user", [roles: ['admin']]))

        def response = client.toBlocking().exchange(request, byte[])
        def returned = {Resource}Proto.parseFrom(response.body())

        then:
        response.status == HttpStatus.CREATED
        returned.publicId.length() > 0
        returned.name == "Test"
    }

    void "returns 401 when JWT missing"() {
        when:
        client.toBlocking().exchange(
            HttpRequest.POST('/', proto.toByteArray()).header("Host", "${SUBDOMAIN}.localhost.com"),
            byte[]
        )

        then:
        def ex = thrown(HttpClientResponseException)
        ex.status == HttpStatus.UNAUTHORIZED
    }

    private void insertTestData() {
        executeWithAutoCommit { conn ->
            conn.createStatement().execute("""
                INSERT INTO private.firm (id, name, subdomain, encryption_key_id)
                VALUES (${FIRM_ID}, 'Test Firm', '${SUBDOMAIN}',
                        '00000000-0000-0000-0000-000000000001')
                ON CONFLICT DO NOTHING
            """)
            conn.createStatement().execute("""
                INSERT INTO private.jurisdiction (id, firm_id, name)
                VALUES ('${FK_TARGET_UUID}', ${FIRM_ID}, 'Test Jurisdiction')
                ON CONFLICT DO NOTHING
            """)
        }
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

**Required `application-test.yml`**: `micronaut.server.port: -1` so adding new `@MockBean`s in sibling specs doesn't collide on a hardcoded port.

## Admin API Key Endpoint Test

For controllers under `/api/v1/admin/**` (guarded by `AdminApiKeyFilter`):

```groovy
void "admin endpoint accepts X-API-Key header, no JWT or host needed"() {
    given:
    def request = HttpRequest.POST('/api/v1/admin/webhook/resubmit', payload)
        .header("X-API-Key", "test-admin-key")     // matches ecfx.admin.api-key

    when:
    def response = client.toBlocking().exchange(request, Map)

    then:
    response.status == HttpStatus.ACCEPTED
}

void "admin endpoint returns 401 with wrong API key"() {
    given:
    def request = HttpRequest.POST('/api/v1/admin/webhook/resubmit', payload)
        .header("X-API-Key", "wrong-key")

    when:
    client.toBlocking().exchange(request, Map)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.status == HttpStatus.UNAUTHORIZED
}
```

Remember: admin paths skip `FirmHttpRequestFilter` entirely — no host header or tenant context needed. Use `@Secured(IS_ANONYMOUS)` on the controller method (the API key filter does its own auth).

## Conditional Endpoint with `Optional<GatedBean>`

```java
@Controller("/api/aaa/provisioning")
public class AaaProvisioningController {
    private final Optional<AaaProvisioningTrigger> trigger;

    public AaaProvisioningController(Optional<AaaProvisioningTrigger> trigger) {
        this.trigger = trigger;
    }

    @Post("/run")
    @ExecuteOn(TaskExecutors.BLOCKING)
    public HttpResponse<ProvisioningRunResponse> run() {
        return trigger
            .map(t -> { var r = t.runOnce(); return HttpResponse.accepted().body(ProvisioningRunResponse.completed(r.start(), r.end())); })
            .orElseGet(() -> HttpResponse.serverError(ProvisioningRunResponse.disabled()).status(HttpStatus.SERVICE_UNAVAILABLE));
    }
}
```

```groovy
void "returns 503 with body when trigger bean disabled"() {
    when:
    client.toBlocking().exchange(HttpRequest.POST('/api/aaa/provisioning/run', '').bearerAuth(jwt), ProvisioningRunResponse)

    then:
    def ex = thrown(HttpClientResponseException)
    ex.response.status == HttpStatus.SERVICE_UNAVAILABLE
    def body = ex.response.getBody(ProvisioningRunResponse).orElseThrow()
    body.code == 'DISABLED'
}
```
