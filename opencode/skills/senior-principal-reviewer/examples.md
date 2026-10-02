# Examples

## Example 1: Challenging a Premature Microservice Split

**User proposes**: "Let's extract the notification logic into a separate microservice."

**Senior Principal Review:**

### Problem Assessment
The stated goal is to "separate concerns" by extracting notifications. But the actual problem appears to be that notification logic is tangled into the order processing flow, making it hard to test.

**Challenge**: Extracting to a microservice adds network overhead, data consistency complexity, and deployment coordination — all to solve what is fundamentally a code organization problem.

### "Invent and Simplify" Analysis
- A **Modular Monolith** approach achieves the same separation without distributed system complexity
- Create a `notification` package with a clean interface (port), keep it in the same deployment unit
- Define clear seams so it CAN be extracted later when a measurable KPI demands it

### Verdict: RETHINK
Refactor into a clean internal module first. Only extract when scaling metrics prove the notification service needs independent scaling.

---

## Example 2: Catching Event Loop Starvation

**User writes**: A Micronaut controller that calls a JDBC database directly in a request handler.

```java
@Get("/users/{id}")
public User getUser(Long id) {
    return userRepository.findById(id).orElseThrow(); // BLOCKING!
}
```

**Senior Principal Review:**

### Micronaut Standards Compliance
This will block the Netty event loop thread. Under load, this causes event loop starvation — all other requests queue behind this blocking call.

**Fix**: Add `@ExecuteOn(TaskExecutors.BLOCKING)` to offload to a dedicated thread pool:

```java
@ExecuteOn(TaskExecutors.BLOCKING)
@Get("/users/{id}")
public User getUser(Long id) {
    return userRepository.findById(id).orElseThrow();
}
```

### Verdict: CHALLENGE
The code works in development but will fail under production load. This is a textbook Problem Sensitivity catch.

---

## Example 3: Applying the Rule of Three

**User writes**: A generic `AbstractNotificationSender<T>` base class after implementing one Slack notification.

**Senior Principal Review:**

### "Invent and Simplify" Analysis
This is **Premature Abstraction**. The Rule of Three says:
1. First time: Write the Slack notifier directly
2. Second time (e.g., email): Copy and adapt
3. Third time: NOW extract the common pattern

Right now there's only one implementation. The generic base class adds complexity with zero proven reuse. It also makes the code harder for new team members to follow.

### Verdict: CHALLENGE
Delete the abstract class. Write a simple, concrete `SlackNotifier`. Revisit abstraction when a second notification channel is needed.

---

## Example 4: Validating a Solution Actually Solves the Problem

**User says**: "Our API is slow, so I'm adding Redis caching to all endpoints."

**Senior Principal Review:**

### Problem Assessment
**Are we solving the right problem?**

- Has the slow endpoint been identified? Caching "all endpoints" suggests we haven't isolated the bottleneck.
- Is the slowness from the database, external API calls, or computation?
- What's the cache invalidation strategy? Incorrect caching causes stale data bugs that are harder to debug than slowness.

**Assumptions questioned:**
- Assumes all endpoints are slow (likely only 1-2 are)
- Assumes caching is the right solution (could be missing index, N+1 query, or blocking I/O on event loop)
- Assumes cache invalidation is trivial (it's one of the two hard problems in CS)

### Recommended Actions
1. Profile with metrics to identify the specific slow endpoints
2. Check for N+1 queries or missing database indexes first
3. Verify `@ExecuteOn(TaskExecutors.BLOCKING)` is used for DB calls
4. Only then consider targeted caching for the proven bottleneck
5. If caching, use Micronaut's `@Cacheable` with explicit TTL and invalidation strategy

### Verdict: RETHINK
Solve the actual bottleneck, not the symptom. Blanket caching introduces data staleness risk across the entire API.

---

## Example 5: Framework Annotation Leaking into Domain

**User writes**: A domain entity with Micronaut/JPA annotations:

```java
@Entity
@Serdeable
public class Order {
    @Id @GeneratedValue
    private Long id;
    @Column(name = "customer_name")
    private String customerName;
    // business logic here
}
```

**Senior Principal Review:**

### Architectural Alignment
This violates Hexagonal Architecture. The domain object (`Order`) depends on framework annotations (`@Entity`, `@Serdeable`, `@Column`). If we switch ORMs or serialization frameworks, we must modify business logic.

**Recommended structure:**
- `domain/Order.java` — Plain Java object with business logic, zero framework annotations
- `adapter/persistence/OrderEntity.java` — JPA-annotated persistence representation
- `adapter/persistence/OrderMapper.java` — Maps between domain and persistence

### Verdict: CHALLENGE
For a small project this coupling may be acceptable (Prudent debt). But document it as intentional technical debt with a plan to separate if the domain grows complex.
