# Library API Verifier - Examples

## Example 1: Verifying EmailInboxItem from com.goecfx:data:0.2.1

### Context
Implementing email webhook processing that needs to create EmailInboxItem entities. Documentation suggests using `EmailInboxItem.create()`, but this needs verification.

### Step 1: Locate the JAR
```bash
$ find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"
/Users/user/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123def456/data-0.2.1.jar
```

### Step 2: Inspect the Class
```bash
$ javap -public -cp /Users/user/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123def456/data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
```

### Step 3: Output Analysis
```java
public class com.goecfx.data.entities.EmailInboxItem extends com.goecfx.data.entities.InboxItem {
  public com.goecfx.data.entities.EmailInboxItem();
  public void setFirm(com.goecfx.data.entities.Firm);
  public com.goecfx.data.entities.Firm getFirm();
  public void setRawEmail(java.lang.String);
  public java.lang.String getRawEmail();
  public void setStatus(com.goecfx.data.entities.InboxItem$Status);
  public com.goecfx.data.entities.InboxItem$Status getStatus();
  public void setProcessedAt(java.time.Instant);
  public java.time.Instant getProcessedAt();
  public void setId(java.lang.Long);
  public java.lang.Long getId();
}
```

### Verification Result
```markdown
## Library API Verification: EmailInboxItem

**Library**: com.goecfx:data:0.2.1
**Class**: com.goecfx.data.entities.EmailInboxItem
**JAR Location**: ~/.gradle/caches/.../data-0.2.1.jar

### Available Constructors
- ✅ No-arg constructor: `public EmailInboxItem()`

### Available Methods
**Setters**:
- `public void setFirm(Firm)`
- `public void setRawEmail(String)`
- `public void setStatus(InboxItem.Status)`
- `public void setProcessedAt(Instant)`
- `public void setId(Long)`

**Getters**:
- `public Firm getFirm()`
- `public String getRawEmail()`
- `public InboxItem.Status getStatus()`
- `public Instant getProcessedAt()`
- `public Long getId()`

### Builder Pattern
- ❌ No builder available

### Factory Methods
- ❌ No `create()` method exists
- ❌ No other factory methods

### Verification Result
❌ Missing methods: `create()`, `builder()`

**Documentation Error**: CLAUDE.md references non-existent `EmailInboxItem.create()` method.

### Recommended Usage Pattern
```java
// Correct usage with standard setters
EmailInboxItem item = new EmailInboxItem();
item.setFirm(firm);
item.setRawEmail(rawEmailContent);
item.setStatus(InboxItem.Status.PENDING);
EmailInboxItem saved = repository.save(item);
```

**DO NOT USE** (these methods don't exist):
```java
// ❌ WRONG - no create() method
EmailInboxItem item = EmailInboxItem.create(firm, rawEmail, status);

// ❌ WRONG - no builder
EmailInboxItem item = EmailInboxItem.builder()
    .firm(firm)
    .rawEmail(rawEmail)
    .build();
```
```

---

## Example 2: Verifying Lombok Builder Availability

### Context
Need to check if a library uses Lombok's `@Builder` annotation which generates builder methods.

### Inspection Command
```bash
javap -public -cp ~/.gradle/caches/.../mylib-1.0.0.jar com.example.User
```

### Output with Lombok Builder
```java
public class com.example.User {
  public static com.example.User.UserBuilder builder();
  public com.example.User(java.lang.String, java.lang.String, int);

  public static class UserBuilder {
    public com.example.User.UserBuilder name(java.lang.String);
    public com.example.User.UserBuilder email(java.lang.String);
    public com.example.User.UserBuilder age(int);
    public com.example.User build();
  }
}
```

### Verification Result
```markdown
✅ Builder pattern available

**Recommended Usage**:
```java
User user = User.builder()
    .name("John")
    .email("john@example.com")
    .age(30)
    .build();
```
```

---

## Example 3: Verifying Method Signatures for Overloaded Methods

### Context
Library has multiple `save()` methods with different signatures.

### Inspection Command
```bash
javap -public -v -cp ~/.gradle/caches/.../repository-lib-2.5.0.jar com.example.Repository
```

### Output Analysis
```java
public interface com.example.Repository {
  public abstract java.lang.Object save(java.lang.Object);
  public abstract java.util.List save(java.util.List);
  public abstract java.lang.Object saveAndFlush(java.lang.Object);
}
```

