# Home link: SSH to the ThinkPad from anywhere

One reverse tunnel, nothing else: the ThinkPad holds `ssh -N -R
127.0.0.1:12222:127.0.0.1:22` open to the VPS (systemd unit
`thinkpad/home-link.service`, riding the sing-box VLESS tunnel via
`Requires=sing-box.service`). From the Mac, `ssh thinkpad-away` ProxyJumps
through the VPS into that loopback port:

```sshconfig
Host vps-jump
  HostName 38.180.151.160
  Port 10001
  User whitelight
Host thinkpad-away
  HostName 127.0.0.1
  Port 12222
  User dmitry
  ProxyJump vps-jump
  HostKeyAlias dmitry-thinkpad-t480.local
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

Apply: on the VPS run `vps/setup-homelink.sh` as whitelight; on the ThinkPad
install `~/.ssh/known_hosts_homelink` (the pinned VPS host key) and
`sudo install -m 644 thinkpad/home-link.service /etc/systemd/system/ &&
sudo systemctl daemon-reload && sudo systemctl enable --now home-link`.

**No-root deviation:** we have no root on the VPS (no sudo, PermitRootLogin
no, fail2ban active), so there is no dedicated tunnel user. Instead the
homelink key gets one restricted `authorized_keys` line under whitelight:
forced `/bin/false`, `restrict`, and `permitlisten` limited to
127.0.0.1:12222 — the key can open the tunnel port and nothing else. The
Mac's own key is a separate, unrestricted line, which is what lets it ask the
laptop's sshd for `-L` forwards through the same link.

## Forwarding a laptop service to the Mac

The link carries any `-L` forward, not just shells. `bin/qbit-tunnel`
(LaunchAgent `local.qbit-tunnel`) holds 127.0.0.1:8090 open to the ThinkPad's
qBittorrent Web UI, and `localsites/Caddyfile` serves it as
http://qbit.localhost. It picks `thinkpad` on the LAN and `thinkpad-away`
otherwise once per start, and launchd restarts it either way. Copy that shape
for another service: a free local port, a `*.localhost` name, and a
`bin/<name>-tunnel` + `launchd/<name>-tunnel.plist` pair wired into install.sh.

Two gotchas found building it: a service that validates the `Host` header
(qBittorrent does, the port included) accepts the name only because Caddy sits
on :80 and the browser then sends no port — a raw `curl 127.0.0.1:8090` gets
401; and the link exists only while the ThinkPad is awake, since WiFi WoL does
not wake it.

Full walkthrough — every hop, the restricted-key fields, the failure-mode
table and the checks that were actually run: `~/wiki/work/system/home-link.md`.
