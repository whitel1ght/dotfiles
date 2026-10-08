---
name: mr-description
description: >-
  Generate comprehensive merge request descriptions that tell the full story of a change. Use when creating MRs, writing MR descriptions, or when user mentions merge requests, MRs, or needs help with MR documentation.
---


# MR Description Generator

Generate structured, reviewer-friendly merge request descriptions that explain the full narrative arc of a change — not just what changed, but why, how the conclusion was reached, and what reviewers should validate.

## Dynamic Context

- **Current branch** — run `git branch --show-current`
- **Upstream ref** — run `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "(none set)"`
- **Recent commits on this branch** — run `git log --oneline -25`
- **Working tree** — run `git status --short`

> **Determining the review range — do this explicitly, in separate Bash calls.**
>
> These context commands are deliberately free of nested command substitution. A
> worktree-isolated session refuses compound git commands it cannot statically verify, and
> the previous `$(git merge-base HEAD origin/$(git rev-parse ...))` form made this whole
> skill unrunnable in every such session — which is most sessions in a worktree-heavy repo.
> It failed as "Shell substitution failed", naming nothing near the cause.
>
> Two further reasons not to derive the target branch from the upstream, which that form did:
> after `git push -u`, the upstream IS the branch itself, so the range collapses to
> `HEAD..HEAD` and reports an empty MR. And the upstream was never the same thing as the MR's
> target — a branch cut from `trv2-phase2` still pushes to its own remote ref.
>
> So ask for (or confirm) the actual target branch, then run these as three separate calls:
>
> ```
> git merge-base HEAD origin/<target-branch>     # -> <base>
> git log <base>..HEAD --oneline
> git diff <base>..HEAD --stat
> ```

## Process

### 1. Analyze the Branch

Review all commits on the branch (not just the latest). Understand:
- The full scope of changes across all commits
- Which changes are the primary fix vs supporting work
- Whether changes are confirmed fixes or speculative mitigations

### 2. Determine the Change Type

Classify the MR to select the right description template:

- **Bug fix**: Use Investigation & Decision Tree sections
- **Feature**: Use Motivation & Approach sections
- **Refactor**: Use Problem & Benefits sections
- **Infrastructure/Config**: Use Context & Impact sections
- **Migration**: Use Before/After & Risk sections

### 3. Write the Title

Format: `ECFX-NNNN: Brief description`

Rules:
- Include JIRA ticket reference
- Keep under 72 characters
- Be specific about the fix/feature, not the symptom

### 4. Build the Description

#### Reviewer Summary (always required — the FIRST section, before everything else)

Open every description with a `## Reviewer Summary` section written in simple human terms,
for a reviewer who has NOT read the ticket. It has two required parts and one conditional:

1. **The problem** — 2–4 sentences: what the ticket is about and what is wrong or missing.
   Plain language, no class names, no jargon. If a paying customer or operator is affected,
   say so in their terms.
2. **What this MR does** — 2–4 sentences: the *shape* of the fix, not the mechanics.
3. **A diagram — only when it shows something the two paragraphs cannot.** GitLab renders
   ` ```mermaid ` fences natively (flowchart or sequenceDiagram). Draw one when the change is
   about a mechanism whose *shape* is what the reviewer must judge: an ordering or a race, a
   state machine, a before/after control flow, the rejected design beside the shipped one
   when the obvious implementation is the dangerous one, the exact statement placement that
   causes a bug. Omit it when it would only restate the prose — docs-only, config-only,
   renames and cleanups, test-only changes, a one-branch guard, a value change. A diagram
   that restates the paragraphs costs the reviewer more than it gives; the two paragraphs
   are the summary, the diagram is evidence. When you do draw one:
   - Draw the **mechanism the change touches**, not a generic architecture map.
   - Use before/after subgraphs when the change replaces a behavior.
   - Make it **carry the argument, not just an illustration**.
   - Use color **only** to mark the failure path, never decoratively.
   - Say nothing when it is omitted — no "no diagram needed" line.

Every technical explanation stays BELOW the Reviewer Summary, in the sections that follow. When
updating an existing MR, prepend the Reviewer Summary onto the description fetched fresh from the
API (never a local copy), and skip if a `## Reviewer Summary` heading is already present. If the
description opens with the heading's earlier spelling, `## TL;DR for reviewers`, rename it in
place rather than adding a second section.

#### Summary (always required)

2-3 sentences stating what the MR does. If there are multiple changes, number them and label each as:
- **Root cause fix** — the primary change
- **Speculative mitigation** — supporting change with uncertain impact
- **Supporting** — test infrastructure, config, etc.

