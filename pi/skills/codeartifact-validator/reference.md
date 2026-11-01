# CodeArtifact Validator - Reference

## AWS CodeArtifact Overview

AWS CodeArtifact is a fully managed artifact repository service that makes it easy to securely store, publish, and share software packages used in software development.

**Key Concepts**:
- **Domain**: Top-level organizational entity (e.g., "goecfx")
- **Repository**: Package repository within a domain (e.g., "ecfx-libs")
- **Package**: Individual library or artifact (e.g., "com.goecfx:data:0.2.1")
- **Authorization Token**: Time-limited JWT for authentication (12-hour validity)

**Supported Package Formats**:
- Maven (Java, Kotlin, Scala)
- npm (JavaScript, TypeScript)
- PyPI (Python)
- NuGet (.NET)

## IAM Policies

### Minimal Developer Access Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CodeArtifactTokenGeneration",
      "Effect": "Allow",
      "Action": [
        "codeartifact:GetAuthorizationToken"
      ],
      "Resource": "arn:aws:codeartifact:REGION:ACCOUNT_ID:domain/DOMAIN_NAME"
    },
    {
      "Sid": "CodeArtifactReadAccess",
      "Effect": "Allow",
      "Action": [
        "codeartifact:ReadFromRepository",
        "codeartifact:DescribeRepository",
        "codeartifact:GetPackageVersionAsset",
        "codeartifact:GetPackageVersionReadme",
        "codeartifact:GetRepositoryEndpoint",
        "codeartifact:ListPackages",
        "codeartifact:ListPackageVersions",
        "codeartifact:ListPackageVersionAssets",
        "codeartifact:ListPackageVersionDependencies"
      ],
      "Resource": [
        "arn:aws:codeartifact:REGION:ACCOUNT_ID:repository/DOMAIN_NAME/*",
        "arn:aws:codeartifact:REGION:ACCOUNT_ID:package/DOMAIN_NAME/*/*/*/*"
      ]
    },
    {
      "Sid": "STSServiceBearerToken",
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

**Replace placeholders**:
- `REGION`: e.g., `us-east-1`
- `ACCOUNT_ID`: Your 12-digit AWS account ID
- `DOMAIN_NAME`: Your CodeArtifact domain name

### Publisher Access Policy (CI/CD)

Adds publishing permissions for CI/CD pipelines:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CodeArtifactPublish",
      "Effect": "Allow",
      "Action": [
        "codeartifact:PublishPackageVersion",
        "codeartifact:PutPackageMetadata"
      ],
      "Resource": "arn:aws:codeartifact:REGION:ACCOUNT_ID:package/DOMAIN_NAME/*/*/*/*/*"
    }
  ]
}
```

### Admin Access Policy

Full management permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CodeArtifactFullAccess",
      "Effect": "Allow",
      "Action": [
        "codeartifact:*"
      ],
      "Resource": [
        "arn:aws:codeartifact:REGION:ACCOUNT_ID:domain/DOMAIN_NAME",
        "arn:aws:codeartifact:REGION:ACCOUNT_ID:repository/DOMAIN_NAME/*"
      ]
    },
    {
      "Sid": "STSServiceBearerToken",
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

## Gradle Configuration Patterns

### Standard Maven Configuration (Recommended)

```groovy
repositories {
    mavenCentral()  // Fallback for public dependencies

    maven {
        name = "codeartifact"
        url = uri("https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com/maven/REPOSITORY/")
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "DOMAIN",
                    "--domain-owner", "ACCOUNT",
                    "--region", "REGION",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}
```

### Multiple Repositories

```groovy
repositories {
    mavenCentral()

    maven {
        name = "codeartifact-libs"
        url = uri("https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com/maven/libs/")
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "DOMAIN",
                    "--domain-owner", "ACCOUNT",
                    "--region", "REGION",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }

    maven {
        name = "codeartifact-plugins"
        url = uri("https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com/maven/plugins/")
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine("aws", "codeartifact", "get-authorization-token",
                    "--domain", "DOMAIN",
                    "--domain-owner", "ACCOUNT",
                    "--region", "REGION",
                    "--query", "authorizationToken",
                    "--output", "text")
            }.standardOutput.asText.get().trim()
        }
    }
}
```

### Kotlin DSL Configuration

```kotlin
repositories {
    mavenCentral()

    maven {
        name = "codeartifact"
        url = uri("https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com/maven/REPOSITORY/")
        credentials {
            username = "aws"
            password = providers.exec {
                commandLine(
                    "aws", "codeartifact", "get-authorization-token",
                    "--domain", "DOMAIN",
                    "--domain-owner", "ACCOUNT",
                    "--region", "REGION",
                    "--query", "authorizationToken",
                    "--output", "text"
                )
            }.standardOutput.asText.get().trim()
        }
    }
}
```

### Repository Resolution Order

Repositories are searched in order. For optimal performance:

```groovy
repositories {
    // 1. Private CodeArtifact first (project-specific dependencies)
    maven {
        name = "codeartifact"
        url = uri("https://...")
        credentials { /* ... */ }
    }

    // 2. Maven Central last (fallback for public dependencies)
    mavenCentral()

    // Note: CodeArtifact can proxy Maven Central, eliminating need for direct access
}
```

### Publishing Configuration

For CI/CD pipelines that publish artifacts:

```groovy
plugins {
    id 'maven-publish'
}

publishing {
    publications {
        maven(MavenPublication) {
            from components.java

            groupId = 'com.goecfx'
            artifactId = 'data'
            version = '0.2.1'
        }
    }

    repositories {
        maven {
            name = "codeartifact"
            url = uri("https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com/maven/REPOSITORY/")
            credentials {
                username = "aws"
                password = providers.exec {
                    commandLine("aws", "codeartifact", "get-authorization-token",
                        "--domain", "DOMAIN",
                        "--domain-owner", "ACCOUNT",
                        "--region", "REGION",
                        "--query", "authorizationToken",
                        "--output", "text")
                }.standardOutput.asText.get().trim()
            }
        }
    }
}
```

## AWS CLI Commands Reference

### Token Generation

```bash
# Basic token generation
aws codeartifact get-authorization-token \
  --domain DOMAIN \
  --domain-owner ACCOUNT_ID \
  --region REGION \
  --query authorizationToken \
  --output text

# With specific duration (default: 12 hours, max: 12 hours)
aws codeartifact get-authorization-token \
  --domain DOMAIN \
  --domain-owner ACCOUNT_ID \
  --region REGION \
  --duration-seconds 43200 \
  --query authorizationToken \
  --output text

# Store in variable
TOKEN=$(aws codeartifact get-authorization-token \
  --domain DOMAIN \
  --domain-owner ACCOUNT_ID \
  --region REGION \
  --query authorizationToken \
  --output text)
```

### Repository Information

```bash
# List repositories in domain
aws codeartifact list-repositories-in-domain \
  --domain DOMAIN \
  --domain-owner ACCOUNT_ID \
  --region REGION

# Describe specific repository
aws codeartifact describe-repository \
  --domain DOMAIN \
  --repository REPOSITORY \
  --domain-owner ACCOUNT_ID \
  --region REGION

# Get repository endpoint
aws codeartifact get-repository-endpoint \
  --domain DOMAIN \
  --repository REPOSITORY \
  --format maven \
  --domain-owner ACCOUNT_ID \
  --region REGION
```

### Package Management

```bash
# List packages in repository
aws codeartifact list-packages \
  --domain DOMAIN \
  --repository REPOSITORY \
  --domain-owner ACCOUNT_ID \
  --region REGION

# List versions of specific package
aws codeartifact list-package-versions \
  --domain DOMAIN \
  --repository REPOSITORY \
  --format maven \
  --namespace com.goecfx \
  --package data \
  --domain-owner ACCOUNT_ID \
  --region REGION

# Get package version details
aws codeartifact describe-package-version \
  --domain DOMAIN \
  --repository REPOSITORY \
  --format maven \
  --namespace com.goecfx \
  --package data \
  --package-version 0.2.1 \
  --domain-owner ACCOUNT_ID \
  --region REGION
```

### Permission Management

```bash
# Get repository permissions policy
aws codeartifact get-repository-permissions-policy \
  --domain DOMAIN \
  --repository REPOSITORY \
  --domain-owner ACCOUNT_ID \
  --region REGION

# Put repository permissions policy
aws codeartifact put-repository-permissions-policy \
  --domain DOMAIN \
  --repository REPOSITORY \
  --policy-document file://policy.json \
  --domain-owner ACCOUNT_ID \
  --region REGION

# Delete repository permissions policy
aws codeartifact delete-repository-permissions-policy \
  --domain DOMAIN \
  --repository REPOSITORY \
  --domain-owner ACCOUNT_ID \
  --region REGION
```

## Token Lifecycle

### Token Validity

- **Duration**: 12 hours (43,200 seconds)
- **Maximum**: 12 hours (cannot be extended)
- **Format**: JWT (JSON Web Token)
- **Storage**: Never commit tokens to version control

### Token Expiration Handling

**Gradle Behavior**:
- Generates fresh token on each build
- No caching of tokens across builds
- No manual refresh needed

**Manual Usage**:
```bash
# Check token expiration (decode JWT)
echo "TOKEN_HERE" | cut -d. -f2 | base64 -d | jq '.exp'

# Compare with current time
date +%s
```

### Token Caching (Not Recommended)

While technically possible, token caching is **not recommended**:

```groovy
// ❌ DON'T DO THIS - Can cause intermittent failures
def tokenFile = file("${System.getProperty('user.home')}/.codeartifact-token")
def token = tokenFile.exists() ? tokenFile.text : generateToken()
```

**Problems**:
- Builds fail when cached token expires
- Requires manual refresh logic
- Adds complexity without benefit
- Gradle `providers.exec` is already efficient

## Network Configuration

### VPC Endpoints

For private network access without internet gateway:

**Create VPC endpoint for CodeArtifact API**:
```bash
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-XXXXXXXXX \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.REGION.codeartifact.api \
  --subnet-ids subnet-XXXXXXXXX \
  --security-group-ids sg-XXXXXXXXX
```

**Create VPC endpoint for CodeArtifact Repositories**:
```bash
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-XXXXXXXXX \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.REGION.codeartifact.repositories \
  --subnet-ids subnet-XXXXXXXXX \
  --security-group-ids sg-XXXXXXXXX
```

**Security group requirements**:
- Inbound: HTTPS (port 443) from VPC CIDR
- Outbound: HTTPS (port 443) to CodeArtifact endpoints

### DNS Resolution

**Public endpoint**:
```
DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com
```

**VPC endpoint (private DNS)**:
```
*.codeartifact.REGION.amazonaws.com
```

**Test DNS resolution**:
```bash
nslookup DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com
dig DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com
```

## Troubleshooting Checklist

### Build Failures

**Symptom**: `Could not resolve com.goecfx:data:X.X.X`

**Check in order**:
1. ✓ AWS CLI installed: `aws --version`
2. ✓ Credentials configured: `aws sts get-caller-identity`
3. ✓ Token generation works: `aws codeartifact get-authorization-token ...`
4. ✓ build.gradle has correct URL and credentials block
5. ✓ Library version exists in repository
6. ✓ Network connectivity to CodeArtifact endpoint
7. ✓ Gradle cache not corrupted: `./gradlew --refresh-dependencies`

### Authentication Failures

**Symptom**: `401 Unauthorized` or `AccessDenied`

**Check in order**:
1. ✓ IAM permissions include `codeartifact:GetAuthorizationToken`
2. ✓ IAM permissions include `codeartifact:ReadFromRepository`
3. ✓ IAM permissions include `sts:GetServiceBearerToken`
4. ✓ Domain and repository names are correct
5. ✓ Account ID matches repository owner
6. ✓ Token is being regenerated (not cached)

### Network Failures

**Symptom**: `Could not GET` or `Connection refused`

**Check in order**:
1. ✓ DNS resolution: `nslookup DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com`
2. ✓ Network connectivity: `curl -I https://DOMAIN-ACCOUNT.d.codeartifact.REGION.amazonaws.com`
3. ✓ VPC endpoints configured (if using private network)
4. ✓ Security groups allow HTTPS egress
5. ✓ No proxy configuration interfering
6. ✓ Firewall rules allow AWS service access

## CI/CD Integration Patterns

### GitHub Actions (OIDC)

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: arn:aws:iam::ACCOUNT:role/GitHubActionsRole
    aws-region: REGION

- name: Build with Gradle
  run: ./gradlew build
```

### GitLab CI (IAM Role)

```yaml
build:
  image: gradle:jdk17
  before_script:
    - apt-get update && apt-get install -y awscli
    - aws sts get-caller-identity
  script:
    - ./gradlew build
  variables:
    AWS_DEFAULT_REGION: REGION
```

### Jenkins (IAM Role or Credentials)

```groovy
pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'REGION'
    }

    stages {
        stage('Build') {
            steps {
                withAWS(role: 'JenkinsCodeArtifactRole', roleAccount: 'ACCOUNT') {
                    sh './gradlew build'
                }
            }
        }
    }
}
```

### Docker Build

```dockerfile
FROM gradle:8.5-jdk17 AS builder

# Install AWS CLI
RUN apt-get update && \
    apt-get install -y awscli && \
    rm -rf /var/lib/apt/lists/*

# Verify AWS CLI
RUN aws --version

WORKDIR /app
COPY . .

# Build (will use AWS credentials from environment)
RUN ./gradlew build --no-daemon
```

**Running with credentials**:
```bash
docker build \
  --build-arg AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --build-arg AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  --build-arg AWS_DEFAULT_REGION=us-east-1 \
  -t myapp .
```

## Official Documentation Links

**AWS CodeArtifact**:
- [CodeArtifact User Guide](https://docs.aws.amazon.com/codeartifact/latest/ug/welcome.html)
- [Working with Maven](https://docs.aws.amazon.com/codeartifact/latest/ug/maven-mvn.html)
- [Authentication and Tokens](https://docs.aws.amazon.com/codeartifact/latest/ug/tokens-authentication.html)
- [IAM Permissions](https://docs.aws.amazon.com/codeartifact/latest/ug/auth-and-access-control-iam-identity-based-access-control.html)

**Gradle**:
- [Declaring Repositories](https://docs.gradle.org/current/userguide/declaring_repositories.html)
- [Provider API](https://docs.gradle.org/current/userguide/provider_api.html)
- [Maven Repository Authentication](https://docs.gradle.org/current/userguide/declaring_repositories.html#sec:authentication_schemes)

**AWS CLI**:
- [CodeArtifact CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/codeartifact/)
- [Configuration and Credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)

## Cost Optimization

**Free Tier**:
- 2 GB storage per month
- 100 GB data transfer per month

**Beyond Free Tier**:
- Storage: $0.05 per GB per month
- Data transfer: $0.09 per GB out to internet
- No charges for API calls

**Optimization strategies**:
1. Enable package version deletion for old versions
2. Use upstream repositories to proxy public packages (reduces storage)
3. Configure lifecycle policies to auto-delete old packages
4. Monitor usage with CloudWatch metrics

**Cost monitoring**:
```bash
# Get repository size
aws codeartifact describe-repository \
  --domain DOMAIN \
  --repository REPOSITORY \
  --region REGION \
  | jq '.repository.externalConnections'
```

## Security Best Practices

1. **Use IAM roles instead of access keys** (especially in CI/CD)
2. **Enable CloudTrail logging** for audit trail
3. **Implement least privilege IAM policies**
4. **Use VPC endpoints** for private network access
5. **Never commit tokens** to version control
6. **Rotate access keys regularly** (if using)
7. **Use resource policies** for cross-account access
8. **Enable package version immutability** when needed
9. **Monitor access patterns** with CloudWatch
10. **Use domain resource policies** for organizational boundaries
