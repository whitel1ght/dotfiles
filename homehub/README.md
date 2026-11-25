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
127.0.0.1:12222 — the key can open the tunnel port and nothing else.
