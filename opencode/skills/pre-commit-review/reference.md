# Pre-Commit Review Reference

This document details all checks performed during pre-commit review and the rationale behind them.

## Check Categories

### 1. Debug Code Detection

**What to Look For:**

| Language | Patterns | Context |
|----------|----------|---------|
| JavaScript/TypeScript | `console.log()`, `console.debug()`, `console.error()`, `console.warn()`, `debugger` | Look for temporary debugging, not production logging |
| Python | `print()`, `pprint()`, `pdb.set_trace()`, `breakpoint()` | Distinguish from intentional CLI output |
| Java | `System.out.println()`, `printStackTrace()`, `.debug()` | Debug output vs. proper logging |
| Ruby | `puts`, `p`, `pp`, `binding.pry` | Interactive debugging statements |
| Go | `fmt.Println()`, `log.Println()` in non-logging contexts | Temporary debug prints |
| C#/C++ | `Console.WriteLine()`, `printf()`, `std::cout` | Debug output in production code |
| PHP | `var_dump()`, `print_r()`, `dd()` | Debugging functions |

**Why This Matters:**
- Debug statements clutter production logs
- May expose sensitive information
- Impact performance
- Indicate incomplete work

**Severity:**
- 🟡 Warning: In most cases
- 🔴 Critical: If logging sensitive data (passwords, tokens, PII)

**Context Matters:**
```javascript
// 🔴 Critical - logging sensitive data
console.log('User password:', password);

// 🟡 Warning - temporary debug
console.log('Testing feature X');

// ✅ OK - proper logging
logger.info('User logged in', { userId: user.id });
```

---

### 2. Incomplete Work Markers

**What to Look For:**

**Standard Markers:**
- `TODO:` - Work that needs to be done
- `FIXME:` - Known bugs or issues
- `HACK:` - Quick fixes that need proper solution
- `XXX:` - Warning or attention needed
- `NOTE:` - Important information
- `OPTIMIZE:` - Performance improvements needed

**Why This Matters:**
- Indicates incomplete implementation
- May represent known bugs
- Suggests code not ready for production
- Can accumulate as technical debt

**Severity Decision Tree:**
```
Is the TODO/FIXME in new code being added?
├─ Yes: Does it indicate incomplete critical functionality?
│  ├─ Yes: 🟡 Warning (should complete before commit)
│  └─ No: 🔵 Info (future improvement)
└─ No: Just noting existing TODOs
   └─ 🔵 Info (awareness)
```

**Examples:**

```javascript
// 🟡 Warning - incomplete critical feature
export function processPayment(amount: number) {
  // TODO: Add error handling
  return stripe.charge(amount);
}

// 🔵 Info - future enhancement
export function formatDate(date: Date) {
  // TODO: Add timezone support in future
  return date.toLocaleDateString();
}

// 🟡 Warning - known bug
function calculateDiscount(price: number) {
  // FIXME: Rounding error for amounts > 1000
  return price * 0.1;
}
```

---

### 3. Dead Code

**What to Look For:**

**Commented-Out Code:**
- Large blocks (>5 lines) of commented code
- Old implementation left "for reference"
- Disabled features

**Unused Artifacts:**
- Unused imports
- Unused variables (if detectable)
- Unreachable code

**Why This Matters:**
- Clutters codebase
- Creates confusion about intent
- Git history preserves old versions
- Maintenance burden

**Severity:**
- 🟡 Warning: Large commented blocks (>5 lines)
- 🔵 Info: Small commented blocks (≤5 lines)
- 🔵 Info: Unused imports (linters usually catch these)

**When It's OK:**
```javascript
// ✅ OK - explanatory comment about approach
// We're using approach A instead of approach B because...

// 🟡 Warning - old code kept "for reference"
// Old implementation:
// function oldWay() {
//   ...15 lines of commented code...
// }
```

---

### 4. Sensitive Data Detection

**What to Look For:**

**API Keys and Tokens:**
```javascript
// 🔴 Critical patterns
api_key = "sk_live_1234567890"
apiKey: "AIzaSyC1234567890"
token = "ghp_1234567890abcdefg"
bearer_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCY"
```

**Passwords and Credentials:**
```javascript
// 🔴 Critical patterns
password: "myPassword123"
db_password = "SuperSecret!"
admin_password: "P@ssw0rd"
```

