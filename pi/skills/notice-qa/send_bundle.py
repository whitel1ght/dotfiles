#!/usr/bin/env python3
"""Step 3 of a notice-QA run: bundle .eml notices into emails and deliver them to a DEV firm inbox.

    send_bundle.py --firm testfirm1 --ticket ECFX-NNNN notice1.eml notice2.eml …
    send_bundle.py --firm testfirm1 --synthetic 2        # smoke test, no client data

Delivers straight to Postmark's inbound MX (no credentials): 587, then 2525, both STARTTLS. Each
notice is attached as message/rfc822, so ForwardedAsAttachmentReceiptProcessor splits it into its
own child inbox item with the original headers intact.

Safety and fidelity (review of !52):
  * the only possible recipient is <firm>@dev.ecfxmail.com, where <firm> is a bare dev subdomain —
    validated on input and asserted again at the moment of sending (M1);
  * the bundle is built with compat32 and flattened ONCE without re-folding; exactly those bytes
    are written to -bundle.eml and sent, so attached notices keep their original header folding
    and encoded words (M4);
  * port 2525 is tried only if 587 failed BEFORE the message data was sent; a failure during or
    after DATA stops with exit 5 ("delivery status unknown") instead of sending twice (M8);
  * notices already sent for this ticket are skipped unless --force-resend: after a fix, dev
    deduplicates a re-sent notice anyway — requeue the original instead (see trace/report) (M8);
  * files are private (umask 077), and real notices can only be written under ~/.cache/notice-qa (M9).
"""
import argparse
import datetime
import email
import email.generator
import email.message
import email.policy
import email.utils
import hashlib
import html
import io
import json
import os
import pathlib
import re
import smtplib
import ssl
import sys
import time
import uuid
from email.mime.message import MIMEMessage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import qa_common as qc  # noqa: E402

MX_HOST = "inbound.postmarkapp.com"
MX_PORTS = (587, 2525)
QA_SENDER = "notice-qa@dev.ecfxmail.com"   # must be in the firm's accepted_email_domains
INBOUND_DOMAIN = "dev.ecfxmail.com"
FIRM_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
WIRE_POLICY = email.policy.compat32.clone(linesep="\r\n")


class DeliveryUnknown(Exception):
    """The server may or may not have accepted the message (failure during/after DATA)."""


def dev_address(firm):
    """The one address this tool can send to. Anything that isn't a bare dev subdomain is refused."""
    if not isinstance(firm, str) or not FIRM_RE.fullmatch(firm):
        raise ValueError(f"--firm must be a bare dev firm subdomain (e.g. testfirm1), got {firm!r}")
    return f"{firm}@{INBOUND_DOMAIN}"


def synthetic_notice(run, n, to_addr):
    m = email.message.EmailMessage()
    m["From"] = "QA Synthetic Court <clerk@qa-synthetic-court.invalid>"
    m["To"] = to_addr
    m["Subject"] = f"[{run}] SYNTHETIC TEST NOTICE {n} - not a real court filing"
    m["Date"] = email.utils.formatdate()
    m["Message-ID"] = f"<{run}-child{n}@notice-qa.ecfx.invalid>"
    m.set_content(f"Synthetic test notice {n} for notice-QA run {run}.\n"
                  "Not a real court filing; contains no case data.\n")
    return email.message_from_bytes(bytes(m), policy=email.policy.compat32)


def flatten(msg):
    buf = io.BytesIO()
    email.generator.BytesGenerator(buf, mangle_from_=False, maxheaderlen=0, policy=WIRE_POLICY).flatten(msg)
    return buf.getvalue()


def build_bundle(run, firm, notices):
    """-> (wire bytes, to_addr). compat32 end to end: attached notices are never re-folded."""
    to_addr = dev_address(firm)
    wrap = MIMEMultipart("mixed")
    wrap["From"] = f"ECFX Notice QA <{QA_SENDER}>"
    wrap["To"] = to_addr
    wrap["Subject"] = f"[{run}] Notice QA bundle ({len(notices)} notices)"
    wrap["Date"] = email.utils.formatdate()
    wrap["Message-ID"] = f"<{run}-bundle@notice-qa.ecfx.invalid>"
    wrap["X-ECFX-QA-Run"] = run
    wrap.attach(MIMEText(f"Notice QA bundle {run}: {len(notices)} attached notice(s).\n"))
    for name, msg in notices:
        part = MIMEMessage(msg)
        part.add_header("Content-Disposition", "attachment", filename=name)
        wrap.attach(part)
    return flatten(wrap), to_addr


