# Java Clean Code Commandments — code reference

Bad → clean examples for the commandments whose violations are easy to miss in review. Trivial cases (empty catch, commented-out code, `System.out.println`) are omitted — you know them when you see them.

## I. Type discipline

**Unchecked cast → pattern matching:**

```java
// VIOLATION — cast after check, and the check can drift from the cast
if (event.getPayload() instanceof NoticeEvent) {
    NoticeEvent notice = (NoticeEvent) event.getPayload();
    process(notice);
}

// CLEAN — one atomic check-and-bind
if (event.getPayload() instanceof NoticeEvent notice) {
    process(notice);
}
```

**Silent default absorbing future enum variants:**

```java
// VIOLATION — when Status gains CANCELED, this silently treats it as "not final"
return switch (status) {
    case SUCCEEDED, FAILED -> true;
    default -> false;
};

// CLEAN — exhaustive; adding a variant breaks the build here, which is the point
return switch (status) {
    case SUCCEEDED, FAILED -> true;
    case NEW, STARTED, RETRY -> false;
};
```

**Optional discipline:**

```java
// VIOLATION — Optional as parameter forces every caller to wrap
void notify(Optional<String> email) { ... }

// CLEAN — overload or nullable-with-contract at the edge, Optional on returns only
Optional<Envelope> findByCourtEnvelopeId(String id);
Envelope envelope = repo.findByCourtEnvelopeId(id)
    .orElseThrow(() -> new EnvelopeNotFoundException(id));   // never bare .get()
```

## II. Error swallowing

**Cause dropped on rewrap:**

```java
// VIOLATION — the stack trace of the real failure is gone forever
} catch (SQLException e) {
    throw new ProcessingException("failed to save notice " + noticeId);
}

// CLEAN — context AND cause
} catch (SQLException e) {
    throw new ProcessingException("failed to save notice %s".formatted(noticeId), e);
}
```

**InterruptedException:**

```java
// VIOLATION — the interrupt signal is silently destroyed; shutdown hangs
} catch (InterruptedException e) {
    log.warn("interrupted");
}

// CLEAN
} catch (InterruptedException e) {
    Thread.currentThread().interrupt();
    throw new JobAbortedException("interrupted while polling court portal", e);
}
```

**Log lines that can be acted on:**

```java
// VIOLATION — which item? which firm? un-queryable
log.error("Failed to process item", e);

// CLEAN — structured, parameterized, identifying
log.error("Failed to process inboxItem={} firm={} attempt={}", item.getId(), firmId, attempt, e);
```

## III. Event loop and hidden state

**Blocking on the event loop:**

```java
// VIOLATION — JDBC call runs on the Netty event loop; every request on this
// loop stalls behind the query
@Get("/notices/{id}")
public NoticeDto get(UUID id) {
    return noticeService.load(id);   // hits the database
}

// CLEAN
@Get("/notices/{id}")
@ExecuteOn(TaskExecutors.BLOCKING)
public NoticeDto get(UUID id) {
    return noticeService.load(id);
}
```

**Mutable singleton state:**

```java
// VIOLATION — two concurrent requests interleave on this map
@Singleton
public class RateTracker {
    private final Map<String, Integer> counts = new HashMap<>();
    public void hit(String key) { counts.merge(key, 1, Integer::sum); }
}

// CLEAN
private final Map<String, Integer> counts = new ConcurrentHashMap<>();
```

**Fire-and-forget with no error path:**

```java
// VIOLATION — if upload fails, nobody ever knows (Commandment II by another road)
CompletableFuture.runAsync(() -> s3Client.upload(document));

// CLEAN
CompletableFuture.runAsync(() -> s3Client.upload(document))
    .exceptionally(e -> {
        log.error("async upload failed document={}", document.getId(), e);
        metrics.increment("document.upload.failed");
        return null;
    });
```

## V. Meaningful Spock assertions

```groovy
// VIOLATION — passes for almost any implementation, including wrong ones
def "processes the notice"() {
    when:
    def result = processor.process(item)

    then:
    result != null
    notThrown(Exception)
}

// CLEAN — asserts the specific contract: outcome, routing, and side effect
def "routes credential failures to the firm, not ECFX ops"() {
    given:
    portal.login(_) >> { throw new InvalidCredentialsException("expired") }

    when:
    processor.process(item)

    then:
    item.status == InboxItem.Status.FAILED
    item.actionRequired == InboxItem.ActionRequired.USER
    0 * ecfxAlertService.notify(_)
}
```

## VI. Layer boundaries

```java
// VIOLATION — entity crosses the HTTP boundary: leaks schema, drags lazy
// relations into serialization, couples the API contract to the table
@Get("/cases/{id}")
public Case get(UUID id) { return caseRepository.findById(id).orElseThrow(); }

// CLEAN — controller → service → DTO
@Get("/cases/{id}")
@ExecuteOn(TaskExecutors.BLOCKING)
public CaseDto get(UUID id) { return caseService.getCase(id); }
```

## VIII. Naming

| Violation | Clean | Why |
|---|---|---|
| `boolean active` | `boolean isActive` | reads as a question |
| `void handleClick()` | `void submitOrderForm()` | action, not trigger |
| `int timeout` | `int timeoutMs` | unit is part of the value |
| `Map<String, Object> data` | `Map<String, CourtConfig> configsByCounty` | says what and keyed how |
| `class NoticeManager` (parse + save + email + retry) | one class per responsibility | "Manager" is a confession the class has no single job |

## X. Config externalization

```java
// VIOLATION — works in dev, silently wrong (or an outage) in prod
private static final String BUCKET = "ecfx-documents-dev";

// CLEAN — property with per-environment override
@Value("${ecfx.documents.bucket-name}")
private String bucketName;
```

With the matching key present in **every** environment's config — `deployment-parity-review` owns verifying that.

## Grep starters for an audit

Quick signal, not proof — each hit still needs human judgment (and generated code is exempt):

```bash
# I — type escapes
grep -rn '@SuppressWarnings("unchecked")' --include='*.java' src/
grep -rn '\.get()' --include='*.java' src/ | grep -i optional

# II — swallowed errors
grep -rn 'catch.*{[[:space:]]*}' --include='*.java' src/
grep -rn 'printStackTrace\|System\.out\.print' --include='*.java' src/

# III — event loop (controllers with no executor annotation)
grep -rln '@Controller' --include='*.java' src/ | xargs grep -L 'ExecuteOn'

# IX — dead code and debt
grep -rn 'TODO' --include='*.java' src/ | grep -v 'ECFX-'

# X — suspicious literals
grep -rnE '(password|secret|api[_-]?key)\s*=\s*"' --include='*.java' --include='*.yml' src/
```
