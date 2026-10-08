# notice-qa — design record

The measurements and decisions the scripts rely on, each with where it was measured and which
code depends on it. How to *use* the skill is in `SKILL.md`. Measured on dev01 and prod,
2026-09-26 to 09-28, while QA'ing ECFX-17643, ECFX-7866, ECFX-8027, ECFX-8021 and ECFX-8087.

## 1. How a notice reaches dev

```
SMTP → Postmark inbound MX (MX for dev.ecfxmail.com: inbound.postmarkapp.com, SES as backups)
     → POST /api/postmark/receipts on receipt_processing_web (partner-api.development.cloud.ecfxglobal.net)
     → inbox_item + job rows (the queue is a DB table, polled every 10 ms)
     → receipt_processing_queue: first matching processor wins
```

**Firm.** The firm is the recipient's **local part** matched against `firm.subdomain`; the domain is
ignored.
- An unknown or inactive firm gets HTTP 200 and is silently dropped (`PostmarkService.java:63-84`).
- Firms listed in `ECFX_PIPELINE_TEST_SUBDOMAINS` bypass the legacy pipeline (dev01: `pipeline`).
- Plus-addressing (`firm+tag@`) is not an option: the whole local part must match the subdomain.

**Transport**, measured from a laptop:
- Postmark's inbound MX accepts unauthenticated STARTTLS on **587 and 2525** (port 25 is blocked on
  typical networks).
- Delivery to the webhook took **2–7 s** every time.
- One 9-notice, about 500 KB email was **silently held** by Postmark, while 3-notice emails always
  arrived.

→ `send_bundle.py`: SMTP straight to the MX, 3 notices per email, 20 s apart, 587 then 2525 only
before DATA.

## 2. Bundling

`ForwardedAsAttachmentReceiptProcessor` (highest precedence) splits any email carrying
`message/rfc822` attachments, or `.eml`/`.emlx` octet-stream attachments.

- **Children:** one child inbox item per attachment. The parent ends SUCCEEDED / SPLIT. Children
  keep the attached message's own headers, so processor matching behaves as if the court had sent
  the notice directly.
- **Inline forwards** (`Fwd:` in the body) are not unwrapped.
- **Sender filters:**
  - `firm.accepted_email_domains` applies to the **wrapper only**. Children of a SPLIT parent are
    exempt. testfirm1 accepts `notice-qa@dev.ecfxmail.com` (added 2026-09-28); without it the
    wrapper is IGNORED.
  - `ignored_email_domains` applies to every item, children included.
  - Mail carrying `X-ECFX-Email-Type` is ignored, so never send through an ECFX mailer.
- **Encoding:** the splitter reads each attachment as UTF-8 text, so 8-bit non-UTF-8 notices could
  change in transit (code-read, not observed).
- **Header fidelity:** the wrapper must not re-fold the attached notices' headers. The Python
  default policy re-folds Subject with a leading space, and processors match on Subject.

→ `send_bundle.py` and `make_variant.py` use compat32 with `maxheaderlen=0`, flattened once.

## 3. Following a notice

**Logs.** The webhook logs only `Subdomain <firm> fetched` and then `| <inboxId> | BACKEND RECEIPTS
COMPLETED PROCESSING` on the same virtual thread. Nothing identifies the email itself.

**Parent attribution** is the only guess left:
- the first parent for the firm after the send that SPLIT into the right number of children;
- parents another run already claimed are excluded;
- a chunk's parent must arrive before the next chunk of the same batch was sent;
- two matches → ambiguous, not settled.

A backend INFO line in the splitter (`SPLIT parent=… child=… messageId=…`) would make this exact;
proposed as an ecfx-backend follow-up.

**Children are exact.** Inbox PublicIds are **UUIDv1** (base32; 100 ns time; monotonic per JVM).
Children are created inside the parent's split job, so their UUID times fall inside that job's
start–end window, and sorting by UUID time gives attachment order. Verified on 12 real ids.