def deliver(data, to_addr, smtp_factory=smtplib.SMTP):
    """Send `data` (bytes) to `to_addr`. Returns the port used.

    Falls back to the next port only for failures BEFORE the DATA command; once DATA has started,
    any error means the message may already be accepted, so raise DeliveryUnknown (never re-send)."""
    local, _, domain = to_addr.partition("@")
    assert domain == INBOUND_DOMAIN and FIRM_RE.fullmatch(local), f"refusing to send to {to_addr!r}"   # M1, last line
    last = None
    for port in MX_PORTS:
        try:
            s = smtp_factory(MX_HOST, port, timeout=30)
        except (OSError, smtplib.SMTPException) as e:
            last = e
            print(f"port {port}: connect failed: {type(e).__name__}: {e}", file=sys.stderr)
            continue
        try:
            try:
                s.ehlo("notice-qa.local")
                s.starttls(context=ssl.create_default_context())
                s.ehlo("notice-qa.local")
                code, resp = s.mail(QA_SENDER)
                if code != 250:
                    raise smtplib.SMTPSenderRefused(code, resp, QA_SENDER)
                code, resp = s.rcpt(to_addr)
                if code not in (250, 251):
                    raise smtplib.SMTPRecipientsRefused({to_addr: (code, resp)})
            except (OSError, smtplib.SMTPException) as e:
                last = e
                print(f"port {port}: failed before DATA: {type(e).__name__}: {e}", file=sys.stderr)
                continue
            try:
                code, resp = s.data(data)
            except (OSError, smtplib.SMTPException) as e:
                raise DeliveryUnknown(f"port {port}: failed during/after DATA ({type(e).__name__}: {e})") from e
            if code != 250:
                raise DeliveryUnknown(f"port {port}: DATA answered {code} {resp!r}")
            return port
        finally:
            try:
                s.quit()
            except Exception:   # noqa: BLE001 — the connection may already be gone
                pass
    raise SystemExit(f"SMTP delivery failed on all ports before sending any data ({last}); nothing was sent")


URL_RE = re.compile(r"https?://[^\s\"'<>)]+")


def copy_key(msg):
    """Same court notice sent to several recipients (JAMS sends one copy each) → same key.

    From + Subject + the set of links in the decoded body parts (quoted-printable/base64 decoded —
    raw bytes hide the links behind soft line breaks). Recipient-specific headers are ignored.
    """
    links = set()
    for part in msg.walk():
        if part.get_content_maintype() != "text":
            continue
        payload = part.get_payload(decode=True) or b""
        text = html.unescape(payload.decode(part.get_content_charset() or "utf-8", "replace"))
        links |= {u.rstrip(".,;") for u in URL_RE.findall(text)}
    key = "|".join([str(msg.get("From", "")).lower(), str(msg.get("Subject", "")), *sorted(links)])
    return hashlib.sha1(key.encode()).hexdigest()[:16] + ("" if links else "-nolinks")


def current_dev_image():
    """The dev receipt-processing image at send time (report.py falls back to dev's rollout history)."""
    import subprocess
    try:
        img = subprocess.run(["kubectl", "--context", "dev01", "-n", "duploservices-dev01", "--request-timeout=20s", "get",
                              "deploy", "ecfx-backend-receipt-processing-queue", "-o",
                              "jsonpath={.spec.template.spec.containers[0].image}"], capture_output=True, text=True, timeout=40).stdout
        return img.rsplit(":", 1)[-1][:40] if ":" in img else None
    except Exception:   # noqa: BLE001 — optional
        return None


def source_id(filename):
    """Prod inbox id from an inbox-lookup filename (inbox_item_inbox_<id>.eml), else None."""
    m = re.search(r"(inbox_(?!job_)[0-9a-z]{20,32})", filename)
    return m.group(1) if m else None


def already_sent(runs_dir):
    """File names of notices sent in earlier runs for this ticket (any batch)."""
    sent = {}
    for f in runs_dir.glob("*.json"):
        if f.name.endswith(".result.json"):
            continue
        m = json.loads(f.read_text())
        for n in m.get("notices", []):
            sent.setdefault(n["file"], m["run"])
    return sent


