---
name: java-clean-code-commandments
description: >-
  Ten enforceable clean-code commandments adapted for Java 17+ / Micronaut 4 (type discipline, error swallowing, event-loop blocking, size limits, meaningful tests, layer boundaries, dependency justification, naming, dead code, externalized secrets/config). Use when writing or reviewing Java code, when the user asks for a clean-code audit / code-quality pass / "purist review", when refactoring a class or module, or as review doctrine for the java-clean-code-purist agent and the multi-agent MR review's clean-code lens.
---


# Java Clean Code Commandments

Adapted for this team's stack (Java 17+, Micronaut 4, Micronaut Data/Hibernate, Spock, Gradle, PostgreSQL, RabbitMQ) from the "Church of Clean Code" commandments ([btachinardi/church](https://github.com/btachinardi/church), MIT). Every rule below is checkable against a diff — no vibes, no "prefer". Code examples for the non-obvious rules are in `reference.md`.

**Scope exclusions:** generated code (protobuf/gRPC stubs, `build/`, `generated/`), Flyway SQL, and third-party vendored code are exempt from all commandments. Mechanical style (indentation, imports order, braces) belongs to `checkstyle-enforcer` — do not re-litigate it here.

## I. Thou shalt not weaken the type system

Every escape hatch out of the compiler's sight is a place bugs enter unseen.

- [ ] No raw generic types (`List` instead of `List<Notice>`); no `Object` parameters/returns where a generic or sealed hierarchy fits.
- [ ] Every unchecked cast / `@SuppressWarnings("unchecked")` carries a one-line comment proving why it is safe. Prefer `instanceof` pattern matching (`if (o instanceof Notice n)`) over cast-after-check.
- [ ] `switch` over an enum or sealed type is exhaustive — no `default` arm that silently absorbs future variants. If a `default` is unavoidable, it throws (`IllegalStateException`), never falls through quietly.
- [ ] Possibly-absent **return values** are `Optional<T>`, never `null`. `Optional` is never used for fields or parameters, and `Optional.get()` never appears without a preceding presence check (`orElseThrow` with a message beats bare `get()`).
- [ ] Domain values are not stringly typed: statuses are enums, IDs that cross module boundaries use their wrapper type (e.g. `PublicId`) rather than bare `String`/`UUID` — see `secured-endpoint-contract` for the boundary rules.
- [ ] Micronaut is compile-time: DTOs crossing serialization boundaries are `@Serdeable` (or `@Introspected`); dependencies arrive by **constructor injection** (no field `@Inject`, no `ApplicationContext.getBean(...)` service lookup in production code).

## II. Thou shalt not swallow errors

An empty catch block is where errors go to die — and your understanding of production dies with them.

- [ ] No empty catch blocks. No `catch (Exception e) { log.error("error"); }` without context either — every log line carries the identifiers needed to act on it (entity IDs, item IDs, external references).
- [ ] Rethrows preserve the cause: `throw new ProcessingException("context", e)` — never `throw new ProcessingException("context")` after catching `e`.
- [ ] `catch (InterruptedException e)` restores the flag (`Thread.currentThread().interrupt()`) or rethrows — never absorbed.
- [ ] SLF4J parameterized logging (`log.info("processed item {}", id)`), never string concatenation, never `System.out.println`.
- [ ] In receipt-processing/poller code, every thrown exception is a deliberate routing decision — defer to `receipt-processor-guardrails` for the hierarchy; this commandment only demands the decision be *visible*, not silent.
- [ ] New critical dependencies (DB, queue, external API) are reflected in a Micronaut `HealthIndicator` where a health endpoint exists — a 200 that doesn't check its dependencies is a false prophet.

## III. Thou shalt not block the event loop nor share hidden state

Micronaut's event loop and singleton scope are the two places where "works on my machine" becomes a production outage.

