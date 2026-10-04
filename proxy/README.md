# Proxy routing (sing-box TUN)

Everything goes through a VPS except a short list of domains that go straight
out. The decision is made at the network layer, so **no application is
configured for a proxy** — no `HTTP_PROXY`, no `NO_PROXY`, no per-tool setting
in npm, git, or the JVM.

This document explains how that works. For the command reference, see
[Everyday operations](#everyday-operations).

## The model

`sing-box` runs as a root LaunchDaemon owning a TUN interface. macOS routes all
traffic into that interface, sing-box inspects each connection, and sends it to
one of two outbounds:

| Outbound | What goes there |
|---|---|
| `proxy` | VLESS + REALITY to the VPS — **everything not listed below** |
| `direct` | domains in `direct-domains.txt`, plus private and LAN addresses |

Because the interception happens below the application layer, a program cannot
opt out, cannot be misconfigured, and cannot be left pointing at a proxy port
that no longer exists. That last failure mode is why this setup replaced a
`HTTP_PROXY`-based one.

**The default is the VPS.** An empty domain list would mean "proxy everything"
— never "proxy nothing". A list that is empty by accident costs bandwidth and
latency, not exposure, and that is the direction the mistake should point.

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
                 4. reader-domains.txt AND process is newsboat?
                          │              └──yes──▶ proxy (reaching a blocked site)
                          │no
                          ▼
                 5. domain in block-domains.txt? ──yes──▶ reject (connection refused)
                          │no
                          ▼
                 6. domain in direct-domains.txt? ──yes──▶ direct
                          │no
                          ▼
                 7. final: proxy  ▶ VPS   (the default)
```

Five details that matter:

- **Step 1 has to come first.** Without sniffing, sing-box only sees a
  destination IP, and a domain rule can never match. Every domain-based
  decision in this config depends on it.
- **Step 3 is the only direct decision that is not a domain.** LAN addresses,
  localhost, Docker and link-local have to stay off the VPS — a printer or a
  captive portal is not reachable through a datacenter in another country. It
  matches on the destination address, so it needs no list entry.
- **Step 4 comes before step 5 on purpose.** The exception has to be reachable
  before the block it is an exception to. It is narrow by construction: it
  matches on process name, so the domain stays rejected for a browser and
  every other process. Its outbound is `proxy` — the same as the default —
  because what it buys is reaching a blocked domain at all, in one program.
  Nothing uses it right now: `reader-domains.txt` is empty and the renderer
  drops step 4 entirely.
- **Step 5 comes before step 6 on purpose.** First match wins, so a domain in
  both lists would go direct rather than be blocked if the order were
  reversed. `render.py` refuses to render an overlap at all, but the ordering
  is what makes blocking authoritative.
- **Step 7 is the default, and it is not switchable.** There is no selector
  outbound and no Clash API — see [When you need everything
  direct](#when-you-need-everything-direct).

## The twin-rule invariant

This is the single most important non-obvious property of the config.

Each domain list is injected in **two** places:

- `dns.rules` — resolve these domains with the system resolver (`dns-local`),
  or refuse to resolve them at all if they are blocked
- `route.rules` — route these domains direct (`direct`), or reject the
  connection if they are blocked

Everything else resolves over DoH through the tunnel (`dns-proxy`) and routes
through the tunnel (`proxy`).

**If those two lists ever diverge, you get a silent failure, not an error.** A
domain routed direct but resolved through the tunnel gets an answer chosen for
the VPS's location and then connects from your ISP's — the wrong CDN edge, or a
geo-block that makes no sense. A domain routed through the tunnel but resolved
locally gets whatever the local network returns — poisoned or geo-wrong — and
the tunnel faithfully carries traffic to a bad address. Nothing logs an error;
the site is just broken in a way that looks like the proxy's fault.

The same argument applies to blocking, less dangerously but just as untidily:
a domain rejected at the route but still resolved at DNS wastes a lookup and
fails later than it should. So blocking is injected in both places too.

`render.py` exists to make that divergence impossible: every rule comes from a
single read of `direct-domains.txt` and `block-domains.txt`. Do not hand-write
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

An entry may also be a bare TLD. `direct-domains.txt` uses `ru`, `by` and `su`
to keep those countries' sites off the VPS, and that expands to
`domain_suffix: ".ru"` — every `.ru` host. It is a wide brush: it covers a
`.ru` site you did want tunnelled. Delete the line, or list the exception,
rather than living with it.

## The render pipeline

The running config is **generated**. Nothing is hand-edited in place.

```
proxy/config.template.json   ──┐
proxy/direct-domains.txt     ──┤
proxy/block-domains.txt      ──┤
proxy/reader-domains.txt     ──┼──▶ render.py ──▶ sing-box check ──▶ install
~/.config/sing-box/secrets.env ┘                        │              -m 600
                                                        │           root:wheel
                                     invalid? ◀─────────┘              │
                                     nothing is installed              ▼
                                                   /usr/local/etc/sing-box/config.json
```

`render.py` refuses to produce a config when anything is off:

| Guard | Why |
|---|---|
| a domain is in both `direct-domains.txt` and `block-domains.txt` | blocking wins on first match, silently disabling a direct entry |
| a reader domain is not blocked | the exception excepts nothing, so the entry does nothing at all |
| a required secret is missing or blank | would render a structurally valid config that cannot connect |
| a `__PLACEHOLDER__` marker is missing from the template | template drifted from the renderer |
| the template contains an unknown `__…__` | a leftover marker would be installed as a literal value |

An empty list is **not** a guard. An empty `direct-domains.txt` means everything
is proxied, which is a legitimate thing to want, so the renderer drops the rule
rather than emit `"domain": []` — which matches nothing but reads as though
direct routing were configured. The same goes for an empty blocklist and an
empty reader list.

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

## When you need everything direct

There is no runtime switch. The setup used to have one — a `final-out`
selector, flipped live through sing-box's Clash API on `127.0.0.1:9090` — and
it existed to send everything through the VPS when a site was blocked and you
didn't know which of its domains to list. That is now the default, so the
switch lost its purpose, and with it went the Clash API: the only thing in this
setup that accepted unauthenticated local connections.

What replaces it is `proxyctl off`. Stopping the daemon hands routing back to
macOS, so everything goes direct immediately — the same escape, without a
second routing path to reason about:

```bash
proxyctl off     # everything direct, right now
proxyctl on      # back through the VPS
```

If you want the *default itself* to be direct — a policy change, not an escape
hatch — edit `route.final` and `dns.final` in `proxy/config.template.json` to
`direct` and `dns-local`, then `proxyctl reload`. That is a change to the
policy, so it belongs in git like any other.

## Everyday operations

```bash
proxyctl status     # daemon state, egress IP
proxyctl on         # render, install, start
proxyctl off        # stop — routing falls back to macOS
proxyctl reload     # re-render and restart — run after editing any domain list
proxyctl logs       # tail /var/log/sing-box.log
proxyctl happ       # routing-profile QR for the phone
```

**To keep a site off the VPS:** add its apex to `proxy/direct-domains.txt`,
then `proxyctl reload`. Commit the change — the list is the routing policy, and
it belongs in git. A site belongs there when it refuses datacenter IPs,
geo-fences its content, or simply needs the address your ISP gave you.

**To route a site through the VPS:** it already is. Nothing to do, unless a
broader entry in `direct-domains.txt` covers it — a bare TLD such as `ru` will
swallow a `.ru` host you wanted tunnelled.

**To make a blocked site readable in newsboat only:** add its apex to
`proxy/reader-domains.txt` as well as `block-domains.txt`, then `proxyctl
reload`. The exception matches on process name, so the site loads in the feed
reader and stays refused everywhere else — including when newsboat's `o` key
tries to hand a link to the browser. That failure is the feature.

`reader-domains.txt` is currently empty, so the renderer drops those rules
altogether and the mechanism is inert — it re-engages the moment a domain goes
back in. Note the shape of the trade before adding an entry: this mechanism
buys a strict block at the cost of exactly one program being able to reach the
site.

**To block a domain:** add its apex to `proxy/block-domains.txt`, then
`proxyctl reload`. Both lists use the same apex-plus-subdomains matching, so
one `linkedin.com` line covers `www.linkedin.com` and `api.linkedin.com` — but
a separate registrable domain needs its own line, the way `redd.it` would not
have been covered by a `reddit.com` entry. Blocking is evaluated before the
direct list, so a block still holds inside a broad direct entry: `onliner.by`
is blocked even though `by` is direct.

Blocking is enforced by the daemon, so `proxyctl off` lifts it. That is a
deliberate trade for keeping every domain decision in one versioned place; if
you want a block that survives the daemon being stopped, `/etc/hosts` is the
tool for it.

**To check where you're going out from:** `proxyctl status` prints the egress
IP. It probes a domain that is not in `direct-domains.txt`, so it should show
the VPS. If it shows your ISP, either the daemon is stopped or a broad direct
entry covers the probe.

## iPhone (Happ)

The phone runs [Happ](https://www.happ.su) with the same split: only
`direct-domains.txt` stays off the VPS, and everything else goes through it. The
phone blocks nothing: `block-domains.txt` and `reader-domains.txt` are Mac-only.
`render-happ.py` builds Happ's routing profile from that same list, so there is one
list to edit for both devices.

| Step | Command |
|---|---|
| First time only: add the VPS to Happ | `proxyctl happ server`, scan, open in Happ |
| Install or update the routing profile | `proxyctl happ`, scan, open in Happ |

Each command opens a QR code in Preview (made with `qrencode`; the image is
deleted two minutes later) that the iPhone camera opens as a `vless://` or
`happ://routing/onadd/...` link. The code is too big for a terminal window;
`--terminal` prints it there anyway. After editing the domain list, run
`proxyctl reload` for the Mac and `proxyctl happ` again for the phone.

Two more things differ from the Mac:

- Domains are written `domain:<apex>`, Xray's apex-plus-subdomains match; a bare
  entry would be a substring match.
- The server QR carries the VPS credentials. Show it only to the phone, and don't
  screenshot it.

## Other VPNs alongside (DuploCloud)

The tun inbound's `route_exclude_address` hands address ranges back to macOS, so another
VPN can carry them while sing-box keeps everything else. It lists the ECFX dev01 AWS
network (`10.221.0.0/16`, where the DuploCloud RDS databases live) and the DuploCloud VPN
server itself (`54.213.49.194`). Without it, `strict_route` pulls the dev01 range into the
tun, and the `ip_is_private` rule sends it out "direct" over Wi-Fi, where a private AWS
address is unreachable. With it, the DuploCloud VPN (OpenVPN) works while `proxyctl on`
stays on; `nc -vz <rds-endpoint> 5432` checks the path. Another network behind a VPN goes
in the same list.

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

**Everything goes direct** — check `proxyctl status` first. With the daemon
stopped, macOS routes everything itself and that looks exactly like a working
direct-only config.

**A site behaves as if you're in the wrong country, or refuses datacenter
IPs** — it is going through the VPS and the site doesn't want that. Add its
apex to `proxy/direct-domains.txt` and `proxyctl reload`.

**A `.ru`, `.by` or `.su` site you wanted tunnelled isn't** — the TLD line in
`direct-domains.txt` covers every host under it. Delete that line if the whole
TLD shouldn't be direct.

**A site in `direct-domains.txt` still misbehaves** — this is the twin-rule
invariant failing: the domain got a route rule but not a DNS rule, or the
reverse, so it connects from one place with an answer from another. Check that
`render.py` produced both rules for that domain; never edit the runtime config
by hand.

**`proxyctl reload` didn't change anything** — it prints the direct and blocked
counts it rendered. A count that didn't move means the edit didn't land: check
for a typo, a leading `#`, or an entry that went into the other list.

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
- **No runtime routing switch.** No selector outbound, no Clash API, no local
  port that can flip the policy. `proxyctl off` is the escape hatch.
- **No secrets in this repository.** They live in
  `~/.config/sing-box/secrets.env`, mode `600`, outside any git working tree.
