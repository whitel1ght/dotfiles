# MR Description Examples

## Example 1: Bug Fix with Investigation (Gold Standard)

This is from MR !4942 (ECFX-12201) — a production bug fix with root cause analysis.

```markdown
## Summary

Fixes `UnexpectedRollbackException` in the Unicourt poller when the Unicourt API
returns 429 rate limit errors. Two changes:

1. **Remove `@Transactional` from `UnicourtPoller.poll()`** — root cause fix
2. **Increase retry backoff from 500ms to 1000ms** — speculative mitigation to
   reduce 429 frequency

## Investigation & Decision Tree

### How we identified the root cause

**Observation**: Production smoketest (MN4 deployed 7:30-9:30 PM CST, Mar 5)
showed `UnexpectedRollbackException` errors in the Unicourt poller. These errors
did not appear in 30 days of MN1 production logs (274M records scanned).

**Step 1 -- Identify the exception source**: CloudWatch logs showed the exception
escaping from `PollerQueueConsumer.receive()`, causing messages to be nacked and
dead-lettered.

**Step 2 -- Compare `UnicourtPoller.poll()` vs `BasePoller.poll()`**: Found that
`UnicourtPoller.poll()` adds `@Transactional` (line 167) which `BasePoller.poll()`
intentionally omits. No other poller overrides `poll()` with `@Transactional`. ITC
poller (which uses `BasePoller.poll()` directly) showed zero rollback errors in MN4.

**Step 3 -- Trace the transaction boundary chain**:

    UnicourtPoller.poll()          <-- @Transactional (starts Transaction A)
      +-- BasePoller.pollCase()     <-- @Transactional (joins Transaction A via REQUIRED)
           +-- publishInboxItemsForCase()  <-- @Transactional (joins Transaction A)
                +-- unicourtApiClient.getCase().block() -> 429 -> exception thrown

All three methods share the **same transaction** because Jakarta `@Transactional`
defaults to `Propagation.REQUIRED`. When an exception propagates through
`pollCase()`, the transaction is marked **rollback-only** by the container.

**Step 4 -- Identify the failure mode**: The `catch` block in `poll()` catches the
exception and logs a warning. Code continues as if nothing happened. But when
`poll()` returns and the AOP proxy tries to **commit** Transaction A, it finds the
transaction is rollback-only -> `UnexpectedRollbackException`.

**Step 5 -- Understand why MN1 didn't have this problem**: MN1 never hit 429 errors
(zero occurrences in 30 days). Without the 429 trigger, the `@Transactional` on
`poll()` was harmless -- the rollback-only state was never triggered.

**Step 6 -- Confirm the fix**: Without `@Transactional` on `poll()`, `pollCase()`
starts its own independent transaction. If it fails, its transaction rolls back in
isolation. The `catch` block handles the exception cleanly with no outer transaction
to commit.

### Why `@Transactional` is unnecessary on `poll()`

The `poll()` method's responsibilities:
- Parse the message string
- Look up firm and jurisdiction (read-only, no transaction needed)
- Delegate to `pollCase()` which manages its own transaction
- OR iterate firms/cases and publish RabbitMQ messages (no transaction needed)

None of these require an enclosing transaction.

## Retry Backoff Change (Speculative)

The second commit increases the Reactor retry backoff initial delay from 500ms to
1000ms to match MN1's effective timing:

- **MN1** (`RetryWithDelay(5, 500, true)`): Pre-increments retry counter -> delays
  of 1000, 2000, 4000, 8000, 16000ms = **31s total**
- **MN4** (`Retry.backoff(5, Duration.ofMillis(500))`): Starts at base delay ->
  delays of 500, 1000, 2000, 4000, 8000ms = **15.5s total**

**This change is speculative** -- we have no documentation of Unicourt's actual rate
limits. However, matching MN1's proven timing is low-risk.

## Test Plan

- [x] Integration test (`UnicourtPollerTransactionSpec`) proving the transaction fix:
  - RED: With `@Transactional` on `poll()`, `UnexpectedRollbackException` is thrown
  - GREEN: Without it, exception is caught cleanly by the `catch` block
- [x] Test uses real Micronaut transaction manager, real database (TestResources
  PostgreSQL), mocked `UnicourtApiClient`
- [ ] Deploy to dev01 and verify no `UnexpectedRollbackException` in poller logs
- [ ] Monitor Unicourt 429 error frequency after backoff change

## New Test Infrastructure

This MR also sets up `poller_queue` integration test infrastructure from scratch:
- `SchemaLoader` for idempotent schema loading
- `application-test.yml` with TestResources PostgreSQL
- Minimal `schema.sql` covering firm, case, jurisdiction, provider_state tables
- Test dependencies for Spock compilation
```

**Why this works:**
- Summary immediately tells the reviewer there are two changes and which is confirmed vs speculative
- Investigation walks through the reasoning step-by-step with evidence at each stage
- Transaction chain is visualized as a call tree
- Explains why the bug didn't exist in MN1 (critical for migration context)
- Speculative change is in its own section, clearly labeled with reasoning
- Test plan describes RED/GREEN methodology, not just "tests pass"
- New infrastructure is called out so reviewers know the full scope

## Example 2: Config/Infrastructure Change

```markdown
## Summary

Move `redis.uri` placeholder from `application.yml` to `application-prod.yml` in
poller_queue to enable TestResources auto-provisioning of Redis in tests.

## Context

TestResources cannot auto-provision Redis when `redis.uri: "${REDIS_URI}"` is in
main `application.yml` because the placeholder fails to resolve before TestResources
can inject. This follows the same pattern established in `receipt_processing_queue`
and `webhook_queue`.

## Changes

- `application.yml`: Remove `redis.uri: "${REDIS_URI}"`
- `application-prod.yml`: Add `redis.uri: "${REDIS_URI}"` (production still resolves
  from environment variable)
- `application-test.yml`: Replace hardcoded `redis.uri` with `redis: enabled: true`

## Impact

- **Production**: No change -- `application-prod.yml` is active in prod environments
- **Tests**: Redis is now auto-provisioned via TestResources TestContainers
- **Local dev**: No change -- developers using Docker Compose redis are unaffected

## Test Plan

- [x] `UnicourtPollerTransactionSpec` passes with TestResources Redis
- [ ] Verify poller_queue connects to Redis in dev01 after deployment
```

**Why this works:**
- Context explains the technical constraint driving the change
- Impact section covers all environments
- Changes are listed file-by-file for easy review

## Example 3: Feature Addition

```markdown
## Summary

Add batch document download endpoint that streams documents as a ZIP archive,
allowing users to download multiple court documents in a single request.

## Motivation

Users currently download documents one at a time, which is tedious for cases with
50+ filings. Support tickets requesting bulk download have increased 3x in Q4.

## Approach

Chose streaming ZIP generation over pre-building ZIP files because:
- No temporary storage needed (streams directly to client)
- Works for arbitrarily large document sets
- Consistent memory footprint regardless of total size

Alternatives considered:
- **Pre-built ZIP on S3**: Adds storage costs, cleanup complexity, and latency
- **Client-side ZIP**: Requires downloading all files first, poor UX on slow connections

## Test Plan

- [x] Unit tests for ZIP stream builder (edge cases: empty set, single doc, 100+ docs)
- [x] Integration test with mocked S3 client verifying correct ZIP structure
- [ ] Manual test with production-size documents (10MB+ PDFs)
- [ ] Load test with concurrent batch downloads
```

**Why this works:**
- Motivation ties to real user pain with data
- Approach explains the decision with alternatives rejected
- Test plan includes both automated and manual validation
