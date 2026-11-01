# Receipt Processor Guardrails — Reference

Verified against ecfx-backend on 2026-07-02. Paths relative to the repo root (`~/gitlab/ecfx-backend-v4/ecfx-backend`). If a class listed here has moved, trust the code — and update this file.

## Exception hierarchy

Package `com.goecfx.backend.receipts.exceptions`, directory `projects/receipt_processing/src/main/java/com/goecfx/backend/receipts/exceptions/`.

```
ReceiptProcessingException (abstract, extends Exception)
├── AutoRetryableReceiptProcessingException (abstract)          ← retryable base
│   └── UnlimitedRetryReceiptProcessingException (abstract, @UnlimitedRetry)
│       └── KeepWaitingForStampException
├── ServerReceiptProcessingException (abstract)                 ← terminal, Action Required: ECFX
│   └── UnknownProcessingException                              ← where unclassified errors land
├── UserReceiptProcessingException (abstract, @UserActionRequired) ← terminal, Action Required: USER
│   └── (subclasses add getFriendlyName(), getActionParameters())
├── DelayProcessingException (@Getter LocalDateTime runAfter)   ← scheduling signal, not failure
│   ├── ConcurrentSessionInUseException
│   └── DocumentTimestampRetryException
└── IgnoreItemException (abstract)                              ← ignore bucket
```

Direct subclasses of `AutoRetryableReceiptProcessingException` (as of 2026-07): `BrowserAutomationTimeoutException`, `BrowserAutomationException`, `AutoRetryableUserReceiptProcessingException`, `CaptchaSolverRetryException`, `CredentialCachingRetryException`, `CredentialEncryptionProcessingException`, `DataConstraintViolationException`, `DocumentDownloadException`, `DocumentNotFoundException`, `DocumentUnavailableException`, `LockContentionRetryException`, `ReceiptProcessingDocumentStorageException`, `ProviderHTTPReceiptProcessingException`, `ReceiptWebParseException`, `ServiceRateLimitExceededException`, `SocketException`, `ServiceUnavailableException`, `UserAlreadyLoggedInException`.

The markers `@UserActionRequired` and `@UnlimitedRetry` are `@Target(TYPE) @Inherited @Retention(RUNTIME) @Qualifier` annotations in the same package. `@Inherited` means every subclass of `UserReceiptProcessingException` automatically routes to USER.

## Retry engine

`projects/receipt_processing_queue/src/main/java/com/goecfx/backend/receipts/processors/InboxItemProcessJobProcessor.java`, `handleJobFailure(...)` (~lines 443–489):

```java
boolean isUnlimitedRetry = unlimitedRetryEnabled
        && job.getErrorExceptionClass() != null
        && job.getErrorExceptionClass().isAnnotationPresent(UnlimitedRetry.class);
int absoluteAttemptCap = job.getMaxAttempts() * 2;
boolean withinAbsoluteCap = isUnlimitedRetry || counts.totalCount() < absoluteAttemptCap;

if ((isUnlimitedRetry || counts.sameClassCount() < job.getMaxAttempts())
        && withinAbsoluteCap
        && !isInboxItemProcessJobBlacklisted(job)) {
    job.requeueWithProviderDelay(counts.sameClassCount());          // RETRY
} else {
    boolean isStampWaitTimeout = errorClass != null
            && StampedDocumentUnavailableAfterWaitingException.class.isAssignableFrom(errorClass);
    boolean isUserAction = errorClass != null
            && errorClass.isAnnotationPresent(UserActionRequired.class)
            && (userActionRoutingEnabled || isStampWaitTimeout);
    if (isUserAction) { job.getParent().markUserActionRequired(); } // Action Required: USER
    else { job.getParent().markEcfxActionRequired(); }              // Action Required: ECFX
}
```

Key facts:
- `InboxItemProcessJob.MAX_ATTEMPTS = 10` (`projects/data/src/main/java/com/goecfx/data/models/InboxItemProcessJob.java:36`); `getMaxAttempts()` is a per-provider `Supplier<Integer>` defaulting to it.
- Per-exception counter matches on the exception **simple class name** (persisted in the `error_exception` column as a string).
- Absolute cap `maxAttempts * 2` over all non-DELAYED attempts (ECFX-13665, the 12-months-stuck fix).
- Backoff in `requeueWithProviderDelay`: `existingAttempts < 8 ? 2^existingAttempts minutes : 4 hours`.
- Feature flags: `ecfx.receipt-processing.user-action-routing-enabled` (default false), `ecfx.receipt-processing.unlimited-retry-enabled` (default false).
- `BaseProcessJob.errorExceptionClass` is the in-memory `Class` (same processing pass only); `getErrorException()` returns the persisted simple-name string.

## Statuses and routing enums