#### Investigation & Decision Tree (bug fixes)

This is the most valuable section. Walk through the investigation step by step:

1. **Observation** — What was seen? Where? When? Include data (log counts, time ranges, environments compared).
2. **Step N — [Action taken]** — Each step should explain what was examined, what was found, and what conclusion was drawn.
3. Show the causal chain with code/call traces where helpful.
4. Explain why the problem didn't manifest before (environment differences, untriggered code paths, behavioral changes in dependencies).
5. State why the fix works — connect it back to the root cause.

Use markdown formatting:
- **Bold** for key terms and conclusions
- Code blocks for call traces, config snippets, stack traces
- Numbered steps for the investigation sequence

#### Speculative Changes (when applicable)

If any change is not a confirmed fix, create a separate section:
- Label it clearly as speculative
- Explain the reasoning and evidence
- State what is unknown
- Explain why it's low-risk

#### Motivation & Approach (features)

- What user/business problem does this solve?
- What approach was chosen and why?
- What alternatives were considered and rejected?

#### Test Plan (always required)

Use checkboxes. Separate into:
- [x] Automated tests — describe what was tested and the RED/GREEN methodology if TDD
- [ ] Manual validation — deployment verification, monitoring checks
- [ ] Post-merge tasks — what to watch for after deployment

Be specific about test methodology:
- What is mocked vs real
- What the test proves (not just "tests pass")

#### New Infrastructure (when applicable)

If the MR introduces test infrastructure, new patterns, or config changes that affect future work, call them out. This helps reviewers understand the full scope.

### 4b. Runbook fields that must be re-verified on every push

Parts of the description are instructions operators will act on before the code runs. They drift
when a later round renames something and only the code moves. On **every** push, not just the
first:

1. Diff the change's config surface against the description:
   ```bash
   git diff origin/<target>...HEAD -- '*.yml' '*.yaml' '*.java' '*.ts' | grep -oE '\$\{[A-Z][A-Z0-9_]*' | sort -u
   ```
   Every variable listed must appear in the description with the **current** name, and every
   variable in the description must still exist in the diff.
2. If a name changed since the last push, **post a standalone MR comment** — "renamed; if you
   already created `OLD`, delete it and create `NEW`" — in addition to editing the description.
   The comment reaches people who already acted on the old text; the edit does not.
3. Decisions recorded in the description ("we deliberately do X") must match the code after each
   round. A reversed decision keeps its section, rewritten, with a one-line note that it was
   reversed and why.
4. Per-environment tables use "operator to fill" for values you cannot know. Never invent them.

