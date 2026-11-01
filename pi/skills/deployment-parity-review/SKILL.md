---
name: deployment-parity-review
description: >-
  Check that new infrastructure touchpoints in ecfx-backend work in deployed environments, not just locally or in tests — RabbitMQ topology declared via a per-app @Factory initializer, S3 buckets and external hosts referenced through config properties with per-environment overrides (never hardcoded), new env vars/secrets present in every environment profile, and firm-active guards on outbound customer-facing jobs. Use when adding a RabbitMQ queue/exchange, a new S3 bucket or external host reference, a new secret or environment variable, or a scheduled job that emails or notifies customers.
---


# Deployment Parity Review

Catches the "works locally and in tests, breaks on prod01" class of bug in **ecfx-backend**. Each section below is a verified production failure mode with the established fix pattern. Run the sections that match the diff; skip the rest.

## 1. New RabbitMQ queue/exchange → per-app `@Factory` initializer required

Topology is declared with the low-level `com.rabbitmq.client.Channel` API through a **two-part pattern**:

1. A **plain, un-annotated** `ChannelInitializer` subclass in `projects/backend_shared/src/main/java/com/goecfx/backend/rabbitmq/initializers/` (e.g. `SchedulerV2RabbitInitializer`; retry topologies extend `AbstractDelayRabbitInitializer`). It overrides `initialize(Channel, String)` and calls `declareExchange` / `declareDlx` / `declareDlq` / `declareQueue` / `bindQueue`.
2. **Each consuming application** wires it via an `@Factory` producing it as a `@Singleton`, e.g. `projects/scheduler_v2/src/main/java/com/goecfx/backend/schedulerv2/config/SchedulerV2RabbitInitializerFactory.java`:

```java
@Factory
public class SchedulerV2RabbitInitializerFactory {
    @Singleton
    @Requires(property = "rabbitmq.uri")
    public SchedulerV2RabbitInitializer schedulerV2RabbitInitializer(Connection connection) {
        return new SchedulerV2RabbitInitializer(connection);
    }
}
```

**The failure mode:** without the `@Factory`, Micronaut never instantiates the initializer, so the topology is never declared in a deployed environment — consumers crash-loop on a queue that doesn't exist. Tests pass anyway because the *other* end (producer or a TestResources-provisioned broker) declares it. This shipped as a production bug (a queue module with the initializer but no production `@Factory`).

Checklist for any diff adding/renaming a queue, exchange, or binding:
- [ ] Initializer subclass exists in `backend_shared/.../rabbitmq/initializers/`
- [ ] **Every app that produces to or consumes from it** has a `RabbitInitializerFactory`-style `@Factory` producing the initializer `@Singleton` (existing examples: `auto_case_creation_queue`, `notifier_queue`, `email_queue`, `webhook_queue`, `poller_queue`, `dms_queue`, `receipt_processing_queue`, `receipt_post_processing_queue`)
- [ ] Prefer gating with `@Requires(property = "rabbitmq.uri")` so contexts without a broker don't fail startup

## 2. S3 buckets / external hosts → config property, exact key match

Convention: services inject **kebab-case** properties, `@Value("${ecfx.<name>-bucket}")`, and `application.yml` supplies `${UPPER_SNAKE_ENV_VAR:local-default}` in the base file with a bare `${UPPER_SNAKE_ENV_VAR}` override in `application-prod.yml`. Verified examples: `ecfx.processor-logging-bucket`, `ecfx.document-bucket`, `ecfx.document-pro-tem-bucket`, `ecfx.response-body-bucket`.

**The failure mode:** a config key that *almost* matches — `processor_logging_bucket:` (underscores) defined in YAML while the service reads `${ecfx.processor-logging-bucket}` (hyphens) — or a hardcoded environment-interpolated name like `"ecfx-processor-logging-${ECFX_ENVIRONMENT}"` that stops matching reality after an infra cutover. Result: `s3:PutObject AccessDenied` in exactly one environment.

Checklist:
- [ ] YAML key **exactly** matches the `@Value`/`@Property` expression, including hyphen vs underscore
- [ ] No hardcoded bucket/host literals in Java or YAML — always `${ENV_VAR:local-default}`
- [ ] Prod profile provides the bare `${ENV_VAR}` override
- [ ] A config-binding Spec pins the property name (pattern: `ProcessorLoggingBucketConfigSpec` in `data_import_web`) so a rename fails the build instead of failing in prod

