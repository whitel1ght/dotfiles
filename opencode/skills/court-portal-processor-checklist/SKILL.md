---
name: court-portal-processor-checklist
description: >-
  Resilience checklist for building or modifying a court/e-filing provider processor in ecfx-backend — correct base class and bean-discovery wiring, login gated on real auth signals, 2FA/OTP correlation, per-document timeouts, format and content-type fallbacks, multi-document completeness, zero-length guards, sealed/restricted handling, selector resilience, and browser/session lifecycle. Use when adding a new email/polling/webhook receipt processor, modifying browser automation (Camoufox/Playwright/Selenium) against a court portal, or fixing a provider parsing bug like case-number, county, or date-format failures.
---


# Court Portal Processor Checklist

Provider processors are ecfx-backend's most fragile surface: bespoke scrapers and parsers against ~150 court systems that change HTML, login flows, and formats without notice. This checklist encodes the recurring production failures. Pair it with `receipt-processor-guardrails` — exception classification and dedup rules live there.

## 1. Wiring — get discovered, get selected

- **Base class:** email processors extend `BaseEmailReceiptProcessor` (channel contract is the interface `IEmailReceiptProcessor` — there is no class named `EmailReceiptProcessor`); Tyler-family states extend `BaseTylersEmailReceiptProcessor` (implement its 5 abstract methods: `serviceUri()`, `getUsername()`, `getPassword()`, `stateSignature()`, `getTimeZoneString()`); PACER-like ones extend `PacerLikeProcessor`; portal pollers extend `BasePollingReceiptProcessor`; webhooks extend `BaseWebhookProcessor`.
- **Selection is by bean enumeration, not a registry:** `ReceiptProcessorService` enumerates bean definitions, filters out abstract and `!isActive()`, orders by `Ordered.getOrder()`, and picks the **first** whose `match(...)` returns true.
  - [ ] `match(...)` is specific enough not to steal another provider's emails, and the processor's order doesn't shadow an existing one
  - [ ] `isActive()` reflects any rollout gating
  - [ ] `providerId()` is stable — it keys signature lookups and metrics

## 2. Login & session

- [ ] Login completion gated on a **positive auth signal** (auth cookie present, post-login element/state reached) — never a sleep or a URL guess. "Post-login state never reached" is a standing failure signature.
- [ ] Already-logged-in / concurrent-session states handled explicitly (`UserAlreadyLoggedInException`, `ConcurrentSessionInUseException` are existing retryable/delay types — use them).
- [ ] 2FA/OTP: the retrieved code must be **correlated to the notice/session that requested it** (request timestamp + recipient), not "latest email wins" — batch processing with uncorrelated codes mismatched Wisconsin filings. When choosing among OTP destination options, select by explicit rule (e.g. forwarding-enabled address), not list position.
- [ ] Failed login distinguishes *invalid credentials* (→ `UserReceiptProcessingException` subclass, customer acts) from *portal transient* (→ retryable). "Credentials valid but not authorized for this court" recurs — don't collapse it into invalid-credentials.

## 3. Browser automation (Camoufox / Nodriver / Playwright)

Shared infra lives in `projects/backend_shared/src/main/java/com/goecfx/backend/util/` — build drivers via `DriverFactory` (Builder; `BrowserType.CAMOUFOX` / `NODRIVER`; grid endpoint from env `CAMOUFOX_GRID_URL`), Playwright via `PlaywrightUtil`. ITA drivers funnel through `ITAServiceCommon.buildDriver(proxy)`.

- [ ] No hand-rolled driver construction — use `DriverFactory`; driver-start failure is `WebDriverCreationException` territory and must be **retryable**, not terminal (Camoufox-sidecar rollouts cause transient start failures)
- [ ] Drivers/sessions in `AutoCloseable` handles (`SessionedDriverHandle`) or quit in `finally`/`@PreDestroy`; a leaked browser on the grid starves every other processor
- [ ] Selectors anchored on **stable attributes** (ids, names, text), not layout wrappers — a removed `div.text-truncate` wrapper once broke every ITA download; a hardcoded JSF root id broke all NJ clicks
- [ ] Per-page and per-download timeouts explicit; a hung "no documents" detection must time out into a retryable exception, not hang the session
- [ ] Bot-detection/CAPTCHA path defined: `CaptchaSolverRetryException` for solvable challenges, headed/Camoufox fallback where the portal blocks headless

