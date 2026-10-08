# Commit Message Examples

This file contains detailed examples of well-formed commit messages for different scenarios.

## Example 1: New Feature

```
feat(payments): add support for subscription billing

Implement recurring payment functionality to support monthly and annual
subscription plans. This enables the product team to launch tiered
pricing as outlined in Q4 roadmap.

The implementation uses Stripe's subscription API and includes:
- Webhook handlers for subscription events
- Database schema for subscription tracking
- Admin UI for subscription management

Customers can now upgrade/downgrade plans without contacting support,
reducing support ticket volume and improving user experience.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Clear type (feat) and scope (payments)
- Subject line is concise and descriptive
- Body explains the business motivation
- Lists the key components added
- Describes the user impact

## Example 2: Bug Fix

```
fix(auth): prevent token expiration race condition

Fix a race condition where concurrent requests could cause token refresh
failures during the expiration window. This was causing intermittent
401 errors for users with active sessions.

The fix implements a mutex lock on the token refresh logic and adds
retry logic with exponential backoff. Existing tokens are now marked
as "refreshing" to prevent duplicate refresh attempts.

Fixes #456

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Clear problem statement (race condition)
- Explains user impact (401 errors)
- Describes solution approach (mutex + retry)
- Links to issue tracker

## Example 3: Breaking Change with Migration Path

Note: In actual usage, add exclamation mark after (api) in the subject line

```
feat(api): migrate to RESTful endpoint naming convention

Standardize all API endpoints to follow REST best practices, improving
API consistency and developer experience. The previous endpoint naming
was inconsistent and caused confusion for API consumers.

This change renames endpoints to use resource-based URLs:
- POST /createUser → POST /users
- GET /getUserById → GET /users/:id
- POST /updateUser → PUT /users/:id
- POST /deleteUser → DELETE /users/:id

BREAKING CHANGE: All API endpoints have been renamed to follow RESTful
conventions. Clients must update their endpoint URLs. A migration guide
is available at docs/api-migration-v2.md. The old endpoints will be
deprecated in v1.x and removed in v2.0.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Uses exclamation mark in subject after (api) to flag breaking change
- Explains motivation for change
- Shows before/after mapping
- Provides clear migration path
- Includes deprecation timeline

## Example 4: Refactoring

```
refactor(database): extract query builder to separate module

The database connection logic had become tightly coupled with query
construction, making it difficult to test and maintain. This refactoring
separates concerns and improves code organization.

Benefits:
- Query builder can now be tested independently
- Connection pooling logic is isolated and reusable
- Easier to add support for different database backends
- Reduced file size from 800 to ~200 lines per module

No changes to public API or behavior. All existing tests pass.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Clear that it's a refactor (no behavior change)
- Explains the problem with old structure
- Lists concrete benefits
- Confirms no breaking changes

## Example 5: Documentation

```
docs: add API authentication examples to quick start guide

New developers were struggling to authenticate API requests based on
the existing documentation. This adds complete working examples for
all supported authentication methods.

Includes examples for:
- API key authentication
- OAuth2 client credentials flow
- JWT bearer tokens

Each example shows both cURL and JavaScript implementations with
common pitfalls highlighted.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Explains the user pain point
- Lists what was added
- Describes the format of examples

## Example 6: Performance Improvement

```
perf(search): implement pagination for large result sets

Search queries returning 1000+ results were causing browser freezes
and excessive memory usage. This implements cursor-based pagination
to load results in batches of 50.

Performance improvements:
- Initial page load time: 3.2s → 0.4s
- Memory usage: 250MB → 45MB for large result sets
- Time to interactive: 5.1s → 0.8s

Pagination is automatic and transparent to users. The UI shows a
loading indicator while fetching additional results on scroll.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Quantifies the performance problem
- Provides concrete before/after metrics
- Explains implementation approach
- Describes UX considerations

## Example 7: Test Addition

```
test(auth): add integration tests for password reset flow

The password reset feature lacked integration tests, making it risky
to refactor. This adds comprehensive test coverage for all password
reset scenarios.

Test coverage:
- Valid reset token flow
- Expired token handling
- Invalid token error cases
- Email delivery verification
- Rate limiting enforcement

Coverage increased from 45% to 92% for auth module.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Explains why tests were needed
- Lists test scenarios covered
- Provides coverage metrics

## Example 8: CI/CD Change

```
ci: add automatic security scanning to PR workflow

Integrate Snyk security scanning into the PR workflow to catch
vulnerabilities before merge. This addresses the requirement from
the recent security audit.

The workflow:
- Runs on every PR and push to main
- Scans dependencies for known vulnerabilities
- Fails the build for high-severity issues
- Posts scan results as PR comments

Security team will be notified of all findings via Slack integration.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Links to business requirement (security audit)
- Describes workflow trigger and behavior
- Explains notification mechanism

## Example 9: Dependency Update

```
build: update React to v18.3.0

Update React from v17.0.2 to v18.3.0 to access concurrent rendering
features and improved TypeScript support. This is a prerequisite for
implementing the new dashboard virtualization feature.

Notable changes:
- Migrated to createRoot API
- Updated event handlers for automatic batching
- Enabled strict mode to catch potential issues

All tests pass. Verified in staging with no performance regressions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Explains motivation for upgrade
- Notes API migrations performed
- Confirms testing and validation

## Example 10: Simple Fix

```
fix: correct timezone handling in report export

Report exports were showing incorrect timestamps for users in
non-UTC timezones. Now properly converts to user's local timezone
before export.

Fixes #789

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Why this works:**
- Concise but complete
- States problem and solution
- Links to issue
- Appropriate for straightforward fix