## 3. New env var / secret → present in every environment

For each new `${VAR}` placeholder introduced:
- [ ] Every profile that runs deployed (`application-dev.yml`, `application-staging.yml`, `application-prod.yml` where present for the module) either defines it or inherits a sane base default
- [ ] The corresponding DuploCloud secret/env entry exists per tenant — list what must be created and for which environments in the MR description; secrets drift between environments was a real cutover bug class
- [ ] No live secret values in tracked files

## 4. Outbound customer-facing jobs → firm-active guard

Firm lifecycle is a single boolean: `Firm.active` (`projects/data/src/main/java/com/goecfx/data/models/Firm.java`, accessor `firm.isActive()`). There is no status enum and no `enabled` field. Disabled/churned firms kept receiving daily digests and failure-summary reports because jobs didn't check it.

The established convention (after an explicit revert of a repository-level `getActiveById` approach) is **fetch then guard in memory**, at the top of the per-firm work unit:

```java
Firm firm = firmRepository.getById(firmId);
if (firm == null || !firm.isActive()) {
    LOG.info("Skipping <JobName> for firm {}: firm is inactive", firmId);
    return;
}
```

Reference implementations: `FailureSummaryReportJob` and `DailyDigestEmailJob` in both `projects/scheduler/` and `projects/scheduler_v2/` (Quartz jobs extending `BaseSchedulerJob`).

Checklist for any job/consumer that emails, notifies, or webhooks customers:
- [ ] `!firm.isActive()` guard at the top of the per-firm path, with the skip logged at INFO
- [ ] Guard covered by a Spec (inactive firm → no send)

## 5. Log lines meant to be seen → a level the module's appender forwards

Each module's `logback.xml` decides what leaves the pod. `receipt_processing_queue` filters its Sentry appender at **ERROR**, so a `LOG.warn` about a tenant-wide misconfiguration reaches nobody; `cli` filters at **WARN**, so a per-firm `LOG.warn` in a survey tool pages someone for every row. The project already has `MisconfigurationReporter.reportOnce(code, property, consequence)` for the first case — it logs at ERROR and dedupes per pod.

Checklist for any new log statement that is an *alert* rather than a trace:
- [ ] Look up the module's `logback.xml` threshold before choosing the level
- [ ] Tenant/config misconfiguration → `MisconfigurationReporter`, not `LOG.warn`
- [ ] Per-row output of a read-only or survey tool → INFO; at most one WARN carrying the total
- [ ] A spec pins the **level** (a real appender with a `ListAppender`, asserting `Level.ERROR`), not just that a message exists — reverting to `warn` must go red

## 6. Operational commands → verify their own preconditions, fail loudly

A CLI or job that can produce the same output when its dependency is missing as when the answer is genuinely zero manufactures confidence. The audit command that decrypts credentials must refuse to start if the bound decrypter is the dummy; a survey that catches only one exception type aborts the whole scan on the first malformed row with no summary line.

Checklist for any new CLI subcommand, one-off job, or migration tool:
- [ ] Detects a fallback/dummy dependency and exits non-zero with an ERROR, instead of reporting a clean result
- [ ] Reports the denominators (`hits / decrypted / unparsed`), so "0 of 0" reads differently from "0 of 312"
- [ ] Per-item failures are caught and counted; one bad row never erases the results for the rest
- [ ] Prints an INFO "starting (scope)" line so an aborted or killed run leaves evidence
- [ ] Unknown `--firm`/id arguments are a logged error and a clean return, not a stack trace
- [ ] Output identifies what to fix (ids, types — never secret values), and the command is listed in the module's `AGENTS.md` and the MR description
- [ ] A spec drives the real entry point (`run()`) over a stubbed page of data, not just the predicate

## Output

Report only the sections relevant to the diff, each finding with `file:line` and the concrete fix. Lead with anything that would fail only in a deployed environment — that's the class of bug this skill exists to catch before the MR merges.

## Scope

Sections 1, 2, 4, 5 and 6 cite ecfx-backend classes and conventions. Section 3 and the general principle — "every infra touchpoint needs a per-environment story, and tests passing proves nothing about deployed topology" — apply to any service repo.
