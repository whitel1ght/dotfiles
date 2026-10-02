---
name: notice-qa
description: >-
  Full QA pass of an ECFX notice-processing ticket in the dev environment — read the Jira ticket, collect the prod notices (inbox ids) it references, email them as attachments to a dev firm inbox (e.g. testfirm1@dev.ecfxmail.com), trace every notice through dev01, resolve duplicates to the original dev item, judge each outcome against the ticket's QA notes, and attach a report to the ticket. Use when the user asks to QA a ticket, "run these notices through dev", "test ECFX-NNNN in dev", or verify a notice-processing fix before sign-off.
---


# notice-qa

Replays a ticket's prod notices into a dev firm and reports what dev did with each one.

The scripts do everything that has a mechanical answer; you judge outcomes against the ticket and
decide at every ⏸.

- **Run state** lives in `~/.cache/notice-qa/<TICKET>/`: `ticket.json`, `emls/`, `runs/`,
  `verdicts.json` and the report. It holds client data, so keep it local.
- **Design and measurements:** `RESEARCH.md`.

```bash
S=${CLAUDE_SKILL_DIR}   # this skill's own directory
```

## When to use

Use it when a notice-processing ticket is In QA and its fix is in the dev01 image.

Use something else to:

- *find* a bug → `research-jira-bug`;
- *fix* a bug → `fix-jira-bug`;
- reproduce a notice locally → `process-email-notice`.

## Allowed tools

`Bash, Read, Write, Edit, AskUserQuestion`

## Prerequisites

Credentials are files each person puts in `~/.config/ecfx/` (mode 600, dir 700), never in this
folder. See claude-components `docs/CREDENTIALS.md`.

| File | Required | Source |
| --- | --- | --- |
| `jira.env` | yes | your own Jira API token |
| `ecfx.env` | yes, unless `--local-emls` | 1Password shared vault → Document `ecfx.env` |
| `duplo.env` | no | 1Password shared vault → Document `duplo.env`; otherwise your `duplo-jit` login |

Per target firm, set once in dev:

- It must accept `notice-qa@dev.ecfxmail.com` as a sender. testfirm1 does.
- Auto case creation avoids most CaseNotFound round trips.

## Flow

**0. Preflight**

```bash
python3 $S/preflight.py [--local-emls]
```

