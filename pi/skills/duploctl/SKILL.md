---
name: duploctl
description: >-
  Look up and construct duploctl commands for managing DuploCloud infrastructure. Use when user asks about duploctl syntax, DuploCloud CLI commands, managing DuploCloud services/tenants/hosts/RDS/S3/lambda/secrets, updating container images, managing Kubernetes resources through DuploCloud, JIT AWS credentials, or when commands reference duplo/duploctl/duplocloud.
---


# duploctl CLI Reference

Construct correct `duploctl` commands for DuploCloud infrastructure management. For infrastructure architecture, migration planning, and CI/CD pipeline design, defer to the `infra:duplo-infra-specialist` agent.

## User's Environment

- **Portal**: `https://duplo.cloud.ecfxglobal.net/`
- **Default tenant**: `dev01`
- **Auth (local)**: `--interactive` (browser OAuth, tokens cached at `~/.duplo/cache/`)
- **Auth (CI/CD)**: `DUPLO_HOST` + `DUPLO_TOKEN` + `DUPLO_TENANT` env vars
- **Binary**: Homebrew-installed at `/opt/homebrew/bin/duploctl` (v0.4.3)
- **ECR Registry**: `225214954425.dkr.ecr.us-west-2.amazonaws.com`

## Command Pattern

```
duploctl <resource> <action> [positional-args] [--flags]
```

**All examples below assume local interactive auth.** Prepend to any command:
```
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 <resource> <action> ...
```

**Key global flags**: `-I` (interactive), `-H` (host), `-T` (tenant), `-o` (output: json|yaml|csv|env|string), `-q` (JMESPath query), `-w` (wait), `--timeout` (wait timeout), `--admin` (admin access)

## Authentication Quick Reference

**Interactive (local dev)** — opens browser, caches token:
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant list
```

**Environment variables (CI/CD)**:
```sh
export DUPLO_HOST=https://duplo.cloud.ecfxglobal.net/
export DUPLO_TOKEN=<api-token>
export DUPLO_TENANT=dev01
duploctl service list
```

**JIT AWS credentials** — get temporary STS creds:
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 jit aws
# Admin access (full account):
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ jit aws --admin
```

## Tier 1 Resources: Quick Reference

For brevity, auth flags (`-I -H <url> -T dev01`) are omitted. Prepend them for local use.

### service (tenant-scoped) — 18 actions

```sh
duploctl service list                                        # List all services
duploctl service find <name>                                 # Get service details
duploctl service create -f service.yaml --wait               # Create from YAML
duploctl service update <name> -f service.yaml               # Update from YAML
duploctl service delete <name>                               # Delete service
duploctl service update_image <name> <image:tag> --wait      # Update container image
duploctl service update_image <name> --container-image <container> <image:tag>  # Multi-container
duploctl service bulk_update_image -S svc1 img1:tag -S svc2 img2:tag           # Bulk image update
duploctl service update_env <name> -V KEY val -V KEY2 val2 --strategy merge    # Update env vars
duploctl service update_replicas <name> --replicas 3 --wait  # Scale replicas
duploctl service restart <name> --wait                       # Rolling restart
duploctl service stop <name>                                 # Stop (or --all, --targets s1 s2)
duploctl service start <name>                                # Start (or --all, --targets s1 s2)
duploctl service logs <name> --wait                          # Stream pod logs
duploctl service pods <name>                                 # List pods
duploctl service expose <name> --lb-type applicationlb --container-port 80 --external-port 80 --protocol http --visibility public --health-check-url /
duploctl service rollback <name>                             # Rollback (or --to-revision N)
```

### tenant (portal-scoped) — 19 actions

```sh
duploctl tenant list                                         # List all tenants
duploctl tenant find <name>                                  # Get tenant details
duploctl tenant create -f tenant.yaml                        # Create tenant
duploctl tenant delete <name>                                # Delete (--force to bypass protection)
duploctl tenant config <name> -V KEY val -D OLD_KEY          # Manage settings
duploctl tenant billing <name>                               # Get spend info
duploctl tenant faults <name>                                # List faults
duploctl tenant start <name>                                 # Start all resources
duploctl tenant stop <name>                                  # Stop all resources (--exclude svc)
duploctl tenant shutdown <name> -s 2h                        # Shutdown with schedule
duploctl tenant add_user <user> --tenant <name>              # Grant user access
duploctl tenant remove_user <user> --tenant <name>           # Revoke user access
duploctl tenant list_users <name>                            # List authorized users
```