**Outcomes** come from dev Loki (`qa_common.loki_query`):
- queries go through the nonprod Grafana proxy (`duplo-logging`);
- the server allows **at most 30d1h per query**, so longer ranges are split into 30-day slices;
- one `query_range` is capped, and the lines it drops are the *newest*, so every query pages
  (`lib/notice_loki.paginate_query`).

Pod logs (`kubectl logs`) were abandoned:
- `--since` returned *fewer* lines for a wider window;
- logs reset on every dev redeploy, which happens on every master merge.

**Which image ran a run.** Dev image tags are git SHAs. The image a run used is the newest
`receipt-processing-queue` ReplicaSet created before the send; dev redeployed mid-session on
2026-09-28. `send_bundle.py` also records it in the manifest.

## 4. Outcomes worth knowing

- **Statuses:**
  - SUCCEEDED / POST_PROCESSING = success.
  - FAILED + Action Required USER = customer action, no retry.
  - Auto-retryable failures back off 2^n minutes for up to 10 attempts; DELAYED/RETRY are not
    final.
- **CaseNotFound with auto case creation:**
  1. The first attempt FAILs with CaseNotFound.
  2. Auto case creation makes the case and requeues within about 1 s.
  3. The requeue is DELAYED about 90 s by the dedup window its *own* first attempt opened.
  4. Then the real attempt runs.

  → The tracer waits 3 min after a CaseNotFound; timeouts scale with the notice count.
- **Missing court credentials** (e.g. JAMS in testfirm1) proves parsing and link pairing, not the
  download. The report lists it under *Not covered*.
- **MyFlorida link lifecycle:** a live link downloads. After about 14 days it answers "This link
  expired" (DocumentLinkExpired). After some months it is **purged** and answers "NEF Audit # …
  is not in the system", which since !6441 is `CourtDocumentNotPublishedException`. Choose notice
  ages deliberately.

## 5. Duplicates

| Path | Disposition text | Original found by |
| --- | --- | --- |
| Redis strong indicator (Message-ID / filing no.) | "Duplicate - Document already in system…" | logged: `<firm>:<id>, classifying item as duplicate of <original>` |
| Envelope unique constraint | "Duplicate - envelope already processed by another item" | logged: `[DUPLICATE_ENVELOPE] … linked inbox item <id> to original item <original>` |
| `hasEnvelope` true | "Duplicate - Document already in system or in linked item still in process" | **not logged**: in Loki, the latest item whose `hasEnvelope called` line has the same **caseId** and courtEnvelopeId, that got `returning false`, and then SUCCEEDED |

Envelope ids are per case, not per firm: the same id existed in `samltest` too. The third path
depends on the `[ECFX-14435-DIAG]` lines in `BaseReceiptProcessor`; if those are removed, it loses
its original lookup.

**Classification** (`trace_run.classify_duplicate`):
- an original from **this batch** is a valid dedup test;
- an original from anything earlier, including this ticket's previous QA pass, is **NOT TESTED**,
  and the original goes on the requeue list.

## 6. Side effects in dev (accepted)

- **Notifications:** dev sends real notification emails. ECFX-action failures went to an internal
  goecfx.com address and to `test@testtest.test`, which is inactive in Postmark (406 on every
  send).
- **Client data:** auto case creation copies client case numbers into the test firm.
- **Court portals:** notices are downloaded with whatever credentials the firm holds.
- **Firm setup gaps:** testfirm1 has no FAI Document Processing, so FAI-only fixes cannot be
  exercised there (ECFX-7866, ECFX-8021).

## 7. Product issues found while QA'ing (to file separately)

1. **CaseNotFound emails the firm** even when auto case creation fixes it about 1 s later.
2. **Purged MyFlorida links are classified as "court has not published"**, which retries for hours,
   then misleads the firm.
3. **Requeues are delayed about 90 s by their own first attempt:** the dedup-delay key does not
   record which item set it.
4. **The most common duplicate path neither links nor logs its original.**
