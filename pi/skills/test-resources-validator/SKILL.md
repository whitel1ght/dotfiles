---
name: test-resources-validator
description: >-
  Validate Micronaut TestResources configuration follows correct patterns for auto-provisioning TestContainers. Use when setting up test infrastructure, before running tests for the first time, when test connection issues occur, or when user mentions TestContainers, test database setup, or test configuration.
---


# TestResources Configuration Validator

Validate that Micronaut TestResources configuration follows the correct three-file pattern required for automatic TestContainer provisioning. This prevents mysterious test failures caused by configuration errors.

## Problem Solved

TestResources auto-provisioning only works when datasource connection properties are MISSING from base configuration. Default values like `${DATABASE_URL:jdbc:...}` prevent TestResources from detecting missing configuration, leading to 30+ minute debugging sessions when tests fail mysteriously.

## Critical Concept

**TestResources Detection Mechanism**:
- TestResources inspects configuration for datasource connection details (url, username, password)
- When these properties are **MISSING**, TestResources auto-provisions TestContainers
- When these properties are **PRESENT** (even with default values), TestResources does nothing
- Configuration files overlay additively: environment-specific files never remove base properties

## Process

### 1. Identify Configuration Files

Locate these three files in the project:
- `src/main/resources/application.yml` (base configuration)
- `src/main/resources/application-test.yml` (test environment overlay)
- `src/main/resources/application-prod.yml` (production environment overlay)

### 2. Validate Base Configuration (application.yml)

**Check for ABSENCE of connection properties**:

```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver  # ✅ OK - shared config
    db-type: postgres                          # ✅ OK - shared config
    dialect: POSTGRES                          # ✅ OK - shared config
    maximum-pool-size: 10                      # ✅ OK - shared config
    minimum-idle: 2                            # ✅ OK - shared config
```

**MUST NOT contain**:
```yaml
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/db   # ❌ WRONG - blocks TestResources
    url: ${DATABASE_URL}                       # ❌ WRONG - blocks TestResources
    url: ${DATABASE_URL:jdbc:...}              # ❌ WRONG - default blocks TestResources
    username: user                             # ❌ WRONG - blocks TestResources
    password: pass                             # ❌ WRONG - blocks TestResources
```

**Validation checks**:
- [ ] NO `datasources.*.url` property
- [ ] NO `datasources.*.username` property
- [ ] NO `datasources.*.password` property
- [ ] NO default values (`:`) in any datasource connection property
- [ ] Shared settings (driver, pool config) present

### 3. Validate Test Configuration (application-test.yml)

**Check for test-resources enablement**:

```yaml
test-resources:
  enabled: true                               # ✅ REQUIRED - enables TestResources
  containers:
    postgres:                                  # ✅ REQUIRED - container config
      db-name: ecfx                           # ✅ OK - test database name
      db-password: ecfx                       # ✅ OK - test password
      db-username: ecfx                       # ✅ OK - test username

jpa:
  default:
    properties:
      hibernate:
        default_schema: private               # ✅ OK if using schemas
```

**MUST NOT contain datasource connection in test config**:
```yaml
# ❌ WRONG - defeats TestResources purpose
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/test
    username: test
    password: test
```

**Validation checks**:
- [ ] `test-resources.enabled: true` present
- [ ] `test-resources.containers.postgres` configured (or appropriate db type)
- [ ] Database name, username, password specified in test-resources section
- [ ] NO `datasources.*.url` in test config
- [ ] NO `datasources.*.username` in test config
- [ ] NO `datasources.*.password` in test config

### 4. Validate Production Configuration (application-prod.yml)

**Check for environment variable references**:

```yaml
datasources:
  default:
    url: ${DATABASE_URL}                      # ✅ OK - from environment
    username: ${DATABASE_USERNAME}            # ✅ OK - from environment
    password: ${DATABASE_PASSWORD}            # ✅ OK - from environment
```

**MUST NOT contain default values**:
```yaml
# ❌ WRONG - defaults prevent detection of missing prod config
datasources:
  default:
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/default}
    username: ${DATABASE_USERNAME:default_user}
    password: ${DATABASE_PASSWORD:default_pass}
```

**Validation checks**:
- [ ] `datasources.*.url` references environment variable
- [ ] `datasources.*.username` references environment variable
- [ ] `datasources.*.password` references environment variable
- [ ] NO default values after `:` in variable references
- [ ] Inherits shared settings from base application.yml

### 5. Check for Anti-Patterns

**Common mistakes that break TestResources**:

**Anti-Pattern 1**: Default values in base config
```yaml
# ❌ application.yml - WRONG
datasources:
  default:
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/default}
```
**Problem**: Default value present → TestResources sees configured value → doesn't provision container

**Anti-Pattern 2**: Connection details in test config
```yaml
# ❌ application-test.yml - WRONG
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/test
```
**Problem**: Explicit URL → TestResources disabled → no auto-provisioning

**Anti-Pattern 3**: Missing test-resources section
```yaml
# ❌ application-test.yml - INCOMPLETE
jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: create-drop
# Missing test-resources.enabled: true
```
**Problem**: TestResources not enabled → no container provisioning

**Anti-Pattern 4**: Test resources in wrong file
```yaml
# ❌ application.yml - WRONG LOCATION
test-resources:
  enabled: true
```
**Problem**: Enables TestResources in ALL environments, not just test

