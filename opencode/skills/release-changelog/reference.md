# Release Changelog Reference

This file provides detailed technical reference for changelog formats, semantic versioning rules, and linking conventions.

## Keep a Changelog Format Specification

### Overview

Keep a Changelog is a standardized format for maintaining human-readable changelogs. Full specification at https://keepachangelog.com/

### Structure

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features that haven't been released yet

## [1.0.0] - 2025-10-21

### Added
- New features for this version

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Now removed features

### Fixed
- Any bug fixes

### Security
- Vulnerabilities fixes

[Unreleased]: https://github.com/user/repo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/user/repo/releases/tag/v1.0.0
```

### Section Definitions

#### Added
For new features.

**Examples:**
- Added user authentication
- Added export functionality
- Added dark mode support
- Added API endpoint for bulk operations

**Conventional Commit Mapping:** `feat:` commits

#### Changed
For changes in existing functionality.

**Examples:**
- Changed database schema for better performance
- Changed API response format to include metadata
- Changed UI layout for improved usability
- Updated dependencies to latest versions

**Conventional Commit Mapping:** `feat:` (modifications), `refactor:`, `perf:`

#### Deprecated
For soon-to-be removed features.

**Examples:**
- Deprecated v1 API endpoints (will be removed in v3.0.0)
- Deprecated legacy configuration format
- Deprecated old authentication method

**Conventional Commit Mapping:** Marked in commit messages, not a standard type

#### Removed
For now removed features.

**Examples:**
- Removed support for Internet Explorer 11
- Removed deprecated v1 API endpoints
- Removed legacy authentication method

**Conventional Commit Mapping:** `chore:` or breaking change commits (with exclamation mark)

#### Fixed
For any bug fixes.

**Examples:**
- Fixed memory leak in connection pool
- Fixed pagination bug on search results
- Fixed race condition in token refresh
- Corrected timezone handling

**Conventional Commit Mapping:** `fix:` commits

#### Security
For vulnerabilities fixes.

**Examples:**
- Fixed SQL injection vulnerability (CVE-2025-1234)
- Updated JWT library to address security issue
- Implemented rate limiting to prevent abuse
- Added CSRF protection

**Conventional Commit Mapping:** `fix:` with security context, or commits mentioning CVE

### Formatting Rules

1. **Version Heading Format:** `## [X.Y.Z] - YYYY-MM-DD`
2. **Date Format:** ISO 8601 (YYYY-MM-DD)
3. **Chronological Order:** Newest versions at top
4. **Category Order:** Added, Changed, Deprecated, Removed, Fixed, Security
5. **Bullet Points:** Use `-` for list items
6. **Tense:** Use past tense ("Added" not "Add")
7. **Specificity:** Be specific but concise
8. **Links:** Include at bottom of file

### Best Practices

1. **One entry per file change or feature:** Don't lump unrelated changes together
2. **User-focused language:** Write for users, not developers (in user-facing changelogs)
3. **Include context:** Explain why, not just what
4. **Link to details:** Reference issues, PRs, commits for more information
5. **Group related items:** Use sub-headings for large releases
6. **Keep updated:** Add to Unreleased section as changes are made
7. **Release process:** Move Unreleased items to versioned section when releasing

---

## Semantic Versioning (Semver) Specification

### Overview

Semantic Versioning uses three-part version numbers: MAJOR.MINOR.PATCH

Full specification at https://semver.org/

### Version Format

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]