def main():
    os.umask(0o077)   # M9: bundles and manifests hold client data
    ap = argparse.ArgumentParser()
    ap.add_argument("--firm", required=True, help="dev firm subdomain, e.g. testfirm1")
    ap.add_argument("--synthetic", type=int, default=0, help="attach N synthetic notices")
    ap.add_argument("--ticket", help="Jira key; runs are stored under ~/.cache/notice-qa/<TICKET>/runs")
    ap.add_argument("--out", help="output dir (must be under ~/.cache/notice-qa when real notices are attached)")
    ap.add_argument("--max-per-bundle", type=int, default=3, help="notices per email (0 = all in one)")
    ap.add_argument("--gap", type=int, default=20, help="seconds between bundles")
    ap.add_argument("--force-resend", action="store_true",
                    help="send notices this ticket already sent (dev will usually deduplicate them)")
    ap.add_argument("emls", nargs="*")
    a = ap.parse_args()
    try:
        to_addr = dev_address(a.firm)
    except ValueError as e:
        ap.error(str(e))

    if a.ticket:
        out = pathlib.Path(a.out) if a.out else qc.ticket_dir(a.ticket) / "runs"
    else:
        out = pathlib.Path(a.out) if a.out else qc.QA_HOME / "adhoc" / "runs"
    if a.emls and qc.QA_HOME.resolve() not in out.resolve().parents:
        ap.error(f"real notices can only be written under {qc.QA_HOME} (use --ticket, or an --out below it)")
    out.mkdir(parents=True, exist_ok=True, mode=0o700)

    run = "notice-qa-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:6]
    notices = [(f"{run}-synthetic{i}.eml", synthetic_notice(run, i, to_addr)) for i in range(1, a.synthetic + 1)]
    previous = already_sent(out) if a.ticket and not a.force_resend else {}
    for p in map(pathlib.Path, a.emls):
        if p.name in previous:
            print(f"skipping {p.name}: already sent in run {previous[p.name]} (re-sending is deduplicated by dev; "
                  "requeue the original instead, or pass --force-resend)", file=sys.stderr)
            continue
        notices.append((p.name, email.message_from_bytes(p.read_bytes(), policy=email.policy.compat32)))
    if not notices:
        ap.error("nothing to send: pass .eml files or --synthetic N (or everything was already sent)")

    # One email per chunk. Postmark silently held a 9-notice / 500 KB bundle (2026-09-28) while
    # 1–3-notice bundles went straight through, so large tickets go out as several small emails,
    # each its own run (own manifest, traced separately).
    size = a.max_per_bundle if a.max_per_bundle > 0 else len(notices)
    chunks = [notices[i:i + size] for i in range(0, len(notices), size)]
    manifests = []
    for n_chunk, chunk in enumerate(chunks, 1):
        chunk_run = run if len(chunks) == 1 else f"{run}-p{n_chunk}"
        data, to = build_bundle(chunk_run, a.firm, chunk)
        (out / f"{chunk_run}-bundle.eml").write_bytes(data)          # exactly the bytes sent
        sent_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        manifest = {
            "run": chunk_run, "batch": run, "ticket": a.ticket, "firm": a.firm, "devImage": current_dev_image(),
            "to": to, "sentAt": sent_at, "bytes": len(data),
            # Children are created in attachment order; trace_run.py maps children back by it.
            "notices": [{"file": n, "sourceInboxId": source_id(n), "messageId": m["Message-ID"], "subject": m["Subject"],
                         "copyKey": copy_key(m), "variant": m.get("X-Notice-QA-Variant")} for n, m in chunk],
        }
        try:
            port = deliver(data, to)
        except DeliveryUnknown as e:
            manifest.update(transport="unknown", deliveryUnknown=str(e))
            (out / f"{chunk_run}.json").write_text(json.dumps(manifest, indent=2))
            print(f"{out / f'{chunk_run}.json'}\n! delivery status unknown for {chunk_run}: {e}\n"
                  "  Do NOT re-send. Trace it: it may well have arrived. Remaining chunks were not sent.", file=sys.stderr)
            print(json.dumps({"runs": manifests + [str(out / f"{chunk_run}.json")], "stoppedAt": chunk_run}, indent=2))
            return 5
        manifest["transport"] = f"smtp:{MX_HOST}:{port}"
        (out / f"{chunk_run}.json").write_text(json.dumps(manifest, indent=2))
        manifests.append(str(out / f"{chunk_run}.json"))
        print(f"sent {chunk_run} ({len(chunk)} notice(s)) → {manifests[-1]}", file=sys.stderr, flush=True)
        if n_chunk < len(chunks):
            time.sleep(a.gap)   # keep separate bundles from landing in the same instant (parent matching)
    print(json.dumps({"runs": manifests, "notices": len(notices), "bundles": len(chunks)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