**Private Keys:**
```
// 🔴 Critical - private key material
-----BEGIN PRIVATE KEY-----
-----BEGIN RSA PRIVATE KEY-----
```

**Connection Strings:**
```javascript
// 🔴 Critical - credentials in connection string
const url = "postgres://user:password@host:5432/db"
const mongo = "mongodb://admin:secret@localhost"
```

**Internal Information:**
```javascript
// 🔴 Critical - internal infrastructure
const host = "db-prod-internal-01.company.local"
const email = "admin@company-internal.com"
```

**Detection Patterns:**

| Type | Regex/Pattern | Example |
|------|---------------|---------|
| AWS Access Key | `AKIA[0-9A-Z]{16}` | `AKIAIOSFODNN7EXAMPLE` |
| GitHub Token | `ghp_[a-zA-Z0-9]{36}` | `ghp_abc123...` |
| Stripe Key | `sk_live_[a-zA-Z0-9]{24}` | `sk_live_abc123...` |
| Generic API Key | `['\"]api[_-]?key['\"]\s*[:=]\s*['\"][^'\"]{10,}['\"]` | `"api_key": "abc123..."` |
| JWT | `eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+` | `eyJhbGci...` |
| Private Key | `-----BEGIN.*PRIVATE KEY-----` | PEM format keys |
| Password | `['\"]password['\"]\s*[:=]\s*['\"][^'\"]+['\"]` | `password: "secret"` |

**Why This Matters:**
- CRITICAL SECURITY RISK
- Exposed in version control forever (even if removed later)
- Can lead to data breaches
- Compliance violations

**Severity:**
- 🔴 Critical: ALWAYS

**Mitigation:**
```javascript
// ❌ Critical
const apiKey = "sk_live_abc123";

// ✅ Correct
const apiKey = process.env.STRIPE_API_KEY;
```

---

### 5. Dangerous Files

**What to Look For:**

**Environment Files:**
- `.env`
- `.env.local`
- `.env.production`
- Any file with actual secrets

**Credentials and Keys:**
- `credentials.json`
- `secrets.yaml`
- `*.pem`
- `*.key`
- `*.p12`
- `*.pfx`
- Service account keys

**IDE and System Files:**
- `.DS_Store` (macOS)
- `Thumbs.db` (Windows)
- `.idea/` (IntelliJ IDEA)
- `.vscode/settings.json` with personal settings

**Build Artifacts:**
- `node_modules/`
- `dist/`
- `build/`
- `*.log`
- `.pyc` files

**Why This Matters:**
- Security: Secrets exposure
- Repository bloat: Large files
- Developer friction: Personal IDE settings
- Confusion: Build artifacts in source

**Severity:**
- 🔴 Critical: Files with secrets
- 🟡 Warning: IDE files, build artifacts

**Proper Approach:**
```bash
# ❌ Critical
git add .env

# ✅ Correct
git add .env.example  # Template with placeholders
# Ensure .env in .gitignore
```

**.env vs .env.example:**
```bash
# .env (NEVER commit)
DATABASE_URL=postgres://user:password@localhost/db
API_KEY=sk_live_abc123

# .env.example (OK to commit)
DATABASE_URL=postgres://user:password@localhost/dbname
API_KEY=your_api_key_here
```

---

### 6. Missing Test Coverage

**What to Look For:**

**New Functions Without Tests:**
```javascript
// 🟡 Warning - new function, no tests
export function calculateTax(amount: number): number {
  return amount * 0.08;
}
```

**New API Endpoints:**
```javascript
// 🟡 Warning - new endpoint without integration test
router.post('/api/users', createUser);
```

**Bug Fixes Without Regression Tests:**
```javascript
// 🟡 Warning - bug fix without test to prevent regression
export function parseDate(dateStr: string): Date {
  // Fixed: Was returning invalid date for some formats
  return new Date(dateStr);
}
```

**New Components Without Tests:**
```typescript
// 🟡 Warning - new React component without tests
export function UserProfile({ userId }: Props) {
  // Component implementation
}
```

**Detection Strategy:**

1. **Check for new files:** Look for new `.ts`, `.js`, `.tsx`, `.jsx`, `.py`, `.java` files
2. **Check for test files:** Look for corresponding `*.test.*`, `*.spec.*`, or tests in test directory
3. **Analyze diffs:** New functions, classes, or endpoints in existing files
4. **Context matters:** Not all code needs tests (types, interfaces, simple formatters)

**When Tests Are Critical:**

