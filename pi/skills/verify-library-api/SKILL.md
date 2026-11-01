---
name: verify-library-api
description: >-
  Verify that methods, classes, and APIs actually exist in external libraries before implementing code. Use when working with external dependencies, when compilation errors occur with "cannot find symbol", when user mentions using a new library or framework, or before implementing interfaces from external libraries.
---


# Library API Verifier

Verify that classes, methods, and APIs actually exist in external libraries before implementing code that depends on them. This prevents entire feature implementations based on hallucinated or non-existent APIs.

## Problem Solved

LLMs can hallucinate methods based on common patterns (e.g., assuming `EmailInboxItem.create()` exists because builder patterns are common). This skill prevents compilation errors and wasted implementation effort by verifying APIs first.

## Process

### 1. Identify the Library and Class

Extract from context:
- **Library name**: e.g., `com.goecfx:data:0.2.1`
- **Group ID**: e.g., `com.goecfx`
- **Artifact ID**: e.g., `data`
- **Version**: e.g., `0.2.1`
- **Fully qualified class name**: e.g., `com.goecfx.data.entities.EmailInboxItem`

### 2. Locate the JAR File

Use the Gradle cache to find the library JAR:

```bash
find ~/.gradle/caches -name "[artifact-id]-*.jar" | grep "[version]"
```

**Example**:
```bash
find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"
```

**Expected output**:
```
~/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/[hash]/data-0.2.1.jar
```

If not found:
- Check if the library is actually declared in build.gradle
- Verify Gradle sync has completed
- For CodeArtifact, verify AWS credentials are valid
- Try running `./gradlew dependencies` to trigger download

### 3. Inspect Available APIs

Use `javap` to inspect the compiled class and see all available methods:

```bash
javap -public -cp /path/to/library.jar com.example.ClassName
```

**Flags explanation**:
- `-public`: Show only public members (what you can actually use)
- `-cp`: Specify classpath to the JAR file
- Can add `-v` for verbose output including signatures

**Example**:
```bash
javap -public -cp ~/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123/data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
```

### 4. Parse and Document Findings

From the `javap` output, identify:

**Constructors**:
- `public EmailInboxItem();` - No-arg constructor available
- List any parameterized constructors

**Methods**:
- Setters: `public void setFirm(Firm);`
- Getters: `public Firm getFirm();`
- Builder methods: `public static EmailInboxItemBuilder builder();`
- Factory methods: `public static EmailInboxItem create(...);`

**Fields** (if public):
- `public static final String CONSTANT;`

### 5. Verify Specific Method Signatures

If looking for a specific method, check:
- **Exact method name** (case-sensitive)
- **Parameter types** (order and types must match)
- **Return type**
- **Static vs instance** method

**Common mistakes**:
- Assuming `create()` exists when only constructor is available
- Wrong parameter order
- Assuming builder pattern when none exists
- Assuming fluent setters (`return this`) when they return `void`

### 6. Report Findings

Create a clear report:

```markdown
## Library API Verification: [ClassName]

**Library**: [groupId]:[artifactId]:[version]
**Class**: [fully.qualified.ClassName]
**JAR Location**: [path]

### Available Constructors
- [ ] No-arg constructor: `public ClassName()`
- [ ] Parameterized: `public ClassName(Type1, Type2)`

### Available Methods
**Setters**:
- `public void setPropertyName(Type value)`

**Getters**:
- `public Type getPropertyName()`

**Other Public Methods**:
- `public ReturnType methodName(ParamType param)`

### Builder Pattern
- [ ] Builder available: `public static ClassNameBuilder builder()`
- [ ] Build method: `public ClassName build()`

### Factory Methods
- [ ] `public static ClassName create(...)`

### Verification Result
✅ All required methods exist
OR
❌ Missing methods: [list]

### Recommended Usage Pattern
[Code example showing correct usage based on available APIs]
```

### 7. Provide Usage Recommendation

Based on findings, recommend the correct usage pattern:

**If standard setters exist**:
```java
ClassName instance = new ClassName();
instance.setProperty1(value1);
instance.setProperty2(value2);
```

**If builder exists**:
```java
ClassName instance = ClassName.builder()
    .property1(value1)
    .property2(value2)
    .build();
```

**If factory method exists**:
```java
ClassName instance = ClassName.create(value1, value2);
```

## Quality Checklist

- [ ] Library name and version confirmed
- [ ] JAR file located successfully
- [ ] `javap` executed without errors
- [ ] All constructors documented
- [ ] All public methods documented with signatures
- [ ] Specific requested methods verified (exist or don't exist)
- [ ] Usage recommendation provided with correct syntax
- [ ] Report clearly states verification result

## When to Use This Skill

**Always use before**:
- Implementing code using a new external library
- Using methods from external dependencies
- Creating entities from shared libraries
- Extending or implementing external interfaces

**Especially when**:
- Documentation is unclear or outdated
- Working with internal/private libraries
- "Cannot find symbol" compilation errors occur
- Assuming common patterns (builders, factories)

**Do NOT use for**:
- Standard JDK classes (java.lang.*, java.util.*)
- Well-known frameworks with stable APIs (Spring, Hibernate core)
- Your own project classes (use IDE or grep)

## Special Cases

**Kotlin Libraries**: Use `javap` on `.class` files, but syntax may differ

**Multiple Versions**: Ensure you're inspecting the version actually used in the project

**Transitive Dependencies**: If class is from transitive dependency, find the actual providing JAR

**Obfuscated JARs**: Method names may be mangled, check proguard mapping if available

**Interface Inspection**: Also verify implementing classes, not just interfaces

## Example Workflow

```bash
# 1. Find the JAR
find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"
# Result: ~/.gradle/caches/.../data-0.2.1.jar

# 2. List classes in JAR (optional, to find the right class)
jar -tf ~/.gradle/caches/.../data-0.2.1.jar | grep EmailInboxItem
# Result: com/goecfx/data/entities/EmailInboxItem.class

# 3. Inspect the class
javap -public -cp ~/.gradle/caches/.../data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem

# 4. Output analysis
# If you see:
#   public EmailInboxItem();
#   public void setFirm(com.goecfx.data.entities.Firm);
#   public void setRawEmail(java.lang.String);
#
# Then use standard setters, NOT a builder or factory
```

---

For detailed examples, see `examples.md`
For common library patterns, see `reference.md`
