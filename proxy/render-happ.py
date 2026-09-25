#!/usr/bin/env python3
"""Render the iPhone's Happ setup from the same lists the Mac's sing-box uses.

    render-happ.py routing <domains>   happ://routing/onadd/... link
    render-happ.py json    <domains>   the routing profile, readable
    render-happ.py server  <secrets>   vless:// link for the VPS

The routing profile mirrors sing-box's proxy split: only proxy-domains.txt goes
through the VPS and everything else goes direct (GlobalProxy "false"). The phone
blocks nothing: block-domains.txt and reader-domains.txt are Mac-only choices.

Domains are written as "domain:<apex>", Xray's match for the apex and its
subdomains. A bare entry would be a substring match in Xray, so "claude.ai" would
also catch "notclaude.ai"; the prefix keeps the Mac's matching.

DNS follows the Mac too: proxied domains resolve over DoH at 8.8.8.8 through the
tunnel, so they never leak to the local resolver; the rest resolve directly.
"""
import base64
import json
import sys
import urllib.parse
from pathlib import Path

sys.dont_write_bytecode = True  # importing render.py must not leave __pycache__ in the repo
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render import load_domains, load_secrets, REQUIRED  # noqa: E402

PRIVATE_NETS = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "127.0.0.0/8"]


def routing_profile(domains_path):
    doms = load_domains(domains_path)
    if not doms:
        sys.exit(f"refusing to render: no domains in {domains_path} (would proxy nothing)")

    # Happ's documented format takes every flag as a string, "true"/"false".
    return {
        "Name": "dotfiles selective",
        "GlobalProxy": "false",
        "RouteOrder": "proxy-direct-block",
        "RemoteDNSType": "DoH",
        "RemoteDNSDomain": "https://dns.google/dns-query",
        "RemoteDNSIP": "8.8.8.8",
        "DomesticDNSType": "DoU",
        "DomesticDNSDomain": "",
        "DomesticDNSIP": "1.1.1.1",
        "DnsHosts": {},
        "DirectSites": [],
        "DirectIp": PRIVATE_NETS,
        "ProxySites": [f"domain:{d}" for d in doms],
        "ProxyIp": [],
        "BlockSites": [],
        "BlockIp": [],
        "DomainStrategy": "IPIfNonMatch",
        "FakeDNS": "false",
    }


def routing_link(profile):
    raw = json.dumps(profile, separators=(",", ":")).encode()
    return "happ://routing/onadd/" + base64.b64encode(raw).decode()


def server_link(secrets_path):
    env = load_secrets(secrets_path)
    missing = [k for k in REQUIRED if not env.get(k)]
    if missing:
        sys.exit(f"missing in {secrets_path}: {', '.join(missing)}")
    # Same parameters as the sing-box outbound in config.template.json.
    query = urllib.parse.urlencode({
        "type": "tcp",
        "security": "reality",
        "flow": "xtls-rprx-vision",
        "sni": env["VLESS_SNI"],
        "pbk": env["VLESS_PBK"],
        "sid": env["VLESS_SID"],
        "fp": "chrome",
    })
    return f"vless://{env['VLESS_UUID']}@{env['VLESS_SERVER']}:{env['VLESS_PORT']}?{query}#vps"


if __name__ == "__main__":
    mode, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if mode in ("routing", "json") and len(args) == 1:
        profile = routing_profile(*args)
        print(routing_link(profile) if mode == "routing" else json.dumps(profile, indent=2))
    elif mode == "server" and len(args) == 1:
        print(server_link(args[0]))
    else:
        sys.exit(__doc__.split("\n\n")[1])
