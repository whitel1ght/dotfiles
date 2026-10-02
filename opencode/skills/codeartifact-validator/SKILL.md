---
name: codeartifact-validator
description: >-
  Validate AWS CodeArtifact access and credentials before builds to prevent cryptic dependency resolution errors. Use before builds, when dependency resolution fails, when setting up a new project with CodeArtifact, or when user mentions AWS CodeArtifact, authentication issues, or build failures related to dependencies.
---


# CodeArtifact Access Validator

Validate that AWS CodeArtifact is properly configured and accessible before attempting builds. This prevents cryptic build errors caused by token generation failures, expired credentials, or misconfigured repositories.

## Problem Solved

CodeArtifact token generation failures lead to confusing Gradle errors like "Could not resolve dependency" or "Unauthorized" without clear root cause. This skill validates the entire authentication chain before build time, saving 15-30 minutes of debugging.

## Critical Concept

**CodeArtifact Authentication Chain**:
1. AWS CLI must be installed and configured with valid credentials
2. Token generation must succeed (valid for 12 hours)
3. Repository URL must be accessible with generated token
4. Specific libraries must be resolvable from the repository

If any step fails, builds fail with unclear error messages.

## Process

### 1. Verify AWS CLI Installation

Check that AWS CLI is installed and accessible:

```bash
which aws
aws --version
```

**Expected output**:
```
/usr/local/bin/aws
aws-cli/2.x.x Python/3.x.x ...
```

**Validation checks**:
- [ ] AWS CLI command found
- [ ] Version 2.x or higher (recommended)

**If AWS CLI not found**:
```bash
# macOS
brew install awscli

# Linux
pip install awscli

# Verify installation
aws --version
```

### 2. Verify AWS Credentials Configuration

Check that AWS credentials are configured:

```bash
aws sts get-caller-identity
```

**Expected output**:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/username"
}
```

**Validation checks**:
- [ ] Command succeeds without error
- [ ] Returns valid AWS account information
- [ ] User has necessary IAM permissions

**Common errors**:

**Error: "Unable to locate credentials"**
```bash
# Configure credentials
aws configure
# Or use environment variables:
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-east-1
```

**Error: "The security token is expired"**
```bash
# Refresh credentials (if using temporary credentials)
aws sts get-session-token
```

### 3. Test CodeArtifact Token Generation

Attempt to generate a CodeArtifact authorization token:

```bash
aws codeartifact get-authorization-token \
  --domain your-domain \
  --domain-owner your-account-id \
  --region your-region \
  --query authorizationToken \
  --output text
```

**How to find these values**:
- Check `build.gradle` for CodeArtifact URL
- URL format: `https://[domain]-[account].d.codeartifact.[region].amazonaws.com/maven/[repo]/`
- Extract domain, account, and region from this URL

**Expected output**:
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
(A long base64-encoded token)

**Validation checks**:
- [ ] Command completes successfully
- [ ] Returns a non-empty token
- [ ] Token is a valid JWT format

**Common errors**:

**Error: "AccessDeniedException"**
- User lacks `codeartifact:GetAuthorizationToken` permission
- Add IAM policy:
```json
{
  "Effect": "Allow",
  "Action": "codeartifact:GetAuthorizationToken",
  "Resource": "arn:aws:codeartifact:REGION:ACCOUNT:domain/DOMAIN"
}
```

**Error: "ResourceNotFoundException"**
- Domain or repository doesn't exist
- Verify domain/account/region values match CodeArtifact configuration

### 4. Validate build.gradle Configuration

Check that CodeArtifact is correctly configured in `build.gradle`:

```bash
# From project root
grep -A 10 "codeartifact" build.gradle
```

**Expected pattern**:
```groovy
repositories {
    maven {
        url = "https://[domain]-[account].d.codeartifact.[region].amazonaws.com/maven/[repo]/"
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "[domain]",
                    "--domain-owner", "[account]",
                    "--region", "[region]",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}
```

**Validation checks**:
- [ ] CodeArtifact URL is correctly formatted
- [ ] Domain, account, region match AWS configuration
- [ ] Token generation command is correct
- [ ] `username = "aws"` (not a custom username)
- [ ] Password uses `providers.exec` for dynamic token generation