Examples:
- 1.0.0
- 1.2.3
- 2.0.0-alpha.1
- 2.0.0-beta.2
- 2.0.0-rc.1
- 1.0.0+20250101
- 2.1.3-beta.1+exp.sha.5114f85
```

### Version Components

#### MAJOR (X.0.0)

Increment when making incompatible API changes.

**Triggers:**
- Breaking changes to public API
- Removing features or endpoints
- Changing behavior users depend on
- Configuration format changes requiring manual intervention
- Database migrations that aren't backwards compatible

**Conventional Commit Indicators:**
- Commits with exclamation mark after type (e.g., type + exclamation + colon format)
- Commits with `BREAKING CHANGE:` footer

**Examples:**
- 1.x.x → 2.0.0: Removed v1 API endpoints
- 2.x.x → 3.0.0: Changed authentication method
- 3.x.x → 4.0.0: Restructured configuration format

#### MINOR (x.X.0)

Increment when adding functionality in a backwards-compatible manner.

**Triggers:**
- New features added
- Existing features enhanced
- Deprecating functionality (not removing)
- New optional configuration options

**Conventional Commit Indicators:**
- `feat:` commits (without breaking changes)

**Examples:**
- 1.2.x → 1.3.0: Added OAuth authentication
- 1.3.x → 1.4.0: Added export functionality
- 1.4.x → 1.5.0: Added webhooks support

**Reset PATCH to 0** when incrementing MINOR.

#### PATCH (x.x.X)

Increment when making backwards-compatible bug fixes.

**Triggers:**
- Bug fixes
- Performance improvements
- Security patches
- Documentation corrections
- Internal refactoring (no external changes)

**Conventional Commit Indicators:**
- `fix:` commits
- `perf:` commits
- `docs:` commits (if user-facing)
- `refactor:` commits (internal only)

**Examples:**
- 1.2.3 → 1.2.4: Fixed memory leak
- 1.2.4 → 1.2.5: Security patch for CVE-2025-1234
- 1.2.5 → 1.2.6: Fixed pagination bug

### Pre-release Versions

Append hyphen and pre-release identifier: `X.Y.Z-prerelease`

**Common Pre-release Identifiers:**

1. **Alpha (`-alpha.N`)**: Early testing, unstable
   - Example: `2.0.0-alpha.1`
   - Use: Internal testing, proof of concept
   - Stability: Expect breaking changes between alphas

2. **Beta (`-beta.N`)**: Feature complete, testing
   - Example: `2.0.0-beta.1`
   - Use: External testing, feedback collection
   - Stability: Features frozen, only bug fixes

3. **Release Candidate (`-rc.N`)**: Potentially final
   - Example: `2.0.0-rc.1`
   - Use: Final testing before stable release
   - Stability: Only critical bugs fixed

**Progression Example:**
```
2.0.0-alpha.1
2.0.0-alpha.2
2.0.0-beta.1
2.0.0-beta.2
2.0.0-rc.1
2.0.0
```

### Build Metadata

Append plus sign and build metadata: `X.Y.Z+build`

**Examples:**
- `1.0.0+20250101`: Build date
- `1.0.0+sha.5114f85`: Git commit SHA
- `1.0.0+exp.sha.5114f85`: Experimental build with SHA

**Note:** Build metadata DOES NOT affect version precedence.

### Version Precedence Rules

1. Compare major, minor, patch numerically
2. Pre-release versions have lower precedence than normal versions
3. Compare pre-release identifiers lexically
4. Build metadata is ignored in precedence

**Examples (in order):**
```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

### Starting Version

- **Public API stable:** Start at `1.0.0`
- **Initial development:** Start at `0.1.0`
- **Major changes during 0.x:** Increment minor (0.x is unstable)
- **First stable release:** Jump to `1.0.0`

### Special Cases

#### Version 0.x.y (Initial Development)

Major version zero (0.y.z) is for initial development. Anything may change at any time. The public API should not be considered stable.

**Rules:**
- Increment MINOR for breaking changes: `0.1.0` → `0.2.0`
- Increment PATCH for backwards-compatible changes: `0.1.0` → `0.1.1`

#### Transitioning to 1.0.0

Version 1.0.0 defines the public API. Increment rules apply from this point forward.

**Indicators for 1.0.0 readiness:**
- Public API is stable
- Used in production by users
- Documented and supported
- Ready to commit to backwards compatibility

---

## Linking Conventions

### Commit Links

#### GitHub

**Format:**
```markdown
- Fixed bug in authentication ([a1b2c3d](https://github.com/user/repo/commit/a1b2c3d))
- Fixed bug in authentication (a1b2c3d)
```

**Short Reference:**
```markdown
- Fixed bug in authentication ([a1b2c3d])

[a1b2c3d]: https://github.com/user/repo/commit/a1b2c3d
```

#### GitLab

**Format:**
```markdown
- Fixed bug in authentication ([a1b2c3d](https://gitlab.com/user/repo/-/commit/a1b2c3d))
- Fixed bug in authentication (a1b2c3d)
```