### Verification Result
```markdown
✅ Multiple save methods available:

1. **Single entity**: `Object save(Object entity)`
   - Returns: Saved entity
   - Use for: Saving one entity

2. **Batch save**: `List save(List entities)`
   - Returns: List of saved entities
   - Use for: Saving multiple entities

3. **Save and flush**: `Object saveAndFlush(Object entity)`
   - Returns: Saved entity
   - Use for: Immediate persistence to DB
```

---

## Example 4: Handling Missing JAR

### Scenario
JAR not found in Gradle cache.

### Command
```bash
$ find ~/.gradle/caches -name "mylib-*.jar"
# No results
```

### Resolution Steps
```bash
# 1. Check if dependency is declared
$ grep "mylib" build.gradle
# If found, dependency exists

# 2. Trigger dependency download
$ ./gradlew dependencies --configuration compileClasspath | grep mylib
# Or force refresh
$ ./gradlew build --refresh-dependencies

# 3. Search again
$ find ~/.gradle/caches -name "mylib-*.jar"

# 4. If still not found, check for typos in dependency declaration
```

---

## Example 5: Verifying Inherited Methods

### Context
Class extends a parent class, need to see all available methods including inherited ones.

### Inspection Commands
```bash
# Inspect child class
javap -public -cp library.jar com.example.ChildClass

# Inspect parent class
javap -public -cp library.jar com.example.ParentClass
```

### Child Class Output
```java
public class com.example.ChildClass extends com.example.ParentClass {
  public com.example.ChildClass();
  public void childMethod();
}
```

### Parent Class Output
```java
public class com.example.ParentClass {
  public com.example.ParentClass();
  public void parentMethod();
  public java.lang.String getName();
  public void setName(java.lang.String);
}
```

### Verification Result
```markdown
✅ ChildClass inherits from ParentClass

**Available methods on ChildClass**:
- From ChildClass: `childMethod()`
- From ParentClass: `parentMethod()`, `getName()`, `setName(String)`

**Usage**:
```java
ChildClass instance = new ChildClass();
instance.setName("example");  // Inherited from parent
instance.childMethod();       // Defined in child
```
```

---

## Example 6: Verifying Interface Implementation

### Context
Need to implement an interface from external library, verify required methods.

### Inspection Command
```bash
javap -public -cp library.jar com.example.PaymentProcessor
```

### Interface Output
```java
public interface com.example.PaymentProcessor {
  public abstract boolean process(com.example.Payment);
  public abstract void refund(java.lang.String);
  public abstract com.example.PaymentStatus getStatus(java.lang.String);
}
```

### Verification Result
```markdown
✅ Interface PaymentProcessor requires 3 methods:

**Required implementations**:
```java
@Singleton
public class MyPaymentProcessor implements PaymentProcessor {

    @Override
    public boolean process(Payment payment) {
        // Implementation required
    }

    @Override
    public void refund(String transactionId) {
        // Implementation required
    }

    @Override
    public PaymentStatus getStatus(String transactionId) {
        // Implementation required
    }
}
```
```

---

## Example 7: CodeArtifact Private Library

### Context
Verifying APIs in a private library from AWS CodeArtifact.

### Special Considerations
```bash
# 1. Ensure AWS credentials are valid
$ aws codeartifact get-authorization-token --domain my-domain --query authorizationToken

# 2. Build project to download from CodeArtifact
$ ./gradlew build

# 3. Locate JAR
$ find ~/.gradle/caches -name "private-lib-*.jar"

# 4. Inspect
$ javap -public -cp ~/.gradle/caches/.../private-lib-1.0.0.jar com.company.PrivateClass
```

### If JAR Not Found
```markdown
❌ JAR not found in cache

**Resolution**:
1. Verify AWS CLI configured: `aws configure list`
2. Test token generation: `aws codeartifact get-authorization-token ...`
3. Check build.gradle has correct repository URL
4. Run `./gradlew dependencies --refresh-dependencies`
5. Check for errors in Gradle output
```

---

## Example 8: Distinguishing Static vs Instance Methods

### Inspection Output
```java
public class com.example.Utility {
  public com.example.Utility();
  public static com.example.Result process(java.lang.String);
  public com.example.Result processInstance(java.lang.String);
}
```

### Verification Result
```markdown
✅ Mixed static and instance methods

**Static method** (no instance needed):
```java
Result result = Utility.process("data");
```

**Instance method** (instance required):
```java
Utility utility = new Utility();
Result result = utility.processInstance("data");
```

**Common mistake**:
```java
// ❌ WRONG - calling static method on instance
Utility utility = new Utility();
Result result = utility.process("data");  // Works but unconventional

// ❌ WRONG - calling instance method statically
Result result = Utility.processInstance("data");  // Compilation error
```
```