| Code Type | Test Requirement | Severity if Missing |
|-----------|------------------|---------------------|
| API endpoints | Integration tests | 🟡 Warning |
| Business logic | Unit tests | 🟡 Warning |
| Bug fixes | Regression tests | 🟡 Warning |
| Utility functions | Unit tests | 🔵 Info |
| React components | Component tests | 🔵 Info |
| Simple formatters | Optional | ⚪ Not flagged |
| Type definitions | Not needed | ⚪ Not flagged |

**Why This Matters:**
- Prevents regressions
- Documents expected behavior
- Enables safe refactoring
- Increases confidence in changes

**Severity:**
- 🟡 Warning: Critical business logic, APIs, bug fixes
- 🔵 Info: Utility functions, components

---

### 7. Formatting Issues

**What to Look For:**

**Indentation Problems:**
```javascript
// 🟡 Warning - mixed tabs and spaces
function example() {
  const x = 1;  // 2 spaces
	const y = 2;  // tab
}
```

**Line Endings:**
- Mixed CRLF and LF
- Usually project uses one consistently

**Trailing Whitespace:**
```javascript
// 🔵 Info - trailing spaces (visible with · )
const name = "John";···
```

**Missing Final Newline:**
```javascript
// 🔵 Info - file should end with newline
export function last() {
  return 42;
}[EOF - no newline]
```

**Inconsistent Style:**
```javascript
// 🟡 Warning - inconsistent with project style
// Project uses single quotes
const greeting = "Hello";  // Should be 'Hello'
```

**Why This Matters:**
- Team consistency
- Tool compatibility
- Diff cleanliness
- POSIX compliance

**Severity:**
- 🟡 Warning: Mixed tabs/spaces, serious inconsistencies
- 🔵 Info: Trailing whitespace, missing final newline

**Detection:**
1. Check for tabs: `\t`
2. Check final character: Should be `\n`
3. Look for trailing whitespace: `\s+$`
4. Detect line endings: `\r\n` vs `\n`

**Tool Recommendations:**
```bash
# Usually handled by:
# - ESLint/Prettier (JavaScript/TypeScript)
# - Black/Flake8 (Python)
# - gofmt (Go)
# - RuboCop (Ruby)
# - EditorConfig (cross-language)
```

---

## Severity Level Guidelines

### 🔴 Critical Issues (Blocks Commit)

**Criteria:**
- Security vulnerabilities
- Data exposure risks
- Will break production
- Violates compliance

**Examples:**
- Hardcoded secrets/API keys
- Credentials in connection strings
- `.env` files with real secrets
- Private key material
- Syntax errors (if detectable)

**Action Required:**
- MUST be fixed before commit
- May require credential rotation if committed
- Cannot be overlooked

---

### 🟡 Warning Issues (Should Fix)

**Criteria:**
- Code quality problems
- Incomplete work
- Missing important elements
- Likely to cause issues

**Examples:**
- Debug statements left in code
- TODO/FIXME indicating incomplete features
- Large commented-out code blocks
- Missing tests for new functionality
- Serious formatting inconsistencies

**Action Required:**
- SHOULD be fixed before commit
- Can be committed with justification
- Reviewer may request changes

---

### 🔵 Info Issues (Consider)

**Criteria:**
- Minor improvements
- Suggestions
- Non-critical observations
- Future enhancements

**Examples:**
- Minor style inconsistencies
- Missing tests for simple utilities
- Trailing whitespace
- Opportunities for refactoring
- Non-critical TODOs

**Action Required:**
- OPTIONAL to fix
- Good to be aware of
- Can address in future commits

---

## Context-Aware Decisions

### When to Flag vs. Not Flag

**Configuration Files:**
```yaml
# Flag hardcoded values in config
database:
  host: prod-db-01.internal  # 🔴 Critical - internal host
  password: secret123        # 🔴 Critical - password

# OK - environment variable references
database:
  host: ${DB_HOST}
  password: ${DB_PASSWORD}
```

**Logging vs. Debugging:**
```javascript
// 🟡 Warning - debug statement
console.log('Testing this feature');

// ✅ OK - proper logging
logger.info('User login successful', { userId });

// ✅ OK - CLI tool output
console.log('Build completed successfully!');
```

**Intentional TODOs:**
```javascript
// 🟡 Warning - incomplete critical feature
export function processPayment() {
  // TODO: Implement payment processing
  throw new Error('Not implemented');
}

// 🔵 Info - future enhancement
export function formatCurrency(amount: number) {
  // TODO: Add internationalization support
  return `$${amount.toFixed(2)}`;
}
```

