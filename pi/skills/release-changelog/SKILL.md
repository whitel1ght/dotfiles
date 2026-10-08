---
name: release-changelog
description: >-
  Generate changelog entries or release notes from commit history. Use when creating releases, writing changelogs, generating release notes, preparing version releases, or when user mentions changelog, release notes, version history, or CHANGELOG.md.
---


# Release Changelog Generator

Generate structured changelog entries or user-facing release notes from commit history, adapting format based on the audience and purpose.

## Process

### 1. Determine Scope and Format

Ask user to clarify:
- **Version range**: "What version or tag should I analyze from?" (e.g., last tag, specific version, date range)
- **Output format**: "Should I generate a technical changelog (CHANGELOG.md) or user-facing release notes?"

If unclear:
- Check for last tag: `git describe --tags --abbrev=0` or `git tag --sort=-v:refname | head -n 1`
- Default to technical changelog if no preference specified
- Use semver for version numbering

### 2. Analyze Commit History

Gather commits in the version range:
- `git log <last-tag>..HEAD --oneline` - List all commits since last release
- `git log <last-tag>..HEAD --format="%h %s"` - Get commit hashes and subjects
- `git log <last-tag>..HEAD` - Full commit messages for context
- `git describe --tags` - Current position relative to tags

If no previous tag exists, analyze all commits: `git log --oneline`

### 3. Categorize Changes

Group commits by type using Conventional Commits prefixes:

**Technical Changelog Categories (Keep a Changelog format):**
- **Added**: New features (`feat:` commits)
- **Changed**: Modifications to existing functionality (`refactor:`, some `feat:`)
- **Deprecated**: Features marked for removal (check commit messages)
- **Removed**: Deleted features (`chore:` with removals)
- **Fixed**: Bug fixes (`fix:` commits)
- **Security**: Security-related changes (check commit messages for security keywords)

**User-Facing Release Notes Categories:**
- **Highlights**: Most impactful features (1-3 items)
- **New Features**: User-visible additions
- **Improvements**: Enhancements to existing features
- **Bug Fixes**: User-facing fixes (skip internal bugs)
- **Breaking Changes**: Changes requiring user action

### 4. Detect Breaking Changes

Identify commits with breaking changes:
- Commits with exclamation mark after type: format is type + exclamation + colon
- Commits with `BREAKING CHANGE:` footer
- Major API changes, configuration format changes, removed features

For each breaking change:
- Describe what broke and why
- Provide migration guidance
- Document new expected behavior

### 5. Suggest Version Number

Apply semantic versioning (semver) rules:
- **Major (X.0.0)**: Breaking changes present
- **Minor (1.X.0)**: New features added (no breaking changes)
- **Patch (1.0.X)**: Only bug fixes and minor improvements

Suggest version based on changes detected. If current version unknown, ask user.

### 6. Generate Output

#### For Technical Changelog (CHANGELOG.md):

Follow Keep a Changelog format:
- Version heading with date: `## [1.2.0] - 2025-10-21`
- Categorized changes with bullet points
- Link to commits/PRs if repository URL available
- Maintain chronological order (newest first)
- Use past tense and be specific

#### For User-Facing Release Notes:

Create friendly announcement:
- Engaging title: "What's New in Version 1.2.0"
- Brief introduction highlighting key benefits
- Organized sections with user-focused language
- Avoid technical jargon
- Include visuals or examples if helpful
- Call to action (upgrade instructions, feedback)

### 7. Add Links and References

If repository URL is available (from `git remote -v`):
- Link commits: `([abc123](https://...))`
- Link issues/PRs: `(#123)` or full URLs
- Add comparison link: `[1.2.0]: https://github.com/user/repo/compare/v1.1.0...v1.2.0`

For GitLab: Use exclamation mark + number for MRs (e.g., MR 123)
For GitHub: Use `#123` for both issues and PRs

### 8. Add Attribution Footer

Always include (after all content):

