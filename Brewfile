tap "bufbuild/buf"
tap "go-task/tap"
tap "homebrew/services"
tap "koekeishiya/formulae"
tap "nikitabobko/tap"
tap "opencode-ai/tap"
# Library for manipulating PNG images
brew "libpng"
# Core application library for C
brew "glib"
# Low-level library for pixel manipulation
brew "pixman"
# Vector graphics library with cross-device output support
brew "cairo"
# TIFF library and utilities
brew "libtiff"
# Toolkit for image loading and pixel buffer manipulation
brew "gdk-pixbuf"
# OpenType text shaping engine
brew "harfbuzz"
# Framework for layout and rendering of i18n text
brew "pango"
# Library to render SVG files using Cairo
brew "librsvg"
# Icons for the GNOME project
brew "adwaita-icon-theme"
# Library and utilities for processing GIFs
brew "giflib"
# Spell checker with better logic than ispell
brew "aspell"
# Protocol definitions and daemon for D-Bus at-spi
brew "at-spi2-core"
# Bourne-Again SHell, a UNIX command interpreter
# Not optional: macOS ships bash 3.2, which has no associative arrays. The
# fuzzmux tmux plugin declares one at scripts/init.sh:52 under `set -u`, so on
# stock bash it aborts there — before binding prefix s/w/f/C-p — and tmux
# reports nothing at all. Same class of limit bin/notes works around by hand.
brew "bash"
# Clone of cat(1) with syntax highlighting and Git integration
brew "bat"
# Console Matrix
brew "cmatrix"
# Apjanke's fork of the classic cowsay project
brew "cowsay"
# Reimplementation of ctags(1)
brew "ctags"
# Cryptography and SSL/TLS Toolkit
brew "openssl@3"
# C library implementing the SSH2 protocol
brew "libssh2"
# Get a file from an HTTP, HTTPS or FTP server
brew "curl"
# Functional metaprogramming aware language built on Erlang VM
brew "elixir"
# Perl lib for reading and writing EXIF metadata
brew "exiftool"
# Modern, maintained replacement for ls
brew "eza"
# Simple, fast and user-friendly alternative to find
brew "fd"
# Play, record, convert, and stream audio and video
brew "ffmpeg"
# Banner-like program prints strings as ASCII art
brew "figlet"
# Command-line fuzzy finder written in Go
brew "fzf"
# GitHub command-line tool
brew "gh"
# Syntax-highlighting pager for git and diff output
brew "git-delta"
# Tcl/Tk UI for the git revision control system
brew "git-gui"
# Open source GitLab command line tool
# The GitLab half of the pair this setup assumes: gh was declared here, glab
# never was. mrglass authenticates GitLab THROUGH glab rather than a token of
# its own, and the handle-ticket skill drives MRs with `glab mr create/view/
# update`, so without it both are dead on a fresh machine.
brew "glab"
# Render markdown on the CLI
brew "glow"
# GSettings schemas for desktop components
brew "gsettings-desktop-schemas"
# Toolkit for creating graphical user interfaces
brew "gtk+3"
# I/O abstraction library for dealing with structured file formats
brew "libgsf"
# Gnumeric spreadsheet program
brew "goffice"
# GNOME Spreadsheet Application
brew "gnumeric"
# Package compiler and linker metadata toolkit
brew "pkgconf"
# Generate introspection data for GObject libraries
brew "gobject-introspection"
# Open source programming language to build simple/reliable/efficient software
# Needed by ~/projects/mrglass, the merge-request TUI, which is built with
# `go install ./cmd/mrglass` into ~/go/bin. Its go.mod requires 1.24.2. Go was
# never declared here — the old
# machine had it installed outside this repo (reddittui-setup.sh's header still
# records "this machine has 1.22.1"), so a fresh machine got no toolchain and
# mrglass could not be built at all.
brew "go"
# Post-modern modal text editor
brew "helix"
# Improved top (interactive process viewer)
brew "htop"
# C/C++ and Java libraries for Unicode and globalization
brew "icu4c@76"
# Cryptography and SSL/TLS Toolkit
brew "openssl@1.1"
# Interpreted, interactive, object-oriented programming language
brew "python@3.10"
# Make XML documents translatable through PO files
brew "itstool"
# Image manipulation library
brew "jpeg"
# Lightweight and flexible command-line JSON processor
brew "jq"
# Simple terminal UI for git commands
brew "lazygit"
# Next-gen compiler infrastructure
brew "llvm"
# Rainbows and unicorns in your console!
brew "lolcat"
# Powerful, lightweight programming language
brew "lua"
# Powerful, lightweight programming language
brew "lua@5.3"
# Package manager for the Lua programming language
brew "luarocks"
# Mac App Store command-line interface
brew "mas"
# Ambitious Vim-fork focused on extensibility and agility
brew "neovim"
# RSS/Atom feed reader for text terminals
brew "newsboat"
# HTTP/2 C Library
brew "nghttp2"
# HTTP(S) server and reverse proxy, and IMAP/POP3 proxy server
brew "nginx"
# Manage multiple Node.js versions
brew "nvm"
# Execute binaries from Python packages in isolated environments
brew "pipx"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"
# Object-relational database system
brew "postgresql@14"
# Protocol buffers (Google's data interchange format)
brew "protobuf"
# Interpreted, interactive, object-oriented programming language
brew "python@3.11"
# Interpreted, interactive, object-oriented programming language
brew "python@3.12"
# Interpreted, interactive, object-oriented programming language
brew "python@3.9"
# Search tool like grep and The Silver Searcher
brew "ripgrep"
# Powerful, clean, object-oriented scripting language
brew "ruby"
# Safe, concurrent, practical language
brew "rust"
# Modern and pretty fancy file manager for the terminal
brew "superfile"
# ISO/Edinburgh-style Prolog interpreter
brew "swi-prolog"
# Tool Command Language
brew "tcl-tk"
# Official tldr client written in Rust
brew "tlrc"
# Terminal multiplexer
brew "tmux"
# Generator for LS_COLORS with support for multiple color themes
brew "vivid"
# Feature-rich command-line audio/video downloader
brew "yt-dlp"
# Shell extension to navigate your filesystem faster
brew "zoxide"
# The best way of working with Protocol Buffers.
brew "bufbuild/buf/buf"
# Task runner / simpler Make alternative written in Go
brew "go-task/tap/go-task"
brew "opencode-ai/tap/opencode"
# Tool for creating locally-trusted development certificates
brew "mkcert"
# Deep clean and optimize your Mac
brew "mole"
# AeroSpace is an i3-like tiling window manager for macOS
cask "nikitabobko/tap/aerospace"
# Password manager app
# This is the tool that opens ~/wiki/machine-rebuild.kdbx, which holds the SSH
# keys, VLESS credentials and git identity a rebuild needs. Its absence is a
# bootstrap deadlock rather than an inconvenience: vault-sync.sh and every
# keepassxc-cli line in the vault runbook fail without it, so the vault that
# exists to rebuild a machine cannot be opened on the machine being rebuilt.
# The cask symlinks keepassxc-cli into the Homebrew prefix; there is no
# CLI-only formula.
cask "keepassxc"
# Open-source keystroke visualiser
cask "keycastr"
# A custom version of Firefox, focused on privacy, security and freedom
cask "librewolf"
# Clipboard manager
cask "maccy"
# Utility to hide the notch
# The notch reserves safeAreaInsets.top = 32pt across the FULL screen width,
# whether or not the menu bar is hidden, so windows can never use it and the
# band just sits empty above every AeroSpace layout. TopNotch masks it black so
# it reads as bezel. It captures the rendered wallpaper and swaps in a masked
# copy, so it works even with the dynamic providers that have no file on disk.
cask "topnotch"
mas "Harvest", id: 506189836
mas "Numbers", id: 409203825
mas "Quiver", id: 866773894
mas "SimpleMind", id: 439654198
mas "Slack", id: 803453959
mas "Telegram", id: 747648890
mas "Xcode", id: 497799835
cargo "cross"
brew "sing-box"