### 6. Generate Validation Report

Create a comprehensive report:

```markdown
## TestResources Configuration Validation

### Base Configuration (application.yml)
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ No datasource URL present
- [ ] ✅ No datasource username present
- [ ] ✅ No datasource password present
- [ ] ✅ No default values in connection properties
- [ ] ✅ Shared settings configured (driver, pool, etc.)

**Issues Found**: [None] / [List issues]

### Test Configuration (application-test.yml)
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ test-resources.enabled: true present
- [ ] ✅ Container configuration present
- [ ] ✅ No datasource connection in test config
- [ ] ✅ Appropriate schema configuration if needed

**Issues Found**: [None] / [List issues]

### Production Configuration (application-prod.yml)
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ Datasource URL from environment variable
- [ ] ✅ Username from environment variable
- [ ] ✅ Password from environment variable
- [ ] ✅ No default values in variable references

**Issues Found**: [None] / [List issues]

### Overall Assessment
**Result**: ✅ READY FOR TESTRESOURCES / ❌ CONFIGURATION ERRORS

### Recommendations
[List specific fixes needed, or confirm configuration is correct]
```

### 7. Provide Corrective Actions

If issues found, provide specific fixes:

**For base config issues**:
```yaml
# Fix: Remove connection properties from application.yml
# BEFORE (wrong):
datasources:
  default:
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/db}

# AFTER (correct):
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    # NO url, username, password here
```

**For test config issues**:
```yaml
# Fix: Add test-resources section to application-test.yml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: your_test_db
      db-password: test_password
      db-username: test_user
```

**For production config issues**:
```yaml
# Fix: Add connection properties to application-prod.yml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
```

## Container preflight — why a correct configuration still fails here

Inside the claude-code-container the environment exports **`RABBITMQ_URI=amqp://rabbit:5672`**,
`RABBITMQ_DEFAULT_USER` and `RABBITMQ_DEFAULT_PASS` for the local stack. Micronaut maps
`RABBITMQ_URI` onto `rabbitmq.uri`, which **overrides the TestResources broker**, so every
`@MicronautTest` spec fails at context startup with:

```
com.rabbitmq.client.AuthenticationFailureException: ACCESS_REFUSED - Login was refused using authentication mechanism PLAIN
```

This is not load, not a dead TestResources server, and not the spec. Two agents misdiagnosed it
as contention and shipped an MR round with "could not run". Run every Gradle test as:

```bash
./gradlew --stop   # a daemon started WITH the variable keeps poisoning test JVMs even after the client unsets it
env -u RABBITMQ_URI -u RABBITMQ_DEFAULT_USER -u RABBITMQ_DEFAULT_PASS ./gradlew :module:test --tests '*Spec*' --console=plain
```

Then reconcile the reported count against the spec's `where:` rows before citing it. For
ecfx-dashboard in the same container: Node is 20 and the project needs 24 — prefix with
`npx -y -p node@24`.

## Quality Checklist

- [ ] All three configuration files located
- [ ] Base config (application.yml) contains NO connection properties
- [ ] Base config has NO default values for connections
- [ ] Test config (application-test.yml) has test-resources enabled
- [ ] Test config has container configuration
- [ ] Test config has NO datasource connection properties
- [ ] Production config (application-prod.yml) references environment variables
- [ ] Production config has NO default values
- [ ] Report clearly identifies all issues
- [ ] Specific corrective actions provided for each issue

## When to Use This Skill

**Always use when**:
- Setting up test infrastructure for the first time
- Tests fail with connection errors
- TestContainers don't start automatically
- Migrating from manual TestContainers setup

**Warning signs that indicate need**:
- Error: "Unable to connect to database"
- Error: "No suitable driver found"
- Tests work locally but fail in CI
- TestContainers dependency present but not starting

**Preventative use**:
- Before first test run in new project
- After adding database dependencies
- When onboarding new developers
- During CI/CD setup

## Expected Behavior When Correct

When configuration is correct:

1. **Test execution**:
   ```bash
   ./gradlew test
   ```

2. **TestResources auto-provisions**:
   ```
   [Test Resources] Starting PostgreSQL container...
   [Test Resources] Container started on port 54321
   [Test Resources] Database URL: jdbc:postgresql://localhost:54321/ecfx
   ```

3. **Tests connect automatically** - no manual container management

4. **Container cleanup** - TestResources stops container after tests

## Special Cases

**Multiple Databases**: Validate configuration for each datasource:
```yaml
datasources:
  default:
    # No connection properties
  secondary:
    # No connection properties

# In application-test.yml:
test-resources:
  containers:
    postgres:
      db-name: main_db
    postgres-secondary:
      db-name: secondary_db
```

**Different Database Types**: Adjust validation for MySQL, Oracle, etc.:
```yaml
test-resources:
  containers:
    mysql:
      image: mysql:8.0
      db-name: test_db
```

**Custom Schemas**: Validate schema configuration in test config:
```yaml
jpa:
  default:
    properties:
      hibernate:
        default_schema: custom_schema
```

**No Production Config**: If application-prod.yml doesn't exist, production values must come from another environment-specific file or solely from environment variables.

---

For detailed examples, see `examples.md`
For TestResources documentation links, see `reference.md`
