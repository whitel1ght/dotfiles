# Release Changelog Examples

This file contains detailed examples of well-formed changelog entries and release notes for different scenarios.

## Example 1: Technical Changelog Entry (Minor Release)

**Context:** SaaS application adding new features and fixes since v1.3.0

**Version Suggested:** 1.4.0 (minor - new features, no breaking changes)

**Output:**

```markdown
## [1.4.0] - 2025-10-21

### Added
- OAuth2 authentication with GitHub and Google providers ([#234](https://github.com/org/repo/pull/234))
- Export functionality for user data in JSON and CSV formats ([#245](https://github.com/org/repo/pull/245))
- Dark mode support with automatic system preference detection ([#256](https://github.com/org/repo/pull/256))
- API rate limiting with configurable thresholds per endpoint ([#267](https://github.com/org/repo/pull/267))

### Changed
- Improved API response time by 40% through query optimization ([#243](https://github.com/org/repo/pull/243))
- Updated user profile UI with better accessibility features ([#251](https://github.com/org/repo/pull/251))
- Migrated from Webpack to Vite for faster build times ([#258](https://github.com/org/repo/pull/258))

### Fixed
- Resolved race condition in token refresh logic ([#238](https://github.com/org/repo/pull/238))
- Fixed pagination bug on search results page ([#249](https://github.com/org/repo/pull/249))
- Corrected timezone handling in scheduled reports ([#253](https://github.com/org/repo/pull/253))
- Fixed memory leak in WebSocket connection handler ([#261](https://github.com/org/repo/pull/261))

### Security
- Updated JWT library to address CVE-2025-1234 ([#239](https://github.com/org/repo/pull/239))
- Implemented rate limiting on authentication endpoints ([#267](https://github.com/org/repo/pull/267))
- Added CSRF protection for all state-changing requests ([#271](https://github.com/org/repo/pull/271))

[1.4.0]: https://github.com/org/repo/compare/v1.3.0...v1.4.0

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 2: User-Facing Release Notes (Minor Release)

**Context:** Same release as Example 1, but formatted for end users

**Output:**

```markdown
# What's New in Version 1.4.0

We're excited to announce version 1.4.0 with powerful new authentication options, improved performance, and enhanced accessibility features. This release focuses on making the platform faster, more secure, and easier to use.

## Highlights

**🔐 Sign in with GitHub or Google** - You can now authenticate using your existing GitHub or Google accounts, making it faster and easier to get started without creating a new password.

**⚡ 40% Faster Performance** - We've optimized our database queries and backend infrastructure to deliver significantly faster response times across the entire platform.

**🌙 Dark Mode** - Enable dark mode in your settings, or let the app automatically match your system preferences for comfortable viewing any time of day.

## New Features

### Authentication & Security
- Sign in with GitHub or Google using OAuth2
- Enhanced security with improved rate limiting and CSRF protection
- More reliable session management to keep you logged in

### Data Management
- Export your data in JSON or CSV formats from account settings
- Better timezone support for scheduled reports
- Improved data consistency and reliability

### User Experience
- Dark mode with automatic system preference detection
- Enhanced accessibility features in the profile editor
- Faster page loads and smoother navigation

## Improvements

- API response times improved by 40% on average
- Build process is now 3x faster (developers will love this!)
- More intuitive user profile editing experience
- Better error messages with helpful guidance

## Bug Fixes

- Fixed pagination issues on search results that could cause missing items
- Resolved authentication errors that occurred during high traffic periods
- Corrected date formatting in exported reports to respect user timezone
- Fixed memory leak that could slow down the app after extended use
- Improved WebSocket reliability for real-time features

## Security Updates

We take security seriously. This release includes several security enhancements:
- Updated authentication library to address security vulnerability CVE-2025-1234
- Added rate limiting to prevent abuse
- Implemented CSRF protection across all forms

## How to Upgrade

**Web Users:** No action needed - you're automatically on the latest version!

**Self-Hosted Users:** Update to the latest version:
```bash
docker pull org/app:1.4.0
# Or
npm install app-name@1.4.0
```

See the [full technical changelog](CHANGELOG.md) for complete details including all commits and pull requests.

## What's Next?

We're already working on version 1.5.0 with exciting features including:
- Team collaboration tools
- Advanced search filters
- Mobile app improvements