**Test Coverage:**
```typescript
// 🟡 Warning - API endpoint needs tests
router.post('/api/checkout', handleCheckout);

// 🔵 Info - simple formatter, tests optional
export const capitalize = (s: string) =>
  s.charAt(0).toUpperCase() + s.slice(1);

// ⚪ Not flagged - type definition
export interface User {
  id: string;
  name: string;
}
```

---

## Language-Specific Patterns

### JavaScript/TypeScript

**Common Debug Patterns:**
```typescript
console.log()
console.debug()
console.error() // in non-error-handling context
debugger
alert()
```

**Secrets Detection:**
```typescript
const apiKey = "sk_live_..."
process.env.API_KEY = "hardcoded"  // 🔴 Critical
```

### Python

**Common Debug Patterns:**
```python
print()  # vs. logger.info()
pprint()
pdb.set_trace()
breakpoint()
import pdb; pdb.set_trace()
```

**Secrets Detection:**
```python
api_key = "sk_live_..."
password = "secret"
DATABASE_URL = "postgres://user:pass@host/db"
```

### Java

**Common Debug Patterns:**
```java
System.out.println()
printStackTrace()
e.printStackTrace() // vs. logger.error()
```

**Secrets Detection:**
```java
String apiKey = "sk_live_...";
String password = "secret";
```

### Go

**Common Debug Patterns:**
```go
fmt.Println()  // vs. log.Printf()
log.Println() // in non-logging context
```

**Secrets Detection:**
```go
apiKey := "sk_live_..."
password := "secret"
```

### Ruby

**Common Debug Patterns:**
```ruby
puts
p
pp
binding.pry
debugger
```

**Secrets Detection:**
```ruby
api_key = "sk_live_..."
password = "secret"
```

---

## Output Format Standards

### Findings Format

Each finding should include:

```markdown
**path/to/file.ext:line_number** (or line range)
- Issue description
- Why it's a concern
- Suggested fix (if applicable)
```

**Example:**
```markdown
**src/api/auth.ts:45**
- Hardcoded API key: `sk_live_abc123`
- CRITICAL SECURITY RISK: API key exposed in source code
- Use environment variable: `process.env.API_KEY`
```

### Recommendation Format

**Critical Issues Found:**
```
❌ NOT READY TO COMMIT

Critical issues must be resolved before committing. See findings above.
```

**Warnings Only:**
```
⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.
```

**Clean:**
```
✅ READY TO COMMIT

No issues found. Changes appear ready to commit.
```

---

## Tool Integration

This skill complements but does not replace:

**Linters:**
- ESLint, TSLint (JavaScript/TypeScript)
- Pylint, Flake8 (Python)
- RuboCop (Ruby)
- Checkstyle (Java)

**Formatters:**
- Prettier (JavaScript/TypeScript)
- Black (Python)
- gofmt (Go)
- rustfmt (Rust)

**Security Scanners:**
- git-secrets
- truffleHog
- detect-secrets

**Pre-commit Hooks:**
- Husky (JavaScript)
- pre-commit framework (Python)
- Lefthook

The skill provides manual review that:
- Catches context-specific issues tools miss
- Explains why issues matter
- Tailors checklist to changes
- Provides human judgment

---

## Edge Cases

### Binary Files
- Note: "Binary file detected, cannot review content"
- Check: Should this binary be committed?

### Generated Code
- Note: "Generated code detected"
- Check: Is generator config tracked?

### Large Changesets
- Note: "Large changeset (>500 lines)"
- Focus: Critical and warning issues first

### No Staged Changes
```
No files staged for commit.

Use `git add <file>` to stage changes for review.
```

### All Files Excluded
```
All staged files are binary or generated.

Manual review recommended for:
- Binary files should be committed
- Generated files have correct configuration
```

---

## Customization Points

Organizations may want to adjust:

1. **Severity thresholds**: What's critical vs. warning
2. **Language patterns**: Add project-specific debug patterns
3. **Secret patterns**: Add company-specific key formats
4. **File exclusions**: Ignore certain file types
5. **Test requirements**: When tests are required vs. optional

The skill should adapt to project context:
- Check for `.gitignore` patterns
- Learn project's logging patterns
- Follow existing test conventions
- Match code style guidelines
