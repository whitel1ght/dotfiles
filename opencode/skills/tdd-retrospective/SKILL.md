---
name: tdd-retrospective
description: >-
  Capture lessons learned after completing TDD work on a Micronaut component. Use after finishing implementation and tests, when user mentions retrospective, lessons learned, or when wrapping up a TDD task.
---


# TDD Retrospective

Capture structured lessons from TDD work to build institutional knowledge. Every completed task should leave the team smarter for the next one.

## Reflection Prompts

Before writing the entry, reflect on:

1. **What worked well?** — Patterns, tools, or approaches that saved time or prevented errors.
2. **What was difficult or surprising?** — Unexpected behavior, confusing APIs, configuration gotchas.
3. **What patterns did you discover?** — New techniques, workarounds, or reusable solutions.
4. **Did learnings from previous tasks help?** — Which Critical Patterns or Recent Lessons were valuable?
5. **What would you do differently next time?** — Concrete changes to approach or workflow.

## Entry Format

Each entry must follow this structure (compatible with tdd-context-loader parsing):

```markdown
### [YYYY-MM-DD] - [Layer] - [Component Name]
- **Lesson**: [what was learned — must be actionable]
- **Discovery**: [unexpected finding, or "None"]
- **Fix Applied**: [what resolved the issue, or "None"]
- **Outcome**: [concrete result, e.g., "8 tests passing, full build green"]
```

**Field rules**:
- **Layer**: One of `Entity`, `Repository`, `Service`, `Controller`
- **Lesson**: Must be actionable, not just "X was hard"
- **Outcome**: Must be measurable, not vague

## Process

### 1. Prompt Structured Reflection

Ask the reflection prompts above (or self-reflect if task context is clear).

### 2. Read Current Learnings File

Read `~/.claude/docs/tdd-learnings.md`. If missing, create it using the template from tdd-context-loader skill.

### 3. Add New Entry Under "Recent Lessons"

Insert the new entry at the **top** of the "Recent Lessons" section (newest first).

### 4. Promote Recurring Patterns to "Critical Patterns"

Scan all entries (Recent Lessons + Archive) for patterns appearing in **3 or more** separate entries:
- Add concise summary to "Critical Patterns" section
- Include which tasks confirmed the pattern (dates and components)
- Do NOT remove original entries

### 5. Prune Recent Lessons to Last 5 Entries

If "Recent Lessons" has more than 5 entries:
- Keep the 5 newest in "Recent Lessons"
- Move older entries to "Archive" section, preserving format

### 6. Save Updated File

Write updated content to `~/.claude/docs/tdd-learnings.md`.

## Quality Checks

Before saving, verify:

- [ ] **Actionable**: Lesson tells you what to DO, not just what happened
- [ ] **Contextual**: Enough detail to be useful in 3 months
- [ ] **No duplicates**: Same lesson not already in Recent Lessons
- [ ] **Correct format**: Follows `[Date] - [Layer] - [Component]` template
- [ ] **Concrete outcome**: Measurable result, not vague statement

If a duplicate is detected, update the existing entry with new context rather than adding a new one.
