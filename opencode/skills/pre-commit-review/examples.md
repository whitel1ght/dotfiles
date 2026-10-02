# Pre-Commit Review Examples

This document provides examples of review findings for different scenarios.

## Example 1: Clean Commit (No Issues)

**Scenario:** Simple documentation update

**Staged Changes:**
```diff
diff --git a/README.md b/README.md
index 1234567..abcdefg 100644
--- a/README.md
+++ b/README.md
@@ -10,7 +10,7 @@ A simple user authentication system.

 ## Installation

-npm install
+npm install --legacy-peer-deps
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (0)
None found.

### 🔵 Info (0)
None found.

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [x] No TODO/FIXME comments for incomplete work
- [x] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [x] Documentation changes accurate

---

✅ READY TO COMMIT

No issues found. Changes appear ready to commit.
```

---

## Example 2: Debug Statements Left In Code

**Scenario:** Feature implementation with forgotten debug code

**Staged Changes:**
```diff
diff --git a/src/services/payment.ts b/src/services/payment.ts
index 1234567..abcdefg 100644
--- a/src/services/payment.ts
+++ b/src/services/payment.ts
@@ -15,6 +15,8 @@ export async function processPayment(amount: number, userId: string) {
+  console.log('Processing payment:', amount, userId);
+  debugger;
   const result = await stripe.charges.create({
     amount: amount * 100,
+    // TODO: Add error handling here
     currency: 'usd',
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (3)

**src/services/payment.ts:17**
- Debug statement: `console.log('Processing payment:', amount, userId)`
- Exposes sensitive payment information in logs
- Should be removed or replaced with proper logging

**src/services/payment.ts:18**
- Debugger statement: `debugger;`
- Will pause execution in production
- Must be removed before commit

**src/services/payment.ts:21**
- TODO comment: `// TODO: Add error handling here`
- Indicates incomplete implementation
- Error handling should be added before committing payment code

### 🔵 Info (0)
None found.

---

## Self-Review Checklist

- [ ] No debug statements or temporary logging
- [ ] No TODO/FIXME comments for incomplete work
- [x] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [ ] New payment functionality has tests
- [ ] Error handling implemented

---

⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.

**Recommendation:** Complete the TODO for error handling before committing payment processing code, and remove debug statements.
```

---

## Example 3: Critical Security Issues

**Scenario:** Hardcoded credentials in configuration

**Staged Changes:**
```diff
diff --git a/src/config/database.ts b/src/config/database.ts
index 1234567..abcdefg 100644
--- a/src/config/database.ts
+++ b/src/config/database.ts
@@ -1,6 +1,10 @@
 export const dbConfig = {
-  host: process.env.DB_HOST,
-  password: process.env.DB_PASSWORD,
+  host: 'prod-db.internal.company.com',
+  username: 'admin',
+  password: 'SuperSecret123!',
+  apiKey: 'sk_live_abc123xyz789',
 };

diff --git a/.env b/.env
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/.env
@@ -0,0 +1,3 @@
+DB_PASSWORD=MyPassword123
+AWS_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
+STRIPE_SECRET_KEY=sk_test_abc123
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (5)

**src/config/database.ts:3**
- Hardcoded database host: `prod-db.internal.company.com`
- Exposes internal infrastructure details
- Use environment variable instead: `process.env.DB_HOST`

**src/config/database.ts:5**
- Hardcoded password: `SuperSecret123!`
- CRITICAL SECURITY RISK: Password exposed in version control
- Use environment variable: `process.env.DB_PASSWORD`

**src/config/database.ts:6**
- Hardcoded API key: `sk_live_abc123xyz789`
- CRITICAL SECURITY RISK: Live API key in source code
- Use environment variable: `process.env.API_KEY`

**.env:1-3**
- `.env` file staged for commit
- CRITICAL SECURITY RISK: Secrets file should never be committed
- Add `.env` to `.gitignore` and unstage this file
- Use `.env.example` with placeholder values instead

**Multiple security issues detected**
- This commit would expose production credentials in git history
- Even if removed later, secrets remain in git history
- All exposed credentials must be rotated immediately if committed

### 🟡 Warnings (0)
None found.

### 🔵 Info (0)
None found.

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [x] No TODO/FIXME comments for incomplete work
- [x] No commented-out code blocks
- [ ] No hardcoded secrets or sensitive data ⚠️ FAILED
- [ ] No files that shouldn't be committed ⚠️ FAILED
- [x] Code follows project formatting standards

---

❌ NOT READY TO COMMIT

Critical security issues must be resolved before committing:

1. Unstage .env file: `git reset HEAD .env`
2. Add .env to .gitignore if not already present
3. Replace all hardcoded values in database.ts with environment variables
4. Create .env.example with placeholder values for documentation
5. If this was accidentally committed and pushed, rotate ALL credentials immediately

**DO NOT COMMIT** until all credentials are removed and environment variables are used.
```

---

## Example 4: Missing Tests for New Feature

**Scenario:** New API endpoint without tests

**Staged Changes:**
```diff
diff --git a/src/api/routes/users.ts b/src/api/routes/users.ts
index 1234567..abcdefg 100644
--- a/src/api/routes/users.ts
+++ b/src/api/routes/users.ts
@@ -10,6 +10,20 @@ router.get('/users/:id', async (req, res) => {
   res.json(user);
 });

