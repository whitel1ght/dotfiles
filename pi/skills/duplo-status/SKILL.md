---
name: duplo-status
description: >-
  Quick DuploCloud tenant health check showing services, faults, and infrastructure status. Use when user asks for duplo status, tenant health, what's running, service overview, or invokes /duplo-status.
---


# DuploCloud Tenant Status Check

Quick health overview of a DuploCloud tenant. Reports services, faults, and resource status.

## Arguments

`$ARGUMENTS` optionally specifies a tenant name. Defaults to `dev01`.

## Process

### 1. Determine Target Tenant

```
TENANT=${ARGUMENTS:-dev01}
```

If the user specified a tenant name in `$ARGUMENTS`, use that. Otherwise default to `dev01`.

### 2. Gather Status (run all in parallel)

Run these commands using the configured context:

```sh
# Service list with key fields
duploctl --ctx ecfxglobal -T $TENANT service list -o json

# Tenant faults
duploctl --ctx ecfxglobal tenant faults $TENANT -o json

# RDS instances (if any)
duploctl --ctx ecfxglobal -T $TENANT rds list -o json
```

If `--ctx ecfxglobal` fails (no config file), fall back to:
```sh
duploctl -I -H https://duplo.cloud.ecfxglobal.net/ -T $TENANT ...
```

### 3. Format Output

Present a concise status report:

```markdown
## DuploCloud Status: {tenant}

### Services ({count})
| Service | Image | Replicas | Status |
|---------|-------|----------|--------|
| ...     | ...   | ...      | ...    |

### Faults ({count})
- {fault description} — {timestamp}
(or "No active faults")

### RDS Instances ({count})
| Instance | Engine | Size | Status |
|----------|--------|------|--------|
| ...      | ...    | ...  | ...    |
(or "No RDS instances")
```

### 4. Highlight Issues

Flag any problems:
- Services with 0 replicas running
- Active faults
- RDS instances in non-available state (stopped, error, etc.)
- Services with images that don't match the ECR registry pattern

## Fallback

If commands fail with auth errors, tell the user:
1. Check if cached token is valid: `duploctl --ctx ecfxglobal tenant list`
2. Re-authenticate: `duploctl -I --no-cache -H https://duplo.cloud.ecfxglobal.net/ tenant list`
