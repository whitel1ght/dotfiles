---
name: tdd-context-loader
description: >-
  Load TDD context and accumulated learnings before starting a TDD task. Use when beginning work on a Micronaut component (entity, repository, service, controller), when the tdd-micronaut-v2 agent starts, or when user mentions starting a new TDD task.
---


# TDD Context Loader

Load accumulated TDD learnings to avoid repeating mistakes and leverage discovered patterns. Primes the agent with institutional knowledge before any TDD work begins.

## Process

### 1. Read the Learnings Files

Read **both** learnings files (if they exist):

1. **Global**: `~/.claude/docs/tdd-learnings.md` — shared learnings across all projects.
2. **Project-local**: `{repo-root}/.claude/docs/tdd-learnings.md` — learnings specific to the current repository.

Determine the repo root from the session's working directory (e.g., the nearest parent containing `.git/`).

- If the **global** file does not exist, create it using the template below.
- The **project-local** file is optional. If it exists, load it; if not, skip it silently.
- When both files exist, merge their contents: project-local entries take precedence when they conflict with global entries for the same layer/component.

### 2. Summarize Recent Lessons

Extract the **5 most recent entries** across both files (merged by date, most recent first). For each, output:
- Date / Layer / Component
- Source: `[global]` or `[project]`
- Key lesson (one sentence)
- Fix applied (if any)

### 3. Highlight Layer-Relevant Patterns

Detect the current layer from conversation context. If detectable:
- Pull matching entries from "Critical Patterns" mentioning that layer
- Pull "Recent Lessons" tagged with the same layer
- Present under a "Relevant to This Layer" heading

If layer is unclear, list the top 3 most broadly applicable Critical Patterns.

### 4. Report Warnings and Blockers

Scan the "Warnings" section. Present any active warnings prominently.

### 5. Output Format

```
--- TDD Context Loaded ---

**Recent Lessons** (last 5):
1. [Date] [Layer] [Component] [global|project] - [lesson summary]
2. ...

**Relevant Patterns**:
- [pattern name]: [one-line description]

**Active Warnings**:
- [warning text, or "None"]

--- Ready to begin TDD work ---
```

## Template for tdd-learnings.md

If `~/.claude/docs/tdd-learnings.md` does not exist, create it with:

```markdown
# TDD Learnings

Accumulated knowledge from TDD work on Micronaut components. Updated after each task by the tdd-retrospective skill.

## Critical Patterns

_Patterns confirmed across 3 or more tasks. These are high-confidence best practices._

## Recent Lessons

_Rolling window of the last 5 completed tasks. Older entries are archived below._

## Warnings

_Active warnings and blockers that must be checked before starting new TDD work._

## Archive

_Lessons older than the recent-5 window, preserved for reference._
```
