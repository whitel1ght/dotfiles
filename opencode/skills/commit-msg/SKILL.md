---
name: commit-msg
description: >-
  Generate Conventional Commits messages for staged changes. Use when creating git commits, writing commit messages, or when user mentions committing changes, git commits, or needs help with commit message format.
---


# Commit Message Generator

Generate clear, informative commit messages following the Conventional Commits specification that explain the "why" behind changes.

## Dynamic Context

- **Staged changes** — run `git diff --cached`
- **Staged files** — run `git status --short`

## Process

### 1. Analyze Staged Changes

Review the pre-loaded staged changes and file summary above to understand what's being committed and the scope of modifications.

### 2. Determine Type and Scope

Identify the commit type from: **feat**, **fix**, **docs**, **style**, **refactor**, **perf**, **test**, **build**, **ci**, **chore**

Determine scope (optional but recommended): the area of codebase affected (e.g., api, ui, auth, database)

If changes span multiple unrelated areas, suggest splitting into separate commits.

### 3. Write Subject Line

Format: `type(scope): brief description`

Rules:
- Use imperative mood: "add" not "added" or "adds"
- Don't capitalize first letter after colon
- No period at end
- Keep under 72 characters
- Be specific and clear

### 4. Compose Body

Explain (wrap at 72 characters):
- **Why** the change was necessary (problem/motivation)
- **What** approach was taken (high-level strategy)
- **How** it impacts the system (side effects, considerations)
- **Any** tradeoffs or alternatives considered

Include:
- Blank lines between paragraphs
- Bullet points for lists
- Issue references (e.g., "Fixes #123")
- Context not obvious from the diff

### 5. Identify Breaking Changes

Check if changes:
- Modify public APIs incompatibly
- Change expected behavior users depend on
- Require migration steps
- Remove or rename features

If yes, you have two options:

**Option A**: Add `BREAKING CHANGE:` footer explaining:
- What broke and why
- Migration path
- New expected behavior

**Option B**: Add an exclamation mark after the type/scope in the subject line:
- Format: `feat(scope)` followed by exclamation mark and colon
- Example: `feat(api)` + exclamation mark + `: redesign authentication`
- This signals breaking changes in the commit subject

### 6. Add Attribution Footer

Always include (separated by blank line):

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### 7. Present and Validate

Before finalizing, verify:
- Type and scope are accurate
- Subject line under 72 characters, proper format
- Body explains WHY, not just WHAT
- Breaking changes properly flagged
- Line wrapping at 72 characters

Present the complete message in a code block and offer to:
- Make revisions based on feedback
- Execute the commit
- Adjust type or scope

## Format Template

```
type(scope): subject line under 72 chars

Body paragraph explaining why this change was made and what
problem it solves. Wrap at 72 characters. Use blank lines to
separate paragraphs.

Additional context, tradeoffs considered, or implementation
details that provide value for future readers.

BREAKING CHANGE: Description of breaking change if applicable.
Include migration path and new behavior.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Quality Checklist

- [ ] Type matches the nature of changes
- [ ] Scope accurately represents affected area
- [ ] Subject line follows all formatting rules
- [ ] Body explains motivation and context
- [ ] Breaking changes documented if applicable
- [ ] Attribution footer included
- [ ] Message clear to someone reviewing in 6 months

## Special Cases

**Multiple Unrelated Changes**: Suggest splitting into focused commits

**Trivial Changes**: Keep simple but follow format:
```
docs: fix typo in README

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Large Refactoring**: Focus body on architectural benefits and testing strategy

**First Commit**: Use `chore: initial commit` with attribution footer

## Output Format

Present commit message in a code block for easy copying. Ask user if they want to:
1. Proceed with this message
2. Make revisions
3. Execute the commit automatically

---

For detailed examples, see `examples.md`
For complete specification, see `reference.md`
