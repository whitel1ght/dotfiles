---
name: fix-jira-bug
description: >-
  Drive a Jira bug ticket from "open" to "approved MR" — read the ticket, reproduce from EMLs in /workspace/shared/<TICKET>/, propose a fix, multi-agent review the proposal and the implementation, open the MR, link/comment back to Jira, and monitor reviewer feedback until approval. Use when the user asks you to "fix ticket ECFX-NNNN", "work this ticket", "handle this bug end-to-end", or similar phrasing that implies the full bug-fix lifecycle.
---


# Fix Jira Bug End-to-End

A long-horizon workflow skill that takes a Jira bug ticket and drives it to an approved MR without losing the steps in between. Composes existing skills (`/setup-jurisdiction-and-case`, `/process-email-notice-cli`) and the Jira/GitLab APIs.

## When to invoke

Trigger phrases:
- "Fix ticket ECFX-NNNN"
- "Work this bug end-to-end"
- "Reproduce and address ECFX-NNNN"
- "Drive ECFX-NNNN to MR"

Do NOT invoke for:
- Pure investigation requests ("what's going on with ECFX-NNNN?", "is this one bug or several?") — those want analysis, not commits. Use `research-jira-bug`.
- Feature work that isn't a bug — this skill assumes a reproducible failure exists.
- Tickets without EMLs in `/workspace/shared/<TICKET>/` — this skill's reproduction strategy is EML-driven. Run `research-jira-bug` first: it pulls the EMLs off the admin site from the inbox ids on the ticket. If that finds nothing either, stop and ask the user for an alternative reproducer.

## Required inputs

- **TICKET**: Jira key, e.g., `ECFX-10938`. Required. Parse from user message if present.
- **FIRM** (optional): Firm ID for local repro. Default `1`.
- **SCOPE** (optional): An issue id from a `research-jira-bug` report, e.g. `--scope issue-2`.
  Restricts this run to that issue's inbox items and EMLs. See Phase 2.

## Required environment

- `JIRA_URL`, `JIRA_USERNAME`, `JIRA_TOKEN_FILE` (or `/run/secrets/jira_api_token`) — present in the claude-code-container by default.
- `/run/secrets/git_credentials` for the GitLab API token.
- Local Postgres + Redis (the embedded skills probe for them).

If any are missing, fail fast with a clear message — do not silently degrade.

## Allowed tools

`Skill, Bash, Read, Write, Edit, Grep, Glob, Agent, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Monitor, ScheduleWakeup`

## Operating principles

- **Pause at decision points, don't barrel through.** Phase 5 (reproduction confirmation) and Phase 8 (approach review) are explicit gates. Use `AskUserQuestion` if reality diverges from expectation. Asking once is cheaper than unwinding a wrong fix.
- **Track progress with TaskCreate/TaskUpdate.** Create the task list in Phase 0; update each task to `in_progress` when you start it and `completed` when done. Reviewers (and the user) read this to know where you are.
- **Never edit unrelated files.** If something blocks you (e.g., a stale import in another module that prevents compilation), call it out as an "incidental fix" in the MR description rather than silently mixing concerns.
- **Verify, don't claim.** "Tests pass" requires you to have run them. "MR is approved" requires you to have seen the approval. The monitoring loop in Phase 14 exists for exactly this reason.

---

## Phase 0: Initialize task tracking

Create the task list once at the start so the workflow is legible:

```
TaskCreate "Read Jira ticket {TICKET}"
TaskCreate "Locate and parse EMLs in /workspace/shared/{TICKET}/"
TaskCreate "Set up jurisdictions/cases for each EML"
TaskCreate "Reproduce the ticket's failure"
TaskCreate "Confirm reproduction matches ticket (gate)"
TaskCreate "Assign ticket to self + transition to In Progress"
TaskCreate "Investigate root cause and propose fix"
TaskCreate "Multi-agent review of proposed approach"
TaskCreate "Implement the fix on a clean branch"
TaskCreate "Multi-agent review of fix (up to 3 rounds)"
TaskCreate "Verify fix end-to-end against the original EML"
TaskCreate "Open MR, link to Jira ticket, post validation comment"
TaskCreate "Transition ticket to In MR"
TaskCreate "Monitor MR for review feedback until approved"
```

