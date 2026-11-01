---
name: inbox-lookup
description: >-
  Given an ECFX inbox id, pull that notice's full record off the admin site — status, firm, processor, every processing attempt with its exception and Java stack trace, and the email itself (rendered text plus raw MIME). Self-contained Python; handles the O365 + TOTP MFA login itself and caches the session. Use when the user gives an inbox id (or an admin URL containing one) and asks for the stack trace, the error, the email, why a notice failed, or what happened to a notice; also when triaging a Processor Error ticket that quotes an inboxId.
---


# inbox-lookup

Fetches everything the ECFX admin site knows about one inbox item and prints it in one place.

Self-contained: standard-library Python for everything except minting a session cookie, which needs
a real browser and runs in a virtualenv this skill builds for itself on first use. No repository
checkout, no Gradle, no JDK.

## Allowed Tools
Bash, Read, Write

## Running it

```bash
# Human-readable report
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_5luwprkz34i7dj5fl733vt6jdy

# Just the stack traces
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_abc123 --trace-only --no-email

# Structured output
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_abc123 --json --out /tmp/notice.json

# Several notices share one login
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_abc123 inbox_def456 --no-email
```

The argument may be a bare id, an id without the `inbox_` prefix, or a pasted admin URL.

| Flag | Effect |
| --- | --- |
| `--json` | JSON instead of the text report |
| `--out <file>` | Write to a file |
| `--trace-only` | Only the failing jobs and their traces |
| `--no-email` | Skip the rendered email fetch; raw MIME is still included |
| `--max-job-pages <n>` | Job detail pages to open per table, newest failures first (default 5) |
| `--all-jobs` | Open every attempt's page |
| `--eml [dir]` | Save the original message as `.eml` (default `~/Downloads`) |
| `--raw <dir>` | Dump the raw HTML of every page fetched |
| `--cookie <value>` | Use this session cookie instead of logging in |
| `--relogin` | Force a fresh login |
| `--quiet` | Suppress progress messages on stderr |

Progress goes to stderr and the report to stdout, so `--json` piped into a parser is always clean.

## What you get

From `inbox_item/details/?id=<inboxId>`:

- **Item fields** — ID, Created, Firm, Processor, Status, DMS Status, Action Required, Disposition,
  Disposition Text, Source, Hidden.
- **Every processing attempt** — Process Jobs and DMS Jobs, newest first, each with created time,
  status, error exception and error message.
- **Stack traces** — the full Java trace from each job's own page (`Error Stack Trace`).
- **The email** — rendered text from `inbox_item/get/<inboxId>/email/`, plus the raw MIME source.

## Saving the .eml

`--eml` downloads the stored message through the admin's own `inbox_item/get/<id>/download_raw/`
endpoint and writes it verbatim, using the filename the server supplies
(`inbox_item_<inboxId>.eml`). Those are the original bytes — the right thing to feed to
`process-email-notice` for a repro.

```bash
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_abc123 --eml            # ~/Downloads
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py inbox_abc123 --eml /tmp/emls
```

If that endpoint is unavailable the skill falls back to the Raw Content block scraped from the
details page. That fallback is a re-encoding, not the original: it is UTF-8 with CRLF endings and
loses trailing blank lines, which is harmless for a plain ASCII notice but can differ from the
stored bytes when there are attachments or a charset like WINDOWS-1252. The log line says which
path was taken (`original bytes` vs `reconstructed`).

The `rawEmail` field in the text and JSON reports is always the scraped version, and the text
report truncates it at 8,000 characters for readability. Use `--eml` when you need the real file.

## Reading the output

The two things that usually matter are the exception histogram under `--- Jobs (N attempts) ---`
and the newest trace. In JSON, `lastFailure` is the most recent job carrying an error, with its
`stackTrace` already extracted; `fields.Status`, `fields.Processor` and `fields["Action Required"]`
classify the notice.

A large attempt count with one repeated exception is a retry loop, not many distinct problems —
report the exception and the attempt count, not each attempt. Only the newest few job pages are
opened by default for that reason; pass `--all-jobs` when you need to see whether the failure mode
changed over time.

## Authentication

Every fetch is just `Cookie: session=<value>` on a GET. Getting that cookie is the only step that
needs a browser: the admin site is behind Azure AD, and with MFA enforced the flow cannot be
replayed over plain HTTP.

Cookie resolution, in order:

1. `--cookie` or `$ECFX_SESSION_COOKIE`
2. `~/.cache/sadron/admin-session.json` — the cached cookie from a previous run
3. A fresh login: headless Chromium through Azure AD, answering the MFA prompt with a TOTP code
   generated from `O365_TOTP_SECRET` (RFC 6238, standard library)

**Sessions die sooner than they claim.** The cookie advertises an 8-hour expiry but the server has
been observed invalidating it after about two, so the tool detects the redirect to the identity
provider, logs in again and retries. Expect a login roughly every couple of hours of active use.
That is normal, not a fault.

