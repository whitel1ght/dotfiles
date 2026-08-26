# Dotfiles

Personal configuration files for macOS development tools.

## Structure

```
.
├── tmux/           # tmux configuration + helper scripts
├── aerospace/      # AeroSpace window manager config
├── ghostty/        # Ghostty terminal config
├── nvim/           # Neovim configuration
├── zsh/            # Zsh configuration (.zshrc, .zprofile, .p10k.zsh)
├── claude/         # Claude Code: personal skills, agents, settings, CLAUDE.md
├── Brewfile        # Homebrew package list
├── install.sh      # Symlink setup script
├── brew-install.sh # Homebrew package installer
└── zsh-setup.sh    # Oh My Zsh and Powerlevel10k installer
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
- **Neovim**: `~/.config/nvim/`
- **Zsh**: `~/.zshrc`, `~/.zprofile`, `~/.p10k.zsh`
- **Claude Code**: `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, and per-item
  links inside `~/.claude/skills/` and `~/.claude/agents/`

## tmux

The prefix is remapped to backtick (`` ` ``). Plugins are managed with
[TPM](https://github.com/tmux-plugins/tpm); install them with `` ` `` + <kbd>I</kbd>.

Declared plugins:

- [`tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect) — save/restore
  sessions.
- [`tmux-claude-picker`](https://github.com/whitel1ght/tmux-claude-picker) — an
  `fzf` picker for jumping between Claude Code sessions across windows, with a
  recap preview. Bindings (after the `` ` `` prefix): `` ` `` `j` = busy Claude
  windows, `` ` `` `a` = all Claude windows. Requires `fzf` (in the `Brewfile`).

### Opening a file path from a pane

`` ` `` + <kbd>o</kbd> opens an `fzf` popup listing every file path visible in
the current pane, newest first, and opens the one you pick in `nvim` in a new
window — jumping to the right line for `path:line` references. It replaces
tmux's built-in prefix-`o` (`select-pane`), which fuzzmux's `C-p` picker already
supersedes; `M-o` is not available because AeroSpace binds every `alt-<letter>`
to a workspace.

It exists for Claude Code, which prints paths to files it has just created.
Clicking one in Ghostty hands it to macOS `open`, which means Finder and a
detour through "Open With"; Ghostty has no run-a-command-on-click hook for links
(`link` reports `error.NotImplemented` as of 1.3.1), so a keystroke is the way.

Because Claude Code runs on the alternate screen, where tmux keeps no scrollback
at all, the visible rows are all `capture-pane` can offer. So for panes in a
project that has Claude Code transcripts (`~/.claude/projects/<slug>/*.jsonl`),
the recently modified ones are read too — that recovers paths which have already
scrolled away.

Candidates are filtered by whether they exist on disk, which is what keeps the
list clean. Paths containing spaces are not detected. Run
`tmux-open-path --list <pane-id>` to see what would be offered without the
picker.

## Claude Code

Personal Claude Code components live in `claude/`:

```
claude/
├── skills/         # personal skills (one directory per skill)
├── agents/         # personal subagent definitions
├── settings.json   # global Claude Code settings
└── CLAUDE.md       # global personal instructions
```

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
