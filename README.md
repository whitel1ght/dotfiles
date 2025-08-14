# Dotfiles

Personal configuration files for macOS development tools.

## Structure

```
.
├── tmux/           # tmux configuration
├── aerospace/      # AeroSpace window manager config
├── ghostty/        # Ghostty terminal config
├── nvim/           # Neovim configuration
├── Brewfile        # Homebrew package list
├── install.sh      # Symlink setup script
└── brew-install.sh # Homebrew package installer
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

3. (Optional) Install Homebrew packages:
   ```bash
   ./brew-install.sh
   ```

The install script will:
- Create symlinks from config files to their expected system locations
- Backup existing files with `.backup` extension
- Create necessary directories if they don't exist

The brew script will:
- Install all Homebrew packages from the Brewfile
- Provide helpful error messages if Homebrew isn't installed

## Config File Locations

- **tmux**: `~/.tmux.conf`
- **Aerospace**: `~/.config/aerospace/aerospace.toml`
- **Ghostty**: `~/.config/ghostty/config`
- **Neovim**: `~/.config/nvim/`

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

## Usage

Edit files directly in this repository - changes will be reflected immediately in the symlinked locations.
