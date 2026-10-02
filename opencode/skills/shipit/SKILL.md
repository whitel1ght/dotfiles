---
name: shipit
description: >-
  Full "local changes to review request" workflow. Commits, pushes, and creates an MR/PR in one shot. Detects GitLab vs GitHub automatically.
---


# Ship It

Fully automatic workflow: safe branch, commit, push, and create MR/PR. No pauses for confirmation -- execute all steps in a single turn.

## Dynamic Context

- **Working directory** — run `pwd`
- **Current branch** — run `git branch --show-current`
- **Git status** — run `git status --short`
- **Git diff (staged + unstaged)** — run `git diff HEAD`
- **Remote URL** — run `git remote get-url origin 2>/dev/null || echo "no remote"`

## Arguments

If the user provided arguments via `/shipit <args>`, they are available as: $ARGUMENTS

- If `$ARGUMENTS` is non-empty and you need to create a new branch, use it as the branch name.
- If `$ARGUMENTS` is empty and a new branch is needed, auto-generate a name in the format `type/short-description` based on the changes (e.g., `feat/add-user-auth`, `fix/null-pointer-login`).

## Workflow

Execute ALL steps in a single message using parallel tool calls where possible. Do not pause for confirmation at any step.

### Step 1: Detect Platform

Determine GitLab vs GitHub:

1. If `pwd` contains `/ecfx/` -> **GitLab** (use `glab`)
2. If `pwd` contains `/src/` -> **GitHub** (use `gh`)
3. Fallback: inspect remote URL -- `gitlab` in URL -> GitLab; `github` in URL -> GitHub
4. If still ambiguous, default to GitHub (`gh`)

### Step 2: Check for Changes

If `git status --short` is empty (no changes, nothing to commit):
- Output: "Nothing to ship -- working tree is clean."
- **Stop here. Do not proceed.**

### Step 3: Ensure Safe Branch

If currently on `main` or `master`:
- Create and switch to a new branch: `git checkout -b <branch-name>`
- Branch name comes from `$ARGUMENTS` if provided, otherwise auto-generate as `type/short-description`

If already on a feature branch:
- Stay on it. Do not change branches.

### Step 4: Stage Changes

Run `git add -A` but then immediately check for sensitive files:

```
git diff --cached --name-only | grep -iE '\.env$|\.env\.|credentials|\.pem$|\.key$|id_rsa|secret'
```

If sensitive files are found:
- Unstage them: `git reset HEAD <file>` for each
- Warn the user: "Skipped staging sensitive file(s): <list>. Review and add manually if intended."
- If ALL files were sensitive and nothing remains staged, stop: "Nothing to ship after excluding sensitive files."

### Step 5: Commit

Generate a Conventional Commits message based on the staged diff.

**Format:**
```
type(scope): subject line under 72 chars

Body explaining WHY this change was made. Wrap at 72 characters.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Determine type from: feat, fix, docs, style, refactor, perf, test, build, ci, chore
- Scope is optional but recommended (the area of codebase affected)
- Subject: imperative mood, no capital after colon, no period, under 72 chars
- Body: explain the motivation/why, not just what changed
- Always include the Co-Authored-By footer
- Use HEREDOC to pass the message:

```bash
git commit -m "$(cat <<'EOF'
type(scope): subject line

Body paragraph.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 6: Push

```bash
git push -u origin <branch-name>
```

- **Never** use `--force` or `--force-with-lease`
- If push fails, report the error and stop

### Step 7: Create MR/PR

**GitLab:**
```bash
glab mr create --fill --title "<title>" --description "$(cat <<'EOF'
## Summary
<2-3 sentences: what changed, why, impact>

## Changes
- <bullet points of key changes>

## Testing
- [ ] <testing checklist items>

---
Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**GitHub:**
```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 sentences: what changed, why, impact>

## Changes
- <bullet points of key changes>

## Testing
- [ ] <testing checklist items>

---
Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Title rules:**
- Under 72 characters
- Imperative mood
- Specific and descriptive

**Description rules:**
- Summary: what, why, and impact (2-3 sentences)
- Changes: bullet points of key changes organized by area
- Testing: actionable checklist for reviewers
- Include Co-Authored-By footer

### Step 8: Report

After all steps complete, output a summary:

```
Shipped!
  Branch: <branch-name>
  Commit: <short-hash> <subject-line>
  <MR/PR>: <URL>
```

## Error Handling

- If any git command fails, report the error clearly and stop. Do not continue to subsequent steps.
- If `glab`/`gh` is not installed, report: "Required CLI tool (<tool>) not found. Install it to use /shipit with <platform>."
- If there is no remote configured, report: "No git remote configured. Add a remote first."

## Constraints

- NEVER commit directly to main/master
- NEVER force-push
- NEVER stage `.env`, credential files, or private keys without warning
- Execute everything in a single turn -- no pauses for user input
- Use only the allowed tools: `git`, `glab`, `gh`, `pwd`
