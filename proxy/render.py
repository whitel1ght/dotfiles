#!/usr/bin/env python3
"""Render the sing-box config from template + domain lists + secrets.

Each domain list is injected into BOTH the DNS rules and the route rules. If
those two ever diverge, direct traffic goes out while its DNS is resolved
through the tunnel — a silent leak returning poisoned or geo-wrong answers —
and a blocked domain still resolves before its connection is refused.
"""
import json
import pathlib
import re
import sys

REQUIRED = ("VLESS_SERVER", "VLESS_PORT", "VLESS_UUID", "VLESS_SNI", "VLESS_PBK", "VLESS_SID")
MARKERS = (
    "__DIRECT_EXACT__", "__DIRECT_SUFFIX__",
    "__BLOCK_EXACT__", "__BLOCK_SUFFIX__",
    "__READER_EXACT__", "__READER_SUFFIX__",
)


def load_domains(path):
    lines = pathlib.Path(path).read_text().splitlines()
    return [s for s in (l.strip() for l in lines) if s and not s.startswith("#")]


def load_secrets(path):
    env = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip()
    return env


def drop_rules(cfg, predicate):
    """Remove matching rules from both rule sets.

    An empty list is legitimate in all three cases — an empty direct list means
    everything is proxied. Leaving "domain": [] behind would match nothing but
    read as though the feature were configured.
    """
    for section in (cfg["dns"], cfg["route"]):
        section["rules"] = [r for r in section["rules"] if not predicate(r)]


def is_empty_domain_rule(rule):
    """A rule that carries nothing but empty domain lists.

    The injected rules differ in what they point at — the block rule carries an
    action, the reader rule a process_name, the direct rule a server in the dns
    rules and an outbound in the route rules — so rather than enumerate those
    shapes (and get one wrong), drop any rule whose domain lists are empty. The
    hand-written rules (sniff, hijack-dns, ip_is_private) have no domain keys
    at all and are left alone.
    """
    keys = [k for k in ("domain", "domain_suffix") if k in rule]
    return bool(keys) and all(not rule[k] for k in keys)


def main(template, direct_domains, block_domains, reader_domains, secrets, out):
    direct = load_domains(direct_domains)

    blocked = load_domains(block_domains)

    # Blocking is checked first, so an overlap silently disables a domain the
    # direct list says to keep off the VPS. That is never intentional.
    overlap = sorted(set(direct) & set(blocked))
    if overlap:
        sys.exit(f"domain in both {direct_domains} and {block_domains}: {', '.join(overlap)}")

    reader = load_domains(reader_domains)

    # A reader domain carves an exception out of a block. One that is not
    # blocked excepts nothing, so it silently does nothing at all.
    unblocked = sorted(set(reader) - set(blocked))
    if unblocked:
        sys.exit(
            f"in {reader_domains} but not blocked in {block_domains}: {', '.join(unblocked)}"
        )

    env = load_secrets(secrets)
    missing = [k for k in REQUIRED if not env.get(k)]
    if missing:
        sys.exit(f"missing in {secrets}: {', '.join(missing)}")

    raw = pathlib.Path(template).read_text()

    # Validate placeholders BEFORE substituting anything. Once a secret is in
    # the text there is no way to tell a leftover marker from a secret that
    # merely contains one: REALITY public keys are base64url, so they use
    # underscores and a key can hold "__" by chance. Checking afterwards made
    # the render fail for some keys and succeed after regenerating.
    known = set(MARKERS) | {f"__{k}__" for k in REQUIRED}
    unknown = sorted(set(re.findall(r"__[A-Z][A-Z0-9_]*__", raw)) - known)
    if unknown:
        sys.exit(f"unknown placeholder in template: {', '.join(unknown)}")
    missing = [m for m in MARKERS if m not in raw]
    if missing:
        sys.exit(f"template is missing {', '.join(missing)}")

    for key in REQUIRED:
        raw = raw.replace(f"__{key}__", env[key])

    # domain_suffix is a plain string-suffix match, so a bare "youtube.com"
    # would also match "fake-youtube.com". Match the apex exactly and
    # subdomains via a leading dot instead.
    raw = raw.replace('"__DIRECT_EXACT__"', json.dumps(direct))
    raw = raw.replace('"__DIRECT_SUFFIX__"', json.dumps(["." + d for d in direct]))
    raw = raw.replace('"__BLOCK_EXACT__"', json.dumps(blocked))
    raw = raw.replace('"__BLOCK_SUFFIX__"', json.dumps(["." + d for d in blocked]))
    raw = raw.replace('"__READER_EXACT__"', json.dumps(reader))
    raw = raw.replace('"__READER_SUFFIX__"', json.dumps(["." + d for d in reader]))
    cfg = json.loads(raw)

    drop_rules(cfg, is_empty_domain_rule)

    pathlib.Path(out).write_text(json.dumps(cfg, indent=2) + "\n")
    print(
        f"rendered {out} ({len(direct)} direct, {len(blocked)} blocked, "
        f"{len(reader)} reader exceptions)"
    )


if __name__ == "__main__":
    if len(sys.argv) != 7:
        sys.exit(
            "usage: render.py <template> <direct-domains> <block-domains> "
            "<reader-domains> <secrets> <out>"
        )
    main(*sys.argv[1:])
