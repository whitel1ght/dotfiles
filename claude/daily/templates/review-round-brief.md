# Review round: {{KEY}} — {{REPO}}!{{MR_IID}}

You address a code review on a merge request. Work in the worktree below. Nothing you do may be pushed or posted: the orchestrator asks the user first.

## Where
- Worktree: {{WORKTREE}} (branch `{{BRANCH}}`). Work only inside it. Read its `CLAUDE.md` first.
- MR: {{MR_URL}} (project path `{{PROJECT_PATH}}`, iid {{MR_IID}})
- Review to answer: the newest review note by someone else. The triggering event was: {{EVENT_LINE}}

## Limits
- You may not: push, post any comment on the MR, no Slack, no Jira transition, or touch another worktree.
- You must never write to `~/wiki` (the long-term memory). You write only `{{REPLY_FILE}}`; give the orchestrator what to record in the `memory:` block below.

## Steps
1. Read the review. Number every finding (use the reviewer's IDs if it has them).
2. For each finding decide: **fix**, **decline** (with a reason and what would change your mind) or **defer** (with where it is tracked). For a fix, write a test that fails before the fix and passes after it where that is possible, make the fix, and commit locally. One commit per finding or group of findings, Conventional Commits, message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.
3. Read the `shared:mr-review-response` skill and follow its steps 1 to 4 exactly (enumerate, classify, attach evidence, state the head). **Stop before its step 5**: do not run `curl`, `glab mr note` or `glab api` to post, do not post a Jira comment, do not change labels or approvals. Every finding appears in the reply, declined and deferred ones included.
4. Write the reply, in that skill's table format, to `{{REPLY_FILE}}`. Where the skill says to take the token from `/run/secrets/git_credentials`, use `glab` instead; you only need read access here. Record the discussion id of the review note.

## Report (under 200 words, no diff, no narration)
1. `discussion: <id of the review's discussion>`
2. `reply_file: {{REPLY_FILE}}`
3. Per finding: id, fixed / declined / deferred, commit SHA if fixed, one line.
4. Tests run: exact command and result; must-fail evidence for each guard test.
5. Old head and new head (short SHAs).
6. `memory:` block:

```
memory:
  project: {{PROJECT}}
  log: "<one paragraph: what the review asked and what was done>"
  decision: {title, context, decision, consequences} | none
  state_change: "<one line>" | none
```
