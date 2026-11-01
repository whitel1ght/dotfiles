# Complete Resource/Action Matrix

All 37 resources organized by scope. Show every action.

## Portal-Scoped Resources

| Resource | Actions |
|----------|---------|
| infrastructure | list, find, create, update, delete, faults, eks_config |
| tenant | list, find, create, delete, apply, config, billing, faults, region, host_images, dns_config, logging, shutdown, start, stop, add_user, remove_user, list_users, get_metadata, set_metadata |
| plan | list, find, create, update, delete |
| user | list, find, create, update, delete |
| system | list, find |
| version | find |
| jit | token, aws, gcp, k8s, k8s_context, argo_wf, update_aws_config, update_kubeconfig, web |

## Tenant-Scoped Resources

| Resource | Actions |
|----------|---------|
| service | list, find, create, update, delete, apply, update_image, bulk_update_image, update_env, update_pod_label, update_replicas, update_otherdockerconfig, restart, stop, start, pods, logs, expose, rollback |
| hosts | list, find, create, apply, delete, stop, start, reboot |
| rds | list, find, find_cluster, create, update, delete, apply, stop, start, reboot, set_instance_size, change_password, set_monitor_interval, logging, iam_auth, final_snapshot, snapshot, restore, retention_period, engine_versions |
| s3 | list, find, apply, delete |
| lambda | list, find, create, delete, update_image, update_s3, update_env |
| ecs | list_services, find_service_family, create_service, update_service, delete_service, apply, list_task_def_family, find_def, find_def_by_arn, find_task_def_family, update_taskdef, update_image, list_tasks, run_task |
| ecr | list, find, create |
| configmap | list, find, create, update, delete |
| secret | list, find, create, update, delete, apply |
| aws_secret | list, find, create, update, delete |
| ssm_param | list, find, create, update, delete |
| ingress | list, find, create, update, delete |
| pod | list, find, delete, logs |
| job | list, find, create, apply, pods |
| cronjob | list, find, apply, update_image, update_schedule |
| asg | list, find, create, update, delete |
| cloudfront | list, find, create, update, delete |
| pvc | list, find, create, delete |
| storageclass | list, find, create, delete |
| cloud_resource | list, find |
| cache | list, find, create, delete |
| argo_wf | list, find, create, update, delete, apply |
| argo_wf_template | list, find, create, update, delete, apply |
| ai | list, find, create, update, delete |
| batch_compute | list, find, create, update, delete |
| batch_definition | list, find, create, update, delete, update_image |
| batch_job | list, find, create |
| batch_queue | list, find, create, update, delete |
| batch_scheduling_policy | list, find, create, update, delete |

---

# Global Flags Reference

| Flag | Short | Env Var | Description |
|------|-------|---------|-------------|
| --host | -H | DUPLO_HOST | Portal URL |
| --token | -t | DUPLO_TOKEN | API token |
| --tenant | -T | DUPLO_TENANT | Tenant name |
| --tenant-id / --tid | | DUPLO_TENANT_ID | Tenant ID (overrides -T) |
| --output | -o | DUPLO_OUTPUT | Output format: json, yaml, csv, env, string |
| --query | -q | DUPLO_QUERY | JMESPath query on result |
| --wait | -w | | Wait for operation to complete |
| --wait-timeout / --timeout | | | Wait timeout in seconds |
| --log-level | -L | DUPLO_LOG_LEVEL | CRITICAL, FATAL, ERROR, WARN, WARNING, INFO, DEBUG, NOTSET |
| --interactive | -I | | Interactive browser login |
| --admin / --isadmin | | | Request admin access (with interactive login) |
| --context / --ctx | | DUPLO_CONTEXT | Use named context from config file |
| --config-file | | DUPLO_CONFIG | Path to config file |
| --home-dir | | | Home directory for duplo configs (default: ~/.duplo) |
| --cache-dir | | DUPLO_CACHE_DIR | Cache directory for credentials |
| --no-cache | | | Don't use cached credentials |
| --web-browser | | | Browser for interactive login: chrome, firefox, safari, edge, opera, etc. |
| --validate | | | Validate body inputs against SDK model schema |
| --version | | | Show version and exit |

---

# Environment Variables

| Variable | Description | Corresponding Flag |
|----------|-------------|--------------------|
| DUPLO_HOST | Portal URL | --host |
| DUPLO_TOKEN | API token | --token |
| DUPLO_TENANT | Default tenant name | --tenant |
| DUPLO_TENANT_ID | Default tenant ID | --tenant-id |
| DUPLO_OUTPUT | Default output format | --output |
| DUPLO_QUERY | Default JMESPath query | --query |
| DUPLO_LOG_LEVEL | Default log level | --log-level |
| DUPLO_CONTEXT | Default config context | --context |
| DUPLO_CONFIG | Config file path | --config-file |
| DUPLO_CACHE_DIR | Cache directory path | --cache-dir |
| DUPLO_PLAN | Default plan name | --plan (on jit/infrastructure) |
| duplo_host | Alias for DUPLO_HOST | --host |
| duplo_token | Alias for DUPLO_TOKEN | --token |
| duplo_default_tenant | Alias for DUPLO_TENANT | --tenant |

