# Library API Verifier - Reference

## javap Command Reference

### Basic Syntax
```bash
javap [options] classname
```

### Common Options

| Option | Description | When to Use |
|--------|-------------|-------------|
| `-public` | Show only public members | Default - what you can actually use |
| `-protected` | Show public and protected members | When extending the class |
| `-private` | Show all members | Deep inspection |
| `-p` | Same as `-private` | Short form |
| `-package` | Show package/protected/public | Analyzing visibility |
| `-v` | Verbose output with signatures | Need exact type signatures |
| `-l` | Print line numbers and local vars | Debugging purposes |
| `-c` | Disassemble code | Understanding implementation |
| `-s` | Print internal type signatures | Generic types inspection |
| `-cp <path>` | Specify classpath | **Required** for external JARs |
| `-classpath <path>` | Same as `-cp` | Alternative form |

### Recommended Usage

**Standard inspection** (most common):
```bash
javap -public -cp /path/to/library.jar com.example.ClassName
```

**Detailed inspection** (with signatures):
```bash
javap -public -v -cp /path/to/library.jar com.example.ClassName
```

**All members** (including private):
```bash
javap -private -cp /path/to/library.jar com.example.ClassName
```

---

## Understanding javap Output

### Constructor Signatures

```java
public com.example.User();
```
- **No-arg constructor** available
- Can create instance with `new User()`

```java
public com.example.User(java.lang.String, int);
```
- **Parameterized constructor** with String and int parameters
- Can create with `new User("name", 25)`

```java
// No constructor listed
```
- Only **default constructor** exists
- Can still use `new User()`

### Method Signatures

```java
public void setName(java.lang.String);
```
- **Setter** method (void return, single parameter)
- Usage: `instance.setName("value")`

```java
public java.lang.String getName();
```
- **Getter** method (returns value, no parameters)
- Usage: `String name = instance.getName()`

```java
public com.example.User setName(java.lang.String);
```
- **Fluent setter** (returns instance for chaining)
- Usage: `instance.setName("value").setAge(25)`

```java
public static com.example.User create(java.lang.String);
```
- **Static factory method**
- Usage: `User user = User.create("name")`

```java
public static com.example.UserBuilder builder();
```
- **Builder pattern** entry point
- Usage: `User user = User.builder().name("value").build()`

### Generic Types

Without `-v` flag:
```java
public java.util.List getItems();
```
- Returns raw List (no generic info)

With `-v` flag:
```java
public java.util.List<com.example.Item> getItems();
  descriptor: ()Ljava/util/List;
  Signature: ()Ljava/util/List<Lcom/example/Item;>;
```
- Shows actual generic type: `List<Item>`

### Inner Classes

```java
public static class com.example.User$Builder {
  public com.example.User$Builder name(java.lang.String);
  public com.example.User build();
}
```
- **Static inner class** (Builder pattern common)
- Usage: `User.Builder` or `User.UserBuilder` depending on declaration

---

## Common Library Patterns

### Pattern 1: Plain Java Bean (Setters/Getters)

**javap output**:
```java
public class com.example.User {
  public com.example.User();
  public void setName(java.lang.String);
  public java.lang.String getName();
  public void setAge(int);
  public int getAge();
}
```

**Usage**:
```java
User user = new User();
user.setName("John");
user.setAge(30);
```

---

### Pattern 2: Lombok @Builder

**javap output**:
```java
public class com.example.User {
  public static com.example.User.UserBuilder builder();

  public static class UserBuilder {
    public com.example.User.UserBuilder name(java.lang.String);
    public com.example.User.UserBuilder age(int);
    public com.example.User build();
  }
}
```

**Usage**:
```java
User user = User.builder()
    .name("John")
    .age(30)
    .build();
```

---

### Pattern 3: Lombok @Data (Combined)

**javap output**:
```java
public class com.example.User {
  public com.example.User();
  public static com.example.User.UserBuilder builder();
  public void setName(java.lang.String);
  public java.lang.String getName();
  public void setAge(int);
  public int getAge();

  public static class UserBuilder {
    // ... builder methods
  }
}
```

**Usage** (both patterns available):
```java
// Option 1: Setters
User user = new User();
user.setName("John");

// Option 2: Builder
User user = User.builder().name("John").build();
```

---

### Pattern 4: Factory Method

**javap output**:
```java
public class com.example.User {
  public static com.example.User create(java.lang.String, int);
  // Constructor may be private
}
```

**Usage**:
```java
User user = User.create("John", 30);
```

---

### Pattern 5: Fluent Interface

**javap output**:
```java
public class com.example.User {
  public com.example.User();
  public com.example.User setName(java.lang.String);  // Returns User, not void
  public com.example.User setAge(int);
}
```

**Usage**:
```java
User user = new User()
    .setName("John")
    .setAge(30);
```

---

## Gradle Cache Structure

### Finding JAR Files

**Standard location**:
```
~/.gradle/caches/modules-2/files-2.1/{groupId}/{artifactId}/{version}/{hash}/{artifactId}-{version}.jar
```

