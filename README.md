# Dotfiles

Personal configuration files for macOS development tools.

## Structure

```
.
├── tmux/           # tmux configuration
├── aerospace/      # AeroSpace window manager config
├── ghostty/        # Ghostty terminal config
├── nvim/           # Neovim configuration
├── zsh/            # Zsh configuration (.zshrc, .zprofile, .p10k.zsh)
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

- **tmux**: `~/.tmux.conf`
- **Aerospace**: `~/.config/aerospace/aerospace.toml`
- **Ghostty**: `~/.config/ghostty/config`
- **Neovim**: `~/.config/nvim/`
- **Zsh**: `~/.zshrc`, `~/.zprofile`, `~/.p10k.zsh`

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
