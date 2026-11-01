---
name: pre-commit-review
description: >-
  Review staged changes before committing to catch common issues and generate self-review checklist. Use when reviewing staged changes, before commits, or when user mentions pre-commit checks, commit readiness, or wants to verify changes before committing.
---


# Pre-Commit Review

Review staged changes to catch common issues before committing and generate a tailored self-review checklist to ensure changes are commit-ready.

## Process

### 1. Analyze Staged Changes

Run these commands to examine what's being committed:
- `git status` - See which files are staged
- `git diff --cached` - View the actual changes
- Understand the scope and type of modifications

### 2. Scan for Common Issues

Check staged changes for these categories of problems:

**Debug Code:**
- `console.log`, `console.debug`, `console.error` (JavaScript/TypeScript)
- `print()`, `pprint()` statements (Python)
- `System.out.println`, `printStackTrace()` (Java)
- `debugger` statements
- Logging statements that appear temporary

**Incomplete Work Markers:**
- `TODO:` comments indicating work not finished
- `FIXME:` comments indicating known problems
- `HACK:` comments indicating problematic solutions
- `XXX:` or similar markers

**Dead Code:**
- Large blocks of commented-out code
- Unused imports or variables
- Unreachable code paths

**Sensitive Data:**
- Hardcoded API keys, tokens, passwords
- Database connection strings with credentials
- Private keys or certificates
- Email addresses or personal information
- Internal URLs or hostnames

**Dangerous Files:**
- `.env` files with secrets
- `credentials.json`, `secrets.yaml`
- Private key files (`.pem`, `.key`)
- Config files with sensitive data
- IDE-specific files that shouldn't be committed

**Missing Test Coverage:**
- New functions/methods without corresponding tests
- New API endpoints without integration tests
- Bug fixes without regression tests
- Public interfaces without test coverage

**Formatting Issues:**
- Inconsistent indentation (mixed tabs/spaces)
- Trailing whitespace
- Missing newline at end of file
- Files with Windows line endings in Unix project (or vice versa)
- Inconsistent code style compared to project

### 2b. Refactor blast radius and guard evidence

Two checks that a green filtered test run cannot substitute for:

**Blast radius of a changed signature.** For every public/package method whose signature or
semantics changed in the staged diff, find *every* caller — production code and tests, including
legacy `*Test.java` files that the repo's Spock-only rule is phasing out but that still compile:

```bash
git diff --cached -U0 -- '*.java' | grep -E '^-\s*(public|protected)\s' | sed -E 's/.*\s([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\1/' | sort -u \
  | while read m; do echo "== $m"; grep -rln --include='*.java' --include='*.groovy' --include='*.kt' "\b$m\s*(" . | grep -v '/build/'; done
```

List the test classes that reference the method and confirm each was executed (an explicit
`--tests` filter per class). A Mockito stub of a method the controller no longer calls does not
fail — it makes every `verify(..., never())` on it vacuous and the class NPEs on the unstubbed
replacement. That shipped once and cost a review round.

**Guard evidence.** For each staged test that exists to guard a specific regression, the commit
message or MR notes must record the mutation performed (what was reverted) and the test that went
red. Restore with a file copy, never `git checkout --` on a file carrying other uncommitted work.
A guard without this evidence is reported as 🟡 *unverified guard*, not as coverage.

**Fixture provenance.** Any staged fixture for an API payload must trace to a captured response
or the producing DTO's serialisation (see the `api-contract-fixtures` skill). Flag fixtures that
carry values the producer strips, or keys in a different case than the wire.

### 3. Categorize Findings by Severity

Organize issues into severity levels:

**🔴 Critical (Blocks Commit):**
- Hardcoded secrets or API keys
- Files that should never be committed (.env, credentials)
- Syntax errors or obvious bugs
- Breaking changes without migration path

**🟡 Warning (Should Fix):**
- Debug statements left in code
- TODO/FIXME indicating incomplete features
- Large blocks of commented-out code
- Missing tests for new functionality
- Inconsistent formatting

**🔵 Info (Consider):**
- Minor style inconsistencies
- Opportunities for refactoring
- Documentation that could be improved
- Non-critical TODOs for future work

### 4. Generate Findings Report

Create a clear, actionable report:

```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues ([count])
[List critical issues or "None found"]

### 🟡 Warnings ([count])
[List warnings or "None found"]

### 🔵 Info ([count])
[List info items or "None found"]
```

