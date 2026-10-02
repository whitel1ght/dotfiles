---
name: checkstyle-enforcer
description: >-
  Automatically validate and fix Java code style violations using checkstyle. Use after writing or modifying Java files, before git commits, when user requests checkstyle validation, or when builds fail due to checkstyle violations.
---


# Checkstyle Enforcer Skill

## Purpose

Automatically run checkstyle validation on Java code and fix violations according to Google Java Style Guide with project customizations. Ensures code quality and prevents build failures.

## When to Invoke

- After writing or modifying any Java file in `src/main/java/`
- Before creating git commits (pre-commit workflow)
- When user explicitly requests "run checkstyle" or "check code style"
- When `./gradlew build` fails with checkstyle violations
- When user asks to "fix style issues" or similar

## Step-by-Step Process

### 1. Detect Trigger Condition

Check if checkstyle validation is needed:
- Java files were just created or modified
- User explicitly requested validation
- Build failure mentions checkstyle

### 2. Run Checkstyle Validation

Execute checkstyle on main sources:

```bash
cd /Users/traviscarter/ecfx/receipt_processing_web
./gradlew checkstyleMain
```

**Expected Behavior**:
- Exit code 0: No violations (success)
- Exit code 1: Violations found (proceed to parsing)

### 3. Parse Violation Reports

If violations exist, read and parse the XML report:

```bash
# Report location
/Users/traviscarter/ecfx/receipt_processing_web/build/reports/checkstyle/main.xml
```

Extract for each violation:
- File path (relative to project root)
- Line number
- Column number (if available)
- Severity (warning/error)
- Violation type (check name)
- Violation message

### 4. Categorize Violations

Group violations by fix complexity:

**Auto-Fixable** (attempt automatic fix):
- LineLength
- CustomImportOrder
- WhitespaceAfter
- WhitespaceAround
- JavadocParagraph
- EmptyLineSeparator
- OperatorWrap
- SeparatorWrap
- NoWhitespaceBefore
- Indentation (simple cases)

**Semi-Auto-Fixable** (attempt with caution):
- MissingJavadocMethod (generate template)
- MissingJavadocType (generate template)

**Manual** (report to user):
- AbbreviationAsWordInName (requires renaming)
- Complex logic issues
- Structural changes

### 5. Apply Automatic Fixes

For each auto-fixable violation, apply the appropriate fix:

#### LineLength Violations

Break lines intelligently at 150 characters:

**Method Signatures**:
```java
// Before (160 chars)
public ResponseEntity<DataObject> processInboundWebhookWithMultipleParameters(String param1, String param2, Long param3)

// After
public ResponseEntity<DataObject> processInboundWebhookWithMultipleParameters(
        String param1, String param2, Long param3)
```

**Method Calls**:
```java
// Before
service.processEmail(request.getFrom(), request.getSubject(), request.getBody(), request.getAttachments());

// After
service.processEmail(
        request.getFrom(), request.getSubject(),
        request.getBody(), request.getAttachments());
```

**String Concatenation**:
```java
// Before
String message = "Very long message that exceeds the line length limit and needs to be broken into multiple lines for readability";

// After
String message = "Very long message that exceeds the line length limit "
        + "and needs to be broken into multiple lines for readability";
```

**Strategy**: Break after commas, before operators, at logical boundaries. Use 8-space continuation indent.

#### CustomImportOrder Violations

Sort imports into three groups with blank lines between:

```java
// Group 1: Static imports (alphabetical)
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

// Group 2: Third-party packages (alphabetical)
import io.micronaut.http.HttpResponse;
import io.micronaut.security.annotation.Secured;
import jakarta.inject.Singleton;

// Group 3: Standard Java packages (alphabetical)
import java.util.List;
import java.util.Optional;
```

**Implementation**:
1. Extract all imports from file
2. Categorize: static, third-party (non-java/javax/jakarta), standard (java/javax/jakarta)
3. Sort each group alphabetically
4. Join with blank lines between groups
5. Replace import block