**Example**:
```
~/.gradle/caches/modules-2/files-2.1/com.goecfx/data/0.2.1/abc123def456/data-0.2.1.jar
```

### Search Strategies

**By artifact name**:
```bash
find ~/.gradle/caches -name "data-*.jar"
```

**By specific version**:
```bash
find ~/.gradle/caches -name "data-*.jar" | grep "0.2.1"
```

**By group and artifact**:
```bash
find ~/.gradle/caches/modules-2/files-2.1/com.goecfx/data -name "*.jar"
```

**Recently modified** (useful after build):
```bash
find ~/.gradle/caches -name "data-*.jar" -mtime -1
```

---

## Common Issues and Solutions

### Issue 1: "Error: class not found"

**Symptoms**:
```bash
$ javap -public -cp library.jar com.example.User
Error: class not found: com.example.User
```

**Causes**:
1. Wrong fully qualified name
2. Class not in that JAR
3. Classpath issue

**Solutions**:
```bash
# List all classes in JAR
jar -tf library.jar | grep User

# Search for class files
jar -tf library.jar | grep "\.class$"

# Use correct package name
javap -public -cp library.jar com.correct.package.User
```

---

### Issue 2: JAR Not Found in Cache

**Symptoms**:
```bash
$ find ~/.gradle/caches -name "mylib-*.jar"
# No results
```

**Solutions**:
```bash
# 1. Check dependency is declared
grep "mylib" build.gradle

# 2. Force dependency download
./gradlew dependencies

# 3. Refresh dependencies
./gradlew build --refresh-dependencies

# 4. Check for CodeArtifact auth issues (if private repo)
aws codeartifact get-authorization-token --domain my-domain
```

---

### Issue 3: Generic Type Information Missing

**Symptoms**:
```java
public java.util.List getItems();  // No generic type shown
```

**Solution**:
```bash
# Use -v flag to see signatures
javap -public -v -cp library.jar com.example.ClassName | grep -A 3 "getItems"

# Output:
# public java.util.List<com.example.Item> getItems();
#   descriptor: ()Ljava/util/List;
#   Signature: ()Ljava/util/List<Lcom/example/Item;>;
```

---

### Issue 4: Multiple Versions in Cache

**Symptoms**:
```bash
$ find ~/.gradle/caches -name "data-*.jar"
~/.gradle/caches/.../data-0.1.0.jar
~/.gradle/caches/.../data-0.2.0.jar
~/.gradle/caches/.../data-0.2.1.jar
```

**Solution**:
```bash
# Check which version is actually used
./gradlew dependencies | grep "com.goecfx:data"

# Output:
# +--- com.goecfx:data:0.2.1

# Use that specific version
javap -public -cp ~/.gradle/caches/.../data-0.2.1.jar com.goecfx.data.entities.EmailInboxItem
```

---

## Alternative Inspection Methods

### Method 1: jar Command

**List contents**:
```bash
jar -tf library.jar
```

**Extract and decompile**:
```bash
jar -xf library.jar com/example/User.class
javap -p com/example/User.class
```

### Method 2: IntelliJ IDEA

1. Go to "External Libraries" in Project view
2. Navigate to library JAR
3. Double-click class file
4. IntelliJ shows decompiled source

### Method 3: Gradle Dependency Insight

```bash
# Show dependency tree
./gradlew dependencies --configuration compileClasspath

# Show specific dependency
./gradlew dependencyInsight --dependency data --configuration compileClasspath
```

### Method 4: JD-GUI (GUI Tool)

Download and open JAR files in JD-GUI for graphical source viewing.

---

## Best Practices

### 1. Always Verify Before Implementing
- Don't assume methods exist based on patterns
- Check actual API before writing code
- Document findings in code comments

### 2. Cache Verification Results
- After verifying once, document in project
- Create usage examples in project docs
- Reduces repeated verification overhead

### 3. Automate When Possible
- Create shell scripts for common checks
- Add verification to pre-commit hooks
- Include in CI/CD pipeline

### 4. Keep Documentation Updated
- When libraries update, re-verify APIs
- Document breaking changes
- Update code examples

### 5. Use Version-Specific Verification
- Always specify exact version
- Don't assume APIs are stable across versions
- Check release notes for breaking changes

---

## Troubleshooting Checklist

- [ ] Correct library name and version
- [ ] JAR file exists in Gradle cache
- [ ] Fully qualified class name is correct (including package)
- [ ] `-cp` flag includes full path to JAR
- [ ] Class exists in the JAR (verify with `jar -tf`)
- [ ] Using appropriate javap flags (-public, -v, etc.)
- [ ] For private repos: AWS credentials valid
- [ ] Gradle sync completed successfully
- [ ] Using the version actually declared in build.gradle

---

## Additional Resources

- [javap Documentation](https://docs.oracle.com/en/java/javase/17/docs/specs/man/javap.html)
- [Gradle Dependency Management](https://docs.gradle.org/current/userguide/dependency_management.html)
- [AWS CodeArtifact Gradle Setup](https://docs.aws.amazon.com/codeartifact/latest/ug/maven-gradle.html)
