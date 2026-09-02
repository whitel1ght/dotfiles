# Dotfiles

Personal configuration files for macOS development tools.

## Structure

```
.
├── tmux/           # tmux configuration + helper scripts
├── aerospace/      # AeroSpace window manager config
├── ghostty/        # Ghostty terminal config
├── superfile/      # superfile terminal file manager config
├── nvim/           # Neovim configuration
├── zsh/            # Zsh configuration (.zshrc, .zprofile, .p10k.zsh)
├── claude/         # Claude Code: personal skills, agents, settings, CLAUDE.md
├── epy/            # epy ebook reader config + vertical padding patch
├── proxy/          # sing-box TUN routing: domain list, config template, daemon
├── bin/            # Helper executables linked into ~/.local/bin
├── Brewfile          # Homebrew package list
├── install.sh        # Symlink setup script
├── brew-install.sh   # Homebrew package installer
├── macos-daemons.sh  # Toggle the macOS media analysis daemons
├── epy-setup.sh      # epy reader installer + padding patch
└── zsh-setup.sh      # Oh My Zsh and Powerlevel10k installer
```

## Installation

1. Clone this repository:
   ```bash
   git clone <your-repo-url> ~/.dotfiles
   cd ~/.dotfiles
   ```

2. Run the install script to create symlinks:
   ```bash
   ./install.sh
   ```

3. (Optional) Set up Zsh with Oh My Zsh and Powerlevel10k:
   ```bash
   ./zsh-setup.sh
   ```

4. (Optional) Install Homebrew packages:
   ```bash
   ./brew-install.sh
   ```