#### WhitespaceAfter Violations

Add space after: comma, semicolon, typecast, control flow keywords

```java
// Before
String result=method(param1,param2,param3);
if(condition){

// After
String result = method(param1, param2, param3);
if (condition) {
```

#### WhitespaceAround Violations

Add space around operators and keywords:

```java
// Before
int result=a+b*c;
for(int i=0;i<10;i++)

// After
int result = a + b * c;
for (int i = 0; i < 10; i++)
```

#### JavadocParagraph Violations

Fix `<p>` tag formatting:

```java
// Before
/**
 * First paragraph.
 * <p> Second paragraph.  // ← Error: space after <p>
 */

// After
/**
 * First paragraph.
 *
 * <p>Second paragraph.
 */
```

**Rules**:
- Empty line (just `*`) before `<p>` tag
- No space after `<p>` tag
- `<p>` starts new paragraph description

#### MissingJavadocMethod Violations

Generate method-level Javadoc for public methods (2+ lines):

```java
// Before
public EmailInboxItem processInboundEmail(PostmarkInboundRequest request) {

// After
/**
 * Processes an inbound email from Postmark webhook.
 *
 * @param request the Postmark inbound webhook request
 * @return the created email inbox item
 */
public EmailInboxItem processInboundEmail(PostmarkInboundRequest request) {
```

**Template Strategy**:
- Derive description from method name (camelCase → sentence)
- Add `@param` for each parameter (derive from param name)
- Add `@return` if non-void (derive from return type)
- Add `@throws` if method declares exceptions

#### MissingJavadocType Violations

Generate class-level Javadoc for public/protected classes:

```java
// Before
@Singleton
public class EmailProcessingService {

// After
/**
 * Service for processing inbound email webhooks.
 *
 * <p>Handles email ingestion from Postmark and Sendgrid webhooks,
 * creating inbox items and processing jobs.
 */
@Singleton
public class EmailProcessingService {
```

**Template Strategy**:
- Derive description from class name
- Add purpose/responsibility summary
- Keep generic but accurate

#### EmptyLineSeparator Violations

Ensure blank lines between major code elements:

```java
// Before
package com.goecfx;
import io.micronaut.http.HttpResponse;
@Controller
public class MyController {

// After
package com.goecfx;

import io.micronaut.http.HttpResponse;

@Controller
public class MyController {
```

**Rules**: Blank line after: package, import block, before class, between methods, between fields and methods.

### 6. Re-Run Validation

After applying fixes:

```bash
./gradlew checkstyleMain
```

Check results:
- If exit code 0: All violations fixed
- If exit code 1: Parse remaining violations, iterate or report

### 7. Report Results

**Success Case**:
```
Checkstyle validation: PASSED
- Fixed 8 violations automatically:
  - 3 LineLength (broken long lines)
  - 2 CustomImportOrder (sorted imports)
  - 2 WhitespaceAfter (added spaces)
  - 1 JavadocParagraph (fixed <p> tag)
- All violations resolved
```

**Partial Success Case**:
```
Checkstyle validation: 5/8 violations fixed

Automatically fixed:
- 3 LineLength violations in PostmarkController.java

Remaining violations (require manual attention):
1. PostmarkController.java:45 - AbbreviationAsWordInName
   Variable 'HTMLURL' should be renamed to 'htmlUrl'

2. SendgridController.java:78 - AbbreviationAsWordInName
   Method 'parseHTMLContent' should be renamed to 'parseHtmlContent'

Recommendation: Rename variables/methods to use camelCase (max 4 consecutive capitals).
```

**Failure Case**:
```
Checkstyle validation: FAILED
- Unable to automatically fix violations
- 3 violations require manual review:
  [List violations with file, line, and guidance]
```

### 8. Integration with Git Workflow

When invoked before commit:
1. Run checkstyle on modified Java files
2. Apply automatic fixes
3. Re-run validation
4. If passing: Inform user "Checkstyle validated, ready to commit"
5. If failing: List remaining issues, ask user to review before committing