Mark each task `in_progress` when starting, `completed` when finished. This is non-optional.

---

## Phase 1: Read the Jira ticket

```bash
JTOKEN=$(cat "${JIRA_TOKEN_FILE:-/run/secrets/jira_api_token}")
curl -s -u "$JIRA_USERNAME:$JTOKEN" \
  "$JIRA_URL/rest/api/3/issue/{TICKET}?fields=summary,status,description,labels,priority,issuetype,assignee,reporter,comment,issuelinks"
```

Extract and surface to the user (and keep for later):
- **Summary, type, status, priority, labels** — drives commit message and decisions.
- **Description** — walk the ADF tree (`fields.description.content`) to get plain text; the reproduction steps, expected vs actual behavior, and any inbox-item hints live here.
- **Linked issues** (`issuelinks`) — note these; you'll cross-link them in Phase 12 if they're "Discovery — Connected", "is blocked by", or similar.
- **Comments** — read recent ones; sometimes the actual reproduction details are added as a comment, not in the description.
- **Reporter** — they're who you'll @mention if you need clarification you can't get from artifacts.

If the ticket is NOT a bug (Story, Task, Spike, Epic), stop and ask the user whether this skill is the right one. The reproduction-first flow doesn't apply to feature work.

---

## Phase 2: Locate EMLs in /workspace/shared/{TICKET}/

### 2a. Prefer an existing research report

```bash
SHARED_DIR="/workspace/shared/{TICKET}"
ls "$SHARED_DIR/{TICKET}.md" "$SHARED_DIR/raw/research.json" 2>/dev/null
```

If `research.json` exists, the `research-jira-bug` skill has already resolved this ticket's inbox
items, dropped duplicate emails, and clustered the failures. Use it instead of rediscovering:

- Read `{TICKET}.md` for the verdict and the per-issue breakdown.
- **With `--scope issue-N`**: take that issue's `emls[]` as your reproduction set and its
  `inboxIds[]`, `exception`, `topAppFrame` and `sampleStackHead` as the expected failure in Phase 5.
- **Without a scope**: if the report found exactly one issue, use it. If it found more than one,
  **stop and `AskUserQuestion`** — ask which issue this run should fix. Do not fix all of them in
  one MR; the report exists precisely because they are separable.
- If the report marks the scoped issue **not reproducible from artifacts**, stop and ask. This
  skill's whole strategy is EML-driven.

Reproduce **one email per issue**, not one per inbox item. The report has already established which
items carry the same email; re-running duplicates proves nothing and costs a full pipeline run each.