**Short Reference:**
```markdown
- Fixed bug in authentication ([a1b2c3d])

[a1b2c3d]: https://gitlab.com/user/repo/-/commit/a1b2c3d
```

### Issue Links

#### GitHub

**Auto-linking (in PR/commit messages):**
```markdown
Closes #123
Fixes #456
Resolves #789
```

**Changelog Format:**
```markdown
- Fixed authentication bug (#123)
- Fixed authentication bug ([#123](https://github.com/user/repo/issues/123))
```

#### GitLab

**Auto-linking (in MR/commit messages):**
```markdown
Closes #123
Fixes #456
Resolves #789
```

**Changelog Format:**
```markdown
- Fixed authentication bug (#123)
- Fixed authentication bug ([#123](https://gitlab.com/user/repo/-/issues/123))
```

### Pull Request / Merge Request Links

#### GitHub (Pull Requests)

**Changelog Format:**
```markdown
- Added OAuth support (#234)
- Added OAuth support ([#234](https://github.com/user/repo/pull/234))
```

**Note:** GitHub uses `#` for both issues and PRs.

#### GitLab (Merge Requests)

**Changelog Format:**
```markdown
- Added OAuth support (!234)
- Added OAuth support ([!234](https://gitlab.com/user/repo/-/merge_requests/234))
```

**Note:** GitLab uses `!` for MRs, `#` for issues.

### Version Comparison Links

#### GitHub

**Format:**
```markdown
[1.2.0]: https://github.com/user/repo/compare/v1.1.0...v1.2.0
[Unreleased]: https://github.com/user/repo/compare/v1.2.0...HEAD
```

**Usage in Changelog:**
```markdown
## [1.2.0] - 2025-10-21

### Added
...

[1.2.0]: https://github.com/user/repo/compare/v1.1.0...v1.2.0
```

#### GitLab

**Format:**
```markdown
[1.2.0]: https://gitlab.com/user/repo/-/compare/v1.1.0...v1.2.0
[Unreleased]: https://gitlab.com/user/repo/-/compare/v1.2.0...HEAD
```

**Usage in Changelog:**
```markdown
## [1.2.0] - 2025-10-21

### Added
...

[1.2.0]: https://gitlab.com/user/repo/-/compare/v1.1.0...v1.2.0
```

### Release Links

#### GitHub

**Format:**
```markdown
[1.0.0]: https://github.com/user/repo/releases/tag/v1.0.0
```

#### GitLab

**Format:**
```markdown
[1.0.0]: https://gitlab.com/user/repo/-/releases/v1.0.0
```

### External References

#### CVE (Common Vulnerabilities and Exposures)

**Format:**
```markdown
- Fixed SQL injection vulnerability (CVE-2025-1234)
- Fixed SQL injection ([CVE-2025-1234](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2025-1234))
```

#### Documentation

**Format:**
```markdown
- See [migration guide](https://docs.example.com/migration/v1-to-v2)
- Review [API documentation](https://docs.example.com/api/v2)
```

---

## Conventional Commits Mapping

### Mapping Commit Types to Changelog Sections

| Commit Type | Changelog Section | Notes |
|-------------|------------------|-------|
| `feat:` | Added | New features |
| `feat:` | Changed | Feature modifications |
| breaking feat | Added + Breaking | New feature with breaking change (exclamation after feat) |
| `fix:` | Fixed | Bug fixes |
| breaking fix | Fixed + Breaking | Fix with breaking change (exclamation after fix) |
| `docs:` | N/A or Changed | Usually not in changelog unless user-facing |
| `style:` | N/A | Code formatting, no functional change |
| `refactor:` | Changed | Internal improvements (if user-visible) |
| `perf:` | Changed | Performance improvements |
| `test:` | N/A | Test additions/changes |
| `build:` | N/A | Build system changes |
| `ci:` | N/A | CI/CD changes |
| `chore:` | N/A | Maintenance tasks |
| `revert:` | Fixed or Removed | Depending on what was reverted |

### Extracting Information from Commits

#### Subject Line Parsing

