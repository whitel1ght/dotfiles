#!/usr/bin/env python3
"""Render the sing-box config from template + domain list + secrets.

The proxied-domain list is injected into BOTH the DNS rules and the route
rules. If those two ever diverge, proxied traffic is tunnelled while its DNS
is resolved locally — a silent leak returning poisoned or geo-wrong answers.
"""
import json
import pathlib
import sys

REQUIRED = ("VLESS_SERVER", "VLESS_PORT", "VLESS_UUID", "VLESS_SNI", "VLESS_PBK", "VLESS_SID")


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


def main(template, domains, secrets, out):
    doms = load_domains(domains)
    if not doms:
        sys.exit(f"refusing to render: no domains in {domains} (would route everything direct)")

    env = load_secrets(secrets)
    missing = [k for k in REQUIRED if not env.get(k)]
    if missing:
        sys.exit(f"missing in {secrets}: {', '.join(missing)}")

    raw = pathlib.Path(template).read_text()
    for key in REQUIRED:
        raw = raw.replace(f"__{key}__", env[key])

    if "__" in raw.replace("__PROXY_DOMAINS__", ""):
        sys.exit("unsubstituted placeholder remains in template")

    cfg = json.loads(raw.replace('"__PROXY_DOMAINS__"', json.dumps(doms)))
    pathlib.Path(out).write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"rendered {out} ({len(doms)} proxied domains)")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: render.py <template> <domains> <secrets> <out>")
    main(*sys.argv[1:])