For a **stacked** MR (target is another MR's branch), the description states: the parent MR,
that GitLab retargets to master automatically when the parent merges, and "do not retarget by
hand". For a **split** MR, both descriptions name the other and state which files moved.

### 5. Add Attribution Footer

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 6. Record Review Approval

Before creating the MR, record a marker so the pre-MR hook knows this skill was run:

```bash
/Users/dmitry/projects/claude-components/hooks/record-mr-review-marker.sh
```

Pass the repo directory as an argument if you are not already in it.

This ties the review to the current repo and branch. The hook will block `glab mr create` if this marker is missing.

**Do not inline the hash recipe here instead.** It used to be a compound one-liner
(`REPO_HASH=$(git rev-parse …) && BRANCH_HASH=$(git branch …) && echo > …`) and that failed
two ways at once: a worktree-isolated session refuses git inside command substitution, so it
could not run at all; and no narrow permission rule can match a shape like that, so it hit the
auto-mode classifier every time. Both failures land on the LAST step of this skill, after the
description is already written — the gate blocks and nothing says why. The script exists so
there is one argv to allow and no substitution to reject; this skill's own frontmatter
(`allowed-tools`) pre-approves exactly it, so it never prompts.

**Important**: Always run this step after generating the description, even if the user wants to make revisions first. The marker just records that `/mr-description` was invoked.

### 7. Create the MR

Write the generated description to a file, then create the MR through `glab api` with a
file field — **not** `glab mr create --description "$(cat …)"`:

```bash
glab api --method POST "projects/<group>%2F<repo>/merge_requests" \
  -f source_branch="$(git branch --show-current)" \
  -f target_branch="<target-branch>" \
  -f title="ECFX-NNNN: title" \
  -F description=@/path/to/description.md
```

Why this form: `glab mr create` has no `--description-file`, and the
`--description "$(cat …)"` shape is nested command substitution, which worktree-isolated
sessions refuse outright — the same failure class that made the old Dynamic Context block
unrunnable. The `glab api` POST to a terminal `merge_requests` path is explicitly covered by
the review hook, so the gate still fires (and consumes the marker) — this is not a bypass.
After posting, **diff the posted description against the source file** (a file-field round trip
is exactly where a mermaid fence gets mangled).

A byte-identical round trip does not mean the diagram renders. **Parse the fence before you post
it**: `mermaid.parse()` under jsdom (`npm i mermaid jsdom`, then set `window`/`document` from a
`JSDOM` and `await mermaid.parse(text)`) reproduces GitLab's "Syntax error in text" exactly, with
the offending line. The trap that prompted this: an edge label that begins with `--`
(`H -- --input unreadable --> G`) is lexed as an arrow, so keep flag names out of labels or
quote them (`-->|"input unreadable"|`) and quote any node text holding `?`, `=`, `:` or `(`.

If the MR already exists, offer to update the description instead — same shape, `--method PUT`
to `merge_requests/<iid>` with `-F description=@file`, after re-recording the marker (it is
consumed per write).

### 8. Post RCA and QA Test Plan to Jira

If the MR title contains a Jira ticket reference (e.g., `ECFX-NNNN`), post a comment to that ticket with an RCA summary and a QA-oriented test plan.

**Adapt the comment based on change type:**

- **Bug fixes**: Include a root cause summary and verification steps
- **Features**: Include a description of the new behavior and validation steps
- **Config/Infra changes**: Include what changed and how to confirm it's working
- **Refactors**: Include what was restructured and regression checks

**Format the Jira comment as:**

```
h3. Root Cause Analysis

[2-3 sentence summary of the root cause written for a non-developer audience. Explain *what* went wrong and *why*, not the code-level fix. For features, explain the motivation instead.]

h3. QA Test Plan

The following steps verify this change in [environment]:

# [Step-by-step manual verification instructions]
# [Each step should be concrete and actionable — specific URLs, buttons, inputs, expected results]
# [Include pre-conditions if needed (e.g., "Using a firm with Unicourt enabled")]
# [Include negative cases — verify the old bug no longer reproduces]
# [Include regression checks — verify related functionality still works]

h3. What to Watch For

* [Post-deployment signals QA should monitor — specific error messages, log patterns, or behaviors that would indicate a problem]

---
_Posted by Claude Code from MR !NNNN_
```

**Rules:**
- Write for a QA engineer who hasn't seen the code — no class names, method names, or technical jargon
- Use Jira wiki markup (not markdown) — `h3.` for headings, `#` for ordered lists, `*` for bullets
- Steps should be executable in a real environment, not abstract ("click X" not "verify the feature works")
- Ask the user which environment to reference (dev, staging, production) if not obvious
- Use the Atlassian MCP’s matching tool to post the comment
- Cloud ID: `1c62390f-4296-41c6-ac4c-07fab33b5185`

### 9. Present and Validate

Before finalizing, verify:
- All commits on the branch are represented
- Investigation steps are traceable and evidence-based
- Speculative changes are clearly labeled
- Test plan is specific and actionable
- Title includes JIRA reference
- Description is useful to a reviewer unfamiliar with the context

## Quality Checklist

- [ ] Reviewer Summary is the FIRST section: plain-language problem + fix, no jargon
- [ ] Reviewer Summary has a mermaid diagram ONLY if it shows a mechanism the prose cannot (ordering, state, before/after, rejected design) — none for docs/config/rename/test-only changes
- [ ] Title includes JIRA ticket reference
- [ ] Summary distinguishes root cause fix from speculative changes
- [ ] Investigation shows the reasoning chain, not just the conclusion
- [ ] Each investigation step cites evidence (logs, code, comparisons)
- [ ] Speculative changes are explicitly labeled with reasoning
- [ ] Test plan describes what is proven, not just "tests pass"
- [ ] New infrastructure or patterns are called out
- [ ] Description is useful to a reviewer in 6 months
- [ ] RCA and QA test plan posted to Jira ticket (if ticket reference present)

## Special Cases

**Single-commit MR**: Keep it concise but follow the structure. Investigation section can be shorter.

**Config-only changes**: Focus on why the config changed, what environments are affected, and how to verify.

**MR addressing review feedback**: If updating an existing MR after review, summarize what changed in a new comment rather than rewriting the entire description.

**Multiple unrelated fixes**: Suggest splitting into separate MRs. If they must stay together, use clear section headers for each fix.

---

For detailed examples, see `examples.md`