The install script will:
- Create symlinks from config files to their expected system locations
- Backup existing files with `.backup` extension
- Create necessary directories if they don't exist
- Disable the macOS media analysis daemons (see [macOS daemons](#macos-daemons))
- Install the epy ebook reader and apply its padding patch (see [epy](#epy))

The zsh setup script will:
- Install Oh My Zsh framework
- Install Powerlevel10k theme
- Copy existing Powerlevel10k configuration if found

The brew script will:
- Install all Homebrew packages from the Brewfile
- Provide helpful error messages if Homebrew isn't installed

## Config File Locations

- **tmux**: `~/.tmux.conf`, and helper scripts in `~/.local/bin/`
- **Aerospace**: `~/.config/aerospace/aerospace.toml`
- **Ghostty**: `~/.config/ghostty/config`
- **superfile**: `~/Library/Application Support/superfile/config.toml` and
  `hotkeys.toml`
- **Neovim**: `~/.config/nvim/`
- **Zsh**: `~/.zshrc`, `~/.zprofile`, `~/.p10k.zsh`
- **Claude Code**: `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, and per-item
  links inside `~/.claude/skills/` and `~/.claude/agents/`
- **epy**: `~/.config/epy/configuration.json`, and `macdict` in `~/.local/bin/`

## macOS daemons

`macos-daemons.sh` toggles the two on-device media analysis agents,
`com.apple.mediaanalysisd` and `com.apple.photoanalysisd`. `install.sh` runs
`disable` on every run, so a fresh machine ends up with them off.

```bash
./macos-daemons.sh          # disable (default)
./macos-daemons.sh enable   # restore stock behaviour
./macos-daemons.sh status   # report current state
```

Skip it during install with `MACOS_DAEMONS=0 ./install.sh`.

These daemons scan the Photos library for faces, scenes, OCR and Visual Look Up.
On macOS 15 `mediaanalysisd` also leaks compiled Neural Engine model bundles into
`~/Library/Containers/com.apple.mediaanalysisd/` — tens of gigabytes of duplicate
`*.tmp.<pid>.bundle` directories.

Two things to know:

- Disabling also kills **HomeKit Secure Video** analysis and **Live Text**, which
  share the same XPC services, along with Photos People, Memories and
  content-based search.
- macOS updates frequently reset launchd's override database, so the daemons come
  back silently. Re-run `./macos-daemons.sh status` after upgrading.

Both are user LaunchAgents, so no `sudo` is needed and the setting survives
reboots. SIP blocks `launchctl bootout`, so an already-running instance keeps
going until it idles out or you reboot — the script says so when it happens.

Run `./macos-daemons.test.sh` to test the script; it stubs `launchctl` and never
touches real daemons.

## epy

[epy](https://github.com/wustho/epy) is a terminal ebook reader. `install.sh`
runs `epy-setup.sh`, which installs it and patches in vertical padding.

```bash
./epy-setup.sh            # install + patch (default)
./epy-setup.sh status     # version, patch state, macdict on PATH
```

Skip it during install with `EPY_SETUP=0 ./install.sh`.

### Why it needs a setup script

Two things the Brewfile cannot express:

- **epy is a pipx app pinned to Python 3.12.** The last release (2023.6.11)
  imports `imghdr`, removed from the stdlib in 3.13. Left to itself pipx picks
  the newest Python on the machine and the install import-errors on first run.
  The interpreter is resolved through `brew --prefix python@3.12`, so it works
  on both Apple Silicon and Intel prefixes.
- **epy has no vertical padding setting.** `epy/vertical-padding.patch` adds
  `Setting.VerticalPadding` (default 1) and reworks the page geometry to match.
  `pipx upgrade` replaces site-packages wholesale, so the patch is re-applied on
  every run rather than applied once; re-run `./epy-setup.sh` after an upgrade.

The patch is pinned to epy 2023.6.11. If upstream ever ships a release it will
stop matching, and the script says so and stops instead of half-applying it.
Regenerate it against the new sources at that point.

### Vertical padding

Text is drawn flush against the top row by default. `VerticalPadding` reserves
that many blank rows above the text and below it:

```json
{ "Setting": { "VerticalPadding": 1 } }
```

Set it to `0` for stock behaviour. The patch touches paging as well as drawing
because epy sizes page jumps separately from what it draws — pad only the draw
and every page turn quietly repeats a line at the boundary.

### Define Word

`bin/macdict` backs epy's `d` (Define Word) key, printing entries from the
macOS built-in dictionaries. It talks to `DCSCopyTextDefinition` through
`ctypes`, so it runs on stock system Python with no venv, no pip and no network.

It never writes to stderr, including on a miss: epy treats any stderr output as
a failure and shows that instead of the definition.

`configuration.json` sets `DictionaryClient` to the bare name `macdict` rather
than an absolute path — epy resolves it with `shutil.which`, and `.zshrc`
already puts `~/.local/bin` on PATH.

Run `./epy-setup.test.sh` to test the setup script; it stubs `pipx` and `brew`
and patches a throwaway copy of the sources.

## tmux

The prefix is remapped to backtick (`` ` ``). Plugins are managed with
[TPM](https://github.com/tmux-plugins/tpm); install them with `` ` `` + <kbd>I</kbd>.

Declared plugins:

- [`tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect) — save/restore
  sessions.
- [`tmux-claude-picker`](https://github.com/whitel1ght/tmux-claude-picker) — an
  `fzf` picker for jumping between Claude Code sessions across windows, with a
  recap preview. Bindings (after the `` ` `` prefix): `` ` `` `j` = busy Claude
  windows, `` ` `` `a` = all Claude windows. Requires `fzf` and `ripgrep` (both
  in the `Brewfile`).

### Opening a file path from a pane

`` ` `` + <kbd>o</kbd> opens an `fzf` popup of the file paths found in the current
pane and opens your pick in `nvim` — provided by the same
[tmux-claude-picker](https://github.com/whitel1ght/tmux-claude-picker) plugin,
which documents how it works. It replaces tmux's built-in prefix-`o`
(`select-pane`), which fuzzmux's `C-p` picker already supersedes; `M-o` is not
available because AeroSpace binds every `alt-<letter>` to a workspace.

## superfile

[superfile](https://superfile.dev) (`spf`) is the terminal file manager. On macOS
its config lives at `~/Library/Application Support/superfile/` — not XDG — and
that directory doubles as its data directory, holding `superfile.log`,
`pinned.json`, version markers and the bundled themes. `install.sh` therefore
links `config.toml` and `hotkeys.toml` individually rather than the directory.

Settings that differ from the stock defaults:

- `transparent_background = true` — superfile paints no background of its own, so
  Ghostty's shows through. The bundled `tokyonight` theme is the *Night* variant
  (`#1a1b26`) while Ghostty runs *Storm* (`#24283b`), so picking the theme alone
  would still mismatch; letting the terminal supply the background also keeps the
  two in step through any future retheme. Nothing is lost — that theme's
  selected-item backgrounds equal its panel background, so selection is signalled
  by foreground colour either way.
- `cd_on_quit = true` — on its own this only makes superfile *print* its last
  directory. The `spf()` wrapper in `zsh/.zshrc` runs `spf --print-last-dir` and
  `cd`s to the result.
- `zoxide_support = true` — <kbd>z</kbd> opens a zoxide jump prompt.
- `sidebar_sections = ["pinned", "disks"]` — drops the XDG home shortcuts, which
  are noise on a machine where the work lives in `~/projects`, and puts pinned
  first. What remains is opt-in: pin a folder with <kbd>P</kbd>, and <kbd>s</kbd>
  focuses the sidebar, which also reveals an undocumented search bar that filters
  across pinned and disks. Set `sidebar_width = 0` to drop the panel entirely.
- `code_previewer = "bat"` and `metadata = true` — require `bat` and `exiftool`
  respectively (both in the `Brewfile`).
- `poppler` is in the `Brewfile` for PDF preview: superfile shells out to
  `pdftoppm` to render page 1 to a thumbnail, then draws it through the image
  preview pipeline. That pipeline only works outside tmux — `isKittyCapable()`
  matches `$TERM_PROGRAM` against a hardcoded allowlist, and tmux reports itself
  rather than Ghostty, so no Kitty graphics are emitted at all
  ([#1169](https://github.com/yorukot/superfile/issues/1169)). Same limitation
  applies to image and `ffmpeg` video previews.
- `editor` and `dir_editor` pinned to `nvim` rather than relying on `$EDITOR`,
  which this shell config does not set.

## Claude Code

Personal Claude Code components live in `claude/`:

```
claude/
├── skills/         # personal skills (one directory per skill)
├── agents/         # personal subagent definitions
├── settings.json   # global Claude Code settings
└── CLAUDE.md       # global personal instructions
```

### Vendored third-party skills

`claude/vendor/` holds skills cherry-picked from other people's repos. Each
subdirectory is one upstream author, packaged as a Claude Code *skills-dir
plugin* — so its skills load namespaced (`mattpocock:grilling`) and can never
collide with the bare names in `claude/skills/`.

Declare what you want in `claude/vendor.json`:

```json
{ "sources": [ { "name": "mattpocock",
                 "repo": "https://github.com/mattpocock/skills.git",
                 "ref": "main",
                 "skills": ["skills/productivity/grilling"] } ] }
```

`ref` takes a branch or tag name — not a raw commit SHA. It defaults to `HEAD`,
the remote's default branch; pin a tag to freeze one source.

`./install.sh` re-syncs every source on each run and `install.sh` links the
wrappers into `~/.claude/skills/`. Skip the network with
`SKILLS_SYNC=0 ./install.sh`.

Updates are applied to the working tree but **never committed**, so
`git diff claude/vendor/` always shows exactly what upstream changed — review it
before committing. `claude/vendor.lock.json` records the exact commit vendored.

Contents of `claude/vendor/*/skills/` are byte-exact upstream copies and are
destroyed on the next sync. To modify one, copy it into `claude/skills/`.

Requires `jq`. Run `./claude/vendor-sync.test.sh` to test the sync itself.

`settings.json` and `CLAUDE.md` are symlinked as whole files. **Skills and agents
are linked per item**, not as whole directories — this is deliberate. The work
repo [`claude-components`](https://gitlab.com/ecfx/claude-components) symlinks all
of `~/.claude/skills` and `~/.claude/agents` to itself, so linking the directories
here would clobber it. Linking each skill individually lets personal and work
components share one directory:

```
~/.claude/skills/           <- claude-components (whole directory)
├── commit-msg/             (work)
├── mr-review/              (work)
└── ecfx-daily-commits/  -> ~/projects/dotfiles/claude/skills/ecfx-daily-commits
```

### Adding a personal skill

1. `mkdir -p claude/skills/my-skill` and add a `SKILL.md` with YAML frontmatter
   (`name` and `description` are required — without them the skill is silently
   undiscoverable).
2. Run `./install.sh`.

Both the symlink and the ignore-list entry (below) are handled automatically.

### Interaction with claude-components

Because personal skills are linked *into* a directory that claude-components owns,
they appear inside that repo's working tree. `install.sh` keeps a managed block in
`claude-components/.git/info/exclude` listing them, so they stay out of its
`git status`. That file is local-only and never committed, so it affects nobody
else. Override the location with `CLAUDE_COMPONENTS_DIR` if you clone it elsewhere.

Order doesn't matter: run either repo's setup script first. If `claude-components`
later replaces the `~/.claude/skills` symlink, re-run `./install.sh` to restore the
personal links.

## Adding New Configs

1. Create a directory for the tool: `mkdir newtool`
2. Add your config file(s) to that directory
3. Update `install.sh` to include the new symlink
4. Run `./install.sh` to create the symlink

## Homebrew Package Management

The `Brewfile` contains all your installed Homebrew packages:
- **Formulae**: Command-line tools and libraries
- **Casks**: GUI applications
- **Mac App Store apps**: Apps installed via `mas`
- **Taps**: Third-party repositories

To update the Brewfile after installing new packages:
```bash
brew bundle dump --describe --force
```

## Private/Sensitive Configurations

For sensitive information (API keys, server credentials, etc.), use the private config system:

1. Copy the example file: `cp zsh/.zshrc.local.example ~/.zshrc.local`
2. Edit `~/.zshrc.local` with your private settings
3. The main `.zshrc` will automatically source this file
4. `.zshrc.local` is gitignored and won't be committed

## Usage

Edit files directly in this repository - changes will be reflected immediately in the symlinked locations.

## Proxy routing

Selective routing through a VPS: a short list of domains goes through the
tunnel, everything else goes direct. sing-box runs as a root LaunchDaemon
owning a TUN interface, so the decision happens at the network layer and **no
application holds proxy settings** — no `HTTP_PROXY`, no `NO_PROXY`, no
per-tool config.

```bash
proxyctl status     # daemon state, current default route, egress IP
proxyctl reload     # apply changes to proxy-domains.txt
proxyctl all        # temporarily route EVERYTHING through the VPS
proxyctl direct     # back to default-direct
proxyctl logs       # tail /var/log/sing-box.log
```

To route a new domain, add its apex to
[`proxy/proxy-domains.txt`](proxy/proxy-domains.txt) and run `proxyctl reload`.
Credentials live in `~/.config/sing-box/secrets.env` and never enter this repo
— [`proxy/secrets.env.example`](proxy/secrets.env.example) documents where each
value comes from.

**How it all works** — routing model, the DNS/route invariant, render pipeline,
daemon lifecycle, first run on a new machine, and troubleshooting:
[`proxy/README.md`](proxy/README.md).
