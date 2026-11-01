# Conventional Commits Reference

Complete specification and guidelines for the Conventional Commits format used in commit messages.

## Format Specification

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Subject Line

- **type**: Category of change (required)
- **scope**: Area of codebase affected (optional)
- **subject**: Brief description (required)

Format rules:
- Maximum 72 characters (50-72 recommended)
- Use imperative mood: "add" not "added" or "adds"
- Lowercase first letter after colon
- No period at the end
- Separate type/scope from subject with colon and space

### Body

- Wrap at 72 characters
- Use blank lines to separate paragraphs
- Explain motivation, approach, and impact
- Focus on "why" not "what"
- Can include bullet points or numbered lists
- Optional but recommended for non-trivial changes

### Footer

Used for:
- Breaking change notifications
- Issue references
- Attribution (required for Claude-generated commits)

## Commit Types

### feat
**Purpose**: New feature for the user

**When to use**:
- Adding new user-facing functionality
- Implementing new API endpoints
- Creating new UI components
- Adding new capabilities

**Examples**:
- `feat(auth): add two-factor authentication`
- `feat(api): add webhook support for order events`
- `feat: add dark mode toggle to settings`

### fix
**Purpose**: Bug fix

**When to use**:
- Correcting broken functionality
- Fixing errors or exceptions
- Resolving incorrect behavior
- Patching security vulnerabilities

**Examples**:
- `fix(payments): correct tax calculation for EU orders`
- `fix: prevent memory leak in image upload`
- `fix(ui): correct button alignment on mobile devices`

### docs
**Purpose**: Documentation changes only

**When to use**:
- Updating README files
- Adding code comments
- Creating or updating guides
- Fixing documentation typos
- No code changes

**Examples**:
- `docs: add installation instructions for Windows`
- `docs(api): update authentication examples`
- `docs: fix typo in contributing guidelines`

### style
**Purpose**: Code style/formatting changes

**When to use**:
- Formatting changes (whitespace, indentation)
- Missing semicolons
- Code style fixes
- No logic changes

**Examples**:
- `style: format code with prettier`
- `style(api): add missing semicolons`
- `style: fix indentation in service files`

### refactor
**Purpose**: Code restructuring without behavior change

**When to use**:
- Renaming variables or functions
- Extracting methods or classes
- Restructuring code organization
- Improving code quality
- No bug fixes or new features

**Examples**:
- `refactor(auth): extract token validation to separate module`
- `refactor: simplify error handling logic`
- `refactor(database): migrate to connection pooling`

### perf
**Purpose**: Performance improvements

**When to use**:
- Optimizing algorithms
- Reducing memory usage
- Improving load times
- Database query optimization
- Behavior remains the same

**Examples**:
- `perf(search): add indexing to improve query speed`
- `perf: implement caching for API responses`
- `perf(ui): lazy load images in gallery`

### test
**Purpose**: Adding or updating tests

**When to use**:
- Adding missing tests
- Updating existing test cases
- Fixing broken tests
- Adding test utilities
- No production code changes

**Examples**:
- `test(auth): add integration tests for login flow`
- `test: increase coverage for payment processing`
- `test(api): add edge case tests for validation`

### build
**Purpose**: Build system or dependency changes

**When to use**:
- Updating dependencies
- Modifying build configuration
- Changing compilation settings
- Adding/removing packages
- Build tool updates

**Examples**:
- `build: update webpack to v5.0`
- `build: add PostCSS to build pipeline`
- `build(deps): bump axios from 0.21.1 to 1.6.0`

### ci
**Purpose**: CI/CD configuration changes

**When to use**:
- Modifying CI workflows
- Updating GitHub Actions
- Changing deployment scripts
- Adjusting CI pipeline settings

**Examples**:
- `ci: add automated security scanning to PR workflow`
- `ci: update Node version in test matrix`
- `ci(deploy): add production deployment workflow`

### chore
**Purpose**: Maintenance tasks

**When to use**:
- Updating gitignore
- Modifying editor config
- License updates
- Other housekeeping
- No src or test file changes

**Examples**:
- `chore: update .gitignore for IDE files`
- `chore: add license headers to source files`
- `chore: initial commit`

## Scope Guidelines

The scope specifies which part of the codebase is affected.

### Common Scopes
- **api**: Backend API changes
- **ui**: User interface changes
- **auth**: Authentication/authorization
- **database**: Database schema or queries
- **config**: Configuration changes
- **deps**: Dependency updates
- **docs**: Documentation (when combined with other types)

### Scope Best Practices
- Use consistent naming across the project
- Keep scopes short and clear
- Use lowercase
- Optional but recommended for medium/large projects
- Can omit for truly global changes

### Examples
```
feat(api): add GraphQL endpoint
fix(ui): correct modal positioning
refactor(auth): simplify JWT validation
perf(database): optimize user query
```

## Breaking Changes

A breaking change is any modification that requires users to update their code or configuration.

### Indicating Breaking Changes

**Method 1**: Add an exclamation mark after type/scope

Format: Place exclamation mark after type or scope, before the colon
- Example: `feat(api)` + exclamation + `: redesign authentication flow`
- Example: `refactor` + exclamation + `: rename config file from .rc to .config.js`

