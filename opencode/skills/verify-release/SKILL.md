---
name: verify-release
description: >-
  Verify that Jira tickets included in a production release are working as intended by checking production logs.
---


# Verify Release

Verify that Jira tickets included in a production release are working as intended by checking production logs.

## Allowed Tools
Read, Grep, Glob, Bash, the Atlassian MCP’s matching tool, mcp__cloudwatch-mcp-server__execute_log_insights_query, mcp__cloudwatch-mcp-server__describe_log_groups

## Slack Notification

After generating the report, **ask the user** if they would like to post it to the Development Slack channel. Only post if they confirm. Use the incoming webhook:

```bash
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d '{"text": "<report_text>", "username": "ECFX Release Bot"}'
```

- Format the report as plain text with Slack mrkdwn (use `*bold*` not `**bold**`, use `\n` for newlines)
- Linkify Jira ticket keys using Slack link syntax: `<https://ecfx.atlassian.net/browse/ECFX-12345|ECFX-12345>`
- Linkify MR references using: `<https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/NNNN|!NNNN>`
- Reference assignees as `@DisplayName` (e.g., `@David Stein`) using the Jira assignee display name
- Post the full report including the summary table and follow-up items
- Confirm to the user whether the Slack post succeeded or failed

## Description
Use this skill after a production release to verify that all tickets in the release are working as intended. It queries Jira for tickets that moved to Done, then checks CloudWatch production logs to confirm fixes are holding and new features are active.

## Arguments
- No arguments: verifies yesterday's release (default)
- A date (e.g., `2026-03-31`): verifies the release on that specific date
- A Jira ticket key (e.g., `ECFX-12603`): verifies a single ticket

---

## Step 1: Identify Release Tickets

Query Jira for tickets that moved to Done on the release date:

```
project = ECFX AND sprint in openSprints() AND status changed to "Done" DURING ("<release_date>", "<release_date + 1 day>") ORDER BY priority DESC
```

- Cloud ID: `1c62390f-4296-41c6-ac4c-07fab33b5185`
- Fields: `summary, status, issuetype, priority, assignee`
- If a single ticket key was provided, query just that ticket instead

Display the ticket list to the user before proceeding.

---

## Step 2: Find MRs and Verify Deployment

For each ticket, find the associated merge request and check if the fix is deployed to production.

### 2a: Find the MR

```bash
glab mr list --merged --search "ECFX-XXXXX" --per-page 3
```

If found, get the merge/squash commit SHA and MR URL:

```bash
glab api projects/ecfx%2Fecfx-backend/merge_requests/<MR_NUMBER> | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('squash_commit_sha') or data.get('merge_commit_sha'))
print(data.get('web_url'))
print(data.get('merged_at'))
"
```

### 2b: Verify Deployment

Check if the commit SHA appears in the running container's image tag by querying CloudWatch:

```
filter kubernetes.container_name == "<container>"
| fields kubernetes.container_image
| sort @timestamp desc
| limit 1
```

The production image tag format is `<full-commit-sha>-<pipeline-id>`. Compare the first 8-10 characters of the MR's squash/merge commit SHA with the image tag. If they match, the fix is deployed. If not, flag it as **NOT DEPLOYED**.

### 2c: Report in Slack

Include the MR link and deployment status for each ticket:
- `MR: !5128 | Deployed: YES (sha 819233700)` or
- `MR: !5128 | Deployed: NO — running old image ba87c08a`

---

## Step 3: Map Tickets to Log Queries

For each ticket, determine:

