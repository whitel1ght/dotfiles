# Service Layer Examples

## Service with Multiple Dependencies

```java
@Singleton
public class OrderProcessingService {

    private final OrderRepository orderRepository;
    private final FirmRepository firmRepository;
    private final NotificationService notificationService;  // external — will be mocked

    public OrderProcessingService(OrderRepository orderRepository,
                                   FirmRepository firmRepository,
                                   NotificationService notificationService) {
        this.orderRepository = orderRepository;
        this.firmRepository = firmRepository;
        this.notificationService = notificationService;
    }

    @Transactional
    public Order createOrder(Integer firmId, CreateOrderRequest request) {
        var firm = firmRepository.findById(firmId)
            .orElseThrow(() -> new FirmNotFoundException(firmId));

        var order = new Order();
        order.setFirmId(firm.getId());
        order.setDescription(request.getDescription());
        var saved = orderRepository.save(order);

        notificationService.notifyOrderCreated(saved);
        return saved;
    }
}
```

## Integration Test with Real Repositories + Mocked External Service

```groovy
@MicronautTest(startApplication = false, packages = "com.goecfx.data")
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class OrderProcessingServiceSpec extends Specification {

    @Inject OrderProcessingService service
    @Inject OrderRepository orderRepository       // REAL
    @Inject FirmRepository firmRepository          // REAL
    @Inject NotificationService notificationService  // MOCKED
    @Inject DataSource dataSource

    @MockBean(NotificationService)
    NotificationService mockNotification() { Mock(NotificationService) }

    def setup() {
        // SchemaLoader is idempotent — no guards needed
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/db/schema.sql").toURI()))
        insertTestData()
    }

    void "creates order with real DB persistence"() {
        given: "a firm exists in the database"
        def firm = firmRepository.save(new Firm(
            name: "Test Firm",
            subdomain: "test-${UUID.randomUUID().toString().substring(0,8)}",
            encryptionKeyId: UUID.randomUUID()
        ))

        when: "creating an order through the service"
        def result = service.createOrder(firm.id, new CreateOrderRequest(description: "Test Order"))

        then: "order is persisted in the database"
        result.id != null
        result.firmId == firm.id
        result.description == "Test Order"

        and: "we can retrieve it from the database"
        def fromDb = orderRepository.findById(result.id)
        fromDb.present
        fromDb.get().description == "Test Order"

        and: "notification was sent"
        1 * notificationService.notifyOrderCreated(_)
    }

    void "throws FirmNotFoundException for non-existent firm"() {
        when: "creating order with non-existent firm"
        service.createOrder(99999, new CreateOrderRequest(description: "Test"))

        then:
        def ex = thrown(FirmNotFoundException)
        ex.message.contains("99999")

        and: "no notification sent"
        0 * notificationService.notifyOrderCreated(_)
    }
}
```

## Transaction Rollback with Real Database

```groovy
@MicronautTest(startApplication = false, transactional = false, packages = "com.goecfx.data")
@Property(name = "datasource.default.schema", value = "private,public_v1,extensions")
class TransactionalOrderServiceSpec extends Specification {

    @Inject OrderProcessingService service
    @Inject OrderRepository orderRepository
    @Inject FirmRepository firmRepository
    @Inject NotificationService notificationService
    @Inject DataSource dataSource

    @MockBean(NotificationService)
    NotificationService mockNotification() { Mock(NotificationService) }

    def setup() {
        SchemaLoader.loadSchema(dataSource, new File(getClass().getResource("/db/schema.sql").toURI()))
        insertTestData()
    }

    void "rolls back order when notification throws"() {
        given: "a firm exists"
        def firm = firmRepository.save(new Firm(
            name: "Rollback Firm",
            subdomain: "rollback-${UUID.randomUUID().toString().substring(0,8)}",
            encryptionKeyId: UUID.randomUUID()
        ))

        and: "notification service will throw"
        notificationService.notifyOrderCreated(_) >> { throw new RuntimeException("Email service down") }

        and: "initial order count"
        def initialCount = orderRepository.count()

        when: "creating order"
        service.createOrder(firm.id, new CreateOrderRequest(description: "Should Rollback"))

        then: "exception propagates"
        thrown(RuntimeException)

        and: "order was NOT persisted (transaction rolled back)"
        orderRepository.count() == initialCount
    }
}
```

## Exception Handling Pattern

```java
public class FirmNotFoundException extends RuntimeException {
    private final Object identifier;

    public FirmNotFoundException(Integer firmId) {
        super(String.format("Firm not found with ID: %d", firmId));
        this.identifier = firmId;
    }

    public FirmNotFoundException(String subdomain) {
        super(String.format("Firm not found with subdomain: %s", subdomain));
        this.identifier = subdomain;
    }

    public Object getIdentifier() { return identifier; }
}
```

```groovy
void "exception contains correct identifier"() {
    when: "looking up non-existent subdomain"
    service.getBySubdomain("nonexistent")

    then:
    def ex = thrown(FirmNotFoundException)
    ex.message.contains("nonexistent")
}
```

## Input Validation Pattern

```java
@Transactional
public EmailInboxItem createInboxItem(Integer firmId, String rawEmail) {
    if (firmId == null) throw new IllegalArgumentException("Firm ID cannot be null");
    if (rawEmail == null || rawEmail.isBlank()) throw new IllegalArgumentException("Raw email cannot be blank");

    var item = new EmailInboxItem();
    item.setFirmId(firmId);
    item.setRawEmail(rawEmail);
    return repository.save(item);
}
```

```groovy
void "rejects null firm ID"() {
    when:
    service.createInboxItem(null, "email")

    then:
    def ex = thrown(IllegalArgumentException)
    ex.message.contains("Firm ID")
}
```

## Test Data Setup Patterns

### Using Repository in `given:` Block

```groovy
void "finds orders by firm"() {
    given: "a firm with orders in the database"
    def firm = firmRepository.save(new Firm(name: "Test", subdomain: "find-test-${UUID.randomUUID().toString().substring(0,8)}"))
    orderRepository.save(new Order(firmId: firm.id, description: "Order 1"))
    orderRepository.save(new Order(firmId: firm.id, description: "Order 2"))

    when:
    def results = service.getOrdersByFirm(firm.id)

    then:
    results.size() == 2
    results.every { it.firmId == firm.id }
}
```

### Shared Setup with `setup()` Method

```groovy
Integer testFirmId

def setup() {
    // ... schema loading ...

    // Create shared test firm (idempotent via unique subdomain)
    def firm = firmRepository.save(new Firm(
        name: "Shared Test Firm",
        subdomain: "shared-${UUID.randomUUID().toString().substring(0,8)}"
    ))
    testFirmId = firm.id
}
```

## javap Verification

```bash
# Find library JAR
find ~/.gradle/caches -name "data-*.jar"

# Inspect actual methods
javap -public -cp /path/to/data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
```

Always verify external library APIs exist before implementing against them.
