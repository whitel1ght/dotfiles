# CodeArtifact Validator - Examples

## Example 1: Complete Validation - All Checks Pass

**Scenario**: Developer setting up project for first time

**Commands executed**:

```bash
# Step 1: Check AWS CLI
$ which aws
/usr/local/bin/aws

$ aws --version
aws-cli/2.13.0 Python/3.11.4 Darwin/23.0.0

# Step 2: Check credentials
$ aws sts get-caller-identity
{
    "UserId": "AIDAI23EXAMPLE456ABC",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/john.doe"
}

# Step 3: Test token generation
$ aws codeartifact get-authorization-token \
  --domain goecfx \
  --domain-owner 123456789012 \
  --region us-east-1 \
  --query authorizationToken \
  --output text
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MzAwMDAwMDAsImlhdCI6MTcyOTk1NjgwMCwibmJmIjoxNzI5OTU2ODAwLCJzdWIiOiJhd3MifQ.dGVzdC10b2tlbi1kYXRh

# Step 4: Check build.gradle
$ grep -A 15 "codeartifact" build.gradle
repositories {
    mavenCentral()
    maven {
        url = "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/"
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "goecfx",
                    "--domain-owner", "123456789012",
                    "--region", "us-east-1",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}

# Step 5: Test repository access
$ TOKEN=$(aws codeartifact get-authorization-token --domain goecfx --domain-owner 123456789012 --region us-east-1 --query authorizationToken --output text)

$ curl -u "aws:${TOKEN}" "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/com/goecfx/data/maven-metadata.xml"
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>com.goecfx</groupId>
  <artifactId>data</artifactId>
  <versioning>
    <latest>0.2.1</latest>
    <release>0.2.1</release>
    <versions>
      <version>0.1.0</version>
      <version>0.2.0</version>
      <version>0.2.1</version>
    </versions>
    <lastUpdated>20250127120000</lastUpdated>
  </versioning>
</metadata>

# Step 6: Test library resolution
$ ./gradlew dependencies --configuration compileClasspath | grep "com.goecfx:data"
|    +--- com.goecfx:data:0.2.1
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:15:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ✅ VALID

**Findings**:
- ✅ AWS CLI installed: version 2.13.0
- ✅ AWS credentials configured
- ✅ Account ID: 123456789012
- ✅ User: john.doe

**Issues Found**: None

### Token Generation Status
**Status**: ✅ VALID

**Findings**:
- ✅ Domain: goecfx
- ✅ Account: 123456789012
- ✅ Region: us-east-1
- ✅ Token generated successfully
- ✅ Token length: 156 characters

**Issues Found**: None

### build.gradle Configuration
**Status**: ✅ VALID

**Findings**:
- ✅ CodeArtifact URL correctly formatted
- ✅ Dynamic token generation configured
- ✅ Uses providers.exec pattern
- ✅ Includes .trim() call

**Issues Found**: None

### Repository Access Status
**Status**: ✅ VALID

**Findings**:
- ✅ Repository responds to authentication
- ✅ Maven metadata accessible
- ✅ Versions 0.1.0, 0.2.0, 0.2.1 available

**Issues Found**: None

### Library Resolution Status
**Status**: ✅ VALID

**Findings**:
- ✅ com.goecfx:data:0.2.1 resolves correctly
- ✅ No dependency resolution errors
- ✅ Library downloadable

**Issues Found**: None

### Overall Assessment
**Result**: ✅ CODEARTIFACT READY

**Build Safety**: SAFE TO BUILD

### Recommendations
Configuration is optimal. Proceed with build.
```

---

## Example 2: Missing AWS CLI

**Scenario**: New developer machine without AWS CLI

**Commands executed**:

```bash
$ which aws
# (no output - command not found)

$ aws --version
-bash: aws: command not found
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:20:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ❌ INVALID

**Findings**:
- ❌ AWS CLI not found in PATH

**Issues Found**:
1. AWS CLI is not installed

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS

**Build Safety**: DO NOT BUILD - INSTALL AWS CLI FIRST

### Recommendations

**Install AWS CLI**:

macOS:
```bash
brew install awscli
```

Linux:
```bash
pip install awscli
```

Windows:
```powershell
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

**Verify installation**:
```bash
aws --version
```