## 4. Parsing — assume format drift

- [ ] **Case numbers:** strip known location suffixes/prefixes before matching; handle multi-case-number notices; never let the case *name* be captured as the case number (recurring TrueFiling/re:SearchTX/Arkansas bug)
- [ ] **Dates:** accept every observed format variant — ITA legitimately interleaves `M/d/yy`, `M/dd/yy`, `MM/d/yy`, `MM/dd/yyyy`; a single-format parser is a latent crash. Timezone comes from the provider (`getTimeZoneString()` for Tyler), never the JVM default
- [ ] **Jurisdiction:** resolution failures throw the typed exceptions (`JurisdictionNotFoundException` from `BaseReceiptProcessor.getECFXJurisdictionForSignature`, or the provider parse exception); a missing mapping is data work — see the `add-signature-mapping` skill
- [ ] Parse failures classify as retryable **only** when re-running could help; a structurally-unsupported email retrying forever is noise — ignore or route to user per `receipt-processor-guardrails` §1

## 5. Documents — all of them, none empty

- [ ] **Multi-document notices process every link/part**, not just the first (Wisconsin multi-pleading, "second filing merged into first" bugs); parts combine **in order**
- [ ] **Zero-length guard:** verify content length before storing — "Attempting to store zero-length document" caused stuck inboxes and a 140×-spike regression; treat empty response bodies from streaming downloads as retryable download failures, not success
- [ ] Content-type fallbacks: portals mislabel PDFs as `application/octet-stream` (ITA) — sniff, don't trust the header alone
- [ ] Sealed/restricted/court-only documents degrade to the provider's Docket-Text-Only path (never terminal-fail the notice); confidential documents route per firm rules, not silently delivered
- [ ] Memory: stream large documents; never accumulate every part's `byte[]` in heap (an accumulator pattern OOM'd the container on an 8,084-page PACER PDF and multi-part Philadelphia bundles)

## 6. Tests

- [ ] A Spock Spec per processor (`*Spec.groovy`, Spock-only policy) with real fixture emails/HTML for: happy path, each format variant seen in production, the duplicate case, and each classified failure path
- [ ] Fixtures capture the *provider's* raw formats — when fixing a parse bug, add the offending real notice (scrubbed) as a fixture so the format can't regress
- [ ] For local end-to-end reproduction of an email notice, use the `process-email-notice` / `process-email-notice-cli` skills

## 7. Credential types — provider-specific on the type, provider-neutral everywhere else

Credential UI is generated from `@CredentialType` / `@CredentialField` descriptors, so a new field is usually ~30 lines and no frontend. The recurring mistakes are in what is *shared*:

- [ ] Portal-specific instructions (where to find a key, what to right-click) live in the field's `hint` on **that provider's** interface — never in a shared service message, a shared dialog string, or a normaliser. Shared copy names no provider; use `{providerName}` where a name is wanted
- [ ] `encId` and `key` on an existing type are never changed (the encryption context; changing it orphans every stored credential)
- [ ] New fields on an existing type are `required = false`; note that a `secret = true` field is **never** in the descriptor's required set regardless of `required`, so its optionality is guarded by the descriptor JSON test, not by `validate()`
- [ ] Every type carries an `accessGroup` (universal since ECFX-16322); `hidden`/`hidden = true` fields are constants the processor reads via defaults and are not persisted
- [ ] **Secret values never leave the API.** GETs map `credentialsSansSecrets` → `fields`, so secret keys are absent, not masked. A client that needs to know whether a secret is *stored* reads `configured_secret_fields` (names only). A test fixture with a secret value inside `fields` describes a payload that cannot exist — see the `api-contract-fixtures` skill
- [ ] Wire keys are exactly as serialised (snake_case for Serde DTOs; field keys are whatever `@CredentialField(key = …)` says, e.g. `myhawaiiusername`) — the dashboard does no case conversion
- [ ] Tests build fixtures for at least two providers (the one under change and one unrelated), so provider-neutrality is asserted, not assumed
- [ ] Anything a *human types* gets an actionable `BadRequestException` message; `OpaqueErrorException` is for enumeration probes only

## Output

Report per-section findings with `file:line`, PASS or the concrete fix. Lead with anything that loses documents, delivers duplicates, or hangs/leaks browser sessions.
