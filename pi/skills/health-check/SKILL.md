---
name: health-check
description: >-
  Check the health of Kubernetes deployments across ECFX environments.
---


# Health Check

Check the health of Kubernetes deployments across ECFX environments.

## Allowed Tools
Bash, mcp__cloudwatch-mcp-server__execute_log_insights_query

## Slack Notification

After displaying the report to the user, **ask if they want to post it to Slack**. If they confirm, post to the **Development** Slack channel using the webhook in `SLACK_WEBHOOK_URL` (set in `~/.zshrc.local`; if it is unset, tell the user instead of posting):

```bash
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d '{"text": "<report_text>", "username": "ECFX Release Bot"}'
```

- Format the report as plain text with Slack mrkdwn (use `*bold*` not `**bold**`, use `\n` for newlines)
- Confirm to the user whether the Slack post succeeded or failed
- Do NOT post automatically — always ask first

## Description
Use this skill to get a quick health overview of the ECFX backend services running in Kubernetes. Reports on pod status, restart events, error rates, and resource utilization.

## Arguments
- No arguments: checks **production** (default)
- An environment name: `development`, `staging`, `production`, or `fourcfx`

## Kubernetes Contexts

| Environment | Context |
|-------------|---------|
| production | `arn:aws:eks:us-west-2:278643824850:cluster/ecfx-production` |
| development | `arn:aws:eks:us-west-2:278643824850:cluster/ecfx-development` |
| staging | `arn:aws:eks:us-west-2:278643824850:cluster/ecfx-staging` |
| fourcfx | `arn:aws:eks:us-west-2:278643824850:cluster/ecfx-fourcfx` |

Switch context before running commands:
```bash
kubectl config use-context <context>
```

**IMPORTANT**: After the health check completes, switch back to the production context:
```bash
kubectl config use-context arn:aws:eks:us-west-2:278643824850:cluster/ecfx-production
```

---

## Step 1: Pod Status & Restarts

### 1a: Get all backend pod statuses

```bash
kubectl get pods -l tier=backend -o wide --no-headers
```

Classify each pod:
- **Healthy**: `Running` with `1/1` ready, 0 restarts
- **Warning**: `Running` but with restarts > 0 in the AGE column (recently restarted)
- **Critical**: `CrashLoopBackOff`, `OOMKilled`, `Error`, `Pending`, or `0/1` ready

### 1b: Check recent restart events (last 1 hour)

```bash
kubectl get events --field-selector reason=BackOff --sort-by=.lastTimestamp
kubectl get events --field-selector reason=OOMKilling --sort-by=.lastTimestamp
kubectl get events --field-selector reason=Killing --sort-by=.lastTimestamp
kubectl get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp
```

### 1c: Summarize by service

Group pods by deployment (strip the pod hash suffix) and report:
- Number of pods running / expected
- Total restarts across all pods
- Any pods in non-Running state

---

## Step 2: Error Rate by Service

### 2a: Current error rate (last 1 hour)

Query CloudWatch for ERROR log volume per container in the last hour:

```
filter @message like /ERROR/
| filter kubernetes.container_name like /ecfx-backend/
| stats count(*) as errorCount by kubernetes.container_name
| sort errorCount desc
| limit 50
```

- **Region**: `us-west-2`
- **Log group**: `/aws/eks/ecfx-production/logs/workload/default`
  - For development: `/aws/eks/ecfx-development/logs/workload/default`
  - For staging: `/aws/eks/ecfx-staging/logs/workload/default`

### 2b: Baseline error rate (same hour yesterday)

Run the same query for the same 1-hour window yesterday to establish a baseline.

### 2c: Spike detection

Compare current vs baseline for each service:
- **Normal**: current <= 1.5x baseline
- **Elevated**: current > 1.5x and <= 3x baseline
- **Spike**: current > 3x baseline
- **New errors**: errors today but zero yesterday

Flag any service with Elevated or Spike status.

### 2d: Top errors for spiking services

For any service showing a spike, get the top error messages:

```
filter kubernetes.container_name == "<container>"
| filter @message like /ERROR/
| stats count(*) as cnt by @message
| sort cnt desc
| limit 5
```

---

## Step 3: Resource Utilization

### 3a: Get current CPU and memory usage

```bash
kubectl top pods -l tier=backend --no-headers
```

### 3b: Get resource limits

```bash
kubectl get pods -l tier=backend -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits.cpu}{"\t"}{.spec.containers[0].resources.limits.memory}{"\n"}{end}'
```

### 3c: Calculate utilization percentages

For each pod, calculate:
- **Memory %** = current memory / memory limit * 100
- **CPU %** = current CPU / CPU limit * 100

Convert units:
- Memory: `Mi` to compare (e.g., `1682Mi` vs `4Gi` = `4096Mi` → 41%)
- CPU: `m` (millicores) to cores (e.g., `126m` vs `4` cores = `4000m` → 3.2%)

### 3d: Flag resource pressure

| Level | Criteria |
|-------|----------|
| **OK** | Memory < 70% and CPU < 70% |
| **Warning** | Memory 70-85% or CPU 70-85% |
| **Critical** | Memory > 85% or CPU > 85% |

---

## Step 4: Generate Report

Present results to the user AND post to Slack in this format:

```
:stethoscope: *ECFX Health Check — <environment> — <timestamp>*

*Pod Status* (via kubectl get pods / kubectl get events)
Total: <N> pods | Healthy: <N> | Warning: <N> | Critical: <N>
_Healthy services omitted — only showing services with issues._

| Service | Pods | Status | Restarts (24h) |
| ... | 1/2 | :red_circle: CrashLoopBackOff | 5 |
| ... | 6/10 | :warning: 4 Pending | 0 |
[or "All services healthy — no issues to report." if everything is green]

*Recent Events*
- <timestamp> | <pod> | <reason> | <message>
[or "No recent restart events" if clean]

*Error Rates — last 1h vs same hour yesterday* (via CloudWatch Logs Insights)
| Service | Current | Baseline | Trend |
| ... | 42 | 38 | :large_green_circle: Normal |
| ... | 350 | 80 | :red_circle: Spike (4.4x) |

[For spiking services, show top error messages]

*Resource Utilization* (via kubectl top pods / resource limits)
| Service | CPU | CPU % | Memory | Mem % | Status |
| ... | 126m/4000m | 3% | 1688Mi/6144Mi | 27% | :large_green_circle: OK |
| ... | 1800m/2000m | 90% | 7200Mi/8192Mi | 88% | :red_circle: Critical |

*Summary*
:large_green_circle: <N> services healthy
:warning: <N> services with warnings — [list service names]
:red_circle: <N> services critical — [list service names]
```

---

## Troubleshooting

### kubectl context expired
If `kubectl` returns an authentication error, the user needs to refresh credentials:
```bash
aws eks update-kubeconfig --region us-west-2 --name ecfx-production
```

### metrics-server not available
If `kubectl top` returns "Metrics API not available", skip the resource utilization section and note it in the report.

### No log group found
If the CloudWatch log group doesn't exist for the environment, skip the error rate section and note it in the report. Only production and development have guaranteed CloudWatch log groups.