1. **Which container to query** — Map the ticket's component/description to the production container name. Known container names:
   - `ecfx-backend-receipt-process-queue` — receipt processing, court processors (PACER, NJ Courts, Alabama, etc.)
   - `ecfx-backend-receipt-process-web-api` — receipt processing web API
   - `ecfx-backend-receipt-post-process-queue` — post-processing of receipts
   - `ecfx-backend-core-rest-api` — core REST API, timekeepers, cases, firms, auto-ignore rules
   - `ecfx-backend-data-import-rest-api` — bulk data import service
   - `ecfx-backend-dms-queue` — document management (Box, Dropbox, NetDocuments, Litify, Clio)
   - `ecfx-backend-poller-queue` — court system polling (Unicourt, PACER poller)
   - `ecfx-backend-email-queue` — email delivery
   - `ecfx-backend-webhook-queue` — webhook processing
   - `ecfx-backend-notifier-queue` — notifications
   - `ecfx-backend-scheduler` — scheduled tasks
   - `ecfx-backend-authapi` — authentication
   - If unsure, use a broad filter: `kubernetes.container_name like /keyword/`

2. **What error patterns to search for** — Derive from the ticket summary:
   - Bug fixes: search for the error message, exception class, or symptom described
   - New processors/features: search for the processor/feature name to confirm activity
   - Performance fixes: search for timeout, OOM, restart, blocking patterns
   - Integration fixes: search for the integration name + error codes (401, 400, Connection reset, etc.)

3. **What "success" looks like**:
   - Bug fixes: error count should drop significantly after the release date
   - New features: should see new log activity after the release date
   - Performance fixes: compare metrics (timeouts, restarts, durations) before vs after

---

## Step 4: Run Before/After Log Comparisons

For each ticket, run TWO CloudWatch Logs Insights queries:

**Before the release** (6 days prior to release date):
```
filter kubernetes.container_name == "<container>"
| filter @message like /<error_pattern>/
| stats count(*) as errorCount by bin(1d)
| sort @timestamp asc
```

**After the release** (release date to now):
```
filter kubernetes.container_name == "<container>"
| filter @message like /<error_pattern>/
| stats count(*) as errorCount by bin(1d)
| sort @timestamp asc
```

### CloudWatch Query Rules
- **Region**: Always use `us-west-2` (production EKS logs are NOT in us-east-1)
- **Log group**: `/aws/eks/ecfx-production/logs/workload/default`
- **Always include `| limit 50`** or use the limit parameter
- **Max timeout**: 60 seconds for large date ranges

If the "after" query still shows errors, run a detail query to get sample log messages:
```
filter kubernetes.container_name == "<container>"
| filter @message like /<error_pattern>/
| fields @timestamp, @message
| sort @timestamp desc
| limit 5
```

---

## Step 5: Determine Verification Status

Classify each ticket into one of these statuses:

| Status | Criteria |
|--------|----------|
| **Fixed** | Error count dropped to zero or near-zero after release |
| **Improved** | Error count significantly reduced but not eliminated |
| **Active** | New feature/processor showing expected log activity |
| **Partial** | Some aspects fixed, but related errors still occurring |
| **Still Broken** | Error count unchanged or increased after release |
| **Inconclusive** | No matching log patterns found (may need different search terms) |

---

## Step 6: Generate Report

Present results in this format:

```
## Release Verification Report — <release_date>

### <TICKET-KEY> | <Summary> | <Assignee>
**Status: <STATUS>**
- Before fix: <error_count>/day (date range)
- After fix: <error_count>/day (date range)
- <Additional context from log samples if relevant>

[Repeat for each ticket]

### Summary Table

| Ticket | Type | Assignee | Status | Action Needed |
|--------|------|----------|--------|---------------|
| ... | ... | ... | ... | ... |

### Items Needing Follow-up
- List any tickets with status Partial, Still Broken, or Inconclusive
- Include specific details about what's still failing
```

---

## Troubleshooting

### Container name not found
If a container name returns zero results, run a discovery query:
```
filter kubernetes.container_name like /<keyword>/
| stats count(*) as logCount by kubernetes.container_name
| sort logCount desc
```

### No matching error patterns
If the initial error pattern returns zero results:
1. Try broader patterns (just the key term, no regex complexity)
2. Search for the processor/service class name instead
3. Check if the service has any logs at all (may not be deployed yet)

### Old image still running
Check the container image tag in log entries. If the post-release logs show an old image hash, the fix may not be deployed to that service yet. Flag this in the report.