For each finding, include:
- File path and line number
- Specific issue description
- Why it's a concern
- Suggested fix (if applicable)

### 5. Create Self-Review Checklist

Generate a tailored checklist based on the changes:

**Always Include:**
- [ ] No debug statements or temporary logging
- [ ] No TODO/FIXME comments for incomplete work
- [ ] No commented-out code blocks
- [ ] No hardcoded secrets or sensitive data
- [ ] No files that shouldn't be committed
- [ ] Code follows project formatting standards

**Add When Relevant:**
- [ ] New functions have corresponding tests
- [ ] API changes have integration tests
- [ ] Bug fixes include regression tests
- [ ] Breaking changes documented
- [ ] Configuration changes validated
- [ ] Dependencies updates tested
- [ ] Documentation updated for new features

### 6. Provide Recommendation

Based on findings, give clear guidance:

**If Critical Issues Found:**
```
❌ NOT READY TO COMMIT

Critical issues must be resolved before committing. See findings above.
```

**If Only Warnings/Info:**
```
⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.
```

**If Clean:**
```
✅ READY TO COMMIT

No issues found. Changes appear ready to commit.
```

### 7. Record Review Approval

After completing the review, record a hash of the staged changes so the pre-commit hook knows this review is valid. Run this command:

```bash
REPO_HASH=$(git rev-parse --show-toplevel | shasum -a 256 | cut -d' ' -f1) && mkdir -p ~/.claude/markers && git diff --cached | shasum -a 256 | cut -d' ' -f1 > ~/.claude/markers/.claude-pcr-${REPO_HASH}
```

This ties the review to the exact staged content. If the user stages new changes after the review, the hook will require re-running `/pre-commit-review`.

**Important**: Always run this step, even if issues were found. The commit hook will block regardless if the user hasn't addressed the issues — this step just records that the review happened.

### 8. Present and Validate

Before finalizing, verify:
- All staged files reviewed
- Issues categorized by appropriate severity
- Findings include file paths and line numbers
- Checklist tailored to changes
- Recommendation clear and actionable
- Review hash recorded (step 7)

Present the complete report and offer to:
- Provide more detail on specific findings
- Help fix identified issues
- Re-run review after fixes

## Output Format

```markdown
## Pre-Commit Review Findings

### 🔴 Critical Issues (0)
None found.

### 🟡 Warnings (2)

**src/api/users.ts:45**
- Debug statement: `console.log('User data:', userData)`
- Should be removed before commit

**src/services/auth.ts:120-135**
- Large commented-out code block (15 lines)
- Remove if no longer needed or document why it's preserved

### 🔵 Info (1)

**src/components/UserProfile.tsx**
- New component added without tests
- Consider adding component tests

---

## Self-Review Checklist

- [x] No debug statements or temporary logging
- [ ] No commented-out code blocks
- [x] No hardcoded secrets or sensitive data
- [x] No files that shouldn't be committed
- [x] Code follows project formatting standards
- [ ] New components have corresponding tests

---

⚠️ READY WITH CAUTIONS

No critical issues found, but consider addressing warnings before committing.
```

## Quality Checklist

- [ ] All staged files reviewed
- [ ] Issues categorized by correct severity
- [ ] Findings include specific file paths and line numbers
- [ ] Each finding explains why it's a concern
- [ ] Checklist tailored to the actual changes
- [ ] Recommendation appropriate to findings
- [ ] Report is clear and actionable

## Special Cases

**No Staged Changes**: Inform user that no files are staged for commit.

**Binary Files**: Note that binary files cannot be reviewed for content issues, only check if they should be committed.

**Large Changesets**: Focus on critical and warning issues first, mention if comprehensive review may need more time.

**Configuration Files**: Extra scrutiny for secrets and ensure changes are intentional.

**Migration Files**: Verify they follow project conventions and are safe to commit.

**Generated Code**: Note which files are generated and may not need detailed review.

## Scope Limitations

**This skill focuses on:**
- Objective, detectable issues
- "Is this ready to commit?" questions
- Pre-commit safety checks

**This skill does NOT:**
- Provide subjective code quality feedback (use conversational review)
- Suggest architectural improvements (use conversational review)
- Perform deep logic analysis (use conversational review)
- Review code that isn't staged

---

For detailed examples of review reports, see `examples.md`
For complete list of checks and rationale, see `reference.md`