+// New endpoint for user preferences
+router.post('/users/:id/preferences', async (req, res) => {
+  const { id } = req.params;
+  const preferences = req.body;
+
+  const updated = await updateUserPreferences(id, preferences);
+  res.json(updated);
+});
+
diff --git a/src/services/userService.ts b/src/services/userService.ts
index 1234567..abcdefg 100644
--- a/src/services/userService.ts
+++ b/src/services/userService.ts
@@ -15,3 +15,10 @@ export async function getUser(id: string) {
   return db.users.findOne({ id });
 }
+
+export async function updateUserPreferences(id: string, preferences: any) {
+  return db.users.updateOne(
+    { id },
+    { $set: { preferences } }
+  );
+}
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (2)

**src/api/routes/users.ts:13-23**
- New API endpoint without tests: `POST /users/:id/preferences`
- No integration tests found for this endpoint
- API endpoints should have test coverage before committing

**src/services/userService.ts:18-24**
- New function without tests: `updateUserPreferences()`
- No unit tests found for this function
- Should add tests covering success case and error handling

### 🔵 Info (2)

**src/services/userService.ts:18**
- Parameter type is `any`: `preferences: any`
- Consider defining a proper interface for preferences

**src/api/routes/users.ts:15**
- No input validation on preferences
- Consider validating request body structure

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [x] No TODO/FIXME comments for incomplete work
- [x] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [ ] New API endpoint has integration tests
- [ ] New service function has unit tests
- [ ] Input validation implemented

---

⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.

**Recommendation:** Add tests for the new endpoint and service function. At minimum:
- Integration test for POST /users/:id/preferences (success and error cases)
- Unit test for updateUserPreferences() function
- Input validation for the preferences object
```

---

## Example 5: Large Commented-Out Code Block

**Scenario:** Refactoring with old code left commented

**Staged Changes:**
```diff
diff --git a/src/utils/validation.ts b/src/utils/validation.ts
index 1234567..abcdefg 100644
--- a/src/utils/validation.ts
+++ b/src/utils/validation.ts
@@ -5,20 +5,30 @@ export function validateEmail(email: string): boolean {
   return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
 }

-// Old implementation - kept for reference
-// export function validatePassword(password: string): boolean {
-//   return password.length >= 8;
-// }
-//
-// export function validateUsername(username: string): boolean {
-//   if (username.length < 3) return false;
-//   if (username.length > 20) return false;
-//   if (!/^[a-zA-Z0-9_]+$/.test(username)) return false;
-//   return true;
-// }
+// New implementation with better validation
+export function validatePassword(password: string): boolean {
+  if (password.length < 8) return false;
+  if (!/[A-Z]/.test(password)) return false;
+  if (!/[a-z]/.test(password)) return false;
+  if (!/[0-9]/.test(password)) return false;
+  return true;
+}
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (1)

**src/utils/validation.ts:8-18**
- Large commented-out code block (11 lines)
- Old implementation marked "kept for reference"
- Should be removed - git history preserves old versions
- If truly needed for reference, document in commit message

### 🔵 Info (1)

**src/utils/validation.ts:20-25**
- New password validation function without tests
- Consider adding tests for all validation rules

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [x] No TODO/FIXME comments for incomplete work
- [ ] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [ ] New validation function has tests

---

⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.