If the report is stale (the ticket has newer comments or inbox items than
`research.json`'s `generatedFor` run), re-run `research-jira-bug` rather than working from it.

### 2b. No research report — discover directly

```bash
ls -la "$SHARED_DIR"
find "$SHARED_DIR" -maxdepth 2 -type f -name "*.eml"
```

Outcomes:

| State | Action |
|---|---|
| 1+ EML present | Continue. List each EML and the `inbox_<id>` extracted from each filename (`inbox_item_inbox_<id>.eml`). |
| Several EMLs and no report | Consider running `research-jira-bug` first — it will tell you whether they are one failure or several before you fix the wrong one. |
| No EMLs but other files (PDF, screenshots, JSON) | Stop. `AskUserQuestion`: "No EMLs in the shared folder, but I see X, Y, Z. Should I use these as the reproducer? How?" |
| Folder doesn't exist or is empty | Run `research-jira-bug {TICKET}` — it pulls the EMLs off the admin site from the ids on the ticket. If that finds nothing either, stop and `AskUserQuestion`. |

If multiple EMLs exist, plan to process each in order. Most tickets have 1–3.

---

## Phase 3: Set up case + jurisdiction for each EML

For each EML, invoke the existing skill:

```
/setup-jurisdiction-and-case <eml-path> --firm {FIRM}
```

The skill:
- Detects provider from the `From:` header.
- Extracts court name and case number.
- Resolves the ECFX jurisdiction ID from `jurisdiction_metadata/Providers/*.csv`.
- Creates the firm jurisdiction, mapping, and case rows in Postgres (or skips if they already exist).

If the skill cannot extract court name or case number (returns an error or asks for manual input), do NOT guess. Inspect the EML headers/body, derive the values yourself, and pass them as overrides — or stop and ask the user.

Record each EML's resolved `inbox_<id>`, case number, and jurisdiction. You'll cite these in the Jira validation comment in Phase 12.

---

## Phase 4: Reproduce the failure

For each EML, invoke:

```
/process-email-notice-cli <eml-path> --firm {FIRM}
```

This builds the CLI from the current branch, processes the EML through the full pipeline, and reports the outcome (PROCESSING COMPLETE / CUSTOMER ACTION REQUIRED / specific Exception / OOM).

Things to extract from each run:
- **Outcome line** (e.g., `CUSTOMER ACTION REQUIRED FAILURE` or `PROCESSING COMPLETE`).
- **Top exception class and message** (`grep -oE "[A-Z][a-zA-Z]+Exception"` on the log).
- **Throwing class + line number** from the stack trace — this is the actual point of failure you'll be fixing.
- **Generated inbox item ID** (`inbox_<26-char>`) and **job ID** (`inbox_job_<26-char>`) — record for Phase 12.
- **Log file path** — keep for evidence.

Common gotchas:
- **Schema out of date** (`column X does not exist`). Run Flyway migrations: `gradle :db_migrator:run --args='migrate'`. May need a Flyway `repair` first if a prior branch left orphan history rows. The `/setup-jurisdiction-and-case` companion can help if specific tables are missing.
- **Prior-run state** triggers `ProcessorResult.duplicate()` instead of the real failure. The CLI skill detects and clears this automatically when `CLEAR_PRIOR_RUN=auto` (the default). If you suspect prior state, explicitly pass `--clear-prior-run yes`.
- **Wrong branch.** The CLI builds from the current git HEAD. Make sure you're on a clean branch from `master` (not someone else's WIP). Stash anything dirty first.

---

## Phase 5: Gate — confirm reproduction matches the ticket

**This is a mandatory pause point.** Before doing anything else, compare what you observed in Phase 4 to what the ticket says.

Reproduction matches when:
- Top exception class matches the ticket's reported exception.
- Throwing location is in the area the ticket implies (same module/class, give or take).
- The outcome (CUSTOMER ACTION REQUIRED / hard failure / OOM) matches the ticket's reported user-visible symptom.

If reproduction does **not** match:
- **Same exception, different location** → likely your repro is hitting a near-but-different code path; flag this and propose investigating further before fixing.
- **Different exception entirely** → either the ticket is stale or you're missing setup (credentials, feature flag, firm setting). Stop and `AskUserQuestion`.
- **No failure at all (passes cleanly)** → either the bug is already fixed, the EML doesn't actually trigger it, or your local env differs from prod in a relevant way. Stop and `AskUserQuestion`.
- **Different failure mode (OOM instead of exception, etc.)** → could be related, could be unrelated. Stop and `AskUserQuestion`.

Use `AskUserQuestion` with concrete observations. Example:

> The ticket says the failure is `ManualProcessNoticeException` at `TylersNorthCarolinaEmailReceiptProcessor.getJurisdictionFromDocument`. My repro instead throws `JurisdictionNotFoundException` at `BaseTylersEmailReceiptProcessor:609`. Options: (a) my setup differs — what should I change? (b) the ticket is stale and the real failure has moved — should I update the ticket? (c) proceed with the divergent failure since it's clearly related.

