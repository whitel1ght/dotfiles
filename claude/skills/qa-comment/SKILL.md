---
name: qa-comment
description: Use when the user wants a QA handoff comment for work done in this session — e.g. "write a QA comment", "what should QA test", "qa comment for this", "prepare this for QA". Writes a Jira-ready Markdown comment from the session's own implementation context and copies it to the clipboard.
---

# QA Comment

## Overview

Write the QA handoff for work done **in this conversation**, and put it on the
clipboard ready to paste into a Jira comment.

**Source the comment from what you already know, not from a fresh `git diff`.**
By the time this is invoked you have context no diff contains: why each change
was made, which decisions were deliberate, what you verified in the browser and
what you did not, which edge cases you already ruled out, which findings came
from review, and what broke along the way and got fixed. That is the material
QA actually needs. Re-deriving from the diff throws it away and produces a
worse comment.

Use git only to fill gaps — the branch name, a commit count, a file you touched
early and want to re-check. Never as the starting point.

## Procedure

### 1. Recall the work

Before writing, answer these from the session:

- What was the user-visible problem, and what does the fix change for someone
  using the app?
- Which pages did you actually load and check? Which did you not?
- What did you deliberately **not** change, and why? (Out-of-scope findings,
  pre-existing issues, things review raised and you rejected with reasoning.)
- What surprised you? A defect found mid-implementation, a false assumption
  caught by a measurement, a review finding you had to verify — those are
  exactly where a regression hides.
- What is already known-broken and unrelated? Every one you name is a bug
  report QA does not file and you do not triage.

If the session covered several tickets, ask which one the comment is for rather
than merging them.

### 2. Work out the blast radius

**The file list is not the affected-area list.** You know from building it
whether a change was local or shared:

- A stylesheet or shared macro reaches every page that loads it
- A base class reaches every subclass
- A widened condition affects records that never took that path before
- A framework-generated route may exist without appearing in any nav menu

Where you already verified reach during the session, say so and give the number.
Where you did not, say that instead of guessing.

### 3. Write the comment

Markdown — Jira Cloud's editor converts it on paste. Keep it short enough to be
read in full; a tester who skims a wall of text tests nothing.

```markdown
## <TICKET>: <one line on what changed and why it matters>

**Branch:** `<branch>` · **Commits:** <n>

### What changed
<2–4 sentences in plain language. The user-visible effect, not the
implementation. A tester should follow this without opening the code.>

### Where to test
| Page | URL | What to check |
|---|---|---|
| Banner Tool | `/banner/` | Saving shows a **green** confirmation, not amber |

### Test cases
**P1 — <area>**
1. <action> → <expected observable result>

**P2 — <area>**
2. ...

### Regression risk
- **<area>** — <why this could break, what to look at>

### Not part of this change
- <known issue QA would otherwise report as new>

### Notes
- Tests: <result, or "not run">
- <data setup, feature flags, anything QA needs before starting>
```

Drop any section that would be empty.

Priority is by consequence, not by how much code changed:

- **P1** — data loss or corruption, money moves, an irreversible action, or a
  previously-broken thing now claimed fixed
- **P2** — visible behaviour a user depends on
- **P3** — cosmetic, or a refactor expected to change nothing

Each test case names a **URL**, an **action** and an **observable result**.
"Check the firm page works" is not a test case. "Save a firm with ECFX Track
ticked → expect a green success message, not amber" is.

For a refactor, say **"expect no visible change"** explicitly and ask QA to
raise anything that differs. That turns a vague look-over into a real check.

### 4. Copy it to the clipboard

```bash
pbcopy < /tmp/qa-comment.md
```

Print the comment in the chat as well, and confirm the character count. The
user should be able to read it without pasting anywhere.

## Rules

- **Write for someone who did not write the code.** No class names, file paths
  or function names in the test cases — QA clicks a UI, so give them the UI.
- **Never invent a URL.** Use one you loaded this session, or mark it clearly:
  `/firm/edit/?id=<FIRM_ID>` with a note to substitute a real id.
- **State what you did not verify.** "Not tested locally — no seed data for a
  firm with ECFX Retrieve" is useful. Silence is not.
- **Point QA at what you nearly got wrong.** If a measurement corrected you, or
  review caught something, that area deserves an explicit test case — it is
  where a second pair of eyes pays off most.
- **No emoji, no exclamation marks.** This goes in a shared ticket.

## Notes

- If invoked in a fresh session with no implementation context, say so and ask
  the user to point at the branch — then read the diff and commit messages
  first. That is the degraded path, not the intended one.
- Markdown is deliberate: it renders in Jira Cloud's editor, and degrades to
  readable plain text if pasted into an older wiki-markup box. Wiki markup
  pasted into a Markdown box does not degrade — it renders as literal `h3.`
  and `||`.