**Method 2**: Add `BREAKING CHANGE:` footer
```
feat(api): redesign authentication flow

BREAKING CHANGE: The /auth endpoint now returns JWT tokens instead
of session cookies. Clients must update to send tokens in the
Authorization header.
```

**Both methods** can be used together for emphasis.

### Breaking Change Footer Format

```
BREAKING CHANGE: <description of what broke>

<migration instructions>

<new expected behavior>
```

### Example

Note: In actual usage, include an exclamation mark after (config)

```
feat(config): migrate from JSON to YAML configuration

Migrate configuration format from JSON to YAML for better readability
and comment support. This aligns with industry standards and user
feedback.

BREAKING CHANGE: Configuration files must be renamed and converted:
- config.json → config.yaml
- Use the provided migration script: npm run migrate-config
- See docs/config-migration.md for manual migration steps

The new format supports comments and is more maintainable.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Subject Line Guidelines

### Imperative Mood
Write as if giving a command:

**Good**:
- `add user authentication`
- `fix memory leak`
- `update dependencies`
- `remove deprecated API`

**Bad**:
- `added user authentication`
- `adds user authentication`
- `fixing memory leak`
- `updated dependencies`

### Length
- Target: 50-72 characters
- Hard maximum: 72 characters
- If struggling to fit, the commit may be too large

### Capitalization
**After type(scope):** → lowercase
```
feat(api): add webhook support  ✓
feat(api): Add webhook support  ✗
```

**Type and scope:** → lowercase
```
feat(api): ...  ✓
Feat(API): ...  ✗
```

### Punctuation
No period at the end:
```
fix(auth): prevent token expiration  ✓
fix(auth): prevent token expiration.  ✗
```

## Body Guidelines

### When to Include a Body
**Always include** for:
- Features (feat)
- Breaking changes
- Complex bug fixes
- Performance improvements
- Refactoring

**Optional** for:
- Simple docs updates
- Trivial fixes
- Style changes

### What to Include
1. **Why**: The motivation or problem
2. **What**: The approach taken
3. **How**: Implementation details (high-level)
4. **Impact**: Side effects or consequences
5. **Alternatives**: Other approaches considered (if relevant)

### Formatting
- Wrap at 72 characters
- Blank line between subject and body
- Blank lines between paragraphs
- Use `-` for bullet points
- Use `1.` for numbered lists

### Example
```
refactor(database): migrate to TypeORM

The existing raw SQL queries were becoming difficult to maintain
and error-prone. TypeORM provides type safety, migration support,
and better testability.

Benefits:
- Compile-time type checking for queries
- Automated schema migrations
- Easier to mock for unit tests
- Better documentation of data models

Considered Prisma and Sequelize but chose TypeORM for its
decorator-based approach which integrates well with our existing
NestJS architecture.
```

## Footer Guidelines

### Issue References
Link to issue trackers:
```
Fixes #123
Closes #456
See #789
```

Multiple issues:
```
Fixes #123, #456
```

### Breaking Changes
```
BREAKING CHANGE: description here
```

### Attribution (Required)
For Claude-generated commits:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Complete Footer Example
```
Fixes #123

BREAKING CHANGE: API version 1 endpoints removed

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Common Mistakes

### Too Vague
❌ `fix: fix bug`
✓ `fix(auth): prevent null pointer in token validation`

### Wrong Type
❌ `feat: fix login error` (should be `fix`)
✓ `fix(auth): correct password validation logic`

### Missing Context
❌ `refactor: update code`
✓ `refactor(api): extract validation to middleware for reusability`

### Wrong Mood
❌ `feat(ui): added dark mode`
✓ `feat(ui): add dark mode`

### Too Long Subject
❌ `feat(api): add comprehensive support for webhooks including retry logic and exponential backoff`
✓ `feat(api): add webhook support with retry logic`

### Missing Body for Complex Change
❌ Simple subject line only (no explanation):
```
feat(api): redesign authentication
```
Note: Add exclamation mark after (api) to signal breaking change

✓ Complete with body and breaking change explanation:
```
feat(api): redesign authentication

Note: Include exclamation mark after (api) in actual usage

Migrate from session-based to JWT authentication for better
scalability and stateless API design.

BREAKING CHANGE: Session cookies are no longer supported.
Clients must use JWT tokens in Authorization header.
```

## Quick Reference

| Type | Purpose | Example |
|------|---------|---------|
| feat | New feature | `feat(auth): add OAuth support` |
| fix | Bug fix | `fix(api): prevent race condition` |
| docs | Documentation | `docs: update API guide` |
| style | Formatting | `style: apply prettier formatting` |
| refactor | Code restructure | `refactor: simplify error handling` |
| perf | Performance | `perf(db): add query caching` |
| test | Tests | `test(auth): add login flow tests` |
| build | Build/deps | `build: update webpack to v5` |
| ci | CI/CD | `ci: add security scanning` |
| chore | Maintenance | `chore: update .gitignore` |

## Resources

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [Angular Commit Guidelines](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#commit)
- [Semantic Versioning](https://semver.org/)
