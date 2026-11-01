# Ubuntu host setup

This branch combines portable configuration from macOS `main` with the Ubuntu
laptop's i3 desktop, Ghostty settings, and systemd-based sing-box proxy. It does
not install or enable system packages/services as a side effect of linking
configuration.

## 1. Check versions and dependencies

```bash
./ubuntu/check-dependencies.sh
```

Full parity expects Neovim >= 0.11, tmux >= 3.5, fzf >= 0.48, `fd` (Ubuntu
ships it as `fdfind`), `bat` (Ubuntu may ship `batcat`), and `keyd` for the
Caps Lock remap. This check reports too-old distribution packages rather than
changing them. The review host had Neovim 0.12.6, tmux 3.4 and fzf 0.44.1, so it
needs newer tmux/fzf for every upstream feature.

The package lists are **review aids, not blindly installable lockfiles**:

- `packages-core.txt`: shell, Git, editor and interactive CLI tools.
- `packages-desktop.txt`: optional i3/session/keyboard packages.
- `packages-work.txt`: optional reader and development tools.

Check package availability and candidates first (`apt-cache policy <package>`).
Ubuntu 24.04 repositories may not meet the required tmux/fzf/Neovim versions.
The helper below pins verified upstream releases for tmux/fzf and a source tag
for keyd rather than replacing distro packages or adding an unreviewed apt
repository. Do not replace a working NVM, Rust, Go, Ruby or project SDK
installation without checking existing versions. Node 24 is used by the Pi
TypeScript tests. A Nerd Font is needed for Powerlevel10k icons; install one for
the user only if wanted.

### Install the known missing dependencies

Preview first (this is the default; it performs no downloads or changes):

```bash
./ubuntu/install-missing.sh
```

Then, when ready, install the pinned tmux 3.5a and fzf 0.61.3 under
`~/.local/opt/dotfiles-toolchain`, put symlinks in `~/.local/bin`, install
`bat`/`fd-find` (and create compatibility links if needed), build/install keyd
v2.6.0, and install only the
pinned `pi-subagents@0.76.0` package:

```bash
./ubuntu/install-missing.sh --apply
```

The script uses `sudo` only for apt dependencies and keyd's system files. It
leaves distro tmux/fzf packages installed, does not enable keyd, and does not
refresh unrelated Pi packages. Installing the Pi package intentionally updates
the user's Pi package settings; authentication and session files are untouched.
Review the pinned versions and script diff before applying.

Only after identifying the internal keyboard with `sudo keyd monitor`, activate
the mapping separately with the exact verified device ID:

```bash
./ubuntu/install-missing.sh --apply --configure-keyboard --device-id 1234:abcd
```

The script checks that the ID exists as a keyboard in sysfs and requires typing
`APPLY 1234:abcd` interactively. It installs a device-specific Caps Lock → grave
rule, validates all keyd configs, and then enables/restarts keyd. Never pass a
wildcard. If declining to configure the mapping, keyd remains installed but
inactive; Caps Lock is not remapped.

If the Pi CLI is intentionally absent, `--skip-pi` skips the package installation.
The updater never installs provider credentials, downloads local models, changes
the sing-box proxy, links dotfiles, or refreshes all Pi packages.

## 2. Link configuration safely

For preview only:

```bash
DRY_RUN=1 DOTFILES_LINKS_ONLY=1 ./install.sh
```

For configuration links and inert local templates only:

```bash
DOTFILES_LINKS_ONLY=1 ./install.sh
```

`install.sh` backs up real files without overwriting prior backups, repairs only
symlinks that resolve into this checkout, and leaves foreign symlinks intact.
It links i3, Ghostty, tmux, Neovim, Git, Zsh, per-item Pi configuration, Claude
instructions/commands, and selected optional app configs. Existing Pi auth and
session state, Claude settings/hooks, application databases, and reader state
are not replaced.

Templates are copied only when the target is absent; seeded secrets are mode
600 and Git identity mode 644. Examples are commented out. Fill in only the
values you need in `~/.zshrc.local`, `~/.gitconfig.local`,
`~/.config/mrglass/secrets.env`, and `~/.config/sing-box/secrets.env`. Never
commit those real files or put proxy environment variables in them.