Do not proceed past this gate without either (a) clean reproduction matching the ticket, or (b) explicit user direction to continue.

---

## Phase 6: Assign + In Progress

Once reproduction is confirmed:

```bash
JTOKEN=$(cat "${JIRA_TOKEN_FILE:-/run/secrets/jira_api_token}")
ACCOUNT_ID=$(curl -s -u "$JIRA_USERNAME:$JTOKEN" "$JIRA_URL/rest/api/3/myself" | python3 -c "import sys,json; print(json.load(sys.stdin)['accountId'])")

# Assign to self
curl -s -X PUT -u "$JIRA_USERNAME:$JTOKEN" -H "Content-Type: application/json" \
  -d "{\"accountId\":\"$ACCOUNT_ID\"}" \
  "$JIRA_URL/rest/api/3/issue/{TICKET}/assignee"

# Find "In Progress" transition ID and apply it
TID=$(curl -s -u "$JIRA_USERNAME:$JTOKEN" "$JIRA_URL/rest/api/3/issue/{TICKET}/transitions" \
  | python3 -c "import sys,json; print([t['id'] for t in json.load(sys.stdin)['transitions'] if t['to']['name']=='In Progress'][0])")
curl -s -X POST -u "$JIRA_USERNAME:$JTOKEN" -H "Content-Type: application/json" \
  -d "{\"transition\":{\"id\":\"$TID\"}}" \
  "$JIRA_URL/rest/api/3/issue/{TICKET}/transitions"
```

Don't hardcode transition IDs — the workflow has per-project quirks. Always look them up.

If the ticket is already "In Progress" and assigned to someone else, stop and ask before stealing it.

---

## Phase 7: Investigate root cause and propose approach

This is where you read code. Open the throwing file + line from Phase 4. Trace up the stack. Find sibling implementations — almost every bug in a multi-tenant codebase has cousins (other states, other providers, other tenants). The cousins usually show you the right answer.

When you have a proposed approach, write it down (in chat, not on disk). The format:

> **Root cause**: [one sentence]
> **Why it's broken**: [walk the failing code path]
> **Proposed fix**: [specific change, with file paths + line numbers + a short before/after diff]
> **Why this works**: [tie back to root cause]
> **Why this is the right shape**: [reference any sibling code that already does it correctly]
> **Risk assessment**: [what could go wrong; what tests will catch it]
> **Scope boundary**: [what you are NOT fixing in this MR]

If the proposal touches more than one module/concept, **split it** before reviewing. Reviewers can evaluate small focused changes; they cannot evaluate sprawling proposals.

---

## Phase 8: Multi-agent review of the approach

Before writing code, get a sanity check. Spawn 2–3 agents **in parallel** (a single message with multiple `task` tool calls — critical for cost/latency). Pick agents based on the change:

| Change type | Suggested reviewers |
|---|---|
| Java/Micronaut backend change | `backend:java-micronaut-dev`, `shared:invent-simplify-reviewer` |
| Data model / query change | `backend:java-micronaut-dev`, `shared:prod-readiness` |
| Security-adjacent (auth, crypto, tenancy) | `shared:security-compliance-reviewer`, `shared:invent-simplify-reviewer` |
| Infra/deployment | `ops:aws-cloud-architect`, `shared:prod-readiness` |
| Anything user-facing or risky | Add `shared:prod-readiness` |

Each agent gets the full proposal (paste it), the affected file paths, and "reply under 400 words, focused, actionable." Do NOT delegate the synthesis — read the responses yourself and decide which feedback to act on.

If reviewers disagree fundamentally on the approach, **do another round** with a revised proposal that addresses the disagreement. Up to 3 rounds. If still no convergence, stop and `AskUserQuestion`.