It checks the credential files, SMTP egress, a **real** dev Loki query (a token that exists but
doesn't work fails here, before anything is sent) and the kubectl context.
Exit 3 = ⏸ stop. Relay its ✗ lines verbatim. Never ask for a secret in chat.

**1. Ticket**

```bash
python3 $S/fetch_ticket.py ECFX-NNNN
```

It collects the ticket's inbox ids, downloads each prod email and prod outcome, and attaches the
QA-notes section that mentions each id (`items[].qaNotes`).

It never collects ids from:

- its own "Notice QA (dev01)" comments;
- dev-admin links;
- ids prod doesn't have. Local or dev repro ids quoted in comments go to `notInProd` and are
  skipped.

Every comment is read (paged past Jira's page size). Each id records **who mentioned it**
(`sourceAuthors`). Ids mentioned only by customer (portal) accounts are held back and listed under
`externalOnly`. ⏸ Show them to the user, with their authors, before re-running with
`--include-external`: anyone who can comment must not be able to choose which prod notices get
replayed into dev.

Exit 3 = ⏸:

- more than 25 ids → sample by cause with `--only --ids …`. `--only` limits what is downloaded;
  `ticket.json` still lists every id, and earlier downloads are kept.
- a missing email. The message says why: stale admin login, inbox-lookup not installed, or
  timed out (a stuck MFA login).

**2. Deployed?** The fix commit must be in the dev image:

```bash
git -C ~/gitlab/ecfx-backend merge-base --is-ancestor <fix> $(kubectl --context dev01 -n duploservices-dev01 get deploy ecfx-backend-receipt-processing-queue -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
```

⏸ If it isn't, stop.

**2b. Edited copies, when the QA notes prescribe one.** Some fixes can only be exercised
deterministically by an edited email. For example, ECFX-8027 switches the document links to
`http://` so the court answers 302. For those:

```bash
python3 $S/make_variant.py ~/.cache/notice-qa/ECFX-NNNN/emls/inbox_item_<id>.eml \
  --replace '<old text>' '<new text>' --tag <short-name>
```

It edits only the decoded text parts and re-encodes them the same way, leaving headers
byte-for-byte. The one exception: a fresh `Message-ID` plus an `X-Notice-QA-Variant` header. Send
the `….variant-<tag>.eml`; the report marks the notice as an *edited copy* with what was changed.

**3. Send**

```bash
python3 $S/send_bundle.py --firm testfirm1 --ticket ECFX-NNNN <emls…>
```

- It sends **3 notices per email** by default, 20 s apart, and each email is its own run.
- One 9-notice, 500 KB email was silently held by Postmark, while 3-notice emails arrived in
  about 2 s.
- All emails from one invocation share a `batch` id. Each notice gets a `copyKey`, so recipient
  copies of the same court notice can be recognised.
- **Recipient:** the only possible recipient is `<firm>@dev.ecfxmail.com`, where `--firm` must be a
  bare subdomain. It is checked on input and again at the moment of sending.
- **Byte-faithful:** attached notices go out byte-for-byte. The wrapper is flattened once, and those
  exact bytes are sent and saved as `-bundle.eml`.
- **Never sent twice:**
  - 2525 is tried only if 587 failed *before* DATA.
  - A failure during or after DATA exits **5, "delivery status unknown"**. Don't re-send; trace it.
  - Notices this ticket already sent are skipped. Re-sending after a fix is only deduplicated by
    dev, so requeue the original instead. `--force-resend` overrides.
- **Location:** real notices can only be written under `~/.cache/notice-qa` (mode 700).

**4. Trace**, once per run manifest:

```bash
python3 $S/trace_run.py ~/.cache/notice-qa/ECFX-NNNN/runs/<run>.json
```

- **Timeout:** scales with the notice count. Copies from the same sender and subject are delayed
  about 90 s each by dev's dedup window, and CaseNotFound waits 3 min for auto case creation.
- **Exit 4:** Postmark accepted the email but never delivered it. Resend those notices with a
  smaller `--max-per-bundle`, or retry the held message in Postmark's inbound activity.
- **Parent attribution:**
  - a chunk only adopts a parent that arrived before the next chunk of its batch was sent;
  - a parent another run already claimed is never adopted;
  - two candidates means `ambiguous`, not settled. Check the dev admin; the tracer never guesses.
- **Loki:** every query is paged, so a busy child's last attempt is never dropped.
- **Output per child:** the attempt history, and `logMarkers` (WARN/ERROR/`[MARKER]` lines).
- **When the QA notes name log lines** (often INFO lines, which `logMarkers` doesn't keep), pass
  them as `--expect-log REGEX` (must appear) and `--forbid-log REGEX` (must not; typically the old
  error). They are counted per child across all levels, and the ✓/✗ counts land in the report
  row.
- **Duplicates:**

  | Classification | Meaning | Verdict |
  | --- | --- | --- |
  | `sameTicket` | deduplicated against another notice **from this same send (batch)** | PASS: dedup works |
  | `previouslyProcessed` | the original is from anything earlier, **including this ticket's previous QA pass** (e.g. before the fix was deployed) | NOT TESTED; the original goes on the ticket for manual Force Requeue |

**5. Judge.** Write `~/.cache/notice-qa/ECFX-NNNN/verdicts.json`:

```json
{"<dev child id | attachment file | prod id>": {"expected": "...", "verdict": "PASS|FAIL|NOT TESTED|INCONCLUSIVE",
                                               "note": "...", "logCheckOverride": "optional reason"},
 "_tested":     ["one line per QA test that passed: **what** was checked and the evidence"],
 "_notCovered": ["coverage gaps only you can see, listed under Not covered in the report"]}
```

**Always write `_tested`.** It becomes the *What was tested → Passed* list at the top of the report
and the Jira comment, the first thing readers see. Write one line per QA-notes test, not per
notice. Name the test, say what was observed, and quote the log lines or errors that prove it.
Without it the report falls back to each passing notice's `expected` text, which is accurate but
reads worse.

Take each expectation from that item's `qaNotes` excerpt. If there is none, fall back to:

1. the bot label (Correspondence ⇒ IGNORED passes);
2. the prod outcome inverted;
3. ⏸ asking.

- **Keys:** key by the **dev child id** or the **attachment file** when an original and its edited copy
  are both in a run. They share a prod id.
- **Failed log checks:** a failed `--expect-log` / `--forbid-log` turns PASS into **FAIL**, unless
  the entry gives a `logCheckOverride` reason, e.g. the line belongs to the case-not-found attempt.

Scenarios seen in practice:

| Situation | How to judge |
| --- | --- |
| **The test firm has no court credential** (`MissingCourtCredentialsException` etc.) | PASS only if the QA notes accept it (typically: "proves parsing, not the download"). The report lists it under *Not covered*. Suggest adding a credential to the firm if the download matters. |
| **The QA notes expect a duplicate, but no copy stored a document** | The dedup test could not happen. Mark it NOT TESTED; the report explains it under *Not covered*. |
| **The QA notes expect a duplicate** because prod had already delivered it | In a fresh test firm this is a first delivery. Judge whether it got past the step that proves the fix: parsed and matched, then failed later for credentials. |
| **A notice the QA notes expect to FAIL** (a behaviour change) | PASS when it FAILED with the named error, and the named log marker is in `logMarkers`. |
| **The test firm lacks the feature the fix lives behind** (e.g. FAI title extraction not configured, so the code path never runs) | Before sending, check that the firm actually reaches the fixed code, using its log lines in dev Loki. If it doesn't, ⏸ ask: set the firm up first, or run only the "unchanged for firms without the feature" test. Mark the rest NOT TESTED and add a `"_notCovered": ["…"]` entry to `verdicts.json` explaining why. |
| **The fix is a logging or labelling change on a failure that retries** (the notice is expected to keep failing, now logged correctly) | Settled after the first attempt that reaches the fixed code. PASS when the `--expect-log` lines appear once and the `--forbid-log` line doesn't. The item stays in retry in dev; list "clear the dev item per the ECFX-queue process" under *Not covered*. |
| **A notice takes a different path than planned because of its age** | Court links age through stages. MyFlorida links answer "This link expired" for a while after their 14 days, then get purged and answer "not in the system", which is a different exception (seen on ECFX-8087 with a notice about 10 months old). Choose notice ages deliberately. When one lands on another test's path, judge it against *that* test and say so in its note; don't call it a failure of the test you meant it for. |
| **Still DELAYED or RETRY at the end** | INCONCLUSIVE. Re-run the trace later. |
| **A setup gap you can fix in dev** (no case and no auto case creation; jurisdiction not mapped) | Fix it, requeue, re-trace. |
| **Anything else unexpected** | ⏸ ask. |

**6. Report**

```bash
python3 $S/report.py ECFX-NNNN --verdicts ~/.cache/notice-qa/ECFX-NNNN/verdicts.json --fix-commit <sha>
```

- It defaults to the **latest batch**. Use `--all-runs` or `--runs <run|batch>` to change that.
- **Shared fixes.** When a ticket's QA notes point at another ticket's test (one MR fixes several
  tickets), don't re-send: a second send to the same firm only comes back as a duplicate. Report
  the existing run instead with
  `--from-ticket <OTHER> --runs <batch> --only-sources <inbox id…>`. The *How* line says the run
  was reused.
- **The dev image shown is the one each run was processed on.** It comes from dev's rollout history
  at send time (and from the manifest for new runs), not the image at report time, because dev
  redeploys on every master merge. The fix-in-image check uses that same image.
- **Overall verdict:** FAIL > INCOMPLETE > **NOT TESTED** (nothing passed) > PASS WITH NOTES > PASS.
- **Missing notices:** every sent notice gets a row. One that never reached dev, or matched no
  child, is **NOT TESTED**, unless it was re-sent and matched in another included run.
- **Fix-in-image:** reads **unverified** (with the cause logged) whenever it can't be proven either
  way. It never reads NO on missing information.
- It exits 3 while any row still says NEEDS VERDICT.

**7. Post**

```bash
python3 $S/jira_post.py ECFX-NNNN --dry-run
python3 $S/jira_post.py ECFX-NNNN
```

It posts the **whole report as one native Jira comment**, so readers don't need to open an
attachment. Top to bottom, the comment contains:

- verdict and counts;
- **What was tested:**
  - *How*, generated from the runs: notice count, edited copies, firm, dev image, how the notices
    were sent, where outcomes were read, and the log checks;
  - *Passed*, from `_tested`;
- **Not covered by this run**, directly beneath it;
- the context table: environment, dev image, whether the fix is in the image, and every run with
  its parent (runs that never reached dev included);
- the manual-requeue list;
- the full results table: verdict, prod notice, dev item link, processor, final outcome, attempt
  history, expected, notes;
- the method.

Details:

- **Re-rendering and re-posting the same send updates that comment in place.** The comment id is
  saved the moment it is created. A 404 on update posts a new one. `--new` forces a new comment,
  and `--update <comment id>` refreshes a specific earlier comment.
- `--attach` also attaches the Markdown file.
- Comments over about 30k characters get their cells trimmed. If a comment is still too big,
  report the runs separately with `report.py --runs …`.
- The heading starts "Notice QA (dev01)", which `fetch_ticket.py` uses to skip the skill's own
  comments.

In chat, report the verdict, the counts, NOT TESTED and not-covered items, the requeue list and the
comment link. Do not paste the report.

**8. Purge the client data**

```bash
python3 $S/purge.py ECFX-NNNN --keep-report     # right after posting
python3 $S/purge.py ECFX-NNNN                   # once the ticket is done
python3 $S/purge.py --older-than 30             # housekeeping
```

`--keep-report` keeps only `report-summary.json`, `verdicts.json` and the rendered report, which is
what updating the comment needs.

## Tests

```bash
python3 skills/notice-qa/test_notice_qa.py      # stdlib only; no network, Jira, Loki, SMTP or dev
```

Each block pins a finding from the review of !52 whose failure mode is a wrong verdict or an unsafe
send. When you change the code, break a guard on purpose and see the test go red before trusting
it.

## Side effects in dev (accepted by the user)

- Real client notices land in the shared test firm.
- Auto case creation copies client case numbers into it.
- Dev sends notification emails.
- Court portals are contacted with the firm's credentials; PACER costs money.
- Send only to *dev* firm inboxes.

## Failure modes

| Symptom | Fix |
| --- | --- |
| Preflight ✗ | Follow the line: it names the file and where to get it. |
| `fetch_ticket` "prod admin login missing or stale" | Re-download `ecfx.env`. If the shared password was rotated, also delete `~/.cache/sadron/admin-session.json`. |
| Trace exit 4, no parent | Postmark held the email. Resend smaller, or retry it in Postmark. |
| Send exit 5, "delivery status unknown" | The connection dropped during or after DATA. Trace the run first; it probably arrived. Never re-send blind. |
| Trace `ambiguous` | Two unclaimed parents fit. Check both in the dev admin. |
| Parent IGNORED "not in accepted domains" | Add `notice-qa@dev.ecfxmail.com` to the firm's accepted senders. |
| `expected N children, found M` | Another bundle arrived at the same instant. Check the parent in the dev admin. |
| Every child "Duplicate" (`previouslyProcessed`) | This ticket was QA'd in this firm before. Requeue the originals from the requeue list, or use another firm. |
| `skipping …: already sent` | Intended. Requeue the original in dev, or pass `--force-resend` if you really want a new copy. |
| SMTP 587 and 2525 blocked | Use another network; the webhook fallback is not built. |
| Auto mode blocks `send_bundle.py` | Add a Bash permission rule for it, or approve each send. |