```
type(scope): description

Examples:
feat(auth): add OAuth2 support → Added: OAuth2 authentication
fix(api): resolve rate limit bug → Fixed: Rate limiting bug
feat(ui): redesign dashboard → Added + Breaking: New dashboard design
Note: Add exclamation mark after (ui) for breaking change
```

#### Breaking Change Detection

**Method 1: Type with exclamation mark**

Format: Add exclamation mark after type or scope, before colon
Example: `feat(api)` + exclamation + `: change response format`

**Method 2: BREAKING CHANGE footer**
```
feat(api): improve response format

BREAKING CHANGE: Response format changed from XML to JSON.
Clients must update parsers to handle JSON.
```

#### Body Extraction

Use commit body for:
- Detailed explanations in changelog
- Migration guidance for breaking changes
- Context about why change was made

#### Example Processing

**Commit:**
```
feat(auth): add OAuth2 support with Google and GitHub

Implements OAuth2 authentication flow allowing users to sign in
with their Google or GitHub accounts. This reduces friction for
new users and improves security by leveraging trusted providers.

Closes #234
```

**Changelog Entry:**
```markdown
### Added
- OAuth2 authentication with Google and GitHub providers, reducing sign-up friction and improving security ([#234](https://github.com/user/repo/pull/234))
```

---

## Git Commands for Changelog Generation

### Finding Version Range

```bash
# Get last tag
git describe --tags --abbrev=0

# Get last tag with pattern
git describe --tags --abbrev=0 --match "v*"

# List all tags sorted by version
git tag --sort=-v:refname

# List tags with dates
git tag -l --format='%(refname:short) %(creatordate:short)'
```

### Analyzing Commits

```bash
# Commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Commits with full messages
git log $(git describe --tags --abbrev=0)..HEAD

# Commits with custom format
git log $(git describe --tags --abbrev=0)..HEAD --format="%h %s"

# Commits grouped by type (Conventional Commits)
git log --oneline --format="%s" | grep "^feat:"
git log --oneline --format="%s" | grep "^fix:"

# Commits with PR numbers (GitHub/GitLab)
git log --oneline --grep="#[0-9]\+"
git log --oneline --grep="![0-9]\+"
```

### Detecting Breaking Changes

```bash
# Find commits with !
git log --oneline --grep="!:" $(git describe --tags --abbrev=0)..HEAD

# Find commits with BREAKING CHANGE
git log --grep="BREAKING CHANGE" $(git describe --tags --abbrev=0)..HEAD

# Show full details of breaking changes
git log --grep="BREAKING CHANGE" $(git describe --tags --abbrev=0)..HEAD --format=fuller
```

### Repository Information

```bash
# Get repository URL
git remote get-url origin

# Parse GitHub/GitLab from URL
git remote get-url origin | sed 's/.*github.com[:/]\(.*\).git/github.com\/\1/'
git remote get-url origin | sed 's/.*gitlab.com[:/]\(.*\).git/gitlab.com\/\1/'

# Get current branch
git rev-parse --abbrev-ref HEAD

# Get commit count
git rev-list --count $(git describe --tags --abbrev=0)..HEAD
```

### Date Formatting

```bash
# ISO 8601 date (YYYY-MM-DD)
date +%Y-%m-%d

# From commit
git log -1 --format="%ad" --date=short

# From tag
git log -1 --format="%ad" --date=short $(git describe --tags --abbrev=0)
```

---

## Additional Resources

### Official Specifications

- **Keep a Changelog:** https://keepachangelog.com/
- **Semantic Versioning:** https://semver.org/
- **Conventional Commits:** https://www.conventionalcommits.org/

### Tools

- **standard-version:** Automated versioning and changelog generation
- **semantic-release:** Fully automated version management and package publishing
- **auto-changelog:** Generate changelog from git metadata
- **git-cliff:** Highly customizable changelog generator

### GitHub/GitLab Features

- **GitHub Releases:** https://docs.github.com/en/repositories/releasing-projects-on-github
- **GitLab Releases:** https://docs.gitlab.com/ee/user/project/releases/
- **GitHub Auto-linking:** https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls
- **GitLab References:** https://docs.gitlab.com/ee/user/markdown.html#gitlab-specific-references
