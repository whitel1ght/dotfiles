# Transaction Boundary Validator - Examples

## Complete Example: Three-Layer Pattern

### Correct Implementation

**Controller Layer** (No @Transactional):
```java
package com.goecfx.controllers;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Post;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.rules.SecurityRule;

@Controller("/webhooks/postmark")
@Secured(SecurityRule.IS_AUTHENTICATED)
public class PostmarkWebhookController {
    private final EmailProcessingService service;

    public PostmarkWebhookController(EmailProcessingService service) {
        this.service = service;
    }

    @Post("/inbound")
    public HttpResponse<Void> handleInbound(@Body PostmarkInboundRequest request) {
        // No @Transactional - delegate to service
        service.processInboundEmail(request);
        return HttpResponse.ok();
    }

    @Post("/bounce")
    public HttpResponse<Void> handleBounce(@Body PostmarkBounceRequest request) {
        // No @Transactional - delegate to service
        service.processBounce(request);
        return HttpResponse.ok();
    }
}
```

**Service Layer** (@Transactional on methods):
```java
package com.goecfx.services;

import com.goecfx.data.entities.EmailInboxItem;
import com.goecfx.data.entities.Firm;
import com.goecfx.data.entities.InboxItemProcessJob;
import com.goecfx.repositories.EmailInboxItemRepository;
import com.goecfx.repositories.FirmRepository;
import com.goecfx.repositories.InboxItemProcessJobRepository;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;

@Singleton
public class EmailProcessingService {
    private final EmailInboxItemRepository emailRepository;
    private final InboxItemProcessJobRepository jobRepository;
    private final FirmRepository firmRepository;

    public EmailProcessingService(
        EmailInboxItemRepository emailRepository,
        InboxItemProcessJobRepository jobRepository,
        FirmRepository firmRepository
    ) {
        this.emailRepository = emailRepository;
        this.jobRepository = jobRepository;
        this.firmRepository = firmRepository;
    }

    @Transactional  // ✅ CORRECT: Service method managing transaction
    public void processInboundEmail(PostmarkInboundRequest request) {
        // Multiple repository operations in single transaction
        Firm firm = firmRepository.findByEmailDomain(extractDomain(request.getFrom()))
            .orElseThrow(() -> new FirmNotFoundException());

        EmailInboxItem item = new EmailInboxItem();
        item.setFirm(firm);
        item.setRawEmail(request.getRawEmail());
        item.setStatus(EmailInboxItem.Status.PENDING);
        EmailInboxItem saved = emailRepository.save(item);

        InboxItemProcessJob job = new InboxItemProcessJob();
        job.setParent(saved);
        job.setFirm(firm);
        job.setStatus(InboxItemProcessJob.Status.PENDING);
        jobRepository.save(job);
    }

    @Transactional(readOnly = true)  // ✅ CORRECT: Read-only transaction
    public List<EmailInboxItem> findPendingItems(Long firmId) {
        return emailRepository.findByFirmIdAndStatus(firmId, EmailInboxItem.Status.PENDING);
    }

    @Transactional  // ✅ CORRECT: Update operation
    public void markAsProcessed(Long itemId) {
        EmailInboxItem item = emailRepository.findById(itemId)
            .orElseThrow(() -> new ItemNotFoundException());
        item.setStatus(EmailInboxItem.Status.PROCESSED);
        emailRepository.update(item);
    }

    // Private helper - no @Transactional needed
    private String extractDomain(String email) {
        return email.substring(email.indexOf('@') + 1);
    }
}
```

**Repository Layer** (No @Transactional):
```java
package com.goecfx.repositories;

import com.goecfx.data.entities.EmailInboxItem;
import io.micronaut.data.annotation.Repository;
import io.micronaut.data.jpa.repository.JpaRepository;

import java.util.List;

@Repository
public interface EmailInboxItemRepository extends JpaRepository<EmailInboxItem, Long> {
    // No @Transactional annotations needed
    List<EmailInboxItem> findByFirmId(Long firmId);

    List<EmailInboxItem> findByFirmIdAndStatus(Long firmId, EmailInboxItem.Status status);

    List<EmailInboxItem> findByStatus(EmailInboxItem.Status status);
}
```

---

## Violation Examples and Fixes

### Violation 1: Controller with @Transactional

**WRONG**:
```java
@Controller("/api/items")
public class ItemController {
    private final ItemRepository repository;

    @Post
    @Transactional  // ❌ VIOLATION: Controller managing transaction
    public HttpResponse<Item> createItem(@Body ItemRequest request) {
        Item item = new Item();
        item.setName(request.getName());
        repository.save(item);
        return HttpResponse.created(item);
    }
}
```