### rds (tenant-scoped, V3) — 18 actions

```sh
duploctl rds list                                            # List RDS instances
duploctl rds find <name>                                     # Get instance details
duploctl rds create -f rds.yaml                              # Create instance
duploctl rds delete <name>                                   # Delete instance
duploctl rds stop <name>                                     # Stop instance
duploctl rds start <name>                                    # Start instance
duploctl rds reboot <name>                                   # Reboot instance
duploctl rds set_instance_size <name> db.r5.large            # Change instance class
duploctl rds change_password <name> <new-pw> --save          # Change password (--save to secrets mgr)
duploctl rds snapshot <name>                                 # Take snapshot
duploctl rds restore <name> --target-name <restored> --time "2024-01-15T10:00:00Z"
duploctl rds engine_versions                                 # List supported engines/sizes
duploctl rds retention_period <name> 7 --immediate           # Set backup retention
```

### hosts (tenant-scoped)

```sh
duploctl hosts list                                          # List hosts
duploctl hosts find <name>                                   # Get host details
duploctl hosts create -f hosts.yaml --wait                   # Create host
duploctl hosts delete <name> --wait                          # Delete host
duploctl hosts stop <name> --wait                            # Stop host
duploctl hosts start <name> --wait                           # Start host
duploctl hosts reboot <name>                                 # Reboot host
```

### infrastructure (portal-scoped)

```sh
duploctl infrastructure list                                 # List infrastructures
duploctl infrastructure find <name>                          # Get infra details
duploctl infrastructure create -f infra.yaml                 # Create infrastructure
duploctl infrastructure faults <name>                        # List faults
duploctl infrastructure eks_config --plan <plan-name>        # Get EKS config
```

### job (tenant-scoped)

```sh
duploctl job create -f job.yaml --wait                       # Create K8s Job and wait
duploctl job list                                            # List jobs
duploctl job pods <name>                                     # List job pods
```

### cronjob (tenant-scoped)

```sh
duploctl cronjob list                                        # List cronjobs
duploctl cronjob find <name>                                 # Get cronjob details
duploctl cronjob update_image <name> <image:tag>             # Update image
duploctl cronjob update_schedule <name> "0 */6 * * *"       # Update schedule
```

### secret (tenant-scoped)

```sh
duploctl secret list                                         # List secrets
duploctl secret find <name>                                  # Get secret
duploctl secret create <name> --from-literal Key1=Val1 --from-literal Key2=Val2
duploctl secret create -f secret.yaml                        # From YAML
duploctl secret update <name> --add /SecretData/NewKey Val   # JSON patch add
duploctl secret update <name> --replace /SecretData/Key Val  # JSON patch replace
duploctl secret update <name> --remove /SecretData/OldKey    # JSON patch remove
duploctl secret delete <name>                                # Delete secret
```

### configmap (tenant-scoped)

```sh
duploctl configmap list                                      # List configmaps
duploctl configmap find <name>                               # Get configmap
duploctl configmap create <name> --from-literal Key1=Val1    # Create from literals
duploctl configmap update <name> --add /data/Key Val         # JSON patch add
duploctl configmap update <name> --replace /data/Key Val     # JSON patch replace
duploctl configmap delete <name>                             # Delete configmap
```

### s3 (tenant-scoped)

```sh
duploctl s3 list                                             # List S3 buckets
duploctl s3 find <name>                                      # Get bucket details
duploctl s3 apply -f s3.yaml                                 # Create/update bucket
duploctl s3 delete <name>                                    # Delete bucket
```

### lambda (tenant-scoped)

```sh
duploctl lambda list                                         # List functions
duploctl lambda find <name>                                  # Get function details
duploctl lambda create -f lambda.yaml                        # Create function
duploctl lambda update_image <name> <image:tag>              # Update container image
duploctl lambda update_s3 <name> <bucket> <key>              # Update S3 code source
duploctl lambda update_env <name> -V KEY val --strategy merge # Update env vars
duploctl lambda delete <name>                                # Delete function
```

