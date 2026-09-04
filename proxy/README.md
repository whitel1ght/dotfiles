# Proxy routing (sing-box TUN)

Selective routing: a short list of domains goes through a VPS, everything else
goes straight out. The decision is made at the network layer, so **no
application is configured for a proxy** — no `HTTP_PROXY`, no `NO_PROXY`, no
per-tool setting in npm, git, or the JVM.

This document explains how that works. For the command reference, see
[Everyday operations](#everyday-operations).

## The model

`sing-box` runs as a root LaunchDaemon owning a TUN interface. macOS routes all
traffic into that interface, sing-box inspects each connection, and sends it to
one of two outbounds:

| Outbound | What goes there |
|---|---|
| `proxy` | VLESS + REALITY to the VPS — only domains listed in `proxy-domains.txt` |
| `direct` | Everything else |

Because the interception happens below the application layer, a program cannot
opt out, cannot be misconfigured, and cannot be left pointing at a proxy port
that no longer exists. That last failure mode is why this setup replaced a
`HTTP_PROXY`-based one.

**The default is direct.** An empty domain list would mean "proxy nothing" —
never "proxy everything".

## How a packet decides

Route rules are evaluated in order; the first match wins.

```
        packet enters TUN (172.19.0.1/30, gvisor stack)
                          │
                          ▼
                 1. sniff  ── read the TLS SNI / HTTP host
                          │     so later rules can match on domain, not IP
                          ▼
                 2. hijack-dns ── DNS queries are answered by sing-box
                          │        itself, never leaked to the LAN resolver
                          ▼
                 3. ip_is_private? ──yes──▶ direct   (LAN, localhost, Docker)
                          │no
                          ▼
                 4. domain in block-domains.txt? ──yes──▶ reject (connection refused)
                          │no
                          ▼
                 5. domain in proxy-domains.txt? ──yes──▶ proxy  ▶ VPS
                          │no
                          ▼
                 6. final: the "final-out" selector ──▶ direct (default)
```

Three details that matter:

- **Step 1 has to come first.** Without sniffing, sing-box only sees a
  destination IP, and a domain rule can never match. Every domain-based
  decision in this config depends on it.
- **Step 4 comes before step 5 on purpose.** First match wins, so a domain in
  both lists would be tunnelled rather than blocked if the order were
  reversed. `render.py` refuses to render an overlap at all, but the ordering
  is what makes blocking authoritative.
- **Step 5 sends matched traffic straight to `proxy`, bypassing the selector.**
  So the escape hatch below only changes what happens to *unmatched* traffic —
  the listed domains are proxied either way.

## The twin-rule invariant

This is the single most important non-obvious property of the config.

Each domain list is injected in **two** places:

- `dns.rules` — resolve these domains via DoH through the tunnel (`dns-proxy`),
  or refuse to resolve them at all if they are blocked
- `route.rules` — route these domains through the tunnel (`proxy`), or reject
  the connection if they are blocked

Everything else resolves through the system resolver (`dns-local`) and routes
direct.

**If those two lists ever diverge, you get a silent failure, not an error.** A
domain routed through the tunnel but resolved locally gets whatever answer the
local network returns — poisoned, geo-wrong, or simply the wrong CDN edge. The
tunnel then faithfully carries traffic to a bad address. Nothing logs an error;
the site is just broken in a way that looks like the proxy's fault.

The same argument applies to blocking, less dangerously but just as untidily:
a domain rejected at the route but still resolved at DNS wastes a lookup and
fails later than it should. So blocking is injected in both places too.

`render.py` exists to make that divergence impossible: every rule comes from a
single read of `proxy-domains.txt` and `block-domains.txt`. Do not hand-write
any of them.

## Exact vs suffix matching

sing-box's `domain_suffix` is a **plain string suffix match**, not a
domain-aware one. A bare `youtube.com` would also match `fake-youtube.com`.

So each entry in either list is expanded into two forms:

| Entry | Becomes | Matches |
|---|---|---|
| `youtube.com` | `domain: "youtube.com"` | the apex, exactly |
| | `domain_suffix: ".youtube.com"` | `www.`, `m.`, any subdomain |

The leading dot is what makes the suffix safe. Write apex domains only in
either list — the renderer handles both forms.

## The render pipeline

The running config is **generated**. Nothing is hand-edited in place.

```
proxy/config.template.json   ──┐
proxy/proxy-domains.txt      ──┤
proxy/block-domains.txt      ──┼──▶ render.py ──▶ sing-box check ──▶ install
~/.config/sing-box/secrets.env ┘                        │              -m 600
                                                        │           root:wheel
                                     invalid? ◀─────────┘              │
                                     nothing is installed              ▼
                                                   /usr/local/etc/sing-box/config.json
```

`render.py` refuses to produce a config when anything is off:

| Guard | Why |
|---|---|
| proxy domain list is empty | would silently route everything direct (an empty *block* list is fine — its rules are dropped instead) |
| a domain is in both lists | blocking wins on first match, silently disabling a domain the proxy list says to tunnel |
| a required secret is missing or blank | would render a structurally valid config that cannot connect |
| a `__PLACEHOLDER__` marker is missing from the template | template drifted from the renderer |
| any `__…__` remains after substitution | a value silently failed to substitute |

Then `proxyctl` runs `sing-box check` on the result and installs it **only if
it passes**, mode `600`, owned by `root:wheel`. A bad edit therefore cannot
take down a working daemon — the previous config stays in place.

Run `./proxy/render.test.sh` to test the renderer. It renders against the real
`config.template.json` with throwaway domain lists and secrets, so template and
renderer cannot drift apart unnoticed; nothing is installed and the daemon is
never touched.

## The daemon

`/Library/LaunchDaemons/local.singbox.plist`, label `local.singbox`.

- **Runs as root** because creating a TUN interface and rewriting the system
  routing table requires it.
- `RunAtLoad` + `KeepAlive` — starts at boot, restarts if it dies. Routing
  survives a reboot with no login and no user session.
- Logs to `/var/log/sing-box.log` at `warn` level with timestamps.

`proxyctl` drives it with `launchctl bootstrap` (start), `bootout` (stop) and
`kickstart -k` (restart, used by `reload`).

## The escape hatch

The `final-out` selector chooses what happens to traffic that matched no domain
rule. It is flipped **live, without restarting the daemon**, through sing-box's
Clash API on `127.0.0.1:9090`:

```bash
proxyctl all      # unmatched traffic ──▶ proxy   (everything through the VPS)
proxyctl direct   # unmatched traffic ──▶ direct  (the default)
```

Use it when a site is blocked and you don't yet know which of its domains to
add: flip everything through the VPS, get on with your work, add the proper
rule to `proxy-domains.txt` later. It resets to `direct` whenever the daemon
restarts, so it cannot silently become the permanent state.

## Everyday operations

```bash
proxyctl status     # daemon state, current default route, egress IP
proxyctl on         # render, install, start
proxyctl off        # stop
proxyctl reload     # re-render and restart — run after editing either domain list
proxyctl all        # route everything through the VPS
proxyctl direct     # back to default-direct
proxyctl logs       # tail /var/log/sing-box.log
```

**To route a new domain:** add its apex to `proxy/proxy-domains.txt`, then
`proxyctl reload`. Commit the change — the list is the routing policy, and it
belongs in git.

**To block a domain:** add its apex to `proxy/block-domains.txt`, then
`proxyctl reload`. Both lists use the same apex-plus-subdomains matching, so
one `reddit.com` line covers `old.reddit.com` and `www.reddit.com` — but not
`redd.it`, which is a separate registrable domain and needs its own line.

Blocking is enforced by the daemon, so `proxyctl off` lifts it. That is a
deliberate trade for keeping every domain decision in one versioned place; if
you want a block that survives the daemon being stopped, `/etc/hosts` is the
tool for it.

**To check where you're going out from:** `proxyctl status` prints the egress
IP. If it shows your ISP, unmatched traffic is going direct, which is correct
unless you've flipped the hatch.

## First run on a new machine

```bash
brew install sing-box
./install.sh                       # symlinks proxyctl, seeds secrets.env

# fill in the six values — see proxy/secrets.env.example for where each comes from
$EDITOR ~/.config/sing-box/secrets.env

sudo install -m 644 -o root -g wheel \
  proxy/local.singbox.plist /Library/LaunchDaemons/local.singbox.plist

proxyctl on
proxyctl status
```

`install.sh` creates `~/.config/sing-box/secrets.env` from the example at mode
`600` if it does not exist, and never overwrites one that does.

## Troubleshooting

**`daemon: stopped`** — `proxyctl logs`, or `sudo tail -50
/var/log/sing-box.log`. A config that fails `sing-box check` was never
installed, so the cause is usually environmental: a missing TUN permission, or
another process holding the interface.

**Everything goes direct, including listed domains** — confirm the domain is
actually in `proxy-domains.txt` and that you ran `proxyctl reload` after
editing — `proxyctl reload` prints the number of proxied domains it found, so
a count that didn't change means the edit didn't land.

**A listed site loads but behaves as if you're in the wrong country** — this is
the twin-rule invariant failing. Check that `render.py` produced both the DNS
and the route rule for that domain; never edit the runtime config by hand.

**Only one TUN client at a time.** Running any other TUN VPN alongside sing-box
means whichever connected last owns the default route — the other silently does
nothing. Closing the other client's *window* is not enough; its network
extension has to be disconnected.

**After upgrading the server's Xray-core, non-Xray clients stop connecting.**
Releases from v26.7.0 broke REALITY authentication for every client that isn't
Xray-core itself — sing-box included — while Xray's own client kept working.
The symptom points at the client, not the server. Pin the server to v26.6.27
and re-test a sing-box client after any upgrade.

**`proxyctl status` reports a running daemon as stopped** — it shouldn't; the
check is deliberately `sudo`-free because `sudo launchctl print` fails silently
in a non-interactive shell. If you add a status check, don't reintroduce
`sudo`.

## Deliberately absent

- **No proxy environment variables.** Not in `.zshrc`, not in `.zshrc.local`,
  not exported to any process. If you find one, it is a bug — delete it.
- **No per-tool proxy configuration.** npm, git, pip and the JVM all route
  through the TUN like everything else. `strict-ssl=false` and
  `-Dhttp.proxyHost=…` style settings are proxy-era residue.
- **No secrets in this repository.** They live in
  `~/.config/sing-box/secrets.env`, mode `600`, outside any git working tree.