A normal `./install.sh` also only links/seeds by default. Optional behavior is
opt-in:

| Variable | Effect when set to `1` |
|---|---|
| `ZSH_SETUP` | Network install of Oh My Zsh, Powerlevel10k and plugins |
| `TMUX_SETUP` | Clone TPM only; plugin installation is manual in an isolated server |
| `REPY_SETUP` | Build the pinned repy release with installed Cargo |
| `SDKMAN_SETUP` | Run SDKMAN's upstream installer |
| `OLLAMA_SETUP` | Build a configured model only if its runtime and base model already exist; no downloads |
| `NEWSBOAT_SETUP` | Generate `urls` only if no file exists |
| `SKILLS_SYNC` | Refresh vendored Claude content from its declared upstream repos |
| `CLAUDE_MARKETPLACE` | Build local wrappers and register the repository with Claude Code |
| `CLAUDE_HOOKS` | Merge the dotfiles worktree hooks into Claude settings, preserving other hooks |
| `KEYBOARD_SETUP` | Apply keyboard mapping only with `KEYBOARD_DEVICE_ID=vvvv:pppp` |
| `PROXY_SETUP` | Show proxy installation status; does not start/enable systemd |

`DOTFILES_LINKS_ONLY=1` and `DRY_RUN=1` suppress optional actions even if their
individual variables are set. Run `bash install.test.sh` before using the
installer on the real home directory.

The installer does **not** run `apt`, change the login shell, register Claude
settings, perform authentication, sync a wiki, enable a systemd service, or
activate keyboard input remapping by default.

## 3. Make Caps Lock the tmux prefix (required parity)

The tmux prefix remains backtick, exactly as on macOS. The laptop's Caps Lock
must emit the grave/backtick key; it is **not** mapped to Linux Super/Mod4, Ctrl,
or Escape. Existing i3 Super shortcuts and the US/RU Super+Space layout switch
must remain intact.

1. Install and verify `keyd` using its current upstream instructions.
2. Identify the **laptop keyboard only** using the output of `sudo keyd monitor`
   (or the device ID exposed under `/sys/class/input/`). Do not guess the ID or
   use the wildcard `*` in `/etc/keyd`.
3. Preview the generated mapping:
   ```bash
   ./keyboard-linux-setup.sh apply --device-id 1234:abcd --dry-run
   ```
   Substitute the verified vendor/product ID.
4. Apply it explicitly:
   ```bash
   sudo ./keyboard-linux-setup.sh apply --device-id 1234:abcd
   ./keyboard-linux-setup.sh status
   ```
5. Verify Caps+`c` creates a tmux window; Caps+`j`/`a`/`o` invokes the configured
   pickers; Caps+`e` opens the day plan. Caps twice sends a literal backtick,
   and the physical backtick still works. Check Caps no longer toggles
   capitalization, while Super+i3 shortcuts and Super+Space layout selection
   still work.
6. Test the active US and RU layouts, Ghostty → tmux, logout/login, reboot, and
   suspend/resume. As on macOS, a keycode is translated through the active
   layout; if the RU layout emits `ё` rather than backtick, the prefix works in
   the coding layout but not while RU is selected. Record this explicitly rather
   than silently changing the user's input-source behavior.

Rollback the managed mapping:

```bash
sudo ./keyboard-linux-setup.sh remove
```

This removes only `dotfiles-capslock.conf`; it does not disable the shared keyd
service or remove other device mappings. `keyboard-linux-setup.test.sh` tests
apply/idempotence/removal using temporary paths and service stubs; it never
accesses real input devices. Do not run the installer with `KEYBOARD_SETUP=1`
until the device ID is verified and a recovery terminal is available.

## 4. Zsh and editor setup

Once you have reviewed the plugin network installs, run:

```bash
ZSH_SETUP=1 ./install.sh
```

Or run `./zsh-setup.sh` by itself. It keeps existing `.zshrc` files, uses GNU
sed-safe temporary files, and generates Docker/kubectl completions only if the
commands are installed. It does not call `chsh`.