If reviewers all say "approach is sound, just minor tweaks", you can incorporate those tweaks directly into the implementation in Phase 9 without another approach-review round.

---

## Phase 9: Implement the fix

Branch from master (NOT from the current branch — it may have unrelated WIP):

```bash
# Preserve any in-progress work first
git stash push -u -m "WIP before {TICKET} branch"

# Fresh branch from master
git fetch origin master
git checkout master
git pull --ff-only origin master
git checkout -b claude/{TICKET}_{short-slug}
```

Branch naming: `claude/{TICKET}_{short-slug}` (per project conventions stored in memory — never `username/...`).

Make the change. Write the test(s) **in the same commit**. Run the targeted test:

```bash
GRADLE_OPTS="-Xms2048m -Xmx2048m" ./gradlew --no-daemon :receipt_processing:test --tests "*YourSpec*" --console=plain
```

Run checkstyle on touched modules:

```bash
./gradlew --no-daemon :{module}:checkstyleMain --console=plain
```

If either fails, fix it before moving on. If the failure is in an unrelated file, treat it as a blocker only if it truly blocks (e.g., compilation-blocking stale import). Surgical incidental fixes are OK; refactor sprees are not.

---

## Phase 10: Multi-agent review of the implementation (up to 3 rounds)

Once tests pass locally, spawn the same flavor of agents you used in Phase 8, but reviewing the **actual diff** this time. Again **in parallel**. Each agent gets:

- The proposed root cause and fix summary (recap from Phase 7).
- The exact files changed + diffs (paste).
- The test you added.
- Verification evidence (test pass output, CLI repro outcome).
- "Reply under 400 words, focused, actionable. Flag blockers vs nits."

Categorize feedback:
- **Blockers** → must address before MR.
- **Should-do** → address in this MR if cheap; defer otherwise (with reason).
- **Nits** → address opportunistically if you're touching adjacent code.
- **Follow-up tickets** → mention in MR description, don't address here.

Up to 3 rounds. Each round, fix the blockers + cheap should-dos, then re-review. Stop early if all agents say "ship."

If two rounds in a row produce no blockers, you're done — don't keep grinding.

---

## Phase 11: Verify the fix end-to-end

Re-run the original EML through `/process-email-notice-cli`. Confirm the outcome changed from the Phase 4 failure to the expected success (or a different, intentional failure mode — e.g., the case fallback now correctly raises `CaseNotFoundException` instead of `ManualProcessNoticeException`).

Record the post-fix:
- Outcome line.
- New inbox item ID + job ID generated during the repro.
- Any new log line that proves the fix path was taken (e.g., `"falling back to case lookup"`).

These go in the Jira validation comment.

---

## Phase 12: Open MR, link to Jira, post validation comments

### Commit + push

```bash
git add <changed files>
git commit -m "$(cat <<'EOF'
{TICKET}: <short imperative description>

<paragraph: what's broken, why it matters, who's affected>

<paragraph: what the fix does and why it's the right shape — reference sibling code if applicable>

<paragraph: incidental fixes, if any>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin claude/{TICKET}_{short-slug}
```

### Create the MR via the GitLab API

```bash
TOKEN=$(sed -E 's#https://([^:]+):([^@]+)@.*#\2#' /run/secrets/git_credentials)
PROJECT_ID=11979607  # ecfx/ecfx-backend; look up via /api/v4/projects/<urlenc> if different

# Build description with: Summary, Problem, Fix, Verification, Reviews, Operational notes,
# Out-of-scope follow-ups, Incidental fix (if any), Test plan.
# Use /pr-description or /mr-description skill to generate a clean MR body.

curl -s -X POST -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
  -d "$PAYLOAD" "https://gitlab.com/api/v4/projects/$PROJECT_ID/merge_requests"
```

Capture the returned `web_url` and `iid` — you'll need both.

### Link the MR back to Jira

