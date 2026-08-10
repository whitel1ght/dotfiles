---
name: qa-comment
description: Use when the user wants a QA handoff comment for a branch or MR — e.g. "write a QA comment", "what should QA test", "qa comment for this branch", "prepare this for QA". Investigates the branch diff, works out affected areas and regression risk, writes a Jira-ready Markdown comment and copies it to the clipboard.
---

# QA Comment

## Overview

Turn a branch into a comment a tester can act on without reading the diff: what
changed, where to click, and what might have broken somewhere else.

The output goes on the clipboard ready to paste into a Jira comment box.

## Procedure

### 1. Gather the facts

```bash
~/.claude/skills/qa-comment/analyse.sh            # vs origin/master
~/.claude/skills/qa-comment/analyse.sh develop    # vs another base
```

Read the whole output before writing anything. It gives you the commits, files
grouped by type, CSS selectors touched, Python definitions changed, every
user-facing string that changed, routes in the changed files, and the test
result.

### 2. Work out the real blast radius

**This is the part the script cannot do, and the part that makes the comment
worth reading.** The file list is not the affected-area list.

Trace each change outward:

- **A stylesheet** reaches every page loading it. Grep the changed selectors —
  a rule scoped to a shared class can touch pages nobody edited. Do not assume
  the file list bounds it.
- **A base class or shared template** reaches every subclass or child. Find
  them rather than listing the parent.
- **A shared macro or partial** reaches every template importing it.
- **A route the framework generates** may not be in any nav menu. Confirm URLs
  rather than inferring them from decorators.
- **A widened condition** (an `if` that now matches more) affects records that
  never took that path before, which is where silent regressions live.

Verify in the browser or with a quick script where you reasonably can. A URL you
have not loaded is a guess; say so rather than putting a guess in front of QA.

### 3. Decide what QA should actually do

Each test case names a **URL**, an **action**, and an **observable result**.
"Check the firm page works" is not a test case. "Save a firm with ECFX Track
ticked → expect a green success message, not amber" is.

Prioritise by consequence, not by how much code changed:

- **P1** — data can be lost or corrupted, money moves, an irreversible action,
  a previously-broken thing now claimed fixed
- **P2** — visible behaviour a user depends on
- **P3** — cosmetic, or a refactor expected to change nothing

For a refactor, say **"expect no visible change"** explicitly and ask them to
raise anything that differs. That turns a vague look-over into a real check.

### 4. Write the comment

Markdown, because Jira Cloud's editor converts it on paste. Keep it short enough
to read in full — a tester who skims a wall of text tests nothing.

Structure:

```markdown
## <TICKET>: <one line on what changed and why it matters>

**Branch:** `<branch>` · **Base:** `<base>` · **Commits:** <n>

### What changed
<2–4 sentences in plain language. Name the user-visible effect, not the
implementation. A tester should understand this without opening the code.>

### Where to test
| Page | URL | What to check |
|---|---|---|
| Banner Tool | `/banner/` | Saving shows a **green** confirmation, not amber |

### Test cases
**P1 — <area>**
1. <action> → <expected observable result>
2. <action> → <expected observable result>

**P2 — <area>**
3. ...

### Regression risk
- **<area>** — <why this could break, what to look at>

### Not part of this change
- <known issue QA will otherwise report as new>

### Notes
- Tests: <result, or "not run — say which">
- <anything QA needs: data setup, feature flags, an env that must be seeded>
```

Drop any section that would be empty. An empty "Regression risk" heading is
noise; no regression risk at all is worth one line saying so.

### 5. Copy it to the clipboard

Write the comment to a file, then:

```bash
pbcopy < /tmp/qa-comment.md          # macOS
```

Confirm with the character count and tell the user it is on the clipboard.
Also print the comment in the chat so they can read it without pasting.

## Rules

- **Write for someone who did not write the code.** No class names, file paths
  or function names in the test cases. QA clicks a UI; give them the UI.
- **Never invent a URL.** Confirm it, or mark it clearly, e.g.
  `/firm/edit/?id=<FIRM_ID>` with a note to substitute a real id.
- **State what you did not verify.** "Not tested locally — no seed data for a
  firm with ECFX Retrieve" is useful. Silence is not.
- **List known-not-this-branch issues.** Every one you name is a bug report QA
  does not have to file and you do not have to triage.
- **Say when nothing should change.** For refactors this is the whole test.
- **No emoji, no exclamation marks.** This goes in a shared ticket.

## Notes

- The script's route section does not resolve blueprint prefixes — treat those
  as hints and confirm real URLs.
- If the repo has no test runner the script says so; report that rather than
  implying the branch is green.
- Works in any git repo, not just this one. Non-Python repos simply get fewer
  populated sections.
