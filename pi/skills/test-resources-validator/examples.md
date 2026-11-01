# TestResources Configuration Validator - Examples

## Example 1: Correct Three-File Configuration

### Project Structure
```
src/main/resources/
├── application.yml
├── application-test.yml
└── application-prod.yml
```

### application.yml (Base Config)
```yaml
micronaut:
  application:
    name: receipt_processing_web

datasources:
  default:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    dialect: POSTGRES
    maximum-pool-size: 10
    minimum-idle: 2
    # ✅ NO url, username, password - allows TestResources to work

jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: none
```

### application-test.yml (Test Config)
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: ecfx
      db-password: ecfx
      db-username: ecfx

jpa:
  default:
    properties:
      hibernate:
        default_schema: private
```

### application-prod.yml (Production Config)
```yaml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Base Configuration (application.yml)
**Status**: ✅ VALID

**Findings**:
- ✅ No datasource URL present
- ✅ No datasource username present
- ✅ No datasource password present
- ✅ No default values in connection properties
- ✅ Shared settings configured (driver, pool, dialect)

**Issues Found**: None

### Test Configuration (application-test.yml)
**Status**: ✅ VALID

**Findings**:
- ✅ test-resources.enabled: true present
- ✅ Container configuration present (postgres)
- ✅ No datasource connection in test config
- ✅ Appropriate schema configuration (private)

**Issues Found**: None

### Production Configuration (application-prod.yml)
**Status**: ✅ VALID

**Findings**:
- ✅ Datasource URL from environment variable (DATABASE_URL)
- ✅ Username from environment variable (DATABASE_USERNAME)
- ✅ Password from environment variable (DATABASE_PASSWORD)
- ✅ No default values in variable references

**Issues Found**: None

### Overall Assessment
**Result**: ✅ READY FOR TESTRESOURCES

Configuration follows the correct three-file pattern. TestResources will automatically provision PostgreSQL containers during test execution.

### Expected Test Behavior
When running tests with `./gradlew test`:
1. TestResources detects missing datasource configuration
2. Automatically starts PostgreSQL TestContainer
3. Provides connection details to test context
4. Stops container after tests complete
```

---

## Example 2: Common Anti-Pattern (Default Values)

### Incorrect application.yml
```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/default}  # ❌ PROBLEM
    username: ${DATABASE_USERNAME:postgres}                        # ❌ PROBLEM
    password: ${DATABASE_PASSWORD:postgres}                        # ❌ PROBLEM
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Base Configuration (application.yml)
**Status**: ❌ INVALID

**Findings**:
- ❌ Datasource URL present with default value
- ❌ Datasource username present with default value
- ❌ Datasource password present with default value

**Issues Found**: 3 critical issues

1. **Line 4**: `url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/default}`
   - **Problem**: Default value `:jdbc:postgresql://...` prevents TestResources detection
   - **Impact**: TestResources will not auto-provision containers
   - **Fix**: Remove entire `url` line from application.yml

2. **Line 5**: `username: ${DATABASE_USERNAME:postgres}`
   - **Problem**: Default value `:postgres` prevents TestResources detection
   - **Impact**: TestResources will not auto-provision containers
   - **Fix**: Remove entire `username` line from application.yml

3. **Line 6**: `password: ${DATABASE_PASSWORD:postgres}`
   - **Problem**: Default value `:postgres` prevents TestResources detection
   - **Impact**: TestResources will not auto-provision containers
   - **Fix**: Remove entire `password` line from application.yml

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS - TestResources will NOT work

### Corrective Action Required

**Step 1**: Update application.yml to remove connection properties:
```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    dialect: POSTGRES
    # Removed url, username, password
```

**Step 2**: Move connection properties to application-prod.yml:
```yaml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
```

**Step 3**: Verify application-test.yml has test-resources enabled:
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: your_db
```
```

---

## Example 3: Missing test-resources Section