### Credentials

Needed only to mint a cookie, and stored **outside the skill** — the skill directory is a checkout
that gets synced and shared, so nothing secret belongs in it.

Run `--show-config` on any machine to see exactly where it looks, what exists, and what resolved
(secrets shown only as a length). `--init-config` creates an empty file in the right place for that
OS, with owner-only permissions.

```bash
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py --show-config
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py --init-config
```

Sources, first hit wins:

1. Environment variables: `O365_USERNAME`, `O365_PASSWORD`, `O365_TOTP_SECRET`, `ECFX_ADMIN_URL`
2. `$ECFX_ENV_FILE`, if set — an explicit path to any file
3. The OS config location:

   | OS | Locations searched, in order |
   | --- | --- |
   | Windows | `%APPDATA%\ecfx\ecfx.env`, then `%LOCALAPPDATA%\ecfx\ecfx.env` |
   | macOS | `~/.config/ecfx/ecfx.env`, then `~/Library/Application Support/ecfx/ecfx.env` |
   | Linux | `$XDG_CONFIG_HOME/ecfx/ecfx.env`, then `~/.config/ecfx/ecfx.env` |
   | any | `~/.ecfx/ecfx.env` — same everywhere, handy for a dotfiles setup |

   `$XDG_CONFIG_HOME` is honoured on every OS if you set it.
4. `$SADRON_DIR/.env`, defaulting to `~/gitlab/Sadron/.env` — a last-resort convenience for
   machines that happen to have that checkout with the same `O365_*` values in it

Use option 3. Option 4 only saves a setup step on a machine already configured for that project;
nothing here depends on it.

## Platform notes

Pure standard library, so it runs anywhere Python 3.9+ does. Use `python` instead of `python3` on
Windows, and `%USERPROFILE%\.claude\skills\inbox-lookup\inbox_lookup.py` for the path.

The virtualenv the login needs is created with the correct layout per OS (`Scripts\python.exe` on
Windows, `bin/python` elsewhere). All files are read and written as UTF-8 explicitly rather than
relying on the platform default, and `.eml` downloads are written as raw bytes, so nothing is
re-encoded in transit.

The session cache stays at `~/.cache/sadron/admin-session.json` on every OS rather than moving to a
platform cache directory, so the same cookie is found regardless of which machine conventions
apply. Delete that file to force a fresh login (or pass `--relogin`).

### Setting up a new machine

```bash
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py --init-config   # creates the file, right place for the OS
# fill in the O365_* values
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py --show-config   # confirm it is picked up
python3 ${CLAUDE_SKILL_DIR}/inbox_lookup.py <some inbox id> # first run builds the venv
```

Nothing else is needed: no repository checkout, no Gradle, no JDK, no `pip install` to run by hand.

### First-run bootstrap

The first time a login is needed, the skill creates a virtualenv at `~/.cache/inbox-lookup/venv`
and installs Playwright plus Chromium (~275 MB, a few minutes, once per machine) — deliberately
outside the skill's own directory, which is a plugin install path a version bump replaces
wholesale; a per-user cache directory survives that. It installs from PyPI explicitly and ignores
any `pip.conf`, because a work machine's pip is often pointed at a private index these public
packages are not in. Override with `$INBOX_LOOKUP_PIP_INDEX` if needed.

A `.bootstrapped` marker records that the install finished, so an interrupted bootstrap is rebuilt
rather than silently reused.

To avoid the bootstrap entirely, pass `--cookie` with a `session` value copied from an
already-authenticated browser (DevTools → Application → Cookies).

## Failure modes

- **`Cannot log in: O365_USERNAME not set`** — see Credentials above.
- **`Session cookie rejected`** — the `--cookie` value is stale; drop the flag and let the skill
  log in.
- **`No inbox item detail table`** — the inbox id does not exist in that environment. Check for a
  typo, or that the notice is in production rather than a lower environment.
- **`Could not build the skill's virtualenv`** — the message prints the exact manual commands, or
  use `--cookie` to skip the browser.
- **Chromium missing from the Playwright cache** — handled automatically. The browsers live in a
  `HOME`-relative cache, separate from the virtualenv, so they can disappear on their own (cache
  cleared, Playwright upgraded, different account). The skill notices, reinstalls, and retries with
  a freshly generated TOTP code.
- **Login runs but no cookie is set** — Azure presented a challenge the flow does not handle
  (device compliance, a re-registration prompt). That one needs a human in a browser.

## Notes

- Every request is a read-only GET. The admin page also carries Force Requeue / Prevent Requeue /
  Hide controls; this skill never touches them.
- Output contains real firm names, email addresses and legal-notice content. Keep it local; prefer
  a summary plus the stack trace when writing into a Jira ticket.
- For log-side history of a notice (Loki, retry timeline across services), use `notice-stats` or
  `categorization-stats`. This skill only reads the admin site.