**Anti-patterns to avoid**:

**Anti-Pattern 1**: Hardcoded token
```groovy
// ❌ WRONG - token expires after 12 hours
credentials {
    username = "aws"
    password = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Anti-Pattern 2**: Environment variable without refresh
```groovy
// ❌ WRONG - token not refreshed automatically
credentials {
    username = "aws"
    password = System.getenv("CODEARTIFACT_TOKEN")
}
```

**Anti-Pattern 3**: Missing .trim()
```groovy
// ❌ WRONG - may include newline characters
password = providers.exec {...}.standardOutput.asText.get()
```

### 5. Test Repository Accessibility

Verify that the CodeArtifact repository responds correctly:

```bash
# Generate token
TOKEN=$(aws codeartifact get-authorization-token \
  --domain your-domain \
  --domain-owner your-account-id \
  --region your-region \
  --query authorizationToken \
  --output text)

# Test repository access
curl -u "aws:${TOKEN}" \
  "https://[domain]-[account].d.codeartifact.[region].amazonaws.com/maven/[repo]/com/goecfx/data/maven-metadata.xml"
```

**Expected output**:
XML metadata containing available versions of the library

**Validation checks**:
- [ ] HTTP 200 response
- [ ] Valid XML returned
- [ ] Contains expected library versions

**Common errors**:

**Error: 401 Unauthorized**
- Token is invalid or expired
- Regenerate token and retry

**Error: 403 Forbidden**
- User lacks `codeartifact:ReadFromRepository` permission
- Add IAM policy:
```json
{
  "Effect": "Allow",
  "Action": "codeartifact:ReadFromRepository",
  "Resource": "arn:aws:codeartifact:REGION:ACCOUNT:repository/DOMAIN/REPO"
}
```

**Error: 404 Not Found**
- Repository URL is incorrect
- Library doesn't exist in repository

### 6. Verify Specific Library Resolution

Test that the specific library (e.g., `com.goecfx:data`) can be resolved:

```bash
# From project root
./gradlew dependencies --configuration compileClasspath | grep "com.goecfx:data"
```

**Expected output**:
```
|    +--- com.goecfx:data:0.2.1
```

**Validation checks**:
- [ ] Library appears in dependency tree
- [ ] Correct version is resolved
- [ ] No "FAILED" markers

**Common errors**:

**Error: "Could not resolve com.goecfx:data:X.X.X"**
- Library version doesn't exist in repository
- Token generation failed during Gradle sync
- Repository not accessible

**Troubleshooting steps**:
1. Verify library exists: Check CodeArtifact console
2. Test token generation manually (step 3)
3. Clear Gradle cache: `./gradlew --refresh-dependencies`
4. Try with `--debug` flag for detailed logs

### 7. Generate Validation Report

Create a comprehensive report:

```markdown
## CodeArtifact Access Validation Report

**Date**: [timestamp]
**Project**: [project name]

### AWS CLI Status
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ AWS CLI installed: version X.X.X
- [ ] ✅ AWS credentials configured
- [ ] ✅ Account ID: XXXXXXXXXXXX
- [ ] ✅ User has necessary permissions

**Issues Found**: [None] / [List issues]

### Token Generation Status
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ Domain: [domain]
- [ ] ✅ Account: [account-id]
- [ ] ✅ Region: [region]
- [ ] ✅ Token generated successfully
- [ ] ✅ Token length: [XXX] characters

**Issues Found**: [None] / [List issues]

### build.gradle Configuration
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ CodeArtifact URL correctly formatted
- [ ] ✅ Dynamic token generation configured
- [ ] ✅ Uses providers.exec pattern
- [ ] ✅ Includes .trim() call

**Issues Found**: [None] / [List issues]

### Repository Access Status
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ Repository responds to authentication
- [ ] ✅ Maven metadata accessible
- [ ] ✅ Expected library versions available

**Issues Found**: [None] / [List issues]

### Library Resolution Status
**Status**: ✅ VALID / ❌ INVALID

**Findings**:
- [ ] ✅ com.goecfx:data:[version] resolves correctly
- [ ] ✅ No dependency resolution errors
- [ ] ✅ Library downloadable

**Issues Found**: [None] / [List issues]