### jit (system/tenant-scoped)

```sh
duploctl jit aws                                             # Get AWS STS credentials
duploctl jit aws --admin                                     # Admin-level AWS creds
duploctl jit k8s --plan <plan>                               # Get K8s exec credentials
duploctl jit update_aws_config <profile> --admin -I          # Add to ~/.aws/config
duploctl jit update_kubeconfig --plan <plan> --admin -I      # Add to kubeconfig
duploctl jit web --browser chrome                            # Open cloud console
duploctl jit token                                           # Get Duplo API token
```

## Tier 2 Resources Index

| Resource | Scope | Key Actions |
|----------|-------|-------------|
| `ecs` | tenant | list_services, find_service_family, create_service, update_image, run_task, list_tasks |
| `ecr` | tenant | list, find, create |
| `asg` | tenant | list, find, create, update, delete |
| `ingress` | tenant | list, find, create, update, delete |
| `pod` | tenant | list, find, delete, logs |
| `pvc` | tenant | list, find, create, delete |
| `storageclass` | tenant | list, find, create, delete |
| `aws_secret` | tenant | list, find, create, update, delete |
| `ssm_param` | tenant | list, find, create, update, delete |
| `cloudfront` | tenant | list, find, create, update, delete |
| `cache` | tenant | list, find, create, delete |
| `cloud_resource` | tenant | list, find |
| `user` | portal | list, find, create, update, delete |
| `system` | portal | list, find |
| `plan` | portal | list, find, create, update, delete |
| `version` | portal | find |

**Tier 3 (specialized)**: `argo_wf`, `argo_wf_template`, `ai`, `batch_compute`, `batch_definition`, `batch_job`, `batch_queue`, `batch_scheduling_policy` — all support standard CRUD via `list`, `find`, `create`, `update`, `delete`, `apply`.

## Output and Filtering

```sh
# JSON output (default for scripting)
duploctl service list -o json

# YAML output
duploctl service find myapp -o yaml

# CSV output (great for tables)
duploctl tenant list -o csv

# JMESPath query
duploctl service list -o json -q '[].Name'
duploctl jit aws -o env -q '{AWS_ACCESS_KEY_ID: AccessKeyId, AWS_SECRET_ACCESS_KEY: SecretAccessKey, AWS_SESSION_TOKEN: SessionToken, AWS_REGION: Region}'

# Pipe to jq for complex filtering
duploctl service list -o json | jq '.[] | select(.Name | contains("api"))'
```

## Common Patterns

**Image update workflow** (CI/CD):
```sh
duploctl service update_image myapp 225214954425.dkr.ecr.us-west-2.amazonaws.com/myapp:${TAG} --wait
```

**JSON Patch** (for V3 resources and secret/configmap):
```sh
duploctl secret update mysecret --add /SecretData/NEW_KEY "value"
duploctl secret update mysecret --replace /SecretData/KEY "new-value"
duploctl secret update mysecret --remove /SecretData/OLD_KEY
```

**Wait for deployment**:
```sh
duploctl service update_image myapp myimage:v2 --wait --timeout 600
```

**Apply from YAML** (create-or-update pattern):
```sh
duploctl service apply -f service.yaml --wait
```

## Supporting Files

- **Complete command reference**: Read `reference.md` for all 37 resources with full action details, all global flags, env vars, config file format, and resource-specific notes
- **Workflow examples**: Read `examples.md` for real-world scenarios (deployment, DB ops, JIT setup, CI/CD, troubleshooting)
- **Infrastructure architecture**: Use the `infra:duplo-infra-specialist` agent for migration planning, account structure, and CI/CD pipeline design

## Quality Checklist

- [ ] Auth flags included: `-I -H <portal-url>` for local, env vars for CI/CD
- [ ] Tenant specified (`-T <name>`) for tenant-scoped resources
- [ ] Host URL matches portal: `https://duplo.cloud.ecfxglobal.net/`
- [ ] Output format appropriate: `-o json` for scripting, default for human reading
- [ ] `--wait` added for operations that should block (deploys, creates, deletes)
- [ ] ECR image paths use `225214954425.dkr.ecr.us-west-2.amazonaws.com`