NVM loads from `$NVM_DIR/nvm.sh`; Go, Cargo, SDKMAN and RVM paths are optional and
home-relative/guarded. The fzf integration uses `fzf --zsh` when supported and
falls back to packaged Zsh keybindings on older versions. The `fd` and `bat`
compatibility symlinks let command-line programs, not just shell aliases, find
Ubuntu's `fdfind` and `batcat` commands.

Neovim plugins and Mason language servers are **not** auto-downloaded by the
installer. Launch Neovim and review/install its locked plugins intentionally.
Node is required by its TypeScript LSPs; individual language servers additionally
need their language toolchains. Use `nvim --headless '+checkhealth' +qa` after
plugin setup.

## 5. Tmux, Ghostty and i3

The preserved i3 config owns Super/Mod4 window/workspace keys. Ghostty keeps
client decorations and GTK's invisible resize border; do not set
`window-decoration = none`. Mac-only Ghostty options and conflicting Super-key
injection bindings are removed. Shift+Enter is unbound so Ghostty/tmux/Pi can
negotiate the modified key rather than Ghostty converting it to ordinary text.

The tmux config retains the backtick prefix and adds portable session/worktree
helpers. Full bindings use tmux >= 3.5 (`extended-keys-format csi-u`); on older
servers the config leaves tmux's default modified-key format instead of failing
to parse. Start a new, isolated tmux server and install plugins there before
replacing an existing server. Do not kill a live server to upgrade tmux.

## 6. Claude Code and Pi

Claude instructions and slash commands can be linked without authentication.
For offline marketplace wrapper generation:

```bash
./claude/vendor-sync.sh --offline
```

`CLAUDE_MARKETPLACE=1` also registers the marketplace in Claude Code and is an
explicit CLI-side change. `SKILLS_SYNC=1` contacts declared upstream Git repos;
review diffs before committing any vendor updates. Do not link the whole
`~/.claude` directory or replace user settings/hooks.

Pi's `bin/plink` links individual settings/resources into `~/.pi/agent`; it
preserves auth, sessions, installations and foreign links. After setup, review
`pi/settings.json` and explicitly refresh packages with `pi update --extensions`.
OpenAI/OpenCode login and local-model serving are manual. Local endpoints stay
on loopback. No API credentials or machine-specific model downloads are stored
here. The configured local models must actually be loaded by the selected Linux
Ollama/LM Studio runtime before their aliases work; MLX is not a Linux backend.

## 7. Optional apps and proxy

- **Newsboat:** config is linked under XDG. The generated `urls` file is
  preserved if present. Set `NEWSBOAT_SETUP=1` to generate it only when absent.
  Links open through `xdg-open`; saved articles expect `~/wiki/saved`.
- **Superfile:** config files are linked individually under XDG; runtime data
  remains application-owned.
- **repy:** config defaults to dictionary auto-detection, not macOS `macdict`.
  Before creating `~/.config/repy`, the installer checks for `~/.repy/states.db`
  to avoid silently hiding an existing library/history prefix.
- **mrglass:** config is linked and its Jira credential template is seeded.
  Building/installing the Go app, GitLab/GitHub login and Jira setup remain manual.
- **sing-box:** Ubuntu `bin/proxyctl`, `proxy/sing-box.service` and
  `proxy/README.md` remain the platform source of truth. `install.sh` links the
  controller and seeds secrets but does not install/replace a system unit or
  enable the tunnel. Inspect the unit/config and use `proxyctl on` only after
  explicit review and a recovery path. No HTTP proxy variables are used.

## Validation

```bash
bash install.test.sh
bash zsh-config.test.sh
bash zsh-setup.test.sh
bash keyboard-linux-setup.test.sh
bash ubuntu/install-missing.test.sh
bash bin/clipboard-copy.test.sh
bash bin/plink.test.sh
bash proxy/render.test.sh
bash proxy/render-happ.test.sh
bash claude/vendor-sync-offline.test.sh
bash claude/vendor-sync.test.sh
./ubuntu/check-dependencies.sh
```

Also run every `bin/*.test.sh`, the Pi extension suites under Node 24, and
separate-socket tmux/i3/Neovim checks. Some optional tests require test-only
secrets/stubs or installed application CLIs; never use real Jira/GitLab APIs,
proxy secrets, input devices, or tmux sessions as fixtures.
