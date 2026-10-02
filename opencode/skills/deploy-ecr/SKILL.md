---
name: deploy-ecr
description: >-
  Build and push a containerized Java service to AWS ECR using Gradle Jib. Use when user invokes /deploy-ecr, asks to build and push a service image, deploy a service to ECR, or run a Jib build for ecfx-backend services. macOS only — relies on docker-credential-osxkeychain for GitLab registry credentials.
---


# Deploy to ECR via Jib

Build and push an ecfx-backend service container image to AWS ECR using Gradle Jib.

**Platform:** macOS only. The GitLab registry credential lookup uses `docker-credential-osxkeychain`. Linux/Windows support would need a different credential helper (e.g., `docker-credential-pass`, `docker-credential-secretservice`).

## Dynamic Context

- **Working directory** — run `pwd`
- **Git commit SHA** — run `git rev-parse --short HEAD`
- **Current branch** — run `git branch --show-current`

All paths and Gradle invocations are relative to the working directory shown above. The skill assumes you have already `cd`'d into the repo root that contains the `projects/` directory.

## Arguments

The service name is provided via `$ARGUMENTS` (e.g., `receipt_processing_queue`, `email_queue`, `authapi`).

If `$ARGUMENTS` is empty, list available services and ask the user to specify one.

## Process

### Step 1: Validate Service Name and Working Directory

First confirm the current working directory has a `projects/` directory (this is the repo root sanity check):

```bash
test -d projects || echo "NOT_A_REPO_ROOT"
```

If `NOT_A_REPO_ROOT`, tell the user the skill must be invoked from the repo root containing `projects/` (typically the ecfx-backend checkout root), then stop.

Check that `$ARGUMENTS` is a valid service with a CI config:

```bash
ls projects/$ARGUMENTS/ci/.gitlab-ci.yaml 2>/dev/null || echo "NOT_FOUND"
```

If not found, list services that have CI configs:

```bash
ls projects/*/ci/.gitlab-ci.yaml | sed 's|projects/||;s|/ci/.gitlab-ci.yaml||' | sort
```

Tell the user the service was not found and show the valid list. Stop.

### Step 2: Extract ECR Variables from CI Config

Read `projects/$ARGUMENTS/ci/.gitlab-ci.yaml` and extract:

1. `ECR_REGISTRY` — e.g., `225214954425.dkr.ecr.us-west-2.amazonaws.com`
2. The ECR repo name — the variable matching `*_ECR_REPO_NAME` (e.g., `RECEIPT_PROCESSING_QUEUE_ECR_REPO_NAME: ecfx-backend-receipt-processing-queue`)

Parse with:

```bash
grep 'ECR_REGISTRY:' projects/$ARGUMENTS/ci/.gitlab-ci.yaml | awk '{print $2}'
grep '_ECR_REPO_NAME:' projects/$ARGUMENTS/ci/.gitlab-ci.yaml | awk '{print $2}'
```

Assign to shell variables `ECR_REGISTRY` and `ECR_REPO_NAME`.

### Step 3: Get Git Commit SHA

```bash
COMMIT_SHA=$(git rev-parse --short HEAD)
```

### Step 4: Resolve AWS Profile and Verify Credentials

Resolve the AWS profile and region with env-var defaults (so contributors with non-default SSO setups can override):

```bash
AWS_PROFILE="${AWS_PROFILE:-ecfx-duplo-admin}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
```

Preflight that the profile resolves to a live caller identity:

```bash
aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1 || echo "AWS_AUTH_FAILED"
```

If `AWS_AUTH_FAILED`, stop and tell the user:
- AWS credentials for profile `$AWS_PROFILE` are missing or expired
- Run `aws sso login --profile $AWS_PROFILE` (or set `AWS_PROFILE=<your-profile>` and re-run)

### Step 5: Get GitLab Registry Credentials from macOS Keychain

This step is macOS-only. On Linux/Windows, the credential helper invocation will need to change.

```bash
GITLAB_CREDS=$(echo "registry.gitlab.com" | docker-credential-osxkeychain get 2>/dev/null)
GITLAB_USER=$(echo "$GITLAB_CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Username'])")
GITLAB_PWD=$(echo "$GITLAB_CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Secret'])")
```

If `GITLAB_CREDS` is empty or the python3 parse fails, stop and tell the user:
- Credentials for `registry.gitlab.com` were not found in the macOS keychain
- Run `docker login registry.gitlab.com` to store them first

### Step 6: Confirm Before Building

Print a summary and ask the user to confirm before running the build:

```
Service:      <service_name>
ECR target:   <ECR_REGISTRY>/<ECR_REPO_NAME>:<COMMIT_SHA>-local
Tags:         <COMMIT_SHA>-local, latest  (will overwrite :latest in ECR)
GitLab user:  <GITLAB_USER>
AWS profile:  <AWS_PROFILE>
AWS region:   <AWS_DEFAULT_REGION>
```

Wait for user confirmation ("yes", "y", or Enter) before proceeding.

### Step 7: Run Jib Build

Run from the working directory (already validated as repo root in Step 1). Tee the full output to a per-service log so the user has the complete failure trace even when the inline view is truncated:

```bash
LOG=/tmp/jib-$SERVICE_NAME.log
AWS_PROFILE="$AWS_PROFILE" AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
  ./gradlew :$SERVICE_NAME:jib \
  -PregistryImage=dummy \
  -PcommitSha=$COMMIT_SHA \
  -PpipelineId=local \
  -PregistryUser="$GITLAB_USER" \
  -PregistryPassword="$GITLAB_PWD" \
  -Djib.to.image=$ECR_REGISTRY/$ECR_REPO_NAME:$COMMIT_SHA-local \
  -Djib.to.tags=$COMMIT_SHA-local,latest \
  2>&1 | tee "$LOG" | tail -30
```

### Step 8: Report Result

On success:
```
Pushed: <ECR_REGISTRY>/<ECR_REPO_NAME>:<COMMIT_SHA>-local
Tags:   <COMMIT_SHA>-local, latest
```

On failure, show the last 30 lines of Gradle output, then point the user at the full log:
```
Full log: /tmp/jib-<service_name>.log
```

Common failure causes:
- `docker-credential-ecr-login` not installed or not on PATH → install with `brew install docker-credential-helper-ecr`
- AWS credentials expired → run `aws sso login --profile $AWS_PROFILE`
- GitLab credentials missing → run `docker login registry.gitlab.com`

## Constraints

- Always run Gradle from the working directory (must contain `projects/`, validated in Step 1)
- Defaults to `AWS_PROFILE=ecfx-duplo-admin` and `AWS_DEFAULT_REGION=us-west-2`; both are overridable via env vars
- The image tag format for local builds is always `<commitSha>-local`
- Never push to the GitLab container registry — only to ECR
- The `-PregistryImage=dummy` placeholder is required even though `jib.to.image` overrides it
- `:latest` is always overwritten on push; warn the user in Step 6 confirmation
