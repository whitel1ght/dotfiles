---
name: tdd-flow
description: >-
  Run the full Micronaut TDD workflow (entity/repository/service/controller/grpc) directly in the main session — load context, detect layer, route to the matching layer skill, run RED→GREEN→REFACTOR→EXPAND, then capture lessons. Use INSTEAD of spawning the tdd-micronaut-v2 subagent when the task is small or you want to stay in the active context. Triggers when the user invokes /tdd-flow, says "start TDD", "TDD this", "TDD workflow", "let's TDD", or asks to build/test a Micronaut entity, repository, service, controller, or gRPC service/client in the main session.
---


# TDD Flow (Main-Session Orchestrator)

You are now executing the same disciplined TDD workflow as the `backend:tdd-micronaut-v2` subagent — but inside the main session. You orchestrate the existing layer skills rather than spawning a subagent.

**Mirrors:** the `backend:tdd-micronaut-v2` agent

> **Sync note:** The workflow, @MicronautTest decision matrix, and absolute constraints in this skill are intentionally duplicated from `tdd-micronaut-v2.md`. When you change any of those sections here, update the matching section in the agent file in the same MR. The split exists so the subagent can run in a clean context while the skill runs inline — drift between them produces conflicting guidance to readers.

## Core Identity

- Tests are written BEFORE implementation (RED phase first).
- The database schema and external contracts are sources of truth.
- Constructor injection only — never field injection.
- Verify external library APIs with `javap` before implementing.
- Every task ends with a retrospective.

## @MicronautTest Decision Matrix (MANDATORY)

Any class in Micronaut's DI graph MUST be tested with `@MicronautTest` and `@Inject`. Never `new MyController()`.

| Class Type        | @MicronautTest? | Reason                                            |
|-------------------|-----------------|---------------------------------------------------|
| Controllers       | YES             | HTTP stack, routing, security, serialization      |
| Services          | YES             | DI, transactions, AOP interceptors                |
| Repositories      | YES             | Data access, TestResources database               |
| Filters           | YES             | HTTP pipeline integration                         |
| DTOs              | NO              | Pure data, no DI involvement                      |
| Static utilities  | NO              | No Micronaut context needed                       |
| Value objects     | NO              | Immutable data holders                            |

Self-check every test file before running it: `@MicronautTest` on the class, `@Inject` for the unit under test, no `new` on any DI-managed class.

## Workflow: START → BUILD → REFLECT

### Phase 1 — START (always)

1. **Invoke `tdd-context-loader`** via the Skill tool. This reads `~/.claude/docs/tdd-learnings.md` (and project-local equivalent if present), summarizes the last 5 lessons, surfaces layer-relevant patterns, and reports active warnings.
2. **Determine test scope:**
   - Single-module repo → `./gradlew test`
   - Multi-module, working in a submodule → `./gradlew :{submodule}:test`
   - Multi-module, modifying a shared library (e.g., `data`, `backend_shared`) → run library tests AND key consumer module tests
3. **Run the scoped baseline** and report: total / passing / failing. New work must NOT increase the failure count.

### Phase 2 — DETECT LAYER

Match the task to ONE layer skill. If ambiguous, ask the user.

| Detection Signal                                                       | Skill to Invoke                          |
|------------------------------------------------------------------------|------------------------------------------|
| `@Entity`, `@Table`, schema mapping, `entities/`, `data/models/`       | `tdd-entity-layer`                       |
| `@Repository`, `JpaRepository`, query derivation, `repositories/`      | `tdd-repository-layer`                   |
| `@Singleton`, `@Transactional`, business logic, `services/`            | `tdd-service-layer`                      |
| `@Controller`, `@Get`, `@Post`, REST endpoints, `controllers/`         | `tdd-controller-layer`                   |
| `@RabbitListener`, `@Scheduled`, `*_queue/`, queue consumer            | `tdd-service-layer` (Queue pattern)      |
| extends `*ImplBase`, `@GrpcChannel`, `@Factory` for stubs, `grpc/`     | `tdd-grpc-layer`                         |

Invoke the matched skill via the Skill tool to load layer-specific patterns before writing any code.

### Phase 3 — BUILD (4-step TDD cycle)

**STEP 1 — RED (failing test)**
- Search for an existing `{ClassName}Spec.groovy` in the module's test dir BEFORE creating a new file. If found, add cases to it. Never create behavior-specific specs (`FooHashCodeSpec`, `FooLazyLoadingSpec`).
- Write the test with `given → when → then` (Spock).
- Apply the @MicronautTest matrix above. Self-check before running.
- Run the new test scoped to the spec and verify it FAILS:
  ```bash
  ./gradlew :{submodule}:test --tests "*{ComponentName}Spec"
  ```

**STEP 2 — GREEN (minimum code)**
- Create the component with correct package, annotations, structure.
- Write the MINIMUM code to pass. No over-engineering.
- Iterate until green; verify stable across 2–3 runs.

**STEP 3 — REFACTOR (clean up)**
- JavaDoc on class + public methods.
- Extract constants, simplify conditionals, remove duplication.
- Confirm: constructor injection, proper error handling, layer boundaries respected, no commented-out code or debug logs.
- Invoke `checkstyle-enforcer` skill to validate/fix style.
- Re-run tests — must remain GREEN.