---

# Config File Format

Located at `~/.duplo/config` (YAML). Create with any text editor.

```yaml
# ~/.duplo/config — contexts is a LIST (not a map)
contexts:
- name: ecfxglobal
  host: https://duplo.cloud.ecfxglobal.net/
  interactive: true              # Use browser OAuth
- name: ecfxglobal-admin
  host: https://duplo.cloud.ecfxglobal.net/
  interactive: true
  admin: true

current-context: ecfxglobal
```

Supported context keys: `name` (required), `host`, `token`, `tenant`, `interactive`, `admin`, `nocache`.

Usage:
```sh
# Use default context
duploctl --ctx ecfxglobal tenant list

# Override context
duploctl --ctx ecfxglobal-admin jit aws
```

---

# Authentication Methods Deep Dive

## 1. Token via Environment Variable
Best for CI/CD pipelines.
```sh
export DUPLO_HOST=https://duplo.cloud.ecfxglobal.net/
export DUPLO_TOKEN=<api-token>
export DUPLO_TENANT=dev01
duploctl service list
```

## 2. Interactive Browser OAuth
Best for local development. Opens browser, caches token at `~/.duplo/cache/`.
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ tenant list
# Token cached — subsequent calls reuse it until expiration
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 service list
```

## 3. Config File Contexts
Best for multiple environments.
```sh
# After setting up ~/.duplo/config:
duploctl --ctx ecfxglobal -T dev01 service list
```

## 4. JIT AWS credential_process
Integrates with AWS CLI config for transparent credential refresh.
```ini
# ~/.aws/config
[profile ecfx-duplo-admin]
region = us-west-2
output = json
credential_process = duploctl jit aws --admin --host https://duplo.cloud.ecfxglobal.net/ --token <token>
```
Then use: `aws --profile ecfx-duplo-admin s3 ls`

## 5. JIT Kubeconfig Exec
Integrates with kubectl for transparent K8s credential refresh.
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 jit update_kubeconfig --plan <plan-name>
# Now use kubectl normally:
kubectl get pods
```

---

# Output Formats

## json (default for scripting)
```sh
duploctl service find myapp -o json
# Returns: {"Name": "myapp", "Image": "...", ...}
```

## yaml
```sh
duploctl service find myapp -o yaml
# Returns YAML representation
```

## csv (tabular)
```sh
duploctl service list -o csv
# Returns: Name,Image,Replicas,...
```

## env (shell export)
```sh
duploctl jit aws -o env
# Returns: export AWS_ACCESS_KEY_ID=... export AWS_SECRET_ACCESS_KEY=...
# Use with eval: eval $(duploctl jit aws -o env)
```

## string (single value)
```sh
duploctl service find myapp -o string -q 'Image'
# Returns just the image string
```

## JMESPath Queries
```sh
# Get list of service names
duploctl service list -q '[].Name'

# Get specific fields
duploctl service find myapp -q '{name: Name, image: Image, replicas: Replicas}'

# Filter by condition
duploctl service list -q "[?contains(Name, 'api')]"

# AWS credentials as env vars
duploctl jit aws -o env -q '{AWS_ACCESS_KEY_ID: AccessKeyId, AWS_SECRET_ACCESS_KEY: SecretAccessKey, AWS_SESSION_TOKEN: SessionToken, AWS_REGION: Region}'
```

---

# JSON Patch Operations

Resources based on V3 (like RDS) and resources with explicit patch support (secret, configmap, service update_otherdockerconfig) support JSON Patch operations.

```sh
# Add a new field
duploctl secret update mysecret --add /SecretData/NEW_KEY "value"

# Replace an existing field
duploctl secret update mysecret --replace /SecretData/EXISTING_KEY "new-value"

# Remove a field
duploctl secret update mysecret --remove /SecretData/OLD_KEY

# Multiple patches in one command
duploctl rds update mydb --add /Tags/Environment "dev" --replace /SizeEx "db.r6g.large"

# Move/Copy (for V3 resources)
duploctl rds update mydb --move /OldPath /NewPath
duploctl rds update mydb --copy /SourcePath /TargetPath
```

JSON Pointer escaping: Use `~0` for `~` and `~1` for `/` in field names.
```sh
# For a key with / in the name: my/key → my~1key
duploctl secret update mysecret --add /SecretData/my~1key "value"
```

