---
name: supply-chain-ioc-check
description: >-
  Read-only sweep of the local machine for indicators of compromise from the May 2026 TanStack / Mini Shai-Hulud npm supply chain attack (and related cascades). Use when checking if a workstation or CI runner was compromised, when responding to npm supply chain advisories, when user mentions Shai-Hulud, tanstack compromise, gh-token-monitor, git-tanstack.com, getsession.org, or wants to verify a host before rotating credentials.
---


# Supply Chain IOC Check — TanStack / Mini Shai-Hulud (May 2026)

## ⚠️ READ THIS FIRST — Dead-man wiper

The malware installs a `gh-token-monitor` daemon that runs `rm -rf ~/` if it sees a 40X (token revoked) response from GitHub.

**Run this skill before any token revocation, package removal, or destructive action.** Treat every step in this skill as observation-only — never delete, kill, or revoke anything from within this skill. If IOCs are found, report findings and stop. Remediation must be planned separately with the user.

If a `gh-token-monitor` artifact is found on the host:
1. Do NOT revoke tokens yet.
2. Do NOT delete the persistence file yet (you'll lose forensic state).
3. Stop and report. The user needs to isolate the host first (network off, OR move to a fresh machine to do the rotation) before any revocation hits GitHub.

## When to run

- A new npm supply chain advisory drops and you want to know if this machine pulled anything bad.
- Before rotating org-wide credentials (verify the host doing the rotation is clean).
- Investigating unexpected `npm install` / `pnpm install` activity.
- User asks: "am I compromised?", "check this machine for IOCs", "did I get hit by the tanstack thing?"

## What this skill checks

Across all platforms, in this order:

1. **Persistence** — launchd / systemd / scheduled tasks named `gh-token-monitor`.
2. **Running processes** — IOC names and the bun runtime (the malware uses Bun v1.3.13).
3. **Active network connections** — to `83.142.209.194`, `*.getsession.org`, `git-tanstack.com`.
4. **Filesystem artifacts** — `router_init.js`, `router_runtime.js`, `tanstack_runner.js`, `opensearch_init.js`, `setup.mjs` (with size hint), `gh-token-monitor*`.
5. **npm/pnpm state** — `~/.npmrc` content (redacted), `npm whoami` login state, `~/.npm/_logs/` for installs during the compromise window, pnpm/yarn store contents.
6. **Shell history** — IOC strings, suspicious `npm/pnpm/bun/npx` invocations.
7. **Git histories** — orphan payload commit `79ac49eedf774dd4...`, commit messages with `IfYouRevokeThis`/`Shai-Hulud`.
8. **Project manifests** — `package.json` / lockfile grep across local repos for compromised namespaces.
9. **IDE caches** — `~/.claude/`, `~/.vscode/` (compromised packages drop runtime files here).

## Compromise window

**Primary window:** 2026-05-11 19:20 UTC → 2026-05-12 11:00 UTC.
Any `npm install` / `pnpm install` of an affected package during this window resolves to a malicious version. Installs before or after that window get the legit version (npm pulled the bad tarballs at disclosure).

## Process — macOS / Linux

Run these blocks one at a time and **read the output before continuing**. If any single block reports a hit, stop and report to the user.

### Step 0 — Identify the OS

```bash
echo "OS: $(uname -s)  Kernel: $(uname -r)  User: $(whoami)  Home: $HOME"
```

If `uname -s` is `Darwin`, use the macOS persistence checks. If `Linux`, use the Linux ones. Both share the rest.

### Step 1 — Persistence

**macOS:**
```bash
echo "--- LaunchAgents ---"
ls -la ~/Library/LaunchAgents/com.user.gh-token-monitor.plist 2>/dev/null || echo "  primary IOC plist: not present"
ls -la ~/Library/LaunchAgents/ 2>/dev/null
ls -la /Library/LaunchAgents/ 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  /Library/LaunchAgents: no matches"
ls -la /Library/LaunchDaemons/ 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  /Library/LaunchDaemons: no matches"
echo "--- launchctl ---"
launchctl list 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  launchctl: no matches"
```

**Linux:**
```bash
echo "--- systemd user units ---"
ls -la ~/.config/systemd/user/gh-token-monitor.service 2>/dev/null || echo "  user service: not present"
systemctl --user list-units --no-pager 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  --user units: no matches"
echo "--- systemd system units ---"
systemctl list-units --no-pager 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  system units: no matches"
echo "--- cron / at ---"
crontab -l 2>/dev/null | grep -iE "gh-token|tanstack|setup\.mjs|router_init" || echo "  user crontab: no matches"
ls -la /etc/cron.d/ /etc/cron.hourly/ /etc/cron.daily/ 2>/dev/null | grep -iE "gh-token|tanstack" || echo "  /etc/cron.*: no matches"
```

### Step 2 — Processes

```bash
ps aux 2>/dev/null | grep -iE "gh-token-monitor|router_init|tanstack_runner|opensearch_init|setup\.mjs" | grep -v grep || echo "  no matching processes"
which bun 2>/dev/null && echo "  WARNING: bun installed — verify version (malware used 1.3.13)" || echo "  bun not installed"
```

### Step 3 — Active network connections

```bash
# macOS / BSD
netstat -an 2>/dev/null | grep -E "83\.142\.209\.194" || echo "  no active connection to 83.142.209.194"
# Open sockets to known C2 endpoints
( command -v lsof >/dev/null && lsof -i -n 2>/dev/null | grep -iE "getsession|git-tanstack|83\.142\.209" ) || echo "  lsof: no matching open sockets"
# DNS cache (best-effort, macOS — needs sudo for cachedump)
if [ "$(uname -s)" = "Darwin" ]; then
  sudo -n true 2>/dev/null && (dscacheutil -cachedump -entries Host 2>/dev/null | grep -iE "getsession|git-tanstack") || echo "  DNS cache: skipped (sudo required)"
fi
```

### Step 4 — Filesystem IOC files

```bash
echo "--- IOC filename sweep (skipping node_modules, Trash, system Caches) ---"
find "$HOME" \
  \( -path "*/node_modules/*" -o -path "*/Trash/*" -o -path "*/.Trash/*" -o -path "*/Library/Caches/*" \) -prune -o \
  -type f \( -name "router_init.js" -o -name "router_runtime.js" -o -name "tanstack_runner.js" -o -name "opensearch_init.js" -o -name "gh-token-monitor*" -o -name "vite_setup.mjs" \) -print 2>/dev/null

echo "--- setup.mjs (legitimate files exist; the IOC is exactly 5047 bytes for the @uipath variant) ---"
find "$HOME" \
  \( -path "*/node_modules/*" -o -path "*/Trash/*" -o -path "*/.Trash/*" \) -prune -o \
  -type f -name "setup.mjs" -print 2>/dev/null | head -50
```

If any `router_init.js` is found, compute its SHA-256:
```bash
shasum -a 256 <path>   # macOS
sha256sum <path>       # Linux
```
Compare to:
- `ab4fcadaec49c03278063dd269ea5eef82d24f2124a8e15d7b90f2fa8601266c`
- `2ec78d556d696e208927cc503d48e4b5eb56b31abc2870c2ed2e98d6be27fc96`

### Step 5 — IDE caches

```bash
ls -la ~/.claude 2>/dev/null && find ~/.claude -type f \( -name "router_init.js" -o -name "router_runtime.js" -o -name "tanstack_runner.js" -o -name "setup.mjs" -o -name "gh-token-monitor*" \) 2>/dev/null
ls -la ~/.vscode 2>/dev/null && find ~/.vscode -type f \( -name "router_init.js" -o -name "router_runtime.js" -o -name "tanstack_runner.js" -o -name "setup.mjs" -o -name "gh-token-monitor*" \) 2>/dev/null
```

### Step 6 — npm / pnpm / yarn state

```bash
echo "--- ~/.npmrc (sensitive — redacting tokens) ---"
[ -f ~/.npmrc ] && grep -v "^#" ~/.npmrc | sed -E 's/(_authToken|_password)=.*/\1=<REDACTED>/g' || echo "  no ~/.npmrc"

echo "--- npm whoami ---"
( command -v npm >/dev/null && npm whoami 2>&1 ) || echo "  npm not installed"

echo "--- npm install logs during compromise window ---"
ls -lat ~/.npm/_logs/ 2>/dev/null | head -20
# Same pattern file as Step 9
grep -lFf /tmp/scan_regex.txt ~/.npm/_logs/*.log 2>/dev/null || echo "  npm logs: no compromised package references"

echo "--- pnpm store ---"
ls -la ~/.pnpm-store 2>/dev/null | head -5 || echo "  no ~/.pnpm-store"
find ~/.pnpm-store -type f \( -name "router_init.js" -o -name "setup.mjs" -o -name "opensearch_init.js" -o -name "router_runtime.js" \) 2>/dev/null || true

echo "--- yarn cache ---"
ls -la ~/.cache/yarn 2>/dev/null | head -5 || ls -la ~/Library/Caches/Yarn 2>/dev/null | head -5 || echo "  no yarn cache"
```

### Step 7 — Shell history IOC strings

```bash
grep -hiE "router_init\.js|setup\.mjs|gh-token-monitor|git-tanstack\.com|getsession\.org|83\.142\.209\.194|tanstack_runner|opensearch_init|79ac49eedf774dd4|zblgg|voicproducoes|Shai-Hulud" \
  ~/.zsh_history ~/.bash_history ~/.history 2>/dev/null || echo "  shell history: no IOC strings"
```

### Step 8 — Git history sweep

```bash
# Pick directories to scan — adjust based on where the user keeps repos
SCAN_DIRS=("$HOME/gitlab" "$HOME/github" "$HOME/src" "$HOME/Projects" "$HOME/Code" "$HOME/dev" "$HOME/workspace")
for d in "${SCAN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 5 -name ".git" -type d 2>/dev/null | while read gitdir; do
    repo=$(dirname "$gitdir")
    if git -C "$repo" cat-file -e 79ac49eedf774dd4b0cfa308722bc463cfe5885c 2>/dev/null; then
      echo "  WARNING: orphan payload commit present in $repo"
    fi
    hit=$(git -C "$repo" log --all --grep="IfYouRevokeThis" --grep="Shai-Hulud" --oneline 2>/dev/null)
    [ -n "$hit" ] && echo "  WARNING: suspicious commit message in $repo: $hit"
  done
done
echo "  (git history scan complete)"
```

### Step 9 — Project manifest sweep

The compromised list spans 172 packages across 15 npm scopes plus 12 unscoped names. Build a pattern file with all 172 names quoted (the canonical list lives at `tanstack-compromised-packages.md`):

```bash
# Build /tmp/scan_regex.txt — one fixed-string pattern per line, double-quote-anchored.
# For namespaces where ALL packages are malicious, use the scope prefix with trailing /:
#   "@uipath/      ← matches every @uipath/* package
#   "@squawk/      ← matches every @squawk/* package
# For mixed scopes, list each compromised package explicitly:
#   "@tanstack/router-core"
#   "@tanstack/virtual-file-routes"   ← do NOT use @tanstack/virtual* — that's the clean family
# See tanstack-compromised-packages.md for the full list.

SCAN_DIRS=("$HOME/gitlab" "$HOME/github" "$HOME/src" "$HOME/Projects" "$HOME/Code" "$HOME/dev" "$HOME/workspace" "$HOME/Desktop" "$HOME/Documents")
for d in "${SCAN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  echo "Scanning $d ..."
  find "$d" -type f \( -name "package.json" -o -name "package-lock.json" -o -name "pnpm-lock.yaml" -o -name "yarn.lock" \) \
    -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" 2>/dev/null \
    | xargs -I{} grep -lFf /tmp/scan_regex.txt {} 2>/dev/null
done
echo "  (manifest scan complete — empty output above = no hits)"
```

**Critical traps to remember when building the pattern file:**

- `@tanstack/virtual` (the scrolling library) is **clean**, but `@tanstack/virtual-file-routes` is **compromised**. Never use a `@tanstack/virtual*` wildcard.
- `@tanstack/start` (the meta-package only) is **clean**, but `@tanstack/start-server-core`, `@tanstack/start-client-core`, `@tanstack/start-plugin-core`, `@tanstack/start-fn-stubs`, `@tanstack/start-storage-context`, `@tanstack/start-static-server-functions` are all **compromised**.
- TanStack-confirmed clean families: `@tanstack/query*`, `@tanstack/table*`, `@tanstack/form*`, `@tanstack/store`. List the specific compromised `@tanstack/*` packages individually rather than using a broad `@tanstack/*` wildcard, or you'll get false positives on these.
- `@opensearch-project` — only `@opensearch-project/opensearch` is compromised, not the whole scope.
- `@beproduct` — only `@beproduct/nestjs-auth` is compromised.
- `@dirigible-ai` — only `@dirigible-ai/sdk`.
- `@taskflow-corp` — only `@taskflow-corp/cli`.
- `@tolka` — only `@tolka/cli`.

## Process — Windows

Run from an elevated PowerShell only if comfortable; non-elevated still catches user-level persistence.

### Step 1 — Persistence (Windows)

```powershell
Write-Host "--- Scheduled tasks ---"
Get-ScheduledTask 2>$null | Where-Object { $_.TaskName -match "gh-token-monitor|tanstack" } | Format-Table -AutoSize
Write-Host "--- Run keys ---"
Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -ErrorAction SilentlyContinue | Out-String | Select-String -Pattern "gh-token-monitor|tanstack|setup\.mjs"
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Run -ErrorAction SilentlyContinue | Out-String | Select-String -Pattern "gh-token-monitor|tanstack|setup\.mjs"
Write-Host "--- Startup folders ---"
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue
Write-Host "--- Services ---"
Get-Service 2>$null | Where-Object { $_.Name -match "gh-token-monitor|tanstack" } | Format-Table -AutoSize
```

### Step 2 — Processes

```powershell
Get-Process 2>$null | Where-Object { $_.Name -match "gh-token-monitor|setup|router_init|bun" } | Format-Table Name,Id,Path -AutoSize
```

### Step 3 — Network connections

```powershell
Get-NetTCPConnection -State Established 2>$null | Where-Object { $_.RemoteAddress -eq "83.142.209.194" } | Format-Table -AutoSize
Resolve-DnsName git-tanstack.com -ErrorAction SilentlyContinue
Resolve-DnsName filev2.getsession.org -ErrorAction SilentlyContinue
```

### Step 4 — Filesystem IOC files

```powershell
$names = @("router_init.js","router_runtime.js","tanstack_runner.js","opensearch_init.js","gh-token-monitor*","vite_setup.mjs")
foreach ($n in $names) {
  Get-ChildItem -Path $env:USERPROFILE -Recurse -Filter $n -ErrorAction SilentlyContinue -Force `
    | Where-Object { $_.FullName -notmatch "node_modules|Recycle|Trash" } `
    | Select-Object FullName, Length, LastWriteTime
}
Get-ChildItem -Path $env:USERPROFILE -Recurse -Filter "setup.mjs" -ErrorAction SilentlyContinue -Force `
  | Where-Object { $_.FullName -notmatch "node_modules" } `
  | Where-Object { $_.Length -eq 5047 } `
  | Select-Object FullName, Length
```

### Step 5 — npm state

```powershell
$npmrc = Join-Path $env:USERPROFILE ".npmrc"
if (Test-Path $npmrc) {
  Get-Content $npmrc | Where-Object { $_ -notmatch "^#" } | ForEach-Object { $_ -replace "(_authToken|_password)=.*", '$1=<REDACTED>' }
} else { "no ~/.npmrc" }
npm whoami 2>&1
$logs = Join-Path $env:APPDATA "npm-cache\_logs"
if (Test-Path $logs) {
  Get-ChildItem $logs | Sort-Object LastWriteTime -Descending | Select-Object -First 20
  Select-String -Path "$logs\*.log" -Pattern "@tanstack/(router|history|start-|react-start|solid-start|vue-start)|@uipath/|@mistralai/mistralai|@opensearch-project/opensearch|guardrails-ai" -ErrorAction SilentlyContinue
}
```

### Step 6 — IDE caches (Windows)

```powershell
Get-ChildItem "$env:USERPROFILE\.claude" -Recurse -ErrorAction SilentlyContinue -Include "router_init.js","router_runtime.js","tanstack_runner.js","setup.mjs","gh-token-monitor*"
Get-ChildItem "$env:USERPROFILE\.vscode" -Recurse -ErrorAction SilentlyContinue -Include "router_init.js","router_runtime.js","tanstack_runner.js","setup.mjs","gh-token-monitor*"
```

## Interpreting results

Report a single-pane summary like this:

```
Supply Chain IOC Sweep — <hostname> — <date>

Persistence (launchd/systemd/scheduled task):  CLEAN  |  HIT (<artifact>)
Running processes:                              CLEAN  |  HIT
Active network to known C2:                     CLEAN  |  HIT
Filesystem IOC files (router_init.js etc.):     CLEAN  |  HIT
IDE caches (~/.claude, ~/.vscode):              CLEAN  |  HIT
npm/pnpm state and install logs in window:      CLEAN  |  HIT
Shell history IOC strings:                      CLEAN  |  HIT
Git histories (orphan commit / messages):       CLEAN  |  HIT
Project manifests (compromised namespaces):     CLEAN  |  HIT (<file>:<line>)

Verdict: <NO INDICATORS FOUND | INDICATORS FOUND — DO NOT REVOKE TOKENS YET>
```

If **any** category shows a HIT:
- Stop. Do not delete artifacts, do not revoke tokens.
- Capture exact paths, file sizes, hashes, and process IDs.
- Recommend the user isolate the host (disconnect from network) and rotate credentials **from a separate, known-clean machine**.
- Suggest preserving the persistence file for forensics before any cleanup.

## What this skill does NOT do

- **No remediation.** No file deletion, no service stop, no token revocation, no package upgrade. Read-only.
- **No cloud-side audit.** CloudTrail / GCP audit / GitHub Audit Log review must be done separately — the skill can't authenticate to those services. Suggested queries are in the incident notes (`tanstack-incident-2026-05-11.md` in this repo).
- **No CI-runner introspection.** The runners are the highest-value target (OIDC tokens, IAM, Vault), but they're not the local host. Run this skill on the runner OS directly via your CI executor, or capture an image of the runner filesystem and run offline.
- **No network capture.** Detects active connections only. For historical egress, query proxy/DNS logs separately for `git-tanstack.com`, `*.getsession.org`, `83.142.209.194`.

## Updating this skill for future supply chain events

The framework (persistence + processes + network + filesystem + manifests + history) is generic. To adapt for a new event:

1. Update the **IOC table** at the top of the SKILL.md (filenames, hashes, C2 endpoints, attacker identifiers, commit hashes).
2. Update the **compromised namespace regex** in Step 9 / Step 5 / npm log grep.
3. Update the **compromise window** timestamps.
4. Update the **confirmed-clean families** note.

The shell logic doesn't need to change — only the IOC values do.

## References

- Snyk advisory: https://security.snyk.io/TanStack-npm-Supply-Chain-Compromise-May-2026
- TanStack post-mortem: https://tanstack.com/blog/npm-supply-chain-compromise-postmortem
- Wiz detection guidance: https://www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised
