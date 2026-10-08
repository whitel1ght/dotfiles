# duploctl Workflow Examples

## 1. Local Development Setup

Show: installing duploctl via Homebrew, first interactive login, verifying connectivity.

```sh
# Install via Homebrew
brew tap duplocloud/tap
brew install duploctl

# Verify installation
duploctl --version

# First login — opens browser for OAuth
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant list

# Token is now cached at ~/.duplo/cache/
# Subsequent commands reuse cached token until expiration

# List services in dev01
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 service list

# Shorthand: set env vars for the session
export DUPLO_HOST=https://duplo.cloud.ecfxglobal.net/
export DUPLO_TENANT=dev01
duploctl -I service list
```

## 2. Service Deployment Workflow

Show the complete flow: check current image → build → push to ECR → update service → verify.

```sh
# Check current service state
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 service find myapp -o json -q 'Image'

# Build and push image to ECR (assumes docker login to ECR already done)
TAG=$(git rev-parse --short HEAD)
IMAGE=225214954425.dkr.ecr.us-west-2.amazonaws.com/myapp:${TAG}
docker build -t ${IMAGE} .
docker push ${IMAGE}

# Update service image and wait for rollout
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service update_image myapp ${IMAGE} --wait

# Verify new image is running
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service find myapp -o json -q 'Image'

# Check pods are healthy
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service pods myapp
```

Multi-container service update:
```sh
# Update multiple containers in one service
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service update_image myapp \
  --container-image main 225214954425.dkr.ecr.us-west-2.amazonaws.com/myapp:v2 \
  --container-image sidecar 225214954425.dkr.ecr.us-west-2.amazonaws.com/sidecar:v2 \
  --wait
```

Bulk update across services:
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service bulk_update_image \
  -S api-service 225214954425.dkr.ecr.us-west-2.amazonaws.com/api:${TAG} \
  -S worker-service 225214954425.dkr.ecr.us-west-2.amazonaws.com/worker:${TAG}
```

## 3. Database Operations

```sh
# List all RDS instances
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds list -o csv

# Get specific instance details
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds find mydb -o yaml

# Stop instance for cost savings (dev/staging)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds stop mydb

# Start instance
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds start mydb

# Take snapshot before migration
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds snapshot mydb

# Restore from snapshot (point-in-time)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  rds restore mydb --target-name mydb-restored --time "2024-06-15T10:00:00Z"

# Change instance size
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  rds set_instance_size mydb db.r6g.large

# Change password and save to secrets manager
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  rds change_password mydb 'NewSecurePassword123!' --save

# List available engine versions
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 rds engine_versions
```

## 4. Running Migration Jobs

```sh
# Create and run a one-time migration job from YAML
# The YAML defines the job spec with the migration container
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  job create -f migration-job.yaml --wait --timeout 1800

# Check job pods
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  job pods db-migration

# List all jobs
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 job list
```

Example migration-job.yaml:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: 225214954425.dkr.ecr.us-west-2.amazonaws.com/db-migrator:latest
          env:
            - name: DB_HOST
              value: mydb.internal
      restartPolicy: Never
  backoffLimit: 0
```

## 5. Secret and ConfigMap Management

```sh
# --- Secrets ---

# Create secret from literal values
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  secret create my-app-secrets \
  --from-literal DB_PASSWORD='s3cret' \
  --from-literal API_KEY='abc123'

# Create secret from YAML file
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  secret create -f secret.yaml

# Update a specific key (JSON patch)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  secret update my-app-secrets --replace /SecretData/DB_PASSWORD 'new-password'

# Add a new key
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  secret update my-app-secrets --add /SecretData/NEW_KEY 'new-value'

# Remove a key
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  secret update my-app-secrets --remove /SecretData/OLD_KEY

# List all secrets
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 secret list

# --- ConfigMaps ---

# Create configmap from literals
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  configmap create app-config \
  --from-literal LOG_LEVEL=INFO \
  --from-literal MAX_CONNECTIONS=50

# Update configmap value
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  configmap update app-config --replace /data/LOG_LEVEL DEBUG

# Add new key to configmap
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  configmap update app-config --add /data/FEATURE_FLAG enabled
```

## 6. JIT AWS Credentials for Local AWS CLI

```sh
# Get temporary AWS credentials (tenant-scoped)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 jit aws

# Get admin-level credentials (full account access)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ jit aws --admin

# Export as shell environment variables
eval $(duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 jit aws -o env \
  -q '{AWS_ACCESS_KEY_ID: AccessKeyId, AWS_SECRET_ACCESS_KEY: SecretAccessKey, AWS_SESSION_TOKEN: SessionToken, AWS_REGION: Region}')

# Verify credentials work
aws sts get-caller-identity

# Set up persistent AWS CLI profile with credential_process
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ \
  jit update_aws_config ecfx-duplo-admin --admin

# Now use the profile transparently
aws --profile ecfx-duplo-admin s3 ls
aws --profile ecfx-duplo-admin ecr describe-repositories
```

## 7. Kubernetes Access Through DuploCloud

```sh
# Generate kubeconfig for dev01 tenant
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  jit update_kubeconfig --plan default-dev01

# Now use kubectl normally — credentials refresh automatically
kubectl get pods
kubectl get services
kubectl logs deployment/myapp

# Get K8s exec credentials directly (for custom kubeconfig)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  jit k8s --plan default-dev01

# Open cloud console in browser
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  jit web --browser chrome
```

## 8. CI/CD Pipeline Integration (GitLab CI)

```yaml
# .gitlab-ci.yml
variables:
  DUPLO_HOST: https://duplo.cloud.ecfxglobal.net/
  DUPLO_TENANT: dev01
  ECR_REGISTRY: 225214954425.dkr.ecr.us-west-2.amazonaws.com

stages:
  - auth
  - build
  - deploy

duplo_auth:
  stage: auth
  image: duplocloud/duploctl:latest
  script:
    - duploctl jit aws -o env -q '{AWS_ACCESS_KEY_ID: AccessKeyId, AWS_SECRET_ACCESS_KEY: SecretAccessKey, AWS_SESSION_TOKEN: SessionToken, AWS_REGION: Region}' > aws_creds.env
  artifacts:
    reports:
      dotenv: aws_creds.env

build_and_push:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  needs: [duplo_auth]
  script:
    - aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${ECR_REGISTRY}
    - docker build -t ${ECR_REGISTRY}/myapp:${CI_COMMIT_SHORT_SHA} .
    - docker push ${ECR_REGISTRY}/myapp:${CI_COMMIT_SHORT_SHA}

deploy:
  stage: deploy
  image: duplocloud/duploctl:latest
  needs: [build_and_push]
  script:
    - duploctl service update_image myapp ${ECR_REGISTRY}/myapp:${CI_COMMIT_SHORT_SHA} --wait --timeout 600
```

## 9. Scripting and Automation

```sh
# List all service names
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service list -o json -q '[].Name'

# Find services with "api" in the name
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service list -o json | jq '.[] | select(.Name | contains("api"))'

# Get all service images as a table
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service list -o json | jq -r '.[] | [.Name, .Image] | @tsv'

# Check tenant faults across all tenants
for tenant in dev01 staging01 prod01; do
  echo "=== ${tenant} ==="
  duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant faults ${tenant} 2>/dev/null
done

# Restart all services matching a pattern
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service list -o json -q '[].Name' | jq -r '.[]' | grep 'api' | while read svc; do
    echo "Restarting ${svc}..."
    duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 service restart ${svc} --wait
  done

# Export service config as YAML backup
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service find myapp -o yaml > myapp-backup.yaml

# Stop all dev services for cost savings (end of day)
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service stop --all

# Or schedule tenant shutdown
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ \
  tenant shutdown dev01 -s 8h
```

## 10. Troubleshooting Common Errors

### "Token expired" or "Unauthorized"
```sh
# Re-authenticate interactively (clears cached token)
duploctl -I --no-cache -H https://duplo.cloud.ecfxglobal.net/ tenant list

# Or clear cache manually
rm ~/.duplo/cache/duplo.cloud.ecfxglobal.net,duplo-creds.json

# Verify token works
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant list
```

### "Tenant not found"
```sh
# List all available tenants to check spelling
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant list -o csv

# Use tenant ID instead of name
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ --tid <tenant-uuid> service list
```

### "Service not found"
```sh
# List all services in the tenant to check name
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 service list -o json -q '[].Name'

# Check you're in the right tenant
```

### Timeout waiting for deployment
```sh
# Increase timeout
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service update_image myapp myimage:v2 --wait --timeout 900

# Check pod status for errors
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service pods myapp

# Stream logs to see startup errors
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 \
  service logs myapp --wait
```

### Permission denied / Admin required
```sh
# Some operations require admin access
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ --admin tenant list

# JIT with admin flag
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ --admin jit aws
```

### Debug logging
```sh
# Enable debug output to see API calls
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 -L DEBUG service list
```