### Incorrect application-test.yml
```yaml
# Only has JPA config, missing test-resources
jpa:
  default:
    properties:
      hibernate:
        hbm2ddl:
          auto: create-drop
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Test Configuration (application-test.yml)
**Status**: ❌ INVALID

**Findings**:
- ❌ test-resources.enabled not present
- ❌ Container configuration not present

**Issues Found**: 2 critical issues

1. **Missing Configuration**: No `test-resources` section found
   - **Problem**: TestResources not enabled for test environment
   - **Impact**: Tests will fail with connection errors
   - **Fix**: Add test-resources configuration

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS - TestResources not enabled

### Corrective Action Required

**Add to application-test.yml**:
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
        hbm2ddl:
          auto: create-drop
```

**Explanation**:
- `enabled: true` - Activates TestResources for test environment
- `containers.postgres` - Configures PostgreSQL TestContainer
- `db-name/username/password` - Test database credentials
```

---

## Example 4: Wrong File for Connection Config

### Incorrect: Connection properties in application-test.yml
```yaml
# ❌ ANTI-PATTERN
datasources:
  default:
    url: jdbc:postgresql://localhost:5432/test
    username: test
    password: test

test-resources:
  enabled: true  # This won't be used!
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Test Configuration (application-test.yml)
**Status**: ❌ INVALID

**Findings**:
- ❌ Datasource connection properties present in test config
- ⚠️  test-resources.enabled present but will be ignored

**Issues Found**: 1 critical issue

1. **Lines 2-5**: Explicit datasource configuration in test config
   - **Problem**: Defeats TestResources auto-provisioning purpose
   - **Impact**: TestResources will NOT start containers (explicit config takes precedence)
   - **Fix**: Remove datasource section from application-test.yml

### Overall Assessment
**Result**: ❌ CONFIGURATION ERROR - Manual connection overrides TestResources

### Why This Fails
When application-test.yml contains explicit datasource configuration:
1. Micronaut loads base application.yml
2. Overlays application-test.yml (adds datasource connection)
3. TestResources inspects final config
4. Sees datasource.url present → assumes database already configured
5. Does NOT start TestContainer
6. Tests fail because localhost:5432 doesn't have the database

### Corrective Action Required

**Remove datasource section from application-test.yml**:
```yaml
# ✅ CORRECT
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: test_db
      db-username: test_user
      db-password: test_pass
# NO datasource section
```

**Result**: TestResources will auto-provision container with these credentials
```

---

## Example 5: Multiple Datasources Configuration

### Correct Multi-Datasource Setup

#### application.yml
```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    maximum-pool-size: 10
    # No connection properties

  secondary:
    driver-class-name: org.postgresql.Driver
    db-type: postgres
    maximum-pool-size: 5
    # No connection properties
```

#### application-test.yml
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: main_db
      db-username: main_user
      db-password: main_pass
    postgres-secondary:
      image-name: postgres:15-alpine
      db-name: secondary_db
      db-username: secondary_user
      db-password: secondary_pass
```

#### application-prod.yml
```yaml
datasources:
  default:
    url: ${PRIMARY_DATABASE_URL}
    username: ${PRIMARY_DATABASE_USERNAME}
    password: ${PRIMARY_DATABASE_PASSWORD}

  secondary:
    url: ${SECONDARY_DATABASE_URL}
    username: ${SECONDARY_DATABASE_USERNAME}
    password: ${SECONDARY_DATABASE_PASSWORD}
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Base Configuration (application.yml)
**Status**: ✅ VALID

**Datasource: default**
- ✅ No connection properties
- ✅ Shared settings configured

**Datasource: secondary**
- ✅ No connection properties
- ✅ Shared settings configured

### Test Configuration (application-test.yml)
**Status**: ✅ VALID

- ✅ test-resources.enabled: true
- ✅ Container for 'default': postgres
- ✅ Container for 'secondary': postgres-secondary
- ✅ No connection properties in test config

### Production Configuration (application-prod.yml)
**Status**: ✅ VALID

**Datasource: default**
- ✅ Connection from environment variables
- ✅ No default values

**Datasource: secondary**
- ✅ Connection from environment variables
- ✅ No default values

### Overall Assessment
**Result**: ✅ READY FOR TESTRESOURCES

Both datasources correctly configured. TestResources will provision two PostgreSQL containers during tests.
```

---

## Example 6: MySQL Configuration

### Correct MySQL Setup

