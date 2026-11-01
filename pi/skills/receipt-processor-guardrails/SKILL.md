---
name: receipt-processor-guardrails
description: >-
  Guardrail checklist for any change under ecfx-backend's receipt_processing / receipt_processing_queue / poller_queue modules — every thrown exception deliberately placed in the retryable/terminal/user-action hierarchy, failure routing (Action Required Client vs ECFX) chosen intentionally, dedup keyed on stable canonical IDs, pooled resources released on the retry path, and new exception types registered with the logging listener. Use when creating or modifying a receipt processor, the retry engine, notice dedup, or any code that throws exceptions during notice processing — and during review of MRs touching those modules. This is the costliest bug class in the project (stuck retry loops, duplicate notices, misrouted failures).
---


# Receipt Processor Guardrails

The single most expensive recurring bug class in ecfx-backend: an exception lands in the wrong place in the classification hierarchy, an item strands in RETRY for months or fails terminally when it should have retried, a duplicate notice ships to a firm, or a failure is routed to ECFX ops when the customer had to act. Run every item below against the diff. Exact class list, retry-engine code, and metric names are in `reference.md`.

## 1. Exception placement — every throw is a routing decision

The hierarchy (package `com.goecfx.backend.receipts.exceptions`) has four intermediate bases under `ReceiptProcessingException`, and **the retry engine routes by annotation and base class, not by instanceof checks in your code**:

| Extend | Meaning | Outcome |
|---|---|---|
| `AutoRetryableReceiptProcessingException` | transient — retry with backoff | requeued, capped attempts |
| `UnlimitedRetryReceiptProcessingException` (`@UnlimitedRetry`) | retry forever (flag-gated) | bypasses both attempt caps |
| `UserReceiptProcessingException` (`@UserActionRequired`) | the **customer** must act (bad credentials, case not assigned, paywall) | terminal → Action Required: USER |
| `ServerReceiptProcessingException` | our defect | terminal → Action Required: ECFX |
| `DelayProcessingException` (extends the root directly) | not a failure — a "run after `runAfter`" scheduling signal | delayed re-run |
| `IgnoreItemException` | intentionally ignore this item | ignored bucket |

Checklist:
- [ ] **No raw `RuntimeException`/`Exception` thrown or rethrown** from processor code — an unclassified exception becomes `UnknownProcessingException` → terminal → Action Required: ECFX, even when the cause was transient. (This exact pattern stranded items: a `PessimisticLockException` rewrapped as unknown → terminal, fixed by adding typed `LockContentionRetryException extends AutoRetryableReceiptProcessingException`.)
- [ ] **Catch-and-wrap preserves classification.** Wrapping a retryable exception in a terminal one (or vice versa) changes the item's fate. When wrapping, extend the same base as the semantics demand.
- [ ] Credential/access/"not assigned to case"/paywall errors extend `UserReceiptProcessingException` — routing them as ECFX errors creates ops tickets for problems only the firm can fix.
- [ ] `@UnlimitedRetry` only for genuinely-must-eventually-succeed waits (e.g. `KeepWaitingForStampException`); remember it is gated on `ecfx.receipt-processing.unlimited-retry-enabled`.
- [ ] Check subclass lists in `reference.md` before inventing a new exception — an existing type may already carry the right semantics.

## 2. Retry-engine invariants (don't fight them)

`InboxItemProcessJobProcessor.handleJobFailure(...)` retries while `sameClassCount < maxAttempts` (default 10, matched on the exception's **simple class name**) AND `totalCount < maxAttempts * 2` (absolute cap, ECFX-13665). Backoff is `2^attempts` minutes for the first 8 attempts, then 4 hours.

- [ ] Don't implement retry loops *inside* a processor for failures the engine already handles — throw the right exception and let the engine own attempts/backoff.
- [ ] The per-class counter keys on the simple name: renaming an exception class resets its retry count for in-flight items; changing which exception a code path throws restarts the count by design. Note it in the MR if items may be mid-retry during deploy.
- [ ] Two distinct status enums exist — `InboxItem.Status` (NEW/RETRY/STARTED/FAILED/SUCCEEDED/MANUAL/CANCELED/POST_PROCESSING) and `JobStatus` (NEW/STARTED/FAILED/SUCCEEDED/CANCELED/DELAYED). Never cross-reference their values.

## 3. Failure routing — verify the terminal destination

Terminal routing: `markUserActionRequired()` fires iff the error class carries `@UserActionRequired` (inherited from `UserReceiptProcessingException`) AND (`ecfx.receipt-processing.user-action-routing-enabled` OR the exception is a stamp-wait timeout, which **always** routes to the firm — ECFX-14932). Everything else terminal → `markEcfxActionRequired()`.

- [ ] For every new terminal failure path, state in the MR which `InboxItem.ActionRequired` value (USER or ECFX) it produces and why that's the party who can act.
- [ ] Sealed/restricted/court-only documents must not fail the whole notice — degrade to the provider's Docket-Text-Only path where one exists (see `reference.md`), or flag that the provider needs one.

## 4. Dedup — stable canonical keys only

Dedup keys on `Envelope.courtEnvelopeId` via `Case.hasEnvelope(...)`. The hard-won rules:

- [ ] Never key duplicate detection on scraped-content equality (all-fields `equals()`): a provider's HTML/format migration makes every historical entry look "new" (this shipped 859 duplicate uploads in 48h before the barcode fix).
- [ ] Build envelope IDs from **stable provider identifiers** (document barcodes/IDs), **canonicalized order-independently** — the ITA pattern joins document IDs sorted lexicographically because the source returns parts in unstable order (ECFX-14369).
- [ ] Run the dedup check *before* expensive work (downloads, browser sessions), and return `ProcessorResult.duplicate()` — don't process-then-discard.

## 5. Resource cleanup on failure/retry paths

- [ ] Every pooled RabbitMQ `Channel` acquired via `channelPool.getChannel()` returned with `channelPool.returnChannel(channel)` in a `finally` — the retry re-publish path leaked channels until ECFX-15303 (pattern: `AbstractRetryDelayConsumer.receive`).
- [ ] Browser drivers held in `AutoCloseable` handles (`SessionedDriverHandle`) or quit in `try/catch` inside `@PreDestroy` shutdown; long-lived processors need two-phase executor shutdown (`shutdown()` → await → `shutdownNow()`).
- [ ] `@PreDestroy` on job processors should fail-and-requeue in-flight work rather than abandoning it (the engine's 420-minute stuck-job sweep is the backstop, not the plan).

## 6. Observability

- [ ] New exception types get an explicit handler registered in `ReceiptProcessingExceptionEventListener` — unregistered types log `"Undefined Exception for Logging: …"`, which auto-files a Jira bug per occurrence and hides the real signal (ECFX-14498). Retryable exceptions should log as `RETRY SCHEDULED` at WARN, not as failures.
- [ ] New terminal outcomes are reflected in the `ecfx.backend.receipt_processing_queue.notice.outcome` Micrometer counter's `result` tag so the notice-stats reporting stays truthful.

## Output

Report findings as a per-section checklist with `file:line`, each PASS or the concrete fix. Lead with anything that changes an item's retry/terminal fate or its USER/ECFX routing — those are the failures that strand notices in production.

## Related skills

`court-portal-processor-checklist` (building/altering a provider processor), `flyway-migration-preflight` (if the change adds migrations), `deployment-parity-review` (if it adds queues/config), `transaction-boundary-validator`.
