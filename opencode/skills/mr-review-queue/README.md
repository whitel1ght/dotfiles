# MR Review Queue skill

Daily-chore wrapper for the `mr-review` skill. Lists every open GitLab MR where you're an assigned reviewer, triages them into "needs action now / needs action when CI is green / waiting on author / informational", and walks through the actionable ones one MR at a time.

## What it does

When you say *"what MRs do I owe a review on?"* (or *"daily review queue"*, *"check my review backlog"*), the skill:

1. Calls `glab` cross-project to find every `state=opened` MR where you're a reviewer.
2. For each MR, fetches non-system notes and inspects pipeline + approval state.
3. Categorizes each into one of nine buckets (see below).
4. Presents a grouped, priority-ordered table.
5. On selection, hands off to the `mr-review` skill (which does the actual review-and-post).
6. In `walk` mode, refreshes after each post and presents the next actionable MR.

The triage is fast — typical queue of 10–20 MRs takes 3–5 seconds. State is always fresh; nothing is cached between invocations.

## Buckets

| Bucket | Display | Meaning |
|---|---|---|
| `review_now` | 🔴 REVIEW NOW | You've never reviewed; not draft; CI is green or N/A |
| `re_review_commits` | 🔄 RE-REVIEW | Author pushed commits since your last review |
| `re_review_response` | 💬 RE-REVIEW (response) | Author commented since your last review (no push) |
| `pipeline_running` | 🟡 PIPELINE RUNNING | CI in progress; soft-skip until done |
| `waiting_on_author` | ⏳ Waiting on author | You reviewed, ball in author's court |
| `pipeline_red` | 🚧 Pipeline red | CI failing; author probably still iterating |
| `already_approved` | ✅ Already approved by you | Skip; merge is on someone else |
| `draft` | 📝 Draft | Skip unless author pings |
| `conflict` | ⚠️ Conflict | Skip; needs rebase first |

The first three buckets are **actionable**; everything else is informational.

## Prerequisites

- **`glab` CLI** authenticated: `glab auth login`. Verify with `glab api user`.
- **Python 3.7+**. Most macOS systems have it via Xcode Command Line Tools (`python3 --version`).
- **The `mr-review` skill installed** (sibling skill in this repo). Composes via Claude's Skill tool — no shell call needed.

No additional setup beyond registering the marketplace (`./setup.sh`).

## How to invoke

In a Claude Code session:

- *"daily review queue"*
- *"what MRs do I owe a review on?"*
- *"check my review backlog"*
- *"walk my review queue"* (auto-walk mode)
- `/mr-review-queue`

### Selecting an MR

After the table is presented, reply with:

- **A specific ref** like `!5338` or `ecfx/ecfx-backend!5338` — invokes `mr-review` for that one.
- **`walk`** or **`all`** — steps through actionable MRs top-down. After each review, the queue refreshes and the next is offered.
- **`refresh`** — re-fetches the queue (useful if you've just posted and want fresh state).
- **`stop`** — exit.

If you pick an MR from a non-actionable bucket (e.g., a draft), the skill prompts before proceeding.

## Output format

Example shape (truncated for illustration):

```
Reviewer queue — 13 open MRs assigned to you (as of 14:35 UTC)

🔴 REVIEW NOW (5)
  ecfx/ecfx-backend!5338                 ECFX-13665: NUL byte strip + retry cap   adam.warbington   first time at you
  ecfx/ecfx-backend!5289                 ECFX-8992: Store import_ignore_…         smtsuchi          first time at you
  ecfx/claude-components!24              feat(skills): add Deploy to ECR…         travisECFX        first time at you
  ecfx/claude-components!22              feat(jira): add Jira CRUD skills         smtsuchi          first time at you
  ecfx/general-utilities/...!1           Update kubectl version handling          travisECFX        first time at you (year-old)

🔄 RE-REVIEW (0)
  (none)

💬 RE-REVIEW — author responded (4)
  ecfx/ecfx-backend!5268                 ECFX-6556, ECFX-13614: CC digest…       smtsuchi          adam.warbington replied since your last review
  ecfx/ecfx-backend!5136                 Migrate CI/CD to Git Flow                travisECFX       niles.ritter replied since your last review
  ecfx/ecfx-encryption-service!42        Modernize encryption-service             travisECFX       travisECFX replied since your last review
  ecfx/ecfx-dashboard!1972               ci: trigger dashboard-automation         levisiebensecfx  travisECFX replied since your last review

⏳ Skipped (4)
  ecfx/ecfx-backend!5321  draft (Postmark webhook shadow-ingest)
  ...

Pick one to start (e.g. `!5338`), say `walk` to step through actionable ones, or `stop` to bail.
```

## Walk mode

When you say `walk`:

1. Skill picks the first MR in the highest-priority actionable bucket (`review_now` first, then `re_review_commits`, then `re_review_response`).
2. Hands off to `mr-review`, which runs its full workflow (pre-flight → draft → approval gate → post).
3. Returns to the queue, re-runs triage (state may have changed), picks next actionable MR.
4. Loops until the actionable buckets are empty or you say `stop` / `pause` / `done`.

You can interrupt at any point — just say something like *"hold on, look at !5350 first"* and the skill will yield to that.

## Files

```
mr-review-queue/
├── SKILL.md                  # Claude-facing instructions
├── scripts/
│   └── triage.py             # Fetches + categorizes MRs, outputs JSON
└── README.md                 # This file
```

## How it works

The full instruction set is in `SKILL.md`. Key design choices:

- **Cross-project by default.** Uses `glab api /merge_requests?reviewer_username=…&scope=all` so a single invocation covers every project you can see — no per-repo flags.
- **System notes filtered out.** GitLab auto-generates notes for events like "approved" and "marked WIP". The triage skips these so they don't count as "author responded".
- **Pipeline-aware.** Pipeline state (`failed` / `running` / `success`) feeds bucketing — no point reviewing an MR whose CI is red because the author's still iterating.
- **No local checkout needed at this layer.** Triage operates entirely off `glab` API output. The local checkout is only required for the actual review (`mr-review` resolves it then).
- **Hand-off to `mr-review`, not duplication.** This skill triages; `mr-review` reviews. They compose via Claude's Skill tool, not shell calls.

## Limitations

- **GitLab only.** A `pr-review-queue` sibling using `gh` is straightforward; not built yet.
- **No persistent state.** The skill doesn't track "I already saw this MR yesterday" — every invocation is a fresh fetch. If you want a "what changed since I last triaged?" view, that's a future feature.
- **Approvals data depends on project config.** Some projects have approval rules; others don't. The `already_approved` bucket only fires when the GitLab API returns explicit approval state for the user.
- **No batch posting.** Each review still goes through `mr-review`'s approval gate individually. Good for safety, slower for queue-clearing if you trust the drafts.

## Troubleshooting

**"glab CLI not found"** — install via `brew install glab` and authenticate with `glab auth login`.

**Empty queue** — if you have no MRs assigned as reviewer, the skill says *"No open MRs assigned to you as a reviewer. 🎉"* and stops. This is correct behavior, not a bug.

**MR appears in wrong bucket** — the triage logic is conservative; if something looks miscategorized, run `python3 ${CLAUDE_SKILL_DIR}/scripts/triage.py | jq` and inspect the JSON. Open an issue with the raw data if it's a real bug.

**Note fetch is slow on large MRs** — triage fetches up to 100 notes per MR (one network call each). For a queue with many active discussions, this can take a few seconds. The script doesn't paginate beyond 100 notes; MRs with longer threads may show slightly stale categorization (rare).

**`walk` mode returns to a triage state that looks identical** — that's expected. Each iteration re-fetches; if nothing has changed externally (other reviewers, the author's actions), the next-up MR is the same as the previous-next-up. The skill handles this gracefully.

## Composition with `mr-review`

This skill explicitly **does not duplicate `mr-review`**. When you pick an MR, control hands off:

```
[mr-review-queue triages]
    ↓
[user picks !5338]
    ↓
[mr-review-queue invokes mr-review with "ecfx/ecfx-backend!5338"]
    ↓
[mr-review pre-flights, drafts, gates, posts — its own workflow]
    ↓
[control returns to mr-review-queue]
    ↓
[walk mode? → re-triage and continue. Else → done.]
```

The two skills compose cleanly: `mr-review-queue` decides *what to review next*; `mr-review` decides *how to review it*.