#### application.yml
```yaml
datasources:
  default:
    driver-class-name: com.mysql.cj.jdbc.Driver
    db-type: mysql
    dialect: MYSQL
    # No connection properties
```

#### application-test.yml
```yaml
test-resources:
  enabled: true
  containers:
    mysql:
      image-name: mysql:8.0
      db-name: test_db
      db-username: test_user
      db-password: test_pass
```

### Validation Report
```markdown
## TestResources Configuration Validation

### Base Configuration (application.yml)
**Status**: ✅ VALID

- ✅ MySQL driver configured
- ✅ No connection properties

### Test Configuration (application-test.yml)
**Status**: ✅ VALID

- ✅ test-resources.enabled: true
- ✅ MySQL container configured
- ✅ Custom image specified (mysql:8.0)

### Overall Assessment
**Result**: ✅ READY FOR TESTRESOURCES

TestResources will provision MySQL 8.0 TestContainer during tests.
```

---

## Example 7: Detecting Configuration Through YAML Inspection

### Using Grep to Validate

```bash
# Check if base config has connection properties (should be empty)
$ grep -n "^\s*url:" src/main/resources/application.yml
# No output = GOOD

# Check if test config has test-resources enabled
$ grep -n "test-resources:" src/main/resources/application-test.yml
2:test-resources:

# Check for default values (anti-pattern)
$ grep -n ":\${.*:.*}" src/main/resources/application.yml
5:    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/db}
# Output found = BAD - has default values

# Check production config uses environment variables
$ grep -n "\${[^:}]*}" src/main/resources/application-prod.yml
3:    url: ${DATABASE_URL}
4:    username: ${DATABASE_USERNAME}
5:    password: ${DATABASE_PASSWORD}
# Output with no defaults = GOOD
```

### Validation Results from Grep
```markdown
## Grep-Based Validation Results

**Base Config Check**:
```
$ grep "^\s*url:" src/main/resources/application.yml
# (no output)
```
✅ PASS - No URL in base config

**Default Values Check**:
```
$ grep ":\${.*:.*}" src/main/resources/application.yml
5:    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/db}
```
❌ FAIL - Default value found on line 5

**Fix Required**: Remove default value from line 5 in application.yml
```

---

## Example 8: Integration Test Failure Diagnosis

### Symptom
```bash
$ ./gradlew test

> Task :test FAILED
EmailProcessingServiceSpec > should save email FAILED
    java.sql.SQLException: No suitable driver found for jdbc:postgresql://localhost:5432/ecfx
```

### Validation Investigation

**Step 1**: Check if test-resources present
```bash
$ grep -A 5 "test-resources:" src/main/resources/application-test.yml
# No output - PROBLEM FOUND
```

**Step 2**: Check base config
```bash
$ grep -A 3 "datasources:" src/main/resources/application.yml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/ecfx}
```

### Validation Report
```markdown
## TestResources Configuration Validation
### (Triggered by test failure diagnosis)

### Issue #1: Base Config Has Default Value
**File**: application.yml
**Line**: 4
**Problem**: `url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/ecfx}`
**Impact**: TestResources sees configured URL, doesn't provision container
**Fix**: Remove URL line from application.yml

### Issue #2: Missing Test Config
**File**: application-test.yml
**Problem**: No test-resources section found
**Impact**: TestResources not enabled
**Fix**: Add test-resources configuration

### Root Cause Analysis
Your test is failing because:
1. Base config has default URL → TestResources doesn't provision container
2. No test-resources configuration → TestResources not enabled
3. Test tries to connect to localhost:5432 → No database running
4. Result: SQLException

### Corrective Actions

**1. Fix application.yml**:
```yaml
datasources:
  default:
    driver-class-name: org.postgresql.Driver
    # Remove url line
```

**2. Create/update application-test.yml**:
```yaml
test-resources:
  enabled: true
  containers:
    postgres:
      db-name: ecfx
      db-username: ecfx
      db-password: ecfx
```

**3. Create application-prod.yml**:
```yaml
datasources:
  default:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
```

**4. Re-run tests**:
```bash
./gradlew clean test
```

**Expected Result**: TestResources provisions container, tests pass
```