- [ ] Blocking work (JDBC, `HttpClient` blocking calls, file I/O, `Thread.sleep`) in an HTTP/reactive path runs on `@ExecuteOn(TaskExecutors.BLOCKING)` (or the module's established executor pattern) — never on the Netty event loop.
- [ ] `@Singleton` beans hold no mutable per-request/per-item state in fields. Anything cached or accumulated in a singleton is thread-safe (`ConcurrentHashMap`, immutable snapshots) — a plain `HashMap` field in a singleton is a data race wearing a disguise.
- [ ] No fire-and-forget async work without an error path: every `CompletableFuture`/reactive chain either joins, or handles failure explicitly (`exceptionally`, `onErrorResume`, subscriber with error consumer). A dropped error is Commandment II by another road.
- [ ] `SimpleDateFormat` and other non-thread-safe classics never live in static/singleton fields — use `java.time` formatters (immutable) instead.

## IV. No class shall exceed its station

By line 80 of a method, no reader remembers line 1. Working memory is the budget; spend it on the domain, not on scrolling.

- [ ] No new file over ~500 lines without stated justification in the MR; existing offenders don't grow — a change that pushes a 600-line class to 700 splits something out instead.
- [ ] Methods over 40 lines are suspicious; over 80 are split. Extract until each method does one nameable thing.
- [ ] Nesting deeper than 4 levels is restructured — guard clauses and early returns, not else-pyramids.
- [ ] A constructor with more than ~6 injected dependencies is a class doing several jobs — split the service, don't widen the constructor.

## V. Untested code does not work — you just don't know it yet

A test asserting `result != null` is a suggestion, not a proof.

- [ ] New public behavior ships with a Spock spec (this repo's TDD skills cover the mechanics; this commandment only demands existence and meaningfulness).
- [ ] Assertions verify **specific** behavior — expected values, expected interactions, expected exception types with their routing semantics. `notThrown(Exception)` or a lone null-check as the only assertion proves nothing.
- [ ] Repository/query behavior is tested against real PostgreSQL (TestResources/TestContainers), not a mocked `EntityManager` — a mocked repository test verifies your mock, not your query.
- [ ] No new `@Ignore`/`@PendingFeature` without a ticket reference. A skipped test is a broken promise with a date on it.
- [ ] Test names state the behavior (`"routes credential failures to the firm"`), not the method under test (`"test processItem 3"`).

## VI. Dependencies flow downward

The layering is the architecture; every upward or sideways import erodes it.

- [ ] Controllers call services; services call repositories. No controller touching a repository directly, no repository containing business logic.
- [ ] `@Transactional` lives on service methods only — never controllers, never repositories (`transaction-boundary-validator` enforces this; treat violations as blocking).
- [ ] Entities never cross the HTTP boundary — controllers return DTOs. A JPA entity in a controller signature leaks schema, lazy-loading behavior, and accidental serialization of relations.
- [ ] No new dependency cycles between Gradle modules; domain/business modules don't import HTTP, controller, or messaging-transport types.
- [ ] Cross-module communication goes through the established seams (gRPC contracts, queue messages, service interfaces) — never reach into another module's internals because the class happens to be public.

## VII. Every dependency must justify its existence

Every new library is an unvetted stranger with access to production.

- [ ] A new Gradle dependency states in the MR what it does that the JDK, Micronaut, or an already-present library cannot. If it saves fewer than ~50 lines, write the code.
- [ ] No dependency with known CVEs at the version pinned; version bumps prefer the current patched line.
- [ ] Scopes honest: `testImplementation` for test-only, `implementation` over `api` unless the type genuinely leaks through the module's own API; no test frameworks on the runtime classpath.
- [ ] One version per library across modules — resolve through the version catalog / BOM, don't let two modules pin different versions of the same artifact.

## VIII. Names are documentation

`data`, `temp`, `result`, `info` — these are lies of omission.

- [ ] Booleans read as questions: `is`, `has`, `should`, `can`, `will`, `did` prefixes.
- [ ] Methods name the **action and outcome** (`markUserActionRequired`), not the trigger (`handleFailure2`) or the mechanism (`doProcess`).
- [ ] No junk-drawer identifiers in non-trivial scope: `data`, `temp`, `stuff`, `obj`, `result` (a `result` in a 3-line method is fine; in a 40-line method it is a fog).
- [ ] No new `*Util`/`*Helper`/`*Manager` class without a single describable responsibility — "miscellaneous static methods" is not a responsibility.
- [ ] Values with units carry them: `timeoutMs`, `delayMinutes`, `maxAttempts`. Constants are `UPPER_SNAKE_CASE` and live with the code that owns them.

## IX. Dead code shall be buried

Git remembers everything; the codebase should carry only what runs.

- [ ] No commented-out code blocks — delete them; the history has them if anyone ever grieves.
- [ ] Unused private methods, fields, and parameters are removed, not kept "in case".
- [ ] A `TODO` carries a ticket reference (`// TODO(ECFX-1234): ...`) or it doesn't ship. Existing TODOs older than a quarter get actioned or deleted when touched.
- [ ] No debug leftovers: `System.out.println`, commented `log.debug` experiments, `e.printStackTrace()`, temporary `@Disabled` toggles.
- [ ] No unreachable branches — code after unconditional returns/throws, conditions the type system already guarantees.

## X. Secrets and config dwell outside the code

A committed credential is a compromised credential — removing it from HEAD does not remove it from history.

- [ ] No credentials, tokens, or API keys in source, `application*.yml`, or test fixtures — environment variables and the deployment platform's secret store (DuploCloud/K8s secrets) only. If one was **ever** committed, rotate it now; deleting the line changes nothing.
- [ ] No hardcoded environment-specific values (bucket names, hostnames, queue names, URLs) — `@ConfigurationProperties`/`@Value` with per-environment overrides. `deployment-parity-review` covers verifying the overrides exist in every environment.
- [ ] `.gitignore` covers `.env*`, local override files, and IDE credential stores before any such file exists.

---

## Relationship to existing components

This doctrine is the general-purpose layer; the specialized skills own their domains and win on conflict:

| Domain | Owner |
|---|---|
| Mechanical Java style | `checkstyle-enforcer` |
| Commit/branch hygiene | `commit-msg`, `pre-commit-review` (Commandment III of the original was retired in favor of these) |
| Exception routing in receipt processing | `receipt-processor-guardrails` |
| `@Secured` / ID types at HTTP boundaries | `secured-endpoint-contract` |
| Per-environment config completeness | `deployment-parity-review` |
| `@Transactional` placement | `transaction-boundary-validator` |
| TDD mechanics per layer | `tdd-*-layer` skills |

For an interactive audit, spawn the `backend:java-clean-code-purist` agent — it loads this doctrine and reports violations by commandment with `file:line` and severity.