- `InboxItem.Status` (`projects/data/src/main/java/com/goecfx/data/models/InboxItem.java:93`): `NEW, RETRY, STARTED, FAILED, SUCCEEDED, MANUAL, CANCELED, POST_PROCESSING`.
- `JobStatus` (`projects/data/src/main/java/com/goecfx/data/models/enums/JobStatus.java`): `NEW, STARTED, FAILED, SUCCEEDED, CANCELED, DELAYED`.
- `InboxItem.ActionRequired`: `USER, ECFX` — set via `markUserActionRequired()` / `markEcfxActionRequired()` (InboxItem.java ~530–536).
- `InboxItem.Disposition`: `PROCESSED, SPLIT, IGNORED, PARTIAL_SUCCESS`.

## Exception logging listener

`projects/receipt_processing/src/main/java/com/goecfx/backend/receipts/events/ReceiptProcessingExceptionEventListener.java` — walks the exception superclass chain against a handler map (`findMostSpecificHandler`). Unregistered types hit:

```java
(e, logger) -> logger.error("Undefined Exception for Logging: " + e.getMessage());
```

which is the string the log-error automation turns into `logerr-auto` Jira bugs. Retryable types (`DelayProcessingException`, `LockContentionRetryException`) have explicit handlers logging `RETRY SCHEDULED: …` at WARN so failure scans don't misread them as terminal (ECFX-14498). Terminal handling: `UserReceiptProcessingException` → `completeActionRequiredFailure()`; server/auto-retryable/unlimited-retry → `completeFailedProcessing()`; `IgnoreItemException` → `completeIgnoreProcessing()`.

## Dedup

- Key: `Envelope.courtEnvelopeId` (column `court_envelope_id`, `Envelope.java:65`), checked via `Case.hasEnvelope(String)` (`Case.java:253`); per-document `Case.hasDocument(...)`.
- ITA canonicalization (`projects/receipt_processing/.../processors/polling/providers/ita/ITADocketEntryProcessor.java`): `buildCourtEnvelopeId(List<DocumentReference>)` joins `getDocumentId()` values **sorted lexicographically**, comma-separated — order-independent because the ACCESS Blazor UI returns document parts in unstable order (landed under ECFX-14369; the original duplicate-notices incident was ECFX-13963). Dedup runs before expensive work (~lines 651–655) and returns `ProcessorResult.duplicate()`.
- Email-side duplicate detection is a separate mechanism: interface `DuplicateNoticeDetection` (`.../processors/email/DuplicateNoticeDetection.java`) implemented by `BaseEmailReceiptProcessor`, returning `DuplicateIndicator`/`DuplicateDecision`.

## Resource cleanup patterns

- RabbitMQ (the ECFX-15303 leak fix), `projects/backend_shared/src/main/java/com/goecfx/backend/rabbitmq/AbstractRetryDelayConsumer.java` `receive(...)`:

```java
Channel channel = null;
try {
    channel = channelPool.getChannel();
    channel.basicPublish("", delayQueueName, newProperties, data);
    rabbitAck.ack();
} catch (Exception ex) {
    rabbitAck.nack(false, true);
} finally {
    if (channel != null) { channelPool.returnChannel(channel); }
}
```

- `SessionedDriverHandle implements AutoCloseable` — `close()` calls `driver.quit()` in try/catch.
- `ItaSessionLockRefresher` (`projects/backend_shared/.../util/ita/session/ItaSessionLockRefresher.java`) — `@PreDestroy` two-phase: `executor.shutdown()` → `awaitTermination` → `executor.shutdownNow()`.
- `ItaBatchOrchestrator` (`projects/receipt_processing_queue/.../ItaBatchOrchestrator.java`) — `@PreDestroy` drains in-flight work, then `safeQuitPooledDriver()`. Caution: its `lockRefresher` field is a local executor, not the singleton refresher.
- `InboxItemProcessJobProcessor` `@PreDestroy` gracefully fails + requeues the in-flight job (`requeueWithProviderDelay(0)`); the 420-minute stuck-job sweep is the fallback.

## Docket-Text-Only fallback (per-provider, no global switch)

- Abstract base example: `MissouriDocketTextOnlyProcessor extends MissouriEmailReceiptProcessor` (nested `DocketTextInfo`, abstract `parseDocketTextInfo(ProcessableEmail)`); concrete `MissouriTrackingNoticeReceiptProcessor`.
- Others: `VirginiaJefsDocketTextEmailProcessor`, `ResearchTXLegacyDocketTextProcessor`, `DelawareCountyCourtOfCommonPleas`.
- Unicourt webhooks: `metadata.setTrackDocketTextOnly(...)` / `getDocketTextDocumentDownload(...)` in `UnicourtWebhookProvider.java`.
- Logging hooks: `ProcessorLogger.docketTextOnlyProcessing()` and `docketTextOnlyDecision(internalEnvelopeId, decisionTrigger, htmlContent)`.

## Outcome metrics

Micrometer counter `ecfx.backend.receipt_processing_queue.notice.outcome` (tags: `processor`, `result`, `attempt_bucket`) and timer `ecfx.backend.receipt_processing_queue.notice.time_to_complete`. `result` values: `success, ignored, partial_success, customer_action, ecfx_action, retry, no_op, exception`. Attempt buckets: `1, 2-3, 4-5, 6+, unknown`.