Have feedback or suggestions? [Let us know!](https://github.com/org/repo/issues/new)

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 3: Major Release with Breaking Changes

**Context:** API platform with significant changes requiring migration

**Version Suggested:** 2.0.0 (major - breaking changes)

**Output:**

```markdown
## [2.0.0] - 2025-10-21

### ⚠️ BREAKING CHANGES

**API v1 Endpoints Removed**

The deprecated v1 API endpoints have been removed. All clients must migrate to v2 API.

**Migration steps:**
1. Update base URL from `api.example.com/v1` to `api.example.com/v2`
2. Update authentication: v2 uses Bearer tokens instead of API keys
3. Update request/response format: v2 uses snake_case instead of camelCase
4. Review [migration guide](https://docs.example.com/migration/v1-to-v2)

**Configuration Format Changed**

Configuration file format has changed from JSON to YAML for better readability.

**Migration steps:**
1. Rename `config.json` to `config.yaml`
2. Convert JSON to YAML format using provided conversion script: `npm run convert-config`
3. Update environment variables: `CONFIG_FILE` now expects `.yaml` extension
4. Review [configuration documentation](https://docs.example.com/config)

**Database Schema Changes**

User table structure has been normalized for better performance.

**Migration steps:**
1. Backup your database before upgrading
2. Run migration: `npm run migrate:v2`
3. Migration is reversible: `npm run migrate:rollback` (within 24 hours)
4. Estimated downtime: 5-10 minutes for databases under 1M users

### Added
- GraphQL API endpoint alongside REST API ([#312](https://github.com/org/repo/pull/312))
- Webhook support for real-time event notifications ([#324](https://github.com/org/repo/pull/324))
- API versioning with graceful deprecation strategy ([#301](https://github.com/org/repo/pull/301))
- Comprehensive API documentation with interactive examples ([#335](https://github.com/org/repo/pull/335))

### Changed
- API v2 uses snake_case for consistency with industry standards ([#298](https://github.com/org/repo/pull/298))
- Configuration format migrated from JSON to YAML ([#307](https://github.com/org/repo/pull/307))
- Authentication now uses Bearer tokens for improved security ([#315](https://github.com/org/repo/pull/315))
- Database schema normalized for better query performance ([#329](https://github.com/org/repo/pull/329))

### Removed
- API v1 endpoints (deprecated since v1.8.0, removed in v2.0.0) ([#298](https://github.com/org/repo/pull/298))
- Legacy API key authentication method ([#315](https://github.com/org/repo/pull/315))
- XML response format support (use JSON instead) ([#298](https://github.com/org/repo/pull/298))

### Fixed
- Resolved data inconsistency issues in user preferences ([#329](https://github.com/org/repo/pull/329))
- Fixed edge case in pagination that caused duplicate results ([#318](https://github.com/org/repo/pull/318))

### Security
- Bearer token authentication provides better security than API keys ([#315](https://github.com/org/repo/pull/315))
- Webhook signatures prevent unauthorized event injection ([#324](https://github.com/org/repo/pull/324))

[2.0.0]: https://github.com/org/repo/compare/v1.9.0...v2.0.0

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 4: Patch Release (Bug Fixes Only)

**Context:** Critical bug fixes without new features

**Version Suggested:** 1.4.3 (patch - bug fixes only)

**Output:**

```markdown
## [1.4.3] - 2025-10-21

### Fixed
- Fixed critical memory leak in WebSocket connection pool that caused server crashes under load ([#456](https://github.com/org/repo/pull/456))
- Resolved authentication token expiration handling that logged users out prematurely ([#458](https://github.com/org/repo/pull/458))
- Fixed race condition in concurrent file uploads causing data corruption ([#461](https://github.com/org/repo/pull/461))
- Corrected SQL query escaping that prevented special characters in search ([#463](https://github.com/org/repo/pull/463))

### Security
- Patched XSS vulnerability in comment rendering ([#460](https://github.com/org/repo/pull/460))

[1.4.3]: https://github.com/org/repo/compare/v1.4.2...v1.4.3

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 5: Pre-release Version (Beta)

**Context:** Beta release for testing new features before stable release

**Version Suggested:** 2.0.0-beta.1 (pre-release)

**Output:**

```markdown
## [2.0.0-beta.1] - 2025-10-21

**⚠️ This is a pre-release version for testing purposes. Do not use in production.**

### Added
- **[EXPERIMENTAL]** GraphQL API endpoint with real-time subscriptions ([#312](https://github.com/org/repo/pull/312))
- **[EXPERIMENTAL]** Plugin system for extending functionality ([#345](https://github.com/org/repo/pull/345))
- Webhook support for event notifications (stable) ([#324](https://github.com/org/repo/pull/324))

### Changed
- API v2 uses snake_case naming convention ([#298](https://github.com/org/repo/pull/298))
- Configuration format changed to YAML ([#307](https://github.com/org/repo/pull/307))

### Known Issues
- GraphQL subscriptions may disconnect after 1 hour (investigating)
- Plugin hot-reloading not yet implemented
- Documentation for plugin API still in progress

### Testing Needed
We need beta testers to help us validate:
- GraphQL API performance under load
- Plugin installation and activation workflow
- Webhook delivery reliability
- Migration from v1 to v2 API

### Feedback
Please report issues or provide feedback:
- GitHub Issues: https://github.com/org/repo/issues
- Discord: https://discord.gg/example
- Email: beta@example.com

[2.0.0-beta.1]: https://github.com/org/repo/compare/v1.9.0...v2.0.0-beta.1

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 6: First Release

**Context:** Initial public release of new project

**Version Suggested:** 1.0.0 (first stable release)

**Output:**

```markdown
## [1.0.0] - 2025-10-21

### Initial Release

First stable release of ExampleApp - a modern task management platform built for distributed teams.

### Added
- User authentication with email/password and OAuth providers
- Create, edit, and organize tasks with tags and priorities
- Team collaboration with shared workspaces
- Real-time updates using WebSocket connections
- Mobile-responsive web interface
- RESTful API for integrations
- Comprehensive documentation and API reference
- Docker support for easy self-hosting
- Dark mode theme
- Keyboard shortcuts for power users

### Supported Platforms
- Web: Modern browsers (Chrome, Firefox, Safari, Edge)
- Self-hosted: Docker, Node.js 18+
- Database: PostgreSQL 14+, MySQL 8+

### Documentation
- Getting Started: https://docs.example.com/getting-started
- API Reference: https://docs.example.com/api
- Self-Hosting Guide: https://docs.example.com/self-hosting

[1.0.0]: https://github.com/org/repo/releases/tag/v1.0.0

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 7: Hotfix Release (Critical Security Fix)

**Context:** Urgent security patch released outside normal schedule

**Version Suggested:** 1.4.4 (patch - critical security fix)

**Output:**

```markdown
## [1.4.4] - 2025-10-21

**🚨 SECURITY RELEASE - Immediate upgrade recommended**

### Security
- **CRITICAL:** Fixed SQL injection vulnerability in search functionality (CVE-2025-5678) ([#489](https://github.com/org/repo/pull/489))
  - Severity: High (CVSS 8.5)
  - Impact: Unauthenticated attackers could execute arbitrary SQL queries
  - Mitigation: All user input is now properly parameterized
  - Affected versions: 1.4.0 through 1.4.3
  - **Action required:** Upgrade immediately to 1.4.4

### Fixed
- Fixed SQL query parameterization in search module ([#489](https://github.com/org/repo/pull/489))

### Upgrade Instructions

**Immediate action required for all users running versions 1.4.0-1.4.3:**

```bash
# NPM/Yarn
npm update app-name@1.4.4
# or
yarn upgrade app-name@1.4.4

# Docker
docker pull org/app:1.4.4

# Manual
Download from: https://github.com/org/repo/releases/tag/v1.4.4
```

### Additional Information
- Security advisory: https://github.com/org/repo/security/advisories/GHSA-xxxx-yyyy-zzzz
- CVE details: https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2025-5678
- Questions? Contact: security@example.com

[1.4.4]: https://github.com/org/repo/compare/v1.4.3...v1.4.4

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 8: Unreleased Changes (Changelog Maintenance)

**Context:** Maintaining unreleased changes at top of CHANGELOG.md

**Output:**

```markdown
## [Unreleased]

### Added
- User preferences sync across devices ([#512](https://github.com/org/repo/pull/512))
- Export functionality for reports in PDF format ([#518](https://github.com/org/repo/pull/518))

### Changed
- Improved loading performance for large datasets ([#521](https://github.com/org/repo/pull/521))

### Fixed
- Fixed dropdown menu positioning on mobile devices ([#515](https://github.com/org/repo/pull/515))

[Unreleased]: https://github.com/org/repo/compare/v1.4.4...HEAD

---

## [1.4.4] - 2025-10-21
...

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 9: GitLab MR Links

**Context:** Using GitLab merge request syntax instead of GitHub PRs

**Output:**

```markdown
## [1.5.0] - 2025-10-21

### Added
- Team collaboration features with role-based permissions (!234)
- Advanced search with filters and saved queries (!245)
- Bulk operations for task management (!256)

### Changed
- Redesigned navigation menu for better usability (!243)
- Updated notification system with granular controls (!251)

### Fixed
- Resolved file upload issues for files larger than 10MB (!238)
- Fixed calendar view timezone synchronization (!249)

### Security
- Implemented two-factor authentication (2FA) (!267)
- Added audit logging for security-sensitive operations (!271)

[1.5.0]: https://gitlab.com/org/repo/-/compare/v1.4.4...v1.5.0

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Example 10: Large Release with Grouped Changes

**Context:** Large release with many changes, grouped for readability

**Output:**

```markdown
## [2.1.0] - 2025-10-21

### Added

#### Collaboration Features
- Real-time collaborative editing with presence indicators ([#567](https://github.com/org/repo/pull/567))
- Comment threads on tasks with @mentions ([#578](https://github.com/org/repo/pull/578))
- Activity feed showing team member actions ([#589](https://github.com/org/repo/pull/589))

#### Integrations
- Slack integration with notifications and commands ([#592](https://github.com/org/repo/pull/592))
- Zapier support for workflow automation ([#601](https://github.com/org/repo/pull/601))
- Calendar sync with Google Calendar and Outlook ([#615](https://github.com/org/repo/pull/615))

#### Mobile Support
- Progressive Web App (PWA) with offline support ([#624](https://github.com/org/repo/pull/624))
- Push notifications for mobile devices ([#635](https://github.com/org/repo/pull/635))
- Touch gestures for common actions ([#642](https://github.com/org/repo/pull/642))

### Changed
- Redesigned dashboard with customizable widgets ([#558](https://github.com/org/repo/pull/558))
- Improved search algorithm with fuzzy matching ([#571](https://github.com/org/repo/pull/571))
- Updated date picker with natural language input ([#584](https://github.com/org/repo/pull/584))

### Fixed
- Various bug fixes and performance improvements across the platform
- Improved error handling and user feedback
- Enhanced accessibility throughout the application

### Performance
- Reduced initial page load time by 60% ([#595](https://github.com/org/repo/pull/595))
- Optimized database queries for large team workspaces ([#608](https://github.com/org/repo/pull/608))
- Implemented caching strategy for frequently accessed data ([#619](https://github.com/org/repo/pull/619))

[2.1.0]: https://github.com/org/repo/compare/v2.0.0...v2.1.0

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Notes on Examples

### Common Patterns

1. **Version Heading**: Always include version number and date in ISO format
2. **Categories**: Use Keep a Changelog categories consistently
3. **Links**: Include links to commits/PRs when available
4. **Attribution**: Always include Claude Code attribution footer
5. **Context**: Provide enough detail for someone reviewing history months later

### Adaptation Tips

- **Technical Changelog**: Focus on WHAT changed, include technical details and links
- **User-Facing Notes**: Focus on WHY and benefits, use friendly language
- **Breaking Changes**: Always put at top with clear migration guidance
- **Security Issues**: Highlight prominently and include severity information
- **Large Releases**: Group related changes for better readability
- **Small Releases**: Keep concise but still informative

### Version Number Selection

- **Major (X.0.0)**: Breaking changes, API incompatibilities
- **Minor (x.X.0)**: New features, backwards-compatible additions
- **Patch (x.x.X)**: Bug fixes, minor improvements
- **Pre-release**: Use `-alpha`, `-beta`, `-rc` suffixes for testing

### Platform-Specific Notes

- **GitHub**: Use `#123` for both issues and PRs
- **GitLab**: Use `#123` for issues, `!123` for MRs
- **Commit Links**: Format as `([abc123](url))` or just `(abc123)` if no URL
- **Comparison Links**: Always include at bottom for easy diff viewing
