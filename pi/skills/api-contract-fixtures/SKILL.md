---
name: api-contract-fixtures
description: >-
  Build and check test fixtures for API payloads from the real contract, not from what the code under test expects — capture an actual response (or serialise the real DTO), derive the fixture from it, declare wire fields by their exact serialised name, and never put a value in a fixture the API cannot emit (a secret field's value, a camelCase key on a snake_case wire). Use when writing or reviewing any test that mocks or stubs an HTTP/JSON response, builds a descriptor or DTO fixture by hand, or asserts on a field name crossing a service boundary — in ecfx-dashboard (vitest), ecfx-backend (Spock) or ecfx-admin (pytest).
---


# API Contract Fixtures

## The failure this prevents

A fixture is a claim about what the other side sends. When the claim is written from the code
under test rather than from the contract, the test can only compare the code to itself. Three
green-but-wrong tests shipped through review this way in one feature:

| Fixture said | The API actually does | Effect |
|---|---|---|
| `fields.myHawaiiUsername` | key is `myhawaiiusername` | descriptor test green, contract already diverged |
| `fields.totpkey = "KEY"` on a `secret: true` field | secret fields are **stripped** from every GET | the "Show TOTP" gate was constant `false` in production |
| `credential.configuredSecretFields` | wire is `configured_secret_fields`, no case conversion in the client | new feature read `undefined` forever; four must-fail checks all passed inside the closed loop |

TypeScript cannot catch this (payloads arrive as `any`), Spock stubs cannot (they return what you
tell them), and CI in these repos runs no tests anyway. Only the fixture-building discipline can.

## Procedure

### 1. Capture the real payload first

Pick one, in order of preference, and paste the result (redacted) into the test file as a comment
or into `tests/fixtures/README.md`:

- **A running service.** Local stack or dev: `curl -s -H "Authorization: Bearer $T" .../api/v1/<resource> | jq '.items[0]'`.
- **The producing DTO's serialisation.** For a Micronaut Serde DTO, a Spock spec that runs it
  through `JsonMapper`/`ObjectMapper` and asserts the key set is the cheapest contract test there is.
- **The producing mapper.** Read `*Mapper.java` / `@Mapping(source = …)` to see which fields are
  *omitted*, not just renamed. In ecfx-backend `FirmCredentialMapper` maps `credentialsSansSecrets`
  → `fields`: secret keys are absent, not masked.

Never derive a fixture from the consuming code, a type declaration, or memory.

### 2. Derive the fixture from the capture

- **Exact key names.** Micronaut Serde in ecfx services emits snake_case (`created_at`,
  `total_count`, `configured_secret_fields`); the dashboard reads keys verbatim (`useJsonTableApi`
  destructures `total_count`, `useProviderPageData` reads `timekeeper_id`). Declare TypeScript
  fields with the wire name, as the repo already does (`timekeeper_id`, `case_id`).
- **Absent means absent.** If the API omits a key (secret fields, nulls under a `non_null`
  inclusion), the fixture omits it. A fixture builder that *refuses* to emit a value for a field
  the descriptor marks `secret: true` makes the worst class unwritable.
- **One fixture module per contract**, shared by every spec that consumes it, with the capture
  date and source at the top. Local per-test literals are where drift hides.

### 3. Assert in both directions

A guard that only checks the right key is present stays green against code that reads nothing at
all. For every renamed or newly consumed field, add:

- the real name **is** read (positive), and
- the plausible wrong name (camelCase twin, old name) **is not** read (negative), so the test
  fails if someone "fixes" the fixture toward the code.

### 4. Mutate before trusting

Change the consuming code to read the wrong name (or to ignore the field) and confirm the test goes
red. If the fixture still satisfies it, the fixture is describing the code, not the contract.

### 5. When the contract changes mid-review

Update the capture, the fixture module, and the type in the same commit, and say in the MR reply
which real response the new fixture was taken from. A cross-repo wire change is not done until the
consuming repo's fixture was regenerated from the producing repo's actual output.

## Review checklist

- [ ] Every stubbed response in the diff traces to a captured payload or a serialisation spec
- [ ] No fixture carries a value for a field the producer strips or never sets
- [ ] Wire keys match the producer's naming strategy exactly; no camelCase-vs-snake_case guess
- [ ] Positive and negative key assertions exist for each new or renamed field
- [ ] The author states which mutation turned the guard red

## Scope

Repo-agnostic. The examples are ecfx-dashboard ↔ ecfx-backend, where the mismatch class recurred,
but the same applies to gRPC contracts (prefixed `PublicId` vs bare UUID — see
`secured-endpoint-contract` §3) and to ecfx-admin's pytest fixtures for Java-service responses.
