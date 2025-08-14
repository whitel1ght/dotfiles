# Dotfiles

Personal configuration files for macOS development tools.

## Structure

```
.
├── tmux/           # tmux configuration
├── aerospace/      # AeroSpace window manager config
├── ghostty/        # Ghostty terminal config
├── Brewfile        # Homebrew package list
└── install.sh      # Symlink setup script
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

The script will:
- Create symlinks from config files to their expected system locations
- Install all Homebrew packages from the Brewfile
- Backup existing files with `.backup` extension
- Create necessary directories if they don't exist

## Config File Locations

- **tmux**: `~/.tmux.conf`
- **Aerospace**: `~/.config/aerospace/aerospace.toml`  
- **Ghostty**: `~/.config/ghostty/config`

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