# TestResources Configuration Validator - Reference

## Micronaut TestResources Documentation

### Official Resources
- [Micronaut TestResources Guide](https://micronaut-projects.github.io/micronaut-test-resources/latest/guide/)
- [Configuration Loading Order](https://docs.micronaut.io/latest/guide/#propertySource)
- [TestContainers Integration](https://www.testcontainers.org/)

### Key Concepts

#### TestResources Auto-Provisioning
TestResources automatically provisions test infrastructure (databases, message brokers, etc.) by:
1. Inspecting resolved configuration for missing properties
2. Starting appropriate TestContainers when properties are absent
3. Injecting connection details into test context
4. Managing container lifecycle (start before tests, stop after)

#### Detection Mechanism
```
Configuration Resolution → TestResources Inspection → Decision
                                                          ↓
                    ┌─────────────────────────────────────┴─────────────────────────────────────┐
                    │                                                                             │
             Properties MISSING                                                        Properties PRESENT
                    │                                                                             │
          ┌─────────┴─────────┐                                                       ┌───────────┴──────────┐
          │ Auto-provision    │                                                       │ Use existing config  │
          │ TestContainers    │                                                       │ No provisioning     │
          └───────────────────┘                                                       └──────────────────────┘
```

---

## Configuration Loading Order

### Micronaut Configuration Resolution

Micronaut loads configuration in this specific order (later overrides earlier):

1. **application.yml** - Base configuration (shared across all environments)
2. **application-{env}.yml** - Environment-specific overlay (additive)
3. **Environment Variables** - Override any YAML property
4. **System Properties** - Command-line arguments
5. **@Property annotations** - Programmatic overrides

**Critical Point**: Environment-specific files ADD to base config, they don't replace it.

### Example Configuration Flow

#### Files
```yaml
# application.yml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    maximum-pool-size: 10

# application-test.yml
test-resources:
  enabled: true
```

#### Resolution with MICRONAUT_ENVIRONMENTS=test

**Step 1**: Load application.yml
```yaml
datasources.default.driver-class-name = org.postgresql.Driver
datasources.default.maximum-pool-size = 10
```

**Step 2**: Overlay application-test.yml
```yaml
datasources.default.driver-class-name = org.postgresql.Driver
datasources.default.maximum-pool-size = 10
test-resources.enabled = true
```

**Step 3**: TestResources inspects final config
```
datasources.default.url = NOT PRESENT
→ Provision PostgreSQL TestContainer
→ Inject url = jdbc:postgresql://localhost:54321/test_db
```

---

## The Three-File Pattern

### Pattern Structure

```
src/main/resources/
├── application.yml              # Shared config only
├── application-test.yml         # Test-specific (test-resources)
└── application-prod.yml         # Production-specific (env vars)
```

### File Responsibilities

#### application.yml (Base)
**Purpose**: Shared configuration across ALL environments

**Should contain**:
- Application name
- Driver classes
- Pool settings
- Dialect configuration
- Default behaviors
- Common settings

**Should NOT contain**:
- Database URLs
- Usernames/passwords
- Environment-specific settings
- Default values with `:` syntax
- test-resources configuration

**Example**:
```yaml
micronaut:
  application:
    name: my-service

datasources:
  default:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    dialect: POSTGRES
    maximum-pool-size: 10
    minimum-idle: 2

jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: none
```

#### application-test.yml (Test)
**Purpose**: Test environment configuration and TestResources enablement

**Should contain**:
- `test-resources.enabled: true`
- Container configuration (db-name, credentials)
- Test-specific overrides (schema, hbm2ddl, etc.)
- Test logging levels

**Should NOT contain**:
- Explicit datasource URLs
- Datasource usernames/passwords
- Production settings

**Example**:
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: test_db
      db-username: test_user
      db-password: test_pass

jpa:
  default:
    properties:
      hibernate:
        default_schema: private
        show_sql: true
```

#### application-prod.yml (Production)
**Purpose**: Production environment configuration

**Should contain**:
- Datasource connection from environment variables
- Production-specific overrides
- Prod logging levels
- Security settings

**Should NOT contain**:
- Hardcoded credentials
- Default values
- test-resources configuration
- Development settings

**Example**:
```yaml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}

logger:
  levels:
    com.myapp: INFO
```

---

## Supported Test Resources

### Databases

| Database | Container Config Key | Driver Class |
|----------|---------------------|--------------|
| PostgreSQL | `postgres` | `org.postgresql.Driver` |
| MySQL | `mysql` | `com.mysql.cj.jdbc.Driver` |
| MariaDB | `mariadb` | `org.mariadb.jdbc.Driver` |
| Oracle | `oracle` | `oracle.jdbc.OracleDriver` |
| SQL Server | `mssql` | `com.microsoft.sqlserver.jdbc.SQLServerDriver` |
| MongoDB | `mongodb` | N/A (not JDBC) |

### PostgreSQL Configuration
```yaml
test-resources:
  containers:
    postgres:
      image-name: postgres:15-alpine  # Optional: specify version
      db-name: my_database
      db-username: my_user
      db-password: my_password
      init-script: classpath:init.sql  # Optional: initialization script
```

### MySQL Configuration
```yaml
test-resources:
  containers:
    mysql:
      image-name: mysql:8.0
      db-name: test_db
      db-username: root
      db-password: test_pass
```

### MongoDB Configuration
```yaml
test-resources:
  containers:
    mongodb:
      image-name: mongo:6.0
```

---

## Common Anti-Patterns

### Anti-Pattern 1: Default Values in Base Config

**Problem**:
```yaml
# application.yml - WRONG
datasources:
  default:
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/db}
```

**Why it fails**:
- Default value `:jdbc:...` means property is ALWAYS present
- TestResources sees configured value
- Doesn't provision container
- Tests fail connecting to localhost:5432

**Solution**:
```yaml
# application.yml - CORRECT
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    # No url property at all

# application-prod.yml
datasources:
  default:
    url: ${DATABASE_URL}  # No default
```

### Anti-Pattern 2: Connection Properties in Test Config

**Problem**:
```yaml
# application-test.yml - WRONG
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/test
```

**Why it fails**:
- Explicit URL overrides TestResources
- TestResources won't start container
- Tests expect localhost:5432 to exist

**Solution**:
```yaml
# application-test.yml - CORRECT
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: test
```

### Anti-Pattern 3: TestResources in Base Config

**Problem**:
```yaml
# application.yml - WRONG
test-resources:
  enabled: true
```

**Why it's problematic**:
- Enables TestResources in ALL environments
- Production might try to start containers
- Should be test-specific only

**Solution**:
```yaml
# application-test.yml - CORRECT
test-resources:
  enabled: true
```

### Anti-Pattern 4: Missing Test Config Entirely

**Problem**:
```
# No application-test.yml exists
```

**Why it fails**:
- TestResources never enabled
- Tests use whatever's in base config
- If base has defaults, connects there
- If base has no connection, fails

**Solution**:
```yaml
# Create application-test.yml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: test_db
```

---

## Validation Commands

### Check for Connection Properties
```bash
# Should return nothing (or only from prod config)
grep -r "^\s*url:" src/main/resources/application.yml

# Check for default values (anti-pattern)
grep -r ":\${.*:.*}" src/main/resources/application.yml
```

### Verify Test Config
```bash
# Should find test-resources
grep -A 5 "test-resources:" src/main/resources/application-test.yml

# Check it's enabled
grep "enabled: true" src/main/resources/application-test.yml
```

### Check Production Config
```bash
# Should have env var references (no defaults)
grep "url: \${" src/main/resources/application-prod.yml
```

### List All Config Files
```bash
find src/main/resources -name "application*.yml" -o -name "application*.yaml"
```

---

## Environment Variables

### Setting Test Environment

**Command line**:
```bash
MICRONAUT_ENVIRONMENTS=test ./gradlew test
```

**Gradle configuration** (already set by Micronaut):
```groovy
test {
    systemProperty "micronaut.environments", "test"
}
```

**IntelliJ Run Configuration**:
- Environment variables: `MICRONAUT_ENVIRONMENTS=test`

### Setting Production Environment

**Docker**:
```bash
docker run -e MICRONAUT_ENVIRONMENTS=prod \
           -e DATABASE_URL=jdbc:postgresql://prod-db:5432/db \
           -e DATABASE_USERNAME=prod_user \
           -e DATABASE_PASSWORD=secret \
           my-app:latest
```

**Kubernetes**:
```yaml
env:
  - name: MICRONAUT_ENVIRONMENTS
    value: "prod"
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: url
```

---

## Debugging TestResources

### Enable Debug Logging

**application-test.yml**:
```yaml
logger:
  levels:
    io.micronaut.testresources: DEBUG
    org.testcontainers: DEBUG
```

### Expected Log Output (Working)

```
[Test Resources] Detected missing property: datasources.default.url
[Test Resources] Starting container: postgres
[TestContainers] Creating container: postgres:15-alpine
[TestContainers] Starting container with ID: abc123def456
[TestContainers] Container started
[TestContainers] Mapped port 5432 to 54321
[Test Resources] Resolved datasources.default.url = jdbc:postgresql://localhost:54321/test_db
[Test Resources] Resolved datasources.default.username = test_user
[Test Resources] Resolved datasources.default.password = test_pass
```

### Error Indicators (Not Working)

**No container start**:
```
[Test Resources] All properties resolved from configuration
# TestResources didn't find missing properties → check base config
```

**Connection failure**:
```
java.sql.SQLException: Connection refused
# Usually means:
# - TestResources not starting container
# - Or trying to connect to wrong location
```

**Driver not found**:
```
java.sql.SQLException: No suitable driver found
# TestResources not injecting URL, using default from config
```

---

## Schema Management

### Test Schema Setup Options

#### Option 1: SQL Script
```yaml
# application-test.yml
test-resources:
  containers:
    postgres:
      init-script: classpath:db/schema.sql
```

```java
// Or programmatically
@Inject DataSource dataSource;

void setupSpec() {
    SchemaLoader.loadSchema(dataSource, "db/schema.sql");
}
```

#### Option 2: Hibernate Auto-DDL
```yaml
# application-test.yml
jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: create-drop  # Create schema before tests, drop after
```

#### Option 3: External Migrator
If schema managed by separate service (like db_migrator):
```java
// Copy schema SQL from external project to test resources
// src/test/resources/db/schema.sql
// Load manually in test setup
```

---

## Troubleshooting Guide

### Issue: Tests fail with "No suitable driver found"

**Diagnosis**:
- TestResources not injecting database URL
- Tests using config from base application.yml

**Check**:
```bash
grep "url:" src/main/resources/application.yml
```

**Solution**: Remove URL from base config, add to application-prod.yml

---

### Issue: Tests fail with "Connection refused"

**Diagnosis**:
- TestResources not starting container
- Tests trying to connect to localhost

**Check**:
```bash
grep "test-resources:" src/main/resources/application-test.yml
```

**Solution**: Add test-resources configuration to application-test.yml

---

### Issue: Container starts but wrong database name

**Diagnosis**:
- Container running but database name mismatch

**Check**:
```bash
grep "db-name:" src/main/resources/application-test.yml
```

**Solution**: Set correct db-name in test-resources configuration

---

### Issue: TestResources works locally but not in CI

**Diagnosis**:
- CI environment differences
- Docker not available in CI

**Check**:
- Docker daemon running in CI
- TestContainers supported in CI environment
- Correct MICRONAUT_ENVIRONMENTS set

**Solution**: Ensure CI has Docker, set environment correctly

---

## Multiple Environments

### Development Environment

**application-dev.yml**:
```yaml
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/dev_db
    username: dev_user
    password: dev_pass
```

**Usage**:
```bash
MICRONAUT_ENVIRONMENTS=dev ./gradlew run
```

### Staging Environment

**application-staging.yml**:
```yaml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}