**STEP 4 — EXPAND (edge cases)**
- Test: nulls, empty collections, boundary values, invalid inputs.
- Test: not-found, validation failures, constraint violations.
- One descriptive test per scenario.
- Re-run scoped suite to confirm no regressions:
  ```bash
  ./gradlew :{submodule}:test
  ```

#### Conditional supporting skills (invoke during BUILD when triggered)

| Trigger                                                       | Skill to Invoke                       |
|---------------------------------------------------------------|---------------------------------------|
| Test infra missing, "unable to proxy", "cannot create mock"   | `spock-test-setup`                    |
| Using methods from an external library                        | `verify-library-api`                  |
| TestContainers config uncertain, connection failures          | `test-resources-validator`            |
| Writing/modifying a service method with `@Transactional`      | `transaction-boundary-validator`      |
| Writing repository query derivation                           | `micronaut-data-repository`           |
| Modifying or creating an entity                               | `schema-drift-detector`               |
| Verifying CodeArtifact creds before a build                   | `codeartifact-validator`              |

### Phase 4 — REFLECT (always)

Invoke `tdd-retrospective` skill. It will:
- Reflect on what worked, what was difficult, what surprised you.
- Append a structured entry to `~/.claude/docs/tdd-learnings.md`.
- Promote patterns recurring 3+ times to "Critical Patterns".
- Prune "Recent Lessons" to the last 5.

## Test File Organization Rules (MANDATORY before writing any test)

1. SEARCH for existing `{ClassName}Spec.groovy` first; ADD cases to it if found.
2. Spec name MUST match the class under test, NOT the behavior.
3. Never mock-only specs without `@MicronautTest` for DI-managed classes.
4. Use the module's `SchemaLoader` + `schema.sql` pattern. NEVER inline `ensureSchema()`, `tryExecute()`, or `splitSqlStatements()`.
5. Controller specs: use `@Client` HttpClient (reference: `ECFXTrackControllerSpec`).
6. Provider specs (`@Prototype`): `applicationContext.createBean()` with `@MockBean` for externals (reference: `LitifyProviderSpec`).
7. Test data: static UUID/ID constants (no `UUID.randomUUID()`), single `insertTestData()` with inline SQL, `executeWithAutoCommit` with `DataSource` (never EntityManager wrapping), unique firm ID per spec.

## Absolute Constraints

1. NEVER write production code before the test (RED first).
2. NEVER test a DI-graph class without `@MicronautTest` + `@Inject`. No exceptions.
3. NEVER test JPA entity behavior (equals, hashCode, persistence, lazy loading) without `@MicronautTest` and a real database. Reflection-based unit tests do not validate Hibernate.
4. NEVER skip `tdd-context-loader` at START.
5. NEVER skip `tdd-retrospective` at REFLECT.
6. NEVER commit while tests are failing.
7. ALWAYS use constructor injection.
8. ALWAYS verify external library APIs with `javap` before implementing.
9. ALWAYS run a scoped baseline before starting (submodule-level for multi-module).
10. NEVER increase the failing-test count from baseline.
11. NEVER modify, override, or editorialize on a user-provided plan. If you see issues, raise them — do not silently change.
12. NEVER use `TransactionOperations<java.sql.Connection>` — always raw `TransactionOperations`. The generic version pulls in JDBC's DataSourceTransactionManager which conflicts with Hibernate.
13. Queue services (`*_queue` projects): `startApplication = true`, `maximum-pool-size: 10` in `application-test.yml`.
14. New project test schemas: copy `core_rest`'s `schema.sql` as the base — never build from scratch (Hibernate scans all entities; missing tables cause startup failures).
15. ALWAYS run `:module:cleanTest :module:test` after adding NEW spec files (not just `:module:test`). Gradle's incremental test cache can report hundreds of stale "failures" from removed tests, masking the real outcome of the new spec.
16. When `compileJava`/`compileTestJava` fails with `FilerException: Attempt to recreate a file` for MapStruct-generated classes (most common in the `data` module), delete `build/generated` ONLY (NOT the entire `build/` directory) and retry. This is Gradle incremental compilation, not a code defect. Deleting the full `build/` will trigger the TestResources 401 cascade — see `test-resources-validator/reference.md` for the recovery procedure.

## When NOT to use this skill (use the subagent instead)

- Multi-phase modernization spanning many files (50+ LOC change across 5+ files).
- Work packages requiring a clean context window.
- Long-running refactors where you want a separate report-back at the end.
- When the team-lead pattern (Skeptic gate, WP-N handoff) applies — keep using `backend:tdd-micronaut-v2` for those.

## Output Format (when finished)

```
{ComponentName} Complete

Type: {Entity|Repository|Service|Controller}
Tests: {X} passing (baseline was {Y})
Coverage: {methods/scenarios covered}

Test Scenarios:
- Happy path: {description}
- Edge cases: {list}
- Error scenarios: {list}

Files Created/Modified:
- Implementation: src/main/java/{package}/{Component}.java
- Test: src/test/groovy/{package}/{Component}Spec.groovy

Learning Captured:
- Key lesson: {brief}
- Pattern discovered: {if any}
- Learnings file updated: Yes
```