**Recommendation:** Remove the commented-out code block. Git history will preserve the old implementation if you need to reference it later.
```

---

## Example 6: Mixed Issues - Realistic Scenario

**Scenario:** Feature work with several common mistakes

**Staged Changes:**
```diff
diff --git a/src/components/UserDashboard.tsx b/src/components/UserDashboard.tsx
index 1234567..abcdefg 100644
--- a/src/components/UserDashboard.tsx
+++ b/src/components/UserDashboard.tsx
@@ -15,6 +15,7 @@ export function UserDashboard({ userId }: Props) {
   useEffect(() => {
     async function loadData() {
       const data = await fetchUserData(userId);
+      console.log('Loaded user data:', data);
       setUserData(data);
     }
     loadData();
@@ -25,6 +26,8 @@ export function UserDashboard({ userId }: Props) {
       <h1>Welcome, {userData.name}</h1>
       <Stats data={userData.stats} />
       <ActivityFeed items={userData.activities} />
+      {/* TODO: Add premium badge if user is premium */}
+      {/* <PremiumBadge show={userData.isPremium} /> */}
     </div>
   );
 }

diff --git a/src/services/analytics.ts b/src/services/analytics.ts
index 1234567..abcdefg 100644
--- a/src/services/analytics.ts
+++ b/src/services/analytics.ts
@@ -1,8 +1,12 @@
 export function trackEvent(event: string, properties?: any) {
-  // TODO: Implement analytics tracking
+  fetch('https://analytics.company.com/track', {
+    method: 'POST',
+    headers: {
+      'Content-Type': 'application/json',
+      'X-API-Key': 'analytics_key_12345'
+    },
+    body: JSON.stringify({ event, properties })
+  });
 }

diff --git a/src/utils/formatting.ts b/src/utils/formatting.ts
index 1234567..abcdefg 100644
--- a/src/utils/formatting.ts
+++ b/src/utils/formatting.ts
@@ -10,3 +10,9 @@ export function formatCurrency(amount: number): string {
   return new Intl.NumberFormat('en-US', options).format(amount);
 }
+
+export function formatDate(date: Date): string {
+	return date.toLocaleDateString();
+}
+
+// End of file
\ No newline at end of file
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (1)

**src/services/analytics.ts:6**
- Hardcoded API key: `analytics_key_12345`
- CRITICAL SECURITY RISK: API key exposed in source code
- Use environment variable: `process.env.ANALYTICS_API_KEY`

### 🟡 Warnings (4)

**src/components/UserDashboard.tsx:18**
- Debug statement: `console.log('Loaded user data:', data)`
- Should be removed or replaced with proper logging

**src/components/UserDashboard.tsx:29**
- TODO comment: `// TODO: Add premium badge if user is premium`
- Commented-out code on line 30
- Either implement the feature or remove the TODO and code

**src/utils/formatting.ts:14**
- Inconsistent indentation: Uses tabs instead of spaces
- File uses spaces elsewhere, line 15 uses tab
- Should use consistent spacing (appears project uses 2 spaces)

**src/utils/formatting.ts:17**
- Missing newline at end of file
- Should add newline for POSIX compliance

### 🔵 Info (2)

**src/services/analytics.ts:2-9**
- New analytics tracking function without error handling
- Consider adding try/catch and error handling

**src/components/UserDashboard.tsx**
- Component changes without tests
- Consider adding component tests

---

## Self-Review Checklist

- [ ] No debug statements or temporary logging
- [ ] No TODO/FIXME comments for incomplete work
- [ ] No commented-out code blocks
- [ ] No hardcoded secrets or sensitive data ⚠️ FAILED
- [x] No files that shouldn't be committed
- [ ] Code follows project formatting standards
- [ ] New functionality has tests

---

❌ NOT READY TO COMMIT

Critical security issue must be resolved before committing:

1. Replace hardcoded API key in analytics.ts with environment variable
2. Add ANALYTICS_API_KEY to .env.example (not .env)
3. Update analytics.ts to use process.env.ANALYTICS_API_KEY

**Additional issues to address:**
- Remove console.log debug statement
- Complete or remove the premium badge TODO
- Fix inconsistent indentation in formatting.ts
- Add newline at end of formatting.ts
```

---

## Example 7: Configuration File Changes

**Scenario:** Database migration and config updates

**Staged Changes:**
```diff
diff --git a/config/database.yml b/config/database.yml
index 1234567..abcdefg 100644
--- a/config/database.yml
+++ b/config/database.yml
@@ -1,6 +1,7 @@
 production:
   adapter: postgresql
-  pool: 5
+  pool: 20
+  timeout: 5000

diff --git a/db/migrations/20240115_add_user_preferences.sql b/db/migrations/20240115_add_user_preferences.sql
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/db/migrations/20240115_add_user_preferences.sql
@@ -0,0 +1,10 @@
+-- Add user preferences table
+CREATE TABLE user_preferences (
+  id SERIAL PRIMARY KEY,
+  user_id INTEGER NOT NULL REFERENCES users(id),
+  preferences JSONB NOT NULL DEFAULT '{}',
+  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
+  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
+);
+
+CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);
```

**Review Output:**
```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (0)
None found.

### 🔵 Info (2)

**config/database.yml:3**
- Database pool size changed from 5 to 20 (4x increase)
- Ensure this change is intentional and infrastructure can handle increased connections

**db/migrations/20240115_add_user_preferences.sql**
- New database migration added
- Verify migration is tested and includes rollback strategy
- Ensure migration file name follows project convention

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [x] No TODO/FIXME comments for incomplete work
- [x] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [x] Migration tested locally
- [x] Migration has rollback plan
- [x] Configuration changes intentional and documented

---

✅ READY TO COMMIT

No issues found. Changes appear ready to commit.

**Note:** Configuration and migration files detected. Ensure:
- Database pool increase is coordinated with infrastructure team
- Migration has been tested and rollback procedure documented
```

---

## Key Patterns in Examples

### Severity Levels Used Consistently

- **🔴 Critical**: Security issues, hardcoded secrets, files that shouldn't be committed
- **🟡 Warning**: Debug code, incomplete work (TODOs), formatting issues, missing tests
- **🔵 Info**: Suggestions, minor improvements, things to consider

### Recommendations Are Actionable

Good findings include:
- Specific file path and line number
- Clear description of the issue
- Why it's a problem
- Concrete steps to fix

### Checklists Adapt to Changes

The self-review checklist includes:
- Standard items always present
- Context-specific items based on changes (tests, migrations, config, etc.)
- Clear indication of failed checks

### Final Recommendation Matches Severity

- Critical issues → NOT READY TO COMMIT
- Warnings only → READY WITH CAUTIONS
- Clean → READY TO COMMIT