logger:
  levels:
    com.myapp: DEBUG
```

---

## Best Practices Summary

1. **Base Config Purity**: No environment-specific values in application.yml
2. **No Default Values**: Never use `${VAR:default}` for connections in base config
3. **Test-Resources in Test**: Only enable test-resources in application-test.yml
4. **Production from Env**: Always use environment variables in application-prod.yml
5. **Validate Early**: Run validator before first test execution
6. **Document Pattern**: Add comments in config files explaining the pattern
7. **Schema Strategy**: Choose one schema management approach consistently
8. **Debug When Needed**: Enable debug logging to understand TestResources behavior

---

## Provider Hints — When TestResources Can't Detect DB Type

The Micronaut TestResources PostgreSQL provider auto-provisions `datasources.default.url`/`username`/`password` only when it can INFER the database type. With application.yml declaring just `driverClassName: org.postgresql.Driver` (camelCase Hikari config), the provider's `shouldAnswer()` does not match — resolution fails with:

```
TestResourcesResolutionException: Test resources doesn't support resolving expression 'datasources.default.password'
```

**Fix**: add explicit hints in `application-test.yml`:

```yaml
datasources:
  default:
    db-type: postgresql
    dialect: POSTGRES
```

Both are needed; the camelCase `driverClassName` in upstream YAML does NOT satisfy the kebab-case `driver-class-name` lookup the provider performs.

## TestResources 401 After `./gradlew clean`

Symptom: tests fail with HTTP 401 from the TestResources server immediately after running `./gradlew clean`.

Cause: `clean` deleted `build/`, but the running TestResources server on a stale port now has a different access token than the regenerated one in `.micronaut/test-resources/test-resources-settings/test-resources.properties`. Also: `test-resources-port.txt` may point to a dead server.

**Fix**:
1. Delete `.micronaut/test-resources/test-resources-settings/test-resources.properties`
2. Delete `projects/{module}/.micronaut/test-resources/test-resources-port.txt` if present
3. Kill any running `micronaut-test-resources` Java process
4. Re-run `./gradlew test` — Gradle will spin up a fresh TestResources server with a matching token

## LocalStack S3 — TestResources Provisioning

For services that interact with S3 (sync `S3Client` or async `S3AsyncClient`), use real LocalStack S3 via TestResources — never `@MockBean(S3Client)`.

**`build.gradle`**:
```groovy
testResourcesService("io.micronaut.testresources:micronaut-test-resources-localstack-s3")
```

**`application-test.yml`**:
```yaml
test-resources:
  containers:
    localstack:
      services: s3
