#!/usr/bin/env python3
"""Make an edited copy of a notice, for QA notes that prescribe one.

    make_variant.py SRC.eml --replace 'https://courts.ms.gov/appellatecourts/docket/sendPDF.php' \\
                                      'http://courts.ms.gov/appellatecourts/docket/sendPDF.php' --tag http-links

Some fixes can only be exercised deterministically by an edited email (ECFX-8027: switch the
document links to http:// so the court answers 302). This edits the DECODED text parts
(quoted-printable / base64 are decoded, edited, and re-encoded the same way), leaves every other
part byte-for-byte, and:

  * gives the copy a fresh Message-ID (so it is never mistaken for the prod original), and
  * stamps X-Notice-QA-Variant: <tag>: <what was replaced>, which send_bundle.py records in the
    run manifest and report.py shows next to the prod notice id.

The output keeps the source's inbox id in its file name (…<inbox id>.variant-<tag>.eml), so the
report still ties the result to the ticket's notice. Fails if a replacement matched nothing.
"""
import argparse
import base64
import email
import email.generator
import email.policy
import email.utils
import io
import os
import pathlib
import quopri
import re
import sys
import uuid


def codec(charset):
    import codecs
    try:
        return codecs.lookup(charset).name
    except LookupError:
        raise SystemExit(f"unknown charset {charset!r} on a text part — edit this email by hand") from None


def reencode(text, charset, cte):
    """Inverse of the decode in edit_message. surrogateescape on both sides means bytes that do not
    fit the declared charset (court emails often mislabel UTF-8 as us-ascii) come back unchanged."""
    raw = text.encode(charset, "surrogateescape")
    if cte == "base64":
        return base64.encodebytes(raw).decode("ascii")
    if cte == "quoted-printable":
        return quopri.encodestring(raw).decode("ascii")
    return raw.decode("ascii", "surrogateescape")      # 7bit / 8bit / binary: BytesGenerator writes the bytes back


def edit_message(raw, replacements, regex=False):
    """-> (compat32 message, {old: count}). Only decoded text parts are edited; everything else,
    including every header, is left exactly as parsed."""
    msg = email.message_from_bytes(raw, policy=email.policy.compat32)
    counts = {old: 0 for old, _ in replacements}
    for part in msg.walk():
        if part.get_content_maintype() != "text" or part.is_multipart():
            continue
        charset = codec(part.get_content_charset() or "us-ascii")
        cte = (part.get("Content-Transfer-Encoding") or "7bit").strip().lower()
        body = (part.get_payload(decode=True) or b"").decode(charset, "surrogateescape")
        new_body = body
        for old, new in replacements:
            if regex:
                new_body, n = re.subn(old, new, new_body)
            else:
                n = new_body.count(old)
                new_body = new_body.replace(old, new)
            counts[old] += n
        if new_body != body:
            part.set_payload(reencode(new_body, charset, cte))     # headers of the part untouched
    return msg, counts


def flatten(msg):
    buf = io.BytesIO()
    email.generator.BytesGenerator(buf, mangle_from_=False, maxheaderlen=0).flatten(msg)
    return buf.getvalue()


def main():
    os.umask(0o077)   # the variant is a copy of a prod client email
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--replace", nargs=2, action="append", metavar=("OLD", "NEW"), required=True,
                    help="literal text to replace in every text part (repeatable)")
    ap.add_argument("--regex", action="store_true", help="treat OLD as a regular expression")
    ap.add_argument("--tag", required=True, help="short name for this edit, e.g. http-links")
    ap.add_argument("--out", help="output directory (default: next to the source)")
    a = ap.parse_args()

    src = pathlib.Path(a.src)
    # compat32 + maxheaderlen=0 on output: headers go out exactly as they came in (no re-folding —
    # the default policy re-folded Subject with a leading space, which processor matching reads).
    msg, counts = edit_message(src.read_bytes(), a.replace, a.regex)
    missing = [old for old, n in counts.items() if n == 0]
    if missing:
        sys.exit(f"no match for: {missing} — nothing written")

    summary = "; ".join(f"{n}x '{old}' -> '{new}'" for (old, new), n in zip(a.replace, counts.values()))
    msg.replace_header("Message-ID", email.utils.make_msgid(idstring=f"notice-qa-variant-{uuid.uuid4().hex[:8]}",
                                                            domain="notice-qa.ecfx.invalid"))
    msg["X-Notice-QA-Variant"] = f"{a.tag}: {summary}"

    out_dir = pathlib.Path(a.out) if a.out else src.parent
    out = out_dir / f"{src.stem}.variant-{a.tag}.eml"
    out.write_bytes(flatten(msg))
    print(f"{out}\n{summary}")


if __name__ == "__main__":
    main()