```
---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### 9. Present and Validate

Before finalizing, verify:
- Version number follows semver correctly
- All significant changes are captured
- Breaking changes clearly documented with migration steps
- Categories are accurate and complete
- Format matches the requested type (changelog vs release notes)
- Links are valid (if included)
- Attribution footer included
- Language appropriate for audience (technical vs user-facing)

Present the complete output in a code block and offer to:
- Make revisions based on feedback
- Adjust categorization or version number
- Switch between technical/user-facing formats
- Add or remove sections

## Format Templates

### Technical Changelog (CHANGELOG.md)

```markdown
## [1.2.0] - 2025-10-21

### Added
- User authentication with OAuth2 providers (GitHub, Google)
- Export functionality for user data in JSON and CSV formats
- Dark mode support with automatic system preference detection

### Changed
- Improved API response time by 40% through query optimization
- Updated dependencies to latest stable versions

### Fixed
- Resolved race condition in token refresh logic
- Fixed pagination bug on search results page
- Corrected timezone handling in scheduled reports

### Security
- Updated JWT library to address CVE-2025-1234
- Implemented rate limiting on authentication endpoints

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### User-Facing Release Notes

```markdown
# What's New in Version 1.2.0

We're excited to announce version 1.2.0 with powerful new authentication options, improved performance, and enhanced accessibility features.

## Highlights

**Sign in with GitHub or Google** - You can now authenticate using your existing GitHub or Google accounts, making it faster to get started.

**40% Faster API Performance** - We've optimized our database queries to deliver significantly faster response times across the platform.

**Dark Mode** - Enable dark mode in your settings, or let the app automatically match your system preferences.

## New Features

- Export your data in JSON or CSV formats from the account settings
- OAuth2 authentication with GitHub and Google providers
- Dark mode with automatic system preference detection

## Improvements

- Faster API response times (40% improvement on average)
- More reliable token refresh handling
- Better timezone support for scheduled reports

## Bug Fixes

- Fixed pagination issues on search results
- Resolved authentication errors during high traffic periods
- Corrected date formatting in exported reports

## How to Upgrade

Update to the latest version:
```bash
npm install app-name@latest
```

See the [full changelog](CHANGELOG.md) for complete details.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Quality Checklist

- [ ] Version range correctly identified
- [ ] All significant commits categorized
- [ ] Breaking changes documented with migration guidance
- [ ] Version number follows semver rules
- [ ] Format appropriate for audience (technical vs user-facing)
- [ ] Links to commits/issues included (if repository URL available)
- [ ] Date is accurate (ISO format for changelog)
- [ ] Attribution footer included
- [ ] Language clear and free of jargon (for user-facing)
- [ ] Changes explained with sufficient context

## Special Cases

**First Release**: Use version `1.0.0` (or `0.1.0` for pre-release). List initial features under "Added" section.

**Hotfix Release**: Focus on the critical bug fixes. Use patch version increment. Keep changelog concise.

**Pre-release Versions**: Use semver pre-release syntax (`1.2.0-alpha.1`, `1.2.0-beta.2`, `1.2.0-rc.1`).

**No Conventional Commits**: Analyze commit messages manually. Group by patterns observed. Ask for clarification if categorization is ambiguous.

**Large Release**: Prioritize most impactful changes. Group minor fixes into summary statements (e.g., "Various bug fixes and performance improvements").

**Multiple Breaking Changes**: Create dedicated "Breaking Changes" section at the top with detailed migration guide for each change.

**Unreleased Changes**: Use `## [Unreleased]` heading at the top of CHANGELOG.md for changes not yet tagged.

## Output Format

Present changelog or release notes in a markdown code block for easy copying. Ask user if they want to:
1. Proceed with this output
2. Make revisions or adjust categorization
3. Switch format (technical to user-facing or vice versa)
4. Append to existing CHANGELOG.md file
5. Create a release tag with these notes

---

For detailed examples, see `examples.md`
For Keep a Changelog format and semver specifications, see `reference.md`