### Overall Assessment
**Result**: ✅ CODEARTIFACT READY / ❌ CONFIGURATION ERRORS

**Build Safety**: SAFE TO BUILD / FIX ISSUES BEFORE BUILD

### Recommendations
[List specific fixes needed, or confirm ready to build]
```

### 8. Provide Setup Guidance

If CodeArtifact is not configured, provide complete setup instructions:

**Step 1: Install AWS CLI**
```bash
# macOS
brew install awscli

# Verify
aws --version
```

**Step 2: Configure AWS Credentials**
```bash
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (e.g., us-east-1)
# - Default output format (json)
```

**Step 3: Verify Permissions**
Required IAM permissions:
- `codeartifact:GetAuthorizationToken`
- `codeartifact:ReadFromRepository`
- `sts:GetServiceBearerToken`

**Step 4: Add to build.gradle**
```groovy
repositories {
    mavenCentral()
    maven {
        url = "https://[your-domain]-[your-account].d.codeartifact.[region].amazonaws.com/maven/[your-repo]/"
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "[your-domain]",
                    "--domain-owner", "[your-account]",
                    "--region", "[region]",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}
```

**Step 5: Test Configuration**
```bash
./gradlew dependencies --refresh-dependencies
```

## Quality Checklist

- [ ] AWS CLI installation verified
- [ ] AWS credentials validated
- [ ] Token generation tested successfully
- [ ] build.gradle configuration inspected
- [ ] Repository accessibility confirmed
- [ ] Specific library resolution tested
- [ ] Report clearly identifies all issues
- [ ] Setup guidance provided if needed
- [ ] Specific corrective actions for each issue

## When to Use This Skill

**Always use when**:
- Setting up a new project with CodeArtifact
- First build attempt in a new environment
- "Could not resolve dependency" errors occur
- After AWS credential changes or rotation
- When onboarding new developers

**Warning signs that indicate need**:
- Error: "Could not resolve com.goecfx:data"
- Error: "Unauthorized" during Gradle sync
- Error: "Unable to load Maven meta-data"
- Build works for some team members but not others
- Build worked yesterday but fails today

**Preventative use**:
- Before first build in CI/CD pipeline
- After modifying build.gradle dependencies
- When AWS credentials are rotated
- Monthly validation of access

## Token Lifecycle Management

**Token Validity**: 12 hours
**Auto-refresh**: Gradle regenerates on each build
**Best Practice**: Don't cache tokens outside Gradle

**Troubleshooting expired tokens**:
```bash
# Token age doesn't matter - Gradle generates fresh token each build
# If seeing auth errors, problem is NOT expired token but:
# 1. Credentials expired/invalid
# 2. IAM permissions revoked
# 3. Repository configuration changed
```

## Special Cases

**Multiple CodeArtifact Repositories**: Validate each separately
```groovy
repositories {
    maven {
        name = "codeartifact-libs"
        url = "https://..."
        credentials { /* ... */ }
    }
    maven {
        name = "codeartifact-plugins"
        url = "https://..."
        credentials { /* ... */ }
    }
}
```

**Cross-Account Access**: Verify resource policy allows access
```bash
aws codeartifact get-repository-permissions-policy \
  --domain your-domain \
  --repository your-repo
```

**VPC/Private Access**: Verify network connectivity
```bash
# Test from build environment
curl -I https://[domain]-[account].d.codeartifact.[region].amazonaws.com
```

**CI/CD Environment**: Ensure build agents have AWS credentials configured via:
- IAM role (recommended)
- Environment variables
- AWS credentials file

## Expected Behavior When Correct

When configuration is correct:

1. **Gradle sync**:
   ```bash
   ./gradlew dependencies
   ```

2. **Token auto-generated**:
   ```
   > Task :dependencies
   Executing: aws codeartifact get-authorization-token...
   ```

3. **Dependencies resolved**:
   ```
   compileClasspath - Compile classpath for source set 'main'.
   +--- com.goecfx:data:0.2.1
   ```

4. **Build succeeds**:
   ```bash
   ./gradlew build
   BUILD SUCCESSFUL
   ```

---

For detailed troubleshooting examples, see `examples.md`
For IAM policy templates, see `reference.md`