## Configuration Context

This project uses:
- **Checkstyle version**: 10.12.5
- **Style guide**: Google Java Style Guide (customized)
- **Line length**: 150 characters (not 100)
- **Abbreviation length**: 4 characters (allows URL, HTML, HTTP, JSON)
- **Test sources**: Excluded from checkstyle
- **Build behavior**: Fails on any violation (ignoreFailures=false, maxWarnings=0)
- **Reports**: XML + HTML in `build/reports/checkstyle/`

## Common Violation Patterns

### LineLength (150 char limit)

**Cause**: Lines exceed 150 characters
**Fix Strategy**:
- Method parameters: Break after opening paren, one param per line or group logically
- Method calls: Break after opening paren or at commas
- Strings: Break into concatenation with `+`
- Chains: Break before dots (fluent APIs)

### CustomImportOrder

**Cause**: Imports not sorted or grouped correctly
**Fix Strategy**:
1. Group 1: Static imports (alphabetical)
2. Blank line
3. Group 2: Third-party imports (alphabetical)
4. Blank line
5. Group 3: java/javax/jakarta imports (alphabetical)

### Whitespace Issues

**WhitespaceAfter**: Add space after `,`, `;`, typecast, `if`, `for`, `while`
**WhitespaceAround**: Add space around `=`, `+`, `-`, `*`, `/`, `{`, `}`, etc.
**NoWhitespaceBefore**: Remove space before `,`, `;`, `.`, `)`, `++`, `--`

### Javadoc Issues

**JavadocParagraph**:
- Blank line (just `*`) before `<p>`
- No space after `<p>`

**MissingJavadocMethod**:
- Required for public methods with 2+ lines (excluding `@Override`, `@Test`)
- Must include description, `@param`, `@return` (if non-void)

**MissingJavadocType**:
- Required for public/protected classes
- Must include class description

### Indentation

**Standard**: 4 spaces per level
**Continuation lines**: 8 spaces (line wrapping)
**Case statements**: Indent 4 spaces from switch

## Error Handling

### Build Fails Before Checkstyle

If `./gradlew checkstyleMain` fails due to compilation errors:
1. Report: "Cannot run checkstyle - compilation errors present"
2. Recommend: "Fix compilation errors first, then re-run checkstyle"

### Cannot Parse XML Report

If XML report is missing or malformed:
1. Check HTML report at `build/reports/checkstyle/main.html`
2. Extract violations manually from HTML
3. Report parsing issue to user

### Fix Causes New Violations

If automatic fix introduces new violations:
1. Revert the problematic fix
2. Mark violation as "manual" in report
3. Continue with other fixes

### Uncertain How to Fix

If violation type is unfamiliar:
1. Read violation message carefully
2. Check checkstyle.xml config for rule details
3. Search checkstyle documentation: https://checkstyle.org/checks.html
4. If still unclear, report to user as "manual" fix needed

## File Locations

- **Project root**: `/Users/traviscarter/ecfx/receipt_processing_web`
- **Checkstyle config**: `config/checkstyle/checkstyle.xml`
- **Suppressions**: `config/checkstyle/suppressions.xml`
- **XML report**: `build/reports/checkstyle/main.xml`
- **HTML report**: `build/reports/checkstyle/main.html`
- **Source files**: `src/main/java/com/goecfx/**/*.java`

## Success Criteria

A successful checkstyle enforcement means:
1. `./gradlew checkstyleMain` exits with code 0
2. All auto-fixable violations have been corrected
3. Remaining violations (if any) are clearly reported with guidance
4. No new violations introduced by fixes
5. Code still compiles and tests pass (if applicable)

## Notes

- Always run checkstyle AFTER modifying Java files, not before
- Test files (src/test/) are excluded from checkstyle
- Lombok-generated code is excluded from checkstyle
- Focus on main source files only (`src/main/java/`)
- Preserve existing code logic and functionality while fixing style
- When uncertain about a fix, report to user rather than guessing