For **the primary ticket** and **every linked ticket** that's relevant (check `issuelinks` from Phase 1):

1. **Remote link** (shows in Web Links panel):
   ```
   POST $JIRA_URL/rest/api/3/issue/<KEY>/remotelink
   { "globalId": "system=gitlab.com&id=<MR_IID>",
     "object": { "url": "<MR_URL>", "title": "MR !<IID>: <commit subject>", ... } }
   ```

2. **Validation-evidence comment** (use ADF format — see structure in this skill's existing usage). Include:
   - Source EML path + byte size + original prod inbox ID embedded in the filename.
   - **Before fix**: local repro inbox ID, job ID, outcome, exception class + message, throwing class:line.
   - **After fix**: local repro inbox ID, job ID, outcome (PROCESSING COMPLETE), log evidence that the fix path was exercised, resolved jurisdiction/case if relevant.
   - Note that "the same EML produced both runs — only the processor code changed between them."
   - Reproducer command verbatim.

Posting this comment is non-negotiable — it's the receipts on the work. Reviewers and future-you will both rely on it.

---

## Phase 13: Transition ticket to In MR

```bash
# Find the transition (may be named "In Code Review" with target "In MR" — they aren't always the same string!)
TID=$(curl -s -u "$JIRA_USERNAME:$JTOKEN" \
  "$JIRA_URL/rest/api/3/issue/{TICKET}/transitions?includeUnavailableTransitions=true" \
  | python3 -c "
import sys, json
ts = json.load(sys.stdin)['transitions']
matches = [t for t in ts if t['to']['name'] == 'In MR']
print(matches[0]['id'] if matches else '', file=sys.stdout)")
curl -s -X POST -u "$JIRA_USERNAME:$JTOKEN" -H "Content-Type: application/json" \
  -d "{\"transition\":{\"id\":\"$TID\"}}" \
  "$JIRA_URL/rest/api/3/issue/{TICKET}/transitions"
```

If "In MR" doesn't appear in the default transitions list, retry with `includeUnavailableTransitions=true`. Some workflows hide transitions behind screen requirements but still allow them.

---

## Phase 14: Monitor MR for reviewer feedback (every 15 minutes until approved)

This is a long-running phase. Use `/loop` with a 15-minute interval, OR `ScheduleWakeup` with `delaySeconds=900`. Either way, the work each tick is the same:

```bash
TOKEN=$(sed -E 's#https://([^:]+):([^@]+)@.*#\2#' /run/secrets/git_credentials)

# Fetch discussions (review comments)
DISCS=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" \
  "https://gitlab.com/api/v4/projects/$PROJECT_ID/merge_requests/$IID/discussions")

# Fetch approvals
APPR=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" \
  "https://gitlab.com/api/v4/projects/$PROJECT_ID/merge_requests/$IID/approvals")
```

Each tick, decide:

1. **Has the MR been approved?** Check `APPR.approved_by[]` length > 0. If yes AND there are no unresolved blocker comments, stop the loop. Done.

2. **Are there new non-system review notes since last tick?** Read each one. Categorize:
   - **Blocker** (reviewer requests changes) → address now.
   - **Nit/should-do** → address now too (the user's instruction: "still address those items" even after approval).
   - **Question** → answer in the thread.
   - **Praise / agreement** → resolve the thread, no action.

3. **For each change you make in response**: commit on the same branch, push. Reply in the discussion thread acknowledging which nits were addressed in which commit. Use `POST .../discussions/<id>/notes` for threaded replies.

4. **If reviewer asks for a change you disagree with**: don't silently ignore it. Reply in the thread explaining your reasoning + ask for direction.

5. **If approved with small items pending**: address the small items, push, reply. Then check next tick that no new feedback appeared in response. THEN stop the loop.

Loop scheduling:
- Use `ScheduleWakeup` with `delaySeconds=900` (15 min) when expecting feedback within a workday.
- Use `delaySeconds=1800–3600` overnight or on weekends — but only with user buy-in (ask if not specified).
- Stop the loop unconditionally if: MR is merged, closed, or the user says "stop monitoring."

After every tick, update the relevant TaskList task with progress so the user can see what happened.

---

## Reference: useful one-liners

```bash
# Jira: get full issue with everything you'd want
JTOKEN=$(cat /run/secrets/jira_api_token)
curl -s -u "$JIRA_USERNAME:$JTOKEN" \
  "$JIRA_URL/rest/api/3/issue/<KEY>?fields=*all"

# Jira: walk the ADF description into plain text
python3 -c "
import sys, json
def walk(n, out):
    if isinstance(n, dict):
        if n.get('type') == 'text': out.append(n.get('text',''))
        for v in n.values():
            if isinstance(v, (list, dict)): walk(v, out)
        if n.get('type') == 'paragraph': out.append('\n')
    elif isinstance(n, list):
        for v in n: walk(v, out)
out = []; walk(json.load(sys.stdin), out); print(''.join(out))"

# GitLab: list MR discussions filtered to human (non-system) notes
TOKEN=$(sed -E 's#https://([^:]+):([^@]+)@.*#\2#' /run/secrets/git_credentials)
curl -s -H "PRIVATE-TOKEN: $TOKEN" \
  "https://gitlab.com/api/v4/projects/<PID>/merge_requests/<IID>/discussions" \
  | python3 -c "
import sys, json
for d in json.load(sys.stdin):
    for n in d.get('notes', []):
        if n.get('system'): continue
        print(f\"[{n['author']['name']}] resolved={n.get('resolved')}\")
        print(n.get('body',''))
        print('---')"

# GitLab: reply on a discussion thread
curl -s -X POST -H "PRIVATE-TOKEN: $TOKEN" \
  --data-urlencode "body=<reply text>" \
  "https://gitlab.com/api/v4/projects/<PID>/merge_requests/<IID>/discussions/<DISC_ID>/notes"
```

---

## Companion skills

- **`/research-jira-bug`** — the pre-phase. Resolves the ticket's inbox items, deduplicates the
  emails, and clusters the failures into distinct issues. Run it first when the ticket references
  more than one inbox item, or when the shared folder is empty. Feeds Phase 2 via `--scope`.
- **`/setup-jurisdiction-and-case`** — Phase 3.
- **`/process-email-notice-cli`** — Phases 4 + 11 (in-container variant). Use `/process-email-notice` instead if running on a developer Mac with the Docker harness.
- **`/cleanup-inbox-item`** — manual prior-run cleanup if the auto-detection in `/process-email-notice-cli` doesn't catch a particular case.
- **`/mr-description`** or **`/pr-description`** — Phase 12, generate the MR body.
- **`/commit-msg`** — Phase 12, generate the commit message.
- **`/loop`** or `ScheduleWakeup` — Phase 14.
- **`/senior-principal-reviewer`** — alternative reviewer in Phases 8 + 10.

## Anti-patterns

- **Skipping Phase 5 because "the ticket said X, it must be X."** Reproduce first, always.
- **Reviewing your own work.** Phase 8 and 10 require *other* agents. Self-review misses what fresh eyes catch.
- **Committing the agent's words verbatim into the MR description.** Synthesize. The MR description is yours, informed by reviews — not a transcript of them.
- **Letting the monitoring loop run forever.** If two ticks in a row produce no feedback and there's no approval, ping the user explicitly rather than continuing to burn cycles.
- **Touching files outside the bug's scope to "clean things up while I'm here."** Each scope creep makes the MR harder to review and easier to reject.
- **Fixing every cluster on a multi-issue ticket in one MR.** When `research-jira-bug` found N issues, fix one per MR. Ask which if no `--scope` was given.
- **Reproducing every inbox item on the ticket.** Duplicates of the same email prove nothing and cost a full pipeline run each. One email per issue.