**Next steps**:
1. Install AWS CLI
2. Configure credentials: `aws configure`
3. Re-run validation
```

---

## Example 3: Invalid/Expired Credentials

**Scenario**: Credentials expired or not configured

**Commands executed**:

```bash
$ aws --version
aws-cli/2.13.0 Python/3.11.4 Darwin/23.0.0

$ aws sts get-caller-identity
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:25:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ❌ INVALID

**Findings**:
- ✅ AWS CLI installed: version 2.13.0
- ❌ AWS credentials not configured

**Issues Found**:
1. Unable to locate AWS credentials

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS

**Build Safety**: DO NOT BUILD - CONFIGURE CREDENTIALS FIRST

### Recommendations

**Configure AWS credentials**:

```bash
aws configure
```

You will be prompted for:
- AWS Access Key ID: [Get from AWS Console > IAM > Users]
- AWS Secret Access Key: [Provided when key created]
- Default region: us-east-1 (or your CodeArtifact region)
- Default output format: json

**Alternative: Environment variables**:
```bash
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_DEFAULT_REGION=us-east-1
```

**Verify credentials**:
```bash
aws sts get-caller-identity
```

**Next steps**:
1. Configure credentials
2. Re-run validation
```

---

## Example 4: IAM Permission Issues

**Scenario**: User has AWS credentials but lacks CodeArtifact permissions

**Commands executed**:

```bash
$ aws sts get-caller-identity
{
    "UserId": "AIDAI23EXAMPLE456ABC",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/jane.smith"
}

$ aws codeartifact get-authorization-token \
  --domain goecfx \
  --domain-owner 123456789012 \
  --region us-east-1 \
  --query authorizationToken \
  --output text

An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation: User: arn:aws:iam::123456789012:user/jane.smith is not authorized to perform: codeartifact:GetAuthorizationToken on resource: arn:aws:codeartifact:us-east-1:123456789012:domain/goecfx
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:30:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ✅ VALID

**Findings**:
- ✅ AWS CLI installed: version 2.13.0
- ✅ AWS credentials configured
- ✅ Account ID: 123456789012
- ✅ User: jane.smith

**Issues Found**: None

### Token Generation Status
**Status**: ❌ INVALID

**Findings**:
- ✅ Domain: goecfx
- ✅ Account: 123456789012
- ✅ Region: us-east-1
- ❌ AccessDeniedException: Missing codeartifact:GetAuthorizationToken permission

**Issues Found**:
1. User lacks CodeArtifact permissions

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS

**Build Safety**: DO NOT BUILD - IAM PERMISSIONS REQUIRED

### Recommendations

**Required IAM Policy**:

Contact your AWS administrator to attach this policy to your IAM user or role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codeartifact:GetAuthorizationToken",
        "codeartifact:ReadFromRepository",
        "codeartifact:DescribeRepository",
        "codeartifact:ListPackages"
      ],
      "Resource": [
        "arn:aws:codeartifact:us-east-1:123456789012:domain/goecfx",
        "arn:aws:codeartifact:us-east-1:123456789012:repository/goecfx/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetServiceBearerToken",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "sts:AWSServiceName": "codeartifact.amazonaws.com"
        }
      }
    }
  ]
}
```

**Quick policy name**: `CodeArtifactDeveloperAccess`

**Next steps**:
1. Request IAM policy attachment from AWS admin
2. Wait for policy propagation (usually immediate)
3. Re-run validation
```

---

## Example 5: Incorrect build.gradle Configuration

**Scenario**: build.gradle has hardcoded token (anti-pattern)

**Commands executed**:

```bash
$ aws sts get-caller-identity
{
    "UserId": "AIDAI23EXAMPLE456ABC",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/john.doe"
}

$ aws codeartifact get-authorization-token \
  --domain goecfx \
  --domain-owner 123456789012 \
  --region us-east-1 \
  --query authorizationToken \
  --output text
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

$ grep -A 10 "codeartifact" build.gradle
repositories {
    maven {
        url = "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/"
        credentials {
            username = "aws"
            password = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.OLD_HARDCODED_TOKEN"
        }
    }
}
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:35:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ✅ VALID

**Findings**:
- ✅ AWS CLI installed: version 2.13.0
- ✅ AWS credentials configured
- ✅ Account ID: 123456789012

**Issues Found**: None

### Token Generation Status
**Status**: ✅ VALID

**Findings**:
- ✅ Token generated successfully

**Issues Found**: None

### build.gradle Configuration
**Status**: ❌ INVALID

**Findings**:
- ✅ CodeArtifact URL correctly formatted
- ❌ Hardcoded token in credentials block
- ❌ Token will expire after 12 hours
- ❌ Not using dynamic token generation

**Issues Found**:
1. **CRITICAL**: Hardcoded token will cause build failures after expiration
2. Missing dynamic token generation with providers.exec

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS

**Build Safety**: BUILDS WILL FAIL AFTER TOKEN EXPIRES

### Recommendations

**Fix build.gradle** - Replace hardcoded token with dynamic generation:

**Current (WRONG)**:
```groovy
repositories {
    maven {
        url = "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/"
        credentials {
            username = "aws"
            password = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.OLD_HARDCODED_TOKEN"
        }
    }
}
```

**Corrected (RIGHT)**:
```groovy
repositories {
    maven {
        url = "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/"
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "goecfx",
                    "--domain-owner", "123456789012",
                    "--region", "us-east-1",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}
```

**Why this matters**:
- CodeArtifact tokens expire after 12 hours
- Dynamic generation ensures fresh token on every build
- No manual token refresh needed

**Next steps**:
1. Update build.gradle with correct configuration
2. Test with: `./gradlew dependencies --refresh-dependencies`
3. Re-run validation
```

---

## Example 6: Library Not Found in Repository

**Scenario**: Library doesn't exist or version is wrong

**Commands executed**:

```bash
$ ./gradlew dependencies --configuration compileClasspath | grep "com.goecfx:data"
FAILURE: Build failed with an exception.

* What went wrong:
Could not resolve all files for configuration ':compileClasspath'.
> Could not resolve com.goecfx:data:0.3.0.
  Required by:
      project :
   > Could not resolve com.goecfx:data:0.3.0.
      > Could not get resource 'https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/com/goecfx/data/0.3.0/data-0.3.0.pom'.
         > Could not GET 'https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/com/goecfx/data/0.3.0/data-0.3.0.pom'. Received status code 404 from server: Not Found

$ curl -u "aws:${TOKEN}" "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/com/goecfx/data/maven-metadata.xml"
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>com.goecfx</groupId>
  <artifactId>data</artifactId>
  <versioning>
    <latest>0.2.1</latest>
    <release>0.2.1</release>
    <versions>
      <version>0.1.0</version>
      <version>0.2.0</version>
      <version>0.2.1</version>
    </versions>
    <lastUpdated>20250127120000</lastUpdated>
  </versioning>
</metadata>
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:40:00
**Project**: receipt_processing_web

### AWS CLI Status
**Status**: ✅ VALID

### Token Generation Status
**Status**: ✅ VALID

### build.gradle Configuration
**Status**: ✅ VALID

### Repository Access Status
**Status**: ✅ VALID

**Findings**:
- ✅ Repository accessible
- ✅ Maven metadata retrieved
- ✅ Available versions: 0.1.0, 0.2.0, 0.2.1

### Library Resolution Status
**Status**: ❌ INVALID

**Findings**:
- ❌ com.goecfx:data:0.3.0 NOT FOUND
- ✅ Repository accessible
- ❌ Requested version does not exist

**Issues Found**:
1. **Version mismatch**: Requesting 0.3.0, but only 0.1.0, 0.2.0, 0.2.1 available

### Overall Assessment
**Result**: ❌ CONFIGURATION ERRORS

**Build Safety**: BUILD WILL FAIL - WRONG VERSION

### Recommendations

**Fix build.gradle** - Update to available version:

**Current (WRONG)**:
```groovy
dependencies {
    implementation "com.goecfx:data:0.3.0"  // Does not exist
}
```

**Corrected (RIGHT)**:
```groovy
dependencies {
    implementation "com.goecfx:data:0.2.1"  // Latest available
}
```

**Available versions**:
- 0.1.0 (old)
- 0.2.0 (previous)
- 0.2.1 (latest) ⭐ **Recommended**

**If you need 0.3.0**:
1. Check with library maintainer if 0.3.0 is published
2. Verify you're checking the correct repository
3. Consider if 0.2.1 meets your requirements

**Next steps**:
1. Update build.gradle to use available version
2. Test with: `./gradlew dependencies --refresh-dependencies`
3. Re-run validation
```

---

## Example 7: Network/VPC Issues

**Scenario**: Build environment can't reach CodeArtifact endpoint

**Commands executed**:

```bash
$ aws sts get-caller-identity
{
    "UserId": "AIDAI23EXAMPLE456ABC",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/ci-builder"
}

$ aws codeartifact get-authorization-token \
  --domain goecfx \
  --domain-owner 123456789012 \
  --region us-east-1 \
  --query authorizationToken \
  --output text
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

$ curl -I "https://goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com/maven/ecfx-libs/"
curl: (6) Could not resolve host: goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com
```

**Validation Report**:

```markdown
## CodeArtifact Access Validation Report

**Date**: 2025-10-27 10:45:00
**Project**: receipt_processing_web (CI Environment)

### AWS CLI Status
**Status**: ✅ VALID

### Token Generation Status
**Status**: ✅ VALID

### Repository Access Status
**Status**: ❌ INVALID

**Findings**:
- ❌ Cannot resolve CodeArtifact hostname
- ❌ Network connectivity issue

**Issues Found**:
1. **DNS resolution failure**: Cannot reach CodeArtifact endpoint
2. Possible VPC/network restriction

### Overall Assessment
**Result**: ❌ NETWORK ERRORS

**Build Safety**: BUILD WILL FAIL - NETWORK UNREACHABLE

### Recommendations

**Diagnose network issue**:

1. **Check DNS resolution**:
```bash
nslookup goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com
```

2. **Check network connectivity**:
```bash
ping goecfx-123456789012.d.codeartifact.us-east-1.amazonaws.com
```

3. **Check VPC endpoint configuration** (if using private VPC):
```bash
aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=com.amazonaws.us-east-1.codeartifact.api"
```

**Common causes**:
- CI/CD runner in private subnet without NAT gateway
- VPC endpoint not configured for CodeArtifact
- Security group blocking HTTPS egress
- Network firewall rules

**Solutions**:

**Option 1: Configure VPC endpoint**:
- Create VPC endpoint for CodeArtifact (com.amazonaws.REGION.codeartifact.api)
- Create VPC endpoint for CodeArtifact repositories (com.amazonaws.REGION.codeartifact.repositories)
- Update security groups to allow access

**Option 2: Enable NAT gateway**:
- Add NAT gateway to VPC
- Update route tables to route 0.0.0.0/0 through NAT

**Option 3: Move to public subnet** (if appropriate):
- Update CI/CD runner configuration
- Ensure security group allows HTTPS egress

**Next steps**:
1. Work with network team to resolve connectivity
2. Verify DNS resolution
3. Re-run validation from build environment
```

---

## Example 8: CI/CD Pipeline Setup

**Scenario**: Setting up GitHub Actions with IAM role

**GitHub Actions Workflow**:

```yaml
name: Build

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsCodeArtifact
          aws-region: us-east-1

      - name: Validate CodeArtifact access
        run: |
          # Run validation skill
          aws sts get-caller-identity
          aws codeartifact get-authorization-token \
            --domain goecfx \
            --domain-owner 123456789012 \
            --region us-east-1 \
            --query authorizationToken \
            --output text

      - name: Build with Gradle
        run: ./gradlew build
```

**IAM Role Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:*"
        }
      }
    }
  ]
}
```

**IAM Role Permissions Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codeartifact:GetAuthorizationToken",
        "codeartifact:ReadFromRepository",
        "codeartifact:DescribeRepository"
      ],
      "Resource": [
        "arn:aws:codeartifact:us-east-1:123456789012:domain/goecfx",
        "arn:aws:codeartifact:us-east-1:123456789012:repository/goecfx/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetServiceBearerToken",
      "Resource": "*"
    }
  ]
}
```

**Validation Output**:

```
Run aws sts get-caller-identity
{
    "UserId": "AROAI23EXAMPLE456ABC:GitHubActions",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/GitHubActionsCodeArtifact/GitHubActions"
}

Run aws codeartifact get-authorization-token...
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

Run ./gradlew build
> Task :test
> Task :build
BUILD SUCCESSFUL in 2m 15s
```
