---
name: processor-error-triage
description: >-
  Triage an auto-filed ECFX "Processor Error" Jira bug (logerr-auto label) — classify the error signature against the known-failure taxonomy, find duplicates and umbrella tickets, and recommend a disposition (close as duplicate, link to umbrella, route to signature-mapping work, or escalate as a real bug). Use when the user asks to triage a Processor Error ticket, work through the logerr-auto queue, or asks "is this ticket real or noise", or pastes an ECFX bug whose summary starts with "Processor Error:".
---


# Processor Error Triage

The ecfx-backend log-error automation files Jira bugs (label `logerr-auto`) at high volume — hundreds per month, and historically ~75% end up manually closed as "Rejected Incomplete". Most match a small set of known signatures. This skill classifies a ticket in minutes and recommends a defensible disposition instead of leaving triage to memory.

Jira cloud ID: `1c62390f-4296-41c6-ac4c-07fab33b5185` (ecfxdev.atlassian.net), project `ECFX`.

## Process

### 1. Fetch and parse the ticket

Get the issue (summary, description, labels, created). Auto-filed summaries follow:

```
Processor Error: <ProcessorClassName> — <error message>
```

Extract the **processor** (e.g. `GreenfilingDocketNoticeEmailReceiptProcessor`) and the **error signature** (the message with volatile parts — IDs, URLs, counts — stripped). Firm labels (`firm-*`) tell you blast radius; multiple firm labels = systemic, single firm = possibly credential/config.

### 2. Classify against the known-signature taxonomy

Match the signature to a bucket. Volumes below are from the June 2026 baseline — treat them as relative weights, not current counts.

| Signature | Class | Disposition |
|---|---|---|
| `Unable to determine county from Greenfiling Court Location: <X>` | **Missing mapping** (top signature, ~95/6wk) | Actionable without a code fix in the parser — route to the `add-signature-mapping` skill with the quoted court-location string; link to the Greenfiling mapping master-tracker ticket (search: `summary ~ "Missing Signature Mappings"`) |
| `NJ Courts transient browser failure: …` (timed out / post-login state never…) | **Known transient** — NJ browser-automation cluster | Duplicate of the standing NJ reliability workstream; link + close. Escalate only if volume spiked or a new sub-message appears |
| `Camoufox driver unavailable` / `Could not start Camoufox web driver` | **Infra readiness** (sidecar rollout race) | Link to the camoufox-sidecar readiness ticket; close as duplicate unless persistent beyond a rollout window |
| `Undefined Exception for Logging: <inner>` | **Unregistered exception type** — the interesting bucket | Triage on the *inner* message (next rows). Also: if the inner exception is a known retry-path type, the real fix is registering a handler in `ReceiptProcessingExceptionEventListener` so it stops being filed at all |
| inner: `EntityManagerFactory is closed` / `Session/EntityManager is closed` | Shutdown race during deploy | Usually noise if clustered around a rollout timestamp; real bug if steady-state |
| inner: `Client '<http://ecfx-…>' …` (connection refused/closed) | Internal service blip | Noise if isolated; infra ticket if recurring for one service |
| `Attempting to store zero-length document for courtDocumentId …` | **Document-download defect** | Real bug class (has caused stuck inboxes); check for an open regression ticket before filing new |
| `Unable to parse document link: https://url.us.m.mimecastprotect…` | Mimecast-wrapped links | Known parsing gap; link to its ticket |
| `Verification code required` (Wisconsin OTP) / `PACER session expired repeatedly` / `Couldn't find case number` (Colorado) / `The court information could not be obtained` (OneLegal) / `Unsupported plain text email` | **Product-decision-pending** — high-volume buckets with standing "product to determine path forward" umbrella tickets | Link to the matching umbrella (search: `summary ~ "product to determine path forward"`); close the instance |
| Anything else | **Novel** | Go to step 4 |

### 3. Duplicate search

Confirm with JQL before closing anything (adapt the distinctive phrase):

```
project = ECFX AND summary ~ "\"<distinctive error phrase>\"" ORDER BY created DESC
```

Also search without the `logerr-auto` restriction — a human-filed ticket for the same root cause is the better link target. Prefer linking to: an open umbrella/workstream ticket > the oldest open duplicate > a resolved ticket (which suggests a regression — say so).

### 4. Novel signatures — decide real vs noise

For a signature with no bucket and no duplicates:
- Multiple firms affected, or a processor that was previously quiet → likely a real regression; check recent MRs touching that processor (`git log --oneline -20 -- '**/<ProcessorName>.java'` in the ecfx-backend checkout) and correlate first-occurrence with a deploy.
- Single firm + credential/access wording ("not authorized", "Acct Not Assigned") → likely customer-side; note that per the failure-routing convention it should surface as **Action Required: Client**, and if it instead landed as an ECFX error ticket, that misrouting is itself the bug worth filing.
- If it's real, hand off to the `fix-jira-bug` skill for the full fix lifecycle.

### 5. Recommend the disposition

Output one block per ticket:

```
ECFX-NNNNN — <processor> — <signature class>
Disposition: <Close as duplicate of ECFX-XXXXX | Link to umbrella ECFX-XXXXX and close | Route to add-signature-mapping | Escalate as real bug (reason)>
Evidence: <duplicate keys found, volume, firms affected, deploy correlation>
```

**Do not transition or comment on the ticket without the user's go-ahead** — present the recommendation, then act (link/comment/transition via the Atlassian MCP tools) once confirmed. Batch mode (triaging a queue) may be pre-authorized by the user; then act per ticket and report a summary table.

## Quality bar

- Never close a ticket on signature-match alone without a duplicate/umbrella JQL check — the taxonomy ages.
- A known-transient signature at 10× its usual volume is not noise; flag volume anomalies explicitly.
- When you link to an umbrella ticket, quote its key and summary so the user can verify in one glance.
