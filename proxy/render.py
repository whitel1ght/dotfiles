#!/usr/bin/env python3
"""Render the sing-box config from template + domain lists + secrets.

Each domain list is injected into BOTH the DNS rules and the route rules. If
those two ever diverge, proxied traffic is tunnelled while its DNS is resolved
locally — a silent leak returning poisoned or geo-wrong answers — and a blocked
domain still resolves before its connection is refused.
"""
import json
import pathlib
import sys

REQUIRED = ("VLESS_SERVER", "VLESS_PORT", "VLESS_UUID", "VLESS_SNI", "VLESS_PBK", "VLESS_SID")
MARKERS = ("__PROXY_EXACT__", "__PROXY_SUFFIX__", "__BLOCK_EXACT__", "__BLOCK_SUFFIX__")


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


def drop_reject_rules(cfg):
    """Remove the block rules entirely when nothing is blocked.

    An empty blocklist is legitimate, unlike an empty proxy list. Leaving
    "domain": [] behind would match nothing but read as though blocking were
    configured.
    """
    for section in (cfg["dns"], cfg["route"]):
        section["rules"] = [r for r in section["rules"] if r.get("action") != "reject"]


def main(template, domains, block_domains, secrets, out):
    doms = load_domains(domains)
    if not doms:
        sys.exit(f"refusing to render: no domains in {domains} (would route everything direct)")

    blocked = load_domains(block_domains)

    # Blocking is checked first, so an overlap silently disables a domain the
    # proxy list says to tunnel. That is never intentional.
    overlap = sorted(set(doms) & set(blocked))
    if overlap:
        sys.exit(f"domain in both {domains} and {block_domains}: {', '.join(overlap)}")

    env = load_secrets(secrets)
    missing = [k for k in REQUIRED if not env.get(k)]
    if missing:
        sys.exit(f"missing in {secrets}: {', '.join(missing)}")

    raw = pathlib.Path(template).read_text()
    for key in REQUIRED:
        raw = raw.replace(f"__{key}__", env[key])

    for marker in MARKERS:
        if marker not in raw:
            sys.exit(f"template is missing {marker}")
    stripped = raw
    for marker in MARKERS:
        stripped = stripped.replace(marker, "")
    if "__" in stripped:
        sys.exit("unsubstituted placeholder remains in template")

    # domain_suffix is a plain string-suffix match, so a bare "youtube.com"
    # would also match "fake-youtube.com". Match the apex exactly and
    # subdomains via a leading dot instead.
    raw = raw.replace('"__PROXY_EXACT__"', json.dumps(doms))
    raw = raw.replace('"__PROXY_SUFFIX__"', json.dumps(["." + d for d in doms]))
    raw = raw.replace('"__BLOCK_EXACT__"', json.dumps(blocked))
    raw = raw.replace('"__BLOCK_SUFFIX__"', json.dumps(["." + d for d in blocked]))
    cfg = json.loads(raw)

    if not blocked:
        drop_reject_rules(cfg)

    pathlib.Path(out).write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"rendered {out} ({len(doms)} proxied, {len(blocked)} blocked)")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit("usage: render.py <template> <domains> <block-domains> <secrets> <out>")
    main(*sys.argv[1:])
