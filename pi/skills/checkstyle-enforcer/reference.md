# Checkstyle Reference Guide

This file provides technical reference for checkstyle violations and XML parsing.

## Checkstyle XML Report Structure

### Report Location
- XML: `build/reports/checkstyle/main.xml`
- HTML: `build/reports/checkstyle/main.html`

### XML Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle version="10.12.5">
    <file name="/absolute/path/to/file.java">
        <error line="45" column="120" severity="warning"
               message="Line is longer than 150 characters (found 165)."
               source="com.puppycrawl.tools.checkstyle.checks.sizes.LineLengthCheck"/>
        <error line="52" column="1" severity="warning"
               message="Missing a Javadoc comment."
               source="com.puppycrawl.tools.checkstyle.checks.javadoc.MissingJavadocMethodCheck"/>
    </file>
</checkstyle>
```

### XML Parsing Strategy

1. Parse XML with standard XML parser
2. Extract `<file>` elements
3. For each file, extract `<error>` elements
4. Extract attributes:
   - `line`: Line number (integer)
   - `column`: Column number (integer, optional)
   - `severity`: "warning" or "error"
   - `message`: Human-readable description
   - `source`: Fully qualified check class name

5. Derive violation type from `source` attribute:
   - Extract class name: `LineLengthCheck` from `com.puppycrawl.tools.checkstyle.checks.sizes.LineLengthCheck`
   - Map to short name: `LineLengthCheck` → `LineLength`

## Violation Type Reference

### Auto-Fixable Violations

| Check Name | Source Class | Fix Complexity | Fix Strategy |
|------------|--------------|----------------|--------------|
| LineLength | LineLengthCheck | Medium | Break lines at 150 chars, 8-space indent |
| CustomImportOrder | CustomImportOrderCheck | Low | Sort imports into groups |
| WhitespaceAfter | WhitespaceAfterCheck | Low | Add space after token |
| WhitespaceAround | WhitespaceAroundCheck | Low | Add space around token |
| JavadocParagraph | JavadocParagraphCheck | Low | Fix `<p>` tag formatting |
| EmptyLineSeparator | EmptyLineSeparatorCheck | Low | Add blank line |
| OperatorWrap | OperatorWrapCheck | Medium | Move operator to new line |
| SeparatorWrap | SeparatorWrapCheck | Medium | Move separator (comma/dot) |
| NoWhitespaceBefore | NoWhitespaceBeforeCheck | Low | Remove space before token |
| Indentation | IndentationCheck | Medium | Fix indentation (4 or 8 spaces) |

### Semi-Auto-Fixable Violations

| Check Name | Source Class | Fix Strategy |
|------------|--------------|--------------|
| MissingJavadocMethod | MissingJavadocMethodCheck | Generate template from method signature |
| MissingJavadocType | MissingJavadocTypeCheck | Generate template from class name |

### Manual Violations (Report to User)

| Check Name | Source Class | Why Manual |
|------------|--------------|------------|
| AbbreviationAsWordInName | AbbreviationAsWordInNameCheck | Requires renaming across codebase |
| MissingSwitchDefault | MissingSwitchDefaultCheck | Requires logic decision |
| FallThrough | FallThroughCheck | Requires logic review |
| VariableDeclarationUsageDistance | VariableDeclarationUsageDistanceCheck | Requires code refactoring |

## Project-Specific Checkstyle Configuration

### Key Settings from checkstyle.xml

```xml
<!-- Line length: 150 characters (not Google's default 100) -->
<module name="LineLength">
    <property name="max" value="150"/>
    <property name="ignorePattern" value="^package.*|^import.*|a href|href|http://|https://|ftp://"/>
</module>

<!-- Abbreviations: Max 4 consecutive capitals (allows URL, HTML, HTTP, JSON) -->
<module name="AbbreviationAsWordInName">
    <property name="allowedAbbreviationLength" value="4"/>
</module>

<!-- Import order: STATIC###THIRD_PARTY_PACKAGE###STANDARD_JAVA_PACKAGE -->
<module name="CustomImportOrder">
    <property name="sortImportsInGroupAlphabetically" value="true"/>
    <property name="separateLineBetweenGroups" value="true"/>
    <property name="customImportOrderRules" value="STATIC###THIRD_PARTY_PACKAGE###STANDARD_JAVA_PACKAGE"/>
</module>

<!-- Javadoc: Public methods with 2+ lines, excluding @Override and @Test -->
<module name="MissingJavadocMethod">
    <property name="scope" value="public"/>
    <property name="minLineCount" value="2"/>
    <property name="allowedAnnotations" value="Override, Test"/>
</module>

<!-- Indentation: 4 spaces base, 8 spaces continuation -->
<module name="Indentation">
    <property name="basicOffset" value="4"/>
    <property name="lineWrappingIndentation" value="8"/>
</module>

<!-- Operator wrap: Operators at beginning of new line (NL) -->
<module name="OperatorWrap">
    <property name="option" value="NL"/>
</module>

<!-- Separator wrap: Comma at end (EOL), dot at beginning (NL) -->
<module name="SeparatorWrap">
    <property name="tokens" value="DOT"/>
    <property name="option" value="nl"/>
</module>
<module name="SeparatorWrap">
    <property name="tokens" value="COMMA"/>
    <property name="option" value="eol"/>
</module>
```

### Suppressions

Location: `config/checkstyle/suppressions.xml`

Currently suppresses:
- Generated code in `[/\\]generated[/\\]` directories

To add suppression:
```xml
<!-- Example: Suppress LineLength for specific file -->
<suppress files="VeryLongLegacyClass\.java" checks="LineLength"/>

<!-- Example: Suppress all checks for specific directory -->
<suppress files="[/\\]legacy[/\\]" checks=".*"/>
```

## Gradle Integration

### Running Checkstyle

```bash
# Run checkstyle on main sources
./gradlew checkstyleMain

# Run checkstyle on test sources (currently disabled)
./gradlew checkstyleTest

# Run all checks including checkstyle
./gradlew check
```

### Build Configuration

From `build.gradle`:

```groovy
checkstyle {
    toolVersion = '10.12.5'
    configFile = file("${rootDir}/config/checkstyle/checkstyle.xml")
    ignoreFailures = false  // Build fails on violations
    maxWarnings = 0         // Zero tolerance for warnings
    configProperties = [
        'suppressionFilterFile': file("${rootDir}/config/checkstyle/suppressions.xml")
    ]
}

// Disable checkstyle on test sources
checkstyleTest.enabled = false
```

**Important**: `ignoreFailures = false` and `maxWarnings = 0` means any violation will fail the build.

## Common Checkstyle Messages

### LineLength

**Message**: `Line is longer than 150 characters (found 165).`

**Line Breaking Priorities**:
1. After commas in parameter lists
2. Before operators (`+`, `&&`, `||`, `?`, `:`)
3. After dots in method chains
4. At natural semantic boundaries

**Indentation**: Use 8 spaces for continuation lines.

### CustomImportOrder

**Message**: `Wrong order for 'io.micronaut.http.HttpResponse' import.`

**Import Groups**:
1. Static imports (e.g., `import static org.junit.jupiter.api.Assertions.*`)
2. Third-party packages (e.g., `io.micronaut`, `com.goecfx`, `jakarta`)
3. Standard Java packages (e.g., `java.util`, `javax.inject`)

**Within each group**: Alphabetical order

### WhitespaceAfter

**Message**: `',' is not followed by whitespace.`

**Tokens requiring space after**:
- `,` (comma)
- `;` (semicolon)
- Typecast: `(String)`
- `if`, `for`, `while`, `do`

### WhitespaceAround

**Message**: `'=' is not preceded with whitespace.`
**Message**: `'=' is not followed by whitespace.`

**Tokens requiring space around**:
- Assignment: `=`, `+=`, `-=`, `*=`, `/=`
- Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `&&`, `||`
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Braces: `{`, `}`
- Lambda: `->`

### JavadocParagraph

**Message**: `<p> tag should be preceded with an empty line.`
**Message**: `<p> tag should be placed immediately before the first word.`

**Correct Format**:
```java
/**
 * First paragraph.
 *
 * <p>Second paragraph (no space after <p>).
 */
```

### MissingJavadocMethod

**Message**: `Missing a Javadoc comment.`

**Requirements**:
- Scope: `public` only
- Min line count: 2 (single-line methods exempt)
- Excluded: `@Override`, `@Test` methods

**Template**:
```java
/**
 * [Verb phrase describing what the method does].
 *
 * [Optional: Additional details about behavior, side effects, or context]
 *
 * @param paramName [description starting with lowercase]
 * @return [description starting with lowercase]
 * @throws ExceptionType [description starting with lowercase]
 */
```

### MissingJavadocType

**Message**: `Missing a Javadoc comment.`

**Requirements**:
- Scope: `protected` and above (includes `public`)
- Types: Classes, interfaces, enums, annotations, records

**Template**:
```java
/**
 * [Noun phrase describing what the class represents or does].
 *
 * <p>[Optional: Additional context, responsibilities, or usage notes]
 */
```

### AbbreviationAsWordInName

**Message**: `Abbreviation in name 'HTMLURL' must contain no more than 4 consecutive capital letters.`

**Allowed Examples** (4 or fewer):
- `HTML` (4 capitals)
- `URL` (3 capitals)
- `HTTP` (4 capitals)
- `JSON` (4 capitals)
- `XMLParser` (XML = 3 capitals, then normal case)

**Not Allowed** (5+ consecutive):
- `HTMLURL` → Use `HtmlUrl`
- `HTTPSConnection` → Use `HttpsConnection`
- `JSONAPIClient` → Use `JsonApiClient`

**Fix Strategy**: Manually rename to camelCase with max 4 consecutive capitals.

## Checkstyle CLI Reference

### Version and Help

```bash
# Check checkstyle version
./gradlew checkstyleMain --version

# Get help
./gradlew help --task checkstyleMain
```

### Report Locations

After running checkstyle, reports are generated:

```
build/
└── reports/
    └── checkstyle/
        ├── main.xml    # Machine-readable XML
        └── main.html   # Human-readable HTML
```

### Exit Codes

- `0`: No violations found (success)
- `1`: Violations found (failure)
- `2+`: Build error (e.g., compilation failure, invalid config)

## Javadoc Tag Reference

### Common Tags

| Tag | Usage | Example |
|-----|-------|---------|
| `@param` | Method parameter | `@param request the inbound email request` |
| `@return` | Method return value | `@return the created inbox item` |
| `@throws` | Exception thrown | `@throws ValidationException if request is invalid` |
| `@deprecated` | Deprecated element | `@deprecated Use {@link #newMethod()} instead` |
| `@see` | Cross-reference | `@see EmailProcessingService` |
| `@since` | Version added | `@since 1.2.0` |

### HTML Tags in Javadoc

| Tag | Usage | Example |
|-----|-------|---------|
| `<p>` | Start new paragraph | `<p>Additional details here.` |
| `<code>` | Inline code | `Use <code>true</code> to enable.` |
| `<pre>` | Code block | `<pre>String example = "value";</pre>` |
| `<ul>` `<li>` | Unordered list | `<ul><li>First item</li></ul>` |
| `<ol>` `<li>` | Ordered list | `<ol><li>Step one</li></ol>` |

### Inline Tags

| Tag | Usage | Example |
|-----|-------|---------|
| `{@code}` | Inline code | `Use {@code null} to skip.` |
| `{@link}` | Link to class/method | `See {@link EmailService#process}` |
| `{@literal}` | Literal text | `Use {@literal <tag>} for HTML.` |

## Line Breaking Rules

### Method Declarations

```java
// Break after opening parenthesis
public ResponseEntity<Result> processLongMethodName(
        String param1, String param2, Long param3) {

// Or break at each parameter
public ResponseEntity<Result> processLongMethodName(
        String param1,
        String param2,
        Long param3) {
```

### Method Calls

```java
// Break after opening parenthesis
service.processEmail(
        from, subject, body, attachments);

// Or break at each argument
service.processEmail(
        from,
        subject,
        body,
        attachments);
```

### String Concatenation

```java
// Break with + at beginning of new line
String message = "First part of message "
        + "second part of message "
        + "third part of message";
```

### Method Chains

```java
// Break before each dot
List<Item> results = repository.findAll()
        .stream()
        .filter(item -> item.isActive())
        .map(item -> item.getName())
        .collect(Collectors.toList());
```

### Binary Operators

```java
// Break before operator
boolean condition = value1 > 10
        && value2 < 20
        || value3 == 30;
```

### Ternary Operator

```java
// Break before ? and :
String result = condition
        ? "true value"
        : "false value";
```

## Testing Checkstyle Configuration Changes

### Modify Suppressions

Edit `config/checkstyle/suppressions.xml`:

```xml
<!-- Suppress specific check for specific file -->
<suppress files="PostmarkController\.java" checks="LineLength"/>

<!-- Suppress specific check for all files -->
<suppress checks="MissingJavadocMethod"/>

<!-- Suppress all checks for specific package -->
<suppress files="com[/\\]goecfx[/\\]legacy[/\\]" checks=".*"/>
```

### Test Configuration

```bash
# Test on specific file
./gradlew checkstyleMain -PcheckstyleFile=src/main/java/com/goecfx/controllers/PostmarkController.java

# Verbose output
./gradlew checkstyleMain --info

# Debug output
./gradlew checkstyleMain --debug
```

## Useful External References

- **Checkstyle Documentation**: https://checkstyle.org/
- **Google Java Style Guide**: https://google.github.io/styleguide/javaguide.html
- **Checkstyle Checks**: https://checkstyle.org/checks.html
- **Javadoc Guide**: https://www.oracle.com/technical-resources/articles/java/javadoc-tool.html