**CORRECT**:
```java
@Controller("/api/items")
public class ItemController {
    private final ItemService service;  // Use service instead of repository

    @Post
    public HttpResponse<Item> createItem(@Body ItemRequest request) {
        Item item = service.createItem(request);  // Service handles transaction
        return HttpResponse.created(item);
    }
}

// In ItemService.java:
@Singleton
public class ItemService {
    private final ItemRepository repository;

    @Transactional  // ✅ Transaction in service layer
    public Item createItem(ItemRequest request) {
        Item item = new Item();
        item.setName(request.getName());
        return repository.save(item);
    }
}
```

---

### Violation 2: Repository with @Transactional

**WRONG**:
```java
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    @Transactional  // ❌ VIOLATION: Redundant, repositories already transactional
    List<Item> findByStatus(String status);

    @Transactional  // ❌ VIOLATION: Unnecessary
    @Query("UPDATE Item i SET i.processed = true WHERE i.id = :id")
    void markAsProcessed(@Param("id") Long id);
}
```

**CORRECT**:
```java
@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {
    List<Item> findByStatus(String status);  // ✅ No annotation needed

    @Query("UPDATE Item i SET i.processed = true WHERE i.id = :id")
    void markAsProcessed(@Param("id") Long id);  // ✅ No annotation needed
}
```

---

### Violation 3: Service Missing @Transactional

**WRONG**:
```java
@Singleton
public class OrderService {
    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;

    // ❌ MISSING @Transactional: Multiple saves should be atomic
    public void createOrder(OrderRequest request) {
        Order order = new Order();
        order.setCustomerId(request.getCustomerId());
        order.setTotal(request.getTotal());
        orderRepository.save(order);

        // If this fails, order is still saved (data inconsistency!)
        Inventory inventory = inventoryRepository.findById(request.getItemId())
            .orElseThrow();
        inventory.setQuantity(inventory.getQuantity() - request.getQuantity());
        inventoryRepository.update(inventory);
    }
}
```

**CORRECT**:
```java
@Singleton
public class OrderService {
    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;

    @Transactional  // ✅ Both operations atomic - rollback if either fails
    public void createOrder(OrderRequest request) {
        Order order = new Order();
        order.setCustomerId(request.getCustomerId());
        order.setTotal(request.getTotal());
        orderRepository.save(order);

        Inventory inventory = inventoryRepository.findById(request.getItemId())
            .orElseThrow();
        inventory.setQuantity(inventory.getQuantity() - request.getQuantity());
        inventoryRepository.update(inventory);
    }
}
```

---

### Violation 4: Wrong Import (Spring instead of Micronaut)

**WRONG**:
```java
package com.goecfx.services;

import org.springframework.transaction.annotation.Transactional;  // ❌ Wrong framework!
import jakarta.inject.Singleton;

@Singleton
public class EmailService {
    @Transactional  // Won't work - this is Spring annotation
    public void processEmail(Email email) {
        // ...
    }
}
```

**CORRECT**:
```java
package com.goecfx.services;

import io.micronaut.transaction.annotation.Transactional;  // ✅ Micronaut annotation
import jakarta.inject.Singleton;

@Singleton
public class EmailService {
    @Transactional  // ✅ Works correctly
    public void processEmail(Email email) {
        // ...
    }
}
```

---

## Class-Level @Transactional Example

**Valid use case**:
```java
@Singleton
@Transactional  // ✅ Applies to all public methods
public class ItemManagementService {
    private final ItemRepository itemRepository;
    private final AuditLogRepository auditRepository;

    // Automatically transactional
    public Item createItem(ItemRequest request) {
        Item item = new Item();
        item.setName(request.getName());
        Item saved = itemRepository.save(item);

        AuditLog log = new AuditLog();
        log.setAction("CREATE");
        log.setItemId(saved.getId());
        auditRepository.save(log);

        return saved;
    }

    // Also automatically transactional
    public void updateItem(Long id, ItemRequest request) {
        Item item = itemRepository.findById(id).orElseThrow();
        item.setName(request.getName());
        itemRepository.update(item);

        AuditLog log = new AuditLog();
        log.setAction("UPDATE");
        log.setItemId(id);
        auditRepository.save(log);
    }

    // Read-only override
    @Transactional(readOnly = true)
    public Item findById(Long id) {
        return itemRepository.findById(id).orElseThrow();
    }

    // Private methods don't need annotation (use transaction from caller)
    private void validateItem(Item item) {
        // Validation logic
    }
}
```

---

## Complex Example: Nested Service Calls

**Correct pattern with service composition**:

```java
@Singleton
public class OrderProcessingService {
    private final OrderService orderService;
    private final PaymentService paymentService;
    private final NotificationService notificationService;

    @Transactional  // ✅ Top-level transaction
    public void processOrder(OrderRequest request) {
        // This starts a transaction

        // Creates order (participates in same transaction)
        Order order = orderService.createOrder(request);

        // Process payment (participates in same transaction)
        paymentService.processPayment(order.getId(), request.getPaymentInfo());

        // Send notification (participates in same transaction if it saves data)
        notificationService.sendOrderConfirmation(order);
    }
}

@Singleton
public class OrderService {
    private final OrderRepository orderRepository;

    @Transactional  // Uses existing transaction if called from transactional method
    public Order createOrder(OrderRequest request) {
        Order order = new Order();
        order.setCustomerId(request.getCustomerId());
        order.setStatus(Order.Status.PENDING);
        return orderRepository.save(order);
    }
}

@Singleton
public class PaymentService {
    private final PaymentRepository paymentRepository;

    @Transactional  // Uses existing transaction if called from transactional method
    public void processPayment(Long orderId, PaymentInfo info) {
        Payment payment = new Payment();
        payment.setOrderId(orderId);
        payment.setAmount(info.getAmount());
        payment.setStatus(Payment.Status.COMPLETED);
        paymentRepository.save(payment);
    }
}
```

**What happens**:
- `processOrder()` starts transaction
- `createOrder()` and `processPayment()` participate in same transaction
- If any method throws exception, entire transaction rolls back
- All saves happen atomically

---

## Read-Only Transaction Example

**Efficient read-only queries**:
```java
@Singleton
public class ReportingService {
    private final OrderRepository orderRepository;
    private final ItemRepository itemRepository;

    @Transactional(readOnly = true)  // ✅ Optimized for reads
    public OrderReport generateReport(Long customerId) {
        List<Order> orders = orderRepository.findByCustomerId(customerId);
        List<Item> items = itemRepository.findByOrderIds(
            orders.stream().map(Order::getId).collect(Collectors.toList())
        );

        return new OrderReport(orders, items);
    }

    @Transactional(readOnly = true)  // ✅ Read-only for search
    public List<Order> searchOrders(SearchCriteria criteria) {
        return orderRepository.findByCriteria(criteria);
    }
}
```

**Benefits of readOnly = true**:
- Performance optimization (no flush, no dirty checking)
- Database routing to read replicas (if configured)
- Prevents accidental writes

---

## Exception Handling and Rollback

**Default rollback behavior**:
```java
@Singleton
public class ItemService {
    private final ItemRepository itemRepository;

    @Transactional
    public void createItem(ItemRequest request) {
        Item item = new Item();
        item.setName(request.getName());
        itemRepository.save(item);

        if (item.getName().isEmpty()) {
            // RuntimeException triggers automatic rollback
            throw new ValidationException("Name cannot be empty");
        }

        // If exception thrown above, save is rolled back
    }
}
```

**Catching exceptions without breaking transaction**:
```java
@Transactional
public void processItems(List<ItemRequest> requests) {
    for (ItemRequest request : requests) {
        try {
            Item item = createItem(request);
            itemRepository.save(item);
        } catch (ValidationException e) {
            // Log and continue - transaction continues
            log.warn("Skipping invalid item: {}", e.getMessage());
        }
    }
    // Transaction commits with successfully processed items
}
```

**Explicit rollback**:
```java
@Transactional
public void riskyOperation(Item item) {
    itemRepository.save(item);

    if (isRisky(item)) {
        // Force rollback even without exception
        throw new RollbackException("Too risky to commit");
    }
}
```

---

## Testing Transaction Boundaries

**Service test with mocked repository**:
```groovy
@MicronautTest
class ItemServiceSpec extends Specification {
    @Inject ItemService service

    @MockBean(ItemRepository)
    ItemRepository repository = Mock()

    void "service method should be transactional"() {
        given:
        ItemRequest request = new ItemRequest(name: "Test Item")

        when:
        service.createItem(request)

        then:
        1 * repository.save(_) >> { Item item ->
            assert item.name == "Test Item"
            return item
        }
    }

    void "transaction should rollback on exception"() {
        given:
        ItemRequest request = new ItemRequest(name: "")

        when:
        service.createItem(request)

        then:
        thrown(ValidationException)
        // Verify save was called but rolled back
        1 * repository.save(_)
    }
}
```

**Integration test with real database**:
```groovy
@MicronautTest
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ItemServiceIntegrationSpec extends Specification {
    @Inject DataSource dataSource
    @Inject ItemService service
    @Inject ItemRepository repository

    void setupSpec() {
        SchemaLoader.loadSchema(dataSource, "db/schema.sql")
    }

    void "transaction should commit on success"() {
        given:
        ItemRequest request = new ItemRequest(name: "Test Item")

        when:
        service.createItem(request)

        then:
        repository.findByName("Test Item").isPresent()
    }

    void "transaction should rollback on exception"() {
        given:
        ItemRequest request = new ItemRequest(name: "")

        when:
        service.createItem(request)

        then:
        thrown(ValidationException)
        repository.findByName("").isEmpty()
    }
}
```
