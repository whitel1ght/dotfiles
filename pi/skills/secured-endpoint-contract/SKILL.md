---
name: secured-endpoint-contract
description: >-
  Verify @Secured role gating, 400-vs-500 error semantics, log-injection safety, and ID-type contracts (PublicId vs bare UUID) when adding or modifying HTTP controllers in ecfx-backend. Use when creating or changing a @Controller/endpoint, choosing @Secured roles, handling malformed request input, mapping gRPC errors to HTTP status codes, or when an endpoint returns 403 for users who should have access.
---


# Secured Endpoint Contract

Contract checklist for HTTP controllers in **ecfx-backend**. Exists because the same endpoint was fixed across four consecutive MRs — wrong role gate (403 for real users), 500s for malformed input that should be 400s, and a prefixed `PublicId` sent where a downstream service wanted a bare UUID. Run this whenever a controller is added or its security/validation/error handling changes.

## 1. Role gating — match the host screen, never guess

Roles are **lowercase string constants** in `projects/data/src/main/java/com/goecfx/data/models/UserSecurityRoleConstants.java` (e.g. `ADMIN = "admin"`, `VIEW_ONLY = "view-only"`), with per-resource triplets like `DOCUMENT = "doc"` / `DOCUMENT_READ = "doc_read"` / `DOCUMENT_UPDATE = "doc_update"`. Token roles are derived in `com.goecfx.data.models.UserSecurityRole#tokenRoles`: a user with `READ` access to a resource gets `<resource>_read`; with `FULL` access gets `<resource>_update` — **mutually exclusive**, so `@Secured({"doc_read"})` does NOT admit a full-access user and vice versa.

**The rule that ends 403 thrash:** an endpoint that backs an existing UI screen must use the *same* gate as the other endpoints that screen already calls — find the host controller and copy its `@Secured` annotation. Do not compose a role set from first principles. (`CategorizationFeedbackController` documents three failed role-set guesses in its Javadoc before landing on `@Secured(SecurityRule.IS_AUTHENTICATED)` to match its host screen `BatchQueryController /api/v1/multiple`.)

Checklist:
- [ ] Gate copied from the host screen's existing endpoints (cite which controller you matched)
- [ ] If a role constant is used, verify it against `UserSecurityRoleConstants` — and remember `_read`/`_update` are mutually exclusive; gating on only one silently excludes the other access level
- [ ] `SecurityRule.IS_ANONYMOUS` only with an explicit justification comment — anonymous mutation endpoints have shipped as security findings

### 1a. Two independent role families — a widening is a widening

Token roles come from two independent fields on `UserSecurityRole`, and a role can hold both:

| Family | Derived from | Constants |
|---|---|---|
| Resource access | `role.getClientAccess()` (`UserSecurityRole#tokenRoles`) | `credential_read` / `credential_update`, `doc_read` / `doc_update`, … |
| Credential-group access | the separate `credentialAccess` field | `cred_view` / `cred_manage`, plus `cred_grp_<group>` claims |

They are **not** mutually exclusive alternatives, so "adding `CRED_MANAGE` is additive, not a widening" is false: a role with `credentialAccess` but no `clientAccess` previously got 403 and now gets in. That is acceptable **only** where the handler re-applies the ECFX-15030 group check (`isCredentialTypeVisible(type, restrictedCredentialGroups(auth))`) and answers an out-of-group credential exactly like a miss.

Checklist when adding roles to an existing `@Secured` list:
- [ ] The comment states the code's actual guarantee (which family each role comes from; that the list widens reachability; what makes it safe) — a security comment that misdescribes the role model will be copied to the next controller
- [ ] A **negative** spec row: the newly admitted role against an out-of-group credential → not-found, not 200 and not 403 (indistinguishability is the point)
- [ ] The union of roles that can *save* a resource can also *read it back* — a caller admitted to `/preview` or `POST` but 403'd on `/current/{id}` is the 403-thrash this skill exists to prevent
- [ ] Every credential type has an `accessGroup` (ECFX-16322 made this universal, with drift guards that flag a type without one); a new type without a group is the exception those guards report

## 2. Input validation — assume `@Valid` is inert; return 400 yourself

Micronaut `@Valid` body validation is **inert in core_rest** (proven by `CategorizationFeedbackControllerBindingSpec`) — annotating the DTO does not reject bad input. Enforce contracts manually and return **400**, not a leaked 500:

- `PublicId` parsing: the constructor throws `IllegalArgumentException` on null/blank/malformed, but a syntactically-plausible-yet-invalid Base32 payload throws `BufferUnderflowException` — catch `RuntimeException` around `PublicId` construction and map to 400.
- Enumerable string fields: validate against an explicit pattern (e.g. `^[A-Z0-9_]{1,16}$`) before use.
- **Never echo the rejected value** into the response body or logs (log-injection guard). Log the field name and reason, not the value.

Checklist:
- [ ] Every request field validated manually; malformed input → 400 with a generic message
- [ ] No rejected input values echoed in responses or logs
- [ ] A binding Spec proves the behavior (400 for each malformed field) — don't trust annotations

## 3. Boundary ID types — PublicId vs bare UUID

`com.goecfx.data.models.util.PublicId` (`projects/data/src/main/java/com/goecfx/data/models/util/PublicId.java`) renders as a **prefixed** string (`doc_<base32>`, `user_role_<base32>`) via `@JsonValue` on `toString()`. Downstream gRPC contracts (e.g. cat-svc) typically want the **bare UUID**. Sending `publicId.toString()` on the wire produces `INVALID_ARGUMENT` at runtime with no compile-time signal.

- [ ] For every ID crossing a service boundary, confirm the contract's expected form; use `publicId.toUUID().toString()` when the peer wants a raw UUID
- [ ] Incoming prefixed IDs parsed with `new PublicId(value)` inside the RuntimeException guard from §2

## 4. Downstream (gRPC) error mapping

Map deliberately; never forward raw gRPC detail strings to the HTTP client. The established mapping in `CategorizationFeedbackController`:

| gRPC status | HTTP | Rationale |
|---|---|---|
| `INVALID_ARGUMENT` | 409 (or 400 if clearly the caller's input) | contract mismatch, caller can act |
| `PERMISSION_DENIED` | 500 + `[ALERT]` log marker | our config error, not the user's |
| `DEADLINE_EXCEEDED`, `UNAVAILABLE`, default | 503 | transient; caller should retry |

- [ ] Every downstream failure mode mapped to an intentional HTTP status
- [ ] Raw downstream error detail logged server-side only, never returned

## 5. Execution & transactions

- [ ] Blocking handlers annotated `@ExecuteOn(TaskExecutors.BLOCKING)`
- [ ] **No `@Transactional` on controllers** — transaction boundaries belong on the service layer (enforced by the `transaction-boundary-validator` skill)

## Output

Report per-section findings with `file:line` references, each tagged PASS or the concrete fix. Lead with anything that would 403 legitimate users or 500 on malformed input — those are the two failure modes this skill exists to prevent.

## Scope

Specific to ecfx-backend conventions. For other Micronaut projects, §2 (verify validation actually fires), §4 (deliberate error mapping), and §5 apply generically; §1 and §3 reference ecfx-specific classes.