---

# Wait Behavior

The `--wait` flag causes duploctl to poll until the operation reaches a terminal state.

```sh
# Wait with default timeout
duploctl service update_image myapp myimage:v2 --wait

# Wait with custom timeout (seconds)
duploctl service update_image myapp myimage:v2 --wait --timeout 600

# Wait on create
duploctl hosts create -f host.yaml --wait

# Wait on job completion
duploctl job create -f migration.yaml --wait --timeout 1800
```

Wait behavior per resource:
- **service**: Waits for all pods to reach Running state with correct image
- **hosts**: Waits for host to reach running/stopped state
- **rds**: Waits for instance to reach available/stopped state
- **job**: Waits for job to reach Complete or Failed state
- **apply**: Waits for the created/updated resource to stabilize

If timeout is reached, duploctl exits with a non-zero status code.

---

# Resource-Specific Notes

## service (18 actions — the richest resource)

**update_image** — The most commonly used action in CI/CD:
- Single container: `duploctl service update_image <name> <image:tag>`
- Multi-container: `duploctl service update_image <name> --container-image <container-name> <image:tag>`
- Init containers: `duploctl service update_image <name> --init-container-image <init-name> <image:tag>`
- With wait: Add `--wait` to block until rollout completes

**update_env** — Environment variable management:
- `-V KEY VALUE` or `--setvar KEY VALUE` to set variables (repeatable)
- `-D KEY` or `--deletevar KEY` to remove variables (repeatable)
- `--strategy merge` (default) adds/overwrites; `replace` is full state replacement

**expose** — Load balancer configuration:
- lb-type values: `applicationlb`, `k8clusterip`, `k8nodeport`, `networklb`, `targetgrouponly`
- Visibility: `public` or `private`
- Protocol: `http`, `https`, `tcp`, `udp`, `tls`

**stop/start** — Service lifecycle:
- By name: `duploctl service stop myapp`
- All services: `duploctl service stop --all`
- Multiple specific: `duploctl service stop --targets svc1 svc2`

## rds (V3-based with rich lifecycle)

**Engine codes** (for YAML creation):
- 0: MySQL, 1: PostgreSQL, 2: MsSQL-Express, 3: MariaDB
- 8: Aurora-MySQL, 9: Aurora-PostgreSQL
- 12: DocumentDB, 14: MemoryDB

**change_password**: Use `--save` to also store in secrets manager.

**restore**: Point-in-time restore from snapshot:
```sh
duploctl rds restore mydb --target-name mydb-restored --time "2024-01-15T10:00:00Z"
```

## ecs (separate service and task definition management)

The ECS resource manages both services and task definitions. Action naming reflects this:
- Service actions: `list_services`, `find_service_family`, `create_service`, `update_service`, `delete_service`
- Task def actions: `list_task_def_family`, `find_def`, `find_def_by_arn`, `find_task_def_family`, `update_taskdef`
- Task actions: `list_tasks`, `run_task`
- Image update: `update_image` (updates the task definition image)

## jit (Just-In-Time credentials)

**aws** — Returns STS credentials in ExecCredential format (for credential_process) by default.
For shell export: `duploctl jit aws -o env -q '{...}'`

**update_aws_config** — Writes a profile entry to `~/.aws/config`:
```sh
duploctl jit update_aws_config duplo-dev -I -H https://duplo.cloud.ecfxglobal.net/ --admin
# Creates [profile duplo-dev] with credential_process pointing to duploctl
```

**update_kubeconfig** — Writes a context to kubeconfig:
```sh
duploctl jit update_kubeconfig -I -H https://duplo.cloud.ecfxglobal.net/ -T dev01 --plan myplan
```

## tenant (tenant lifecycle and user management)

**shutdown** with schedule: Accepts time durations like `5m`, `2h`, `1d`:
```sh
duploctl tenant shutdown dev01 -s 2h  # Shutdown in 2 hours
```

**set_metadata** — Typed metadata entries:
```sh
duploctl tenant set_metadata dev01 --metadata featureFlag text enabled --metadata docs url https://docs.example.com
# Types: text, url, aws_console
```

**config** — Tenant configuration (key-value settings):
```sh
duploctl tenant config dev01 -V delete_protection true -D old_setting
```

---

# CLI Documentation Links

- Main docs: https://cli.duplocloud.com/
- GitHub wiki: https://github.com/duplocloud/duploctl/wiki
- DuploCloud overview: https://docs.duplocloud.com/docs/automation-platform/automation-and-tools/duploctl
- PyPI package: https://pypi.org/project/duplocloud-client/
- GitHub repo: https://github.com/duplocloud/duploctl