aws:
  region: us-east-1
  services:
    s3:
```

**Spec pattern**:
```groovy
@Inject S3Client s3Client          // sync client; available even when service uses S3AsyncClient
@Shared boolean bucketsCreated = false

def setup() {
    if (!bucketsCreated) {
        try { s3Client.createBucket(CreateBucketRequest.builder().bucket("test-bucket").build()) } catch (e) {}
        bucketsCreated = true
    }
}

void "service stores object via async client, sync client reads it back"() {
    when:
    service.store(payload).block()

    then:
    def object = s3Client.getObject(GetObjectRequest.builder().bucket("test-bucket").key(key).build())
    object.response().contentLength() == payload.length
}
```

`S3AsyncClient` writes go to the SAME LocalStack instance as `S3Client` reads — round-trip verification is reliable.

## Queue Services Still Need Postgres TestResources

Queue services (RabbitMQ consumers, scheduled processors) typically don't have repositories themselves — but they often inject services that do, OR Micronaut eagerly initializes the datasource on context startup. Symptom: queue consumer tests fail with `HibernateException: Could not obtain transaction-synchronized Session` or `No URL specified` even when the test never calls a repository.

**Fix**: declare PostgreSQL TestResources deps even for pure queue services:

```groovy
testImplementation(project(":commons_test"))
testResourcesService("org.postgresql:postgresql")
testResourcesService("io.micronaut.testresources:micronaut-test-resources-jdbc-postgresql")
```

---

## Additional Resources

- [Micronaut Configuration Reference](https://docs.micronaut.io/latest/guide/configurationreference.html)
- [TestContainers Documentation](https://www.testcontainers.org/quickstart/)
- [Gradle TestContainers Plugin](https://github.com/avast/gradle-docker-compose-plugin)
