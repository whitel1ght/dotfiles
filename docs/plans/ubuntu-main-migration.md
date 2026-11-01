# Ubuntu configuration migration from main

## Purpose and implementation contract

Bring the `ubuntu` branch up to the useful, current configuration on the macOS `main` branch, **not** to an identical filesystem or software inventory. Preserve Ubuntu's desktop, networking, credentials, and machine-local state.

This plan has now been implemented and fast-forwarded into the local `ubuntu` branch at commit `43f98d0`, based on the pinned Ubuntu baseline below. It has **not been pushed to `origin/ubuntu`**. Existing home symlinks point into this checkout, so the tracked config contents they reference now reflect the migration; no installer was run. Use the numbered steps as the design/acceptance record and review the remaining activation gates below.

Implemented so far: selective portable-config import, Ubuntu-specific Zsh/editor/tmux/application adaptations, non-destructive installer and tests, clipboard helper, Linux keyd setup/rollback scripts, and the Linux documentation/package checker. Ubuntu i3, Ghostty resize behavior, and the Linux proxy service/controller were preserved.

Still requiring the user's laptop/explicit activation: install a verified `keyd` package, confirm the laptop keyboard ID with `keyd monitor`, apply and manually test the Caps Lock mapping across US/RU layouts/reboot/suspend; upgrade or explicitly accept older tmux/fzf; install/refresh Pi packages (the host did not have the pinned `pi-subagents` package); and selectively install optional applications. Read-only input inspection identified the internal ThinkPad keyboard as a candidate, but no ID was committed or mapping applied. No installer, package changes, proxy/keyboard services, real credentials, or authentication were changed during implementation.

Validation on the Ubuntu 24.04 host: all imported `bin/*.test.sh` suites passed (including portable path/clipboard fixes); install, Zsh setup/config, keyboard-script, proxy render/Happ, offline vendor, Pi linker, daily-plugin shell and four Pi-extension suites passed. Neovim parsed all 30 Lua files; i3 and Ghostty config validation passed; an isolated tmux 3.4 server parsed the config. Claude Code 2.1.219 validates the daily plugin and its run-all tests pass; its unsupported `plugin test` command is now skipped. The pinned Pi subagent package is not installed, so its package-backed agent-discovery test was not run. The dependency checker correctly reports tmux 3.4 (<3.5), fzf 0.44.1 (<0.48), missing `bat`, and missing `keyd`. No real tmux server, desktop session, provider API, or input device was modified.

### Exact source of truth

The branch names were misleading at review time. `git fetch origin` succeeded, and the refs were:

| Ref | Commit | Meaning |
|---|---|---|
| local `main` | `3db353400fdb1fc7d5b4b9574526645294443b76` | Stale; already an ancestor of Ubuntu |
| `origin/main` | `4bc05e98a23b8ef4be3310ef1b5b92f09c63e37d` | Current macOS configuration; migration source |
| `ubuntu`, `origin/ubuntu` | `8bb69c4a5e510a1bc4e84a90b9f728006d416589` | Migration baseline |

`ubuntu...origin/main` has **2 Ubuntu-only and 244 main-only commits**. The tree comparison reports 467 changed paths, largely because of new Claude/Pi skills and documentation. Comparing only local `main` would miss almost the entire migration.

Use the pinned source SHA below. If newer commits are requested, re-run the comparison and update this plan before importing them. Do not reset/fast-forward local `main` as part of this work, merge the entire mainline wholesale, or cherry-pick 244 historical commits.

```sh
SOURCE=4bc05e98a23b8ef4be3310ef1b5b92f09c63e37d
UBUNTU_BASE=8bb69c4a5e510a1bc4e84a90b9f728006d416589
```

### Non-negotiable preservation rules

- Keep `i3/config` and `i3/scripts/file-search.sh` unless making a separately justified, tested Ubuntu improvement.
- Keep Ubuntu's `bin/proxyctl`, `proxy/sing-box.service`, and Linux proxy installation logic. Main's controller is macOS-only; Ubuntu's already supports Linux and macOS.
- Keep Ubuntu's Ghostty GTK decoration/tab-bar behavior. No `window-decoration = none`: it removes resize edges on GNOME/Wayland.
- Do not copy credentials, authentication databases, agent sessions, generated caches, or model weights from the Mac.
- The original checkout has an **untracked root `.gitconfig`**, distinct from tracked `git/.gitconfig`. Leave it untouched and do not add it to a commit. Its contents were not needed for this review.
- Never run `git clean`, blanket `git add .`, destructive resets, proxy on/off/reload, real worktree cleanup, real ticket transitions, or wiki push/pull to validate this migration.
- Do not replace an entire `~/.pi/agent` or `~/.claude` directory with a symlink. Preserve runtime state and unrelated user configuration.
- **Required keyboard parity:** Caps Lock must act as the tmux prefix, matching macOS: Caps Lock sends backtick/grave and tmux keeps its backtick prefix. It must not become Linux Super/Mod4, Ctrl, or Escape. This requirement supersedes the original optional-remap recommendation.
- Do not change the user's default shell, keyboard layout, desktop session, browser, model billing route, or system services automatically. Apply the requested Caps Lock remap in the explicit keyboard activation step below; links-only installs and tests must not change live input devices.

## Findings that drive the plan

### What is worth bringing across

- **Zsh:** Powerlevel10k, fzf-tab, history/file/directory previews, zoxide, consistent TokyoNight colors, Superfile's `cd_on_quit` wrapper, wiki/Jira/day-workflow aliases, SDKMAN support, a non-interactive environment file, and better setup of plugins/completions.
- **Neovim:** modern `vim.lsp.config`/`vim.lsp.enable`, root markers, consolidated Mason setup, Python/Jinja/Go/Rust/Elm support in addition to the existing web stack, project/worktree Telescope picker, wiki topic links, Treesitter fixes, plugin cleanup, and updated lockfile.
- **tmux:** session/window/pane pickers, multi-agent session/path pickers, worktree-aware navigation, current-directory splits, pruning, day-plan popup, continuum/resurrect, extended keys, and status improvements.
- **Portable commands:** worktree, diary, Jira/MR, wiki, agent-linking, and session-management utilities under `bin/`.
- **Optional applications:** Superfile, Newsboat, repy, mrglass, Claude Code, Pi, local model providers. Their configurations are useful on Linux; installing or authenticating every application is not a prerequisite for a usable shell.
- **Installation:** inert local-config templates, explicit missing-configuration summaries, per-item links, plugin setup, and tests.

### Concrete portability and correctness gaps

| Location | Observed issue | Required treatment |
|---|---|---|
| `zsh/.zprofile` | Homebrew invocation, `/Users/dmitry/.docker/bin`, macOS Ruby paths | Replace with a small Linux login profile; no Homebrew dependency |
| `zsh/.zshrc` | `brew` plugin; `pbcopy`; BSD `date -v`; Rosetta `arch -x86_64`; `/opt/homebrew`; multiple `/Users/dmitry` PATH entries | Adapt selectively; see step 4 |
| `zsh/.zshrc`, `bin/dev` | NVM initialized only from Homebrew | Source Linux `$NVM_DIR/nvm.sh`, honoring an existing installation |
| `zsh/.zshenv` | Unguarded `. "$HOME/.cargo/env"` | Guard with readability check; clean hosts must start silently |
| `zsh-setup.sh` | `sed -i ''` when patching completions; brew install hint | GNU-compatible edit, correct Ubuntu hint |
| `bin/jt` | `pbcopy` | Shared Linux clipboard command, also used by fzf and shell helpers |
| `git/.gitconfig` | Sourcetree and `opendiff` commands under `/Applications` | Remove those optional tool sections; keep delta and local identity include |
| `install.sh` | Superfile path under `~/Library/Application Support`; AeroSpace/macdict/macOS services; LaunchDaemon proxy | Linux paths and installer composition, not a blind copy |
| `install.sh` | Does not link `bin/newsboat-urls` or generate its output | Add explicit helper installation and safe generation workflow |
| `install.sh` | Existing symlinks skipped even when wrong/broken; fixed `.backup` name | Repair owned links, protect foreign links, collision-safe backups |
| `install.test.sh` | BSD `stat -f %Lp`; claims every optional step is off but omits `SDKMAN_SETUP=0` | Fix before running; stub remaining CLI side effects too |
| `bin/session-picker.test.sh` | Five absolute `/Users/dmitry/projects/dotfiles/...` references | Resolve script relative to the test; fail if extraction is empty |
| `bin/mr-watch.test.sh` | BSD-only `sed -i ''` | Portable temporary-file edit or GNU sed on Ubuntu |
| `proxy/render-happ.test.sh` | Main regresses Ubuntu's portable fixture edit to BSD sed | Keep Ubuntu's version |
| `newsboat/config` | `browser "open %u"` | `xdg-open` browser command with tested URL quoting |
| `repy/configuration.json` | `dictionary_client = macdict` | `auto` by default; document optional `sdcv` plus dictionary data |
| `pi/models.json` | LM Studio model named MLX 4bit | MLX is Apple-specific; optional Linux GGUF/runtime and actual served ID |
| `pi/settings.json` / `pi/README.md` | Settings have two scoped models, while README lists six OpenAI models; documented `pi-subagents@0.76.0` is absent from packages | Reconcile against actual supported Pi runtime; do not import a second stale runtime |
| `zsh/.zshrc` / Pi docs | `pianthropic` uses `claude-bridge`, while docs say it is retired and active settings don't declare it | Omit/disable alias unless that provider is explicitly installed and verified |
| `pi/settings.json` | Mac's `deviceId`, runtime changelog marker | Keep machine-generated identity out of portable defaults |
| `ghostty/config` / `i3/config` | Ghostty Super+h/j/k/l/f/s/w overlap i3's Mod4 bindings | Keep i3 authoritative and use Neovim's native mappings; don't copy Mac shortcuts blindly |
| `ghostty/config` | `shift+enter=text:\n` can erase modified-Enter distinction | Explicitly validate with tmux/Pi; remove only if needed for intended terminal protocol behavior |

Some BSD/GNU differences are **already handled**: `changes-since`, `start-day`, `end-day`, and `daily-stats` have GNU date fallbacks. Test them; don't rewrite working date logic just because a grep finds `date -j`.

The source README is not authoritative in several places: its Claude skills/settings linking description predates marketplace-based discovery, and its Pi package/model description predates the actual settings. Read executable configuration first and update documentation accordingly.

### Observed Ubuntu environment, not installation assumptions

The review host reports Ubuntu **24.04.5 LTS**, x86-64, Bash 5.2, Zsh 5.9, Neovim **0.12.6** via Snap, tmux **3.4**, fzf **0.44.1**, Node **24.22.0** via NVM, Python **3.12.3**, and sing-box **1.14.3**.

Two immediate blockers for main's exact configuration:

- `fzf --zsh` needs **fzf >= 0.48**; current fzf is too old. Check all imported picker options against the selected release too.
- `extended-keys-format csi-u` needs **tmux >= 3.5**; current tmux is too old for that line.

`fd` currently resolves from Pi's private tool directory, not a system installation. Do not rely on a coding-agent-only PATH for normal interactive shells. `bat`/`batcat`, `fdfind`, and `go` were not found on the review process's PATH; this is a dependency check, not proof they are absent everywhere on disk.

## Migration strategy and file disposition

Use **selective snapshot imports onto an Ubuntu-based integration branch**. Keep upstream-like content where portable; make narrowly scoped Linux changes. Do not introduce a full cross-platform dotfile framework as part of this task.

| Path/group | Disposition |
|---|---|
| `nvim/` | Import current main tree including deletions and lockfile; validate runtimes |
| `tmux/.tmux.conf` | Import; satisfy/guard version requirements and validate key behavior |
| `zsh/`, `zsh-setup.sh` | Import/adapt; preserve useful Ubuntu runtime paths via guarded initialization |
| `git/` | Import updated templates/ignores; strip macOS-only diff/merge tools |
| `ghostty/config` | Ubuntu base; remove irrelevant Mac options and resolve shortcut conflicts deliberately |
| `i3/` | Preserve Ubuntu; no AeroSpace emulation or desktop replacement |
| `bin/` | Import everything except `macdict` and `proxyctl`; retain Ubuntu proxyctl; adapt identified scripts/tests |
| `claude/` | Import portable marketplace, commands, daily plugin, skills, vendor manifests/locks and licensed vendored sources |
| `pi/` | Import portable active configuration/content, then reconcile runtime/model/docs discrepancies; archive remains inert |
| `mrglass/`, `newsboat/`, `superfile/`, `repy/` | Import/adapt; make runtime installation optional |
| `ollama/` | Import Modelfile as optional local-model configuration; no automatic downloads |
| `proxy/` | Preserve Ubuntu tree; shared renderer/config/domain files already agree with source; do not replace Linux docs/unit |
| `.gitignore` | Merge source additions; preserve `secrets.env` exclusion |
| `install.sh`, `install.test.sh`, `README.md` | Compose/rewrite for Ubuntu and current behavior |
| `Brewfile`, `brew-install.sh`, `aerospace/` | Remove inherited copies from Ubuntu; replace bootstrap docs with Ubuntu equivalents |
| `keyboard/`, `keyboard-setup.sh`, `keyboard-setup.test.sh`, `macos-daemons.sh`, `macos-daemons.test.sh`, `bin/macdict`, `proxy/local.singbox.plist` | Do not import |
| Main's `docs/plans/2026-10-03-interactive-subagent-model-selection-design.md` | Historical design, not migration instructions; not needed for Ubuntu runtime |

No Linux replacement is required for Maccy, KeyCastr, TopNotch, Mole, `mas`, Xcode, or Apple media daemons. The **Caps Lock → backtick behavior does require a Linux replacement**, but the macOS hidutil/LaunchAgent implementation must not be imported. Linux versions of Slack/Telegram/LibreWolf/etc. are user choices, not reasons to translate every Brewfile entry.

## Step 1 — Establish an isolated integration checkout

1. Recheck `git status --short`, refs, and local changes. Leave the original checkout and its untracked `.gitconfig` alone.
2. Create an integration worktree from the Ubuntu baseline, e.g.:
   ```sh
   git worktree add -b ubuntu-main-migration ../dotfiles-ubuntu-migration "$UBUNTU_BASE"
   ```
   Use a different unused path/name if either exists. Bring this plan into that worktree explicitly if it has not been committed.
3. Capture a before-state file list and the hashes of protected Ubuntu paths in a review artifact outside credentials. Record the source SHA in the migration notes.
4. Inspect the actual laptop's config symlinks before eventual activation. Existing symlinks into the original checkout mean changing that checkout would change live configuration immediately; the separate worktree avoids this during development.
5. Do not link the sandbox or integration checkout into the user's real home directory yet.

**Acceptance:** clean, separate implementation worktree; source and baseline pinned; original checkout unchanged apart from this plan.

## Step 2 — Define the Ubuntu dependency/bootstrap contract

**New files suggested:** `ubuntu/packages.txt`, `ubuntu/README.md`, `ubuntu-install.sh`, and a dependency/version check script or tests.

Separate package installation from linking configuration. `install.sh` should not silently install a desktop, run apt, replace an existing toolchain, or download model weights.

### Core dependency mapping

| Purpose | Ubuntu package/tool |
|---|---|
| Shell, transport, build utilities | `zsh`, `git`, `curl`, `ca-certificates`, `build-essential`, `pkg-config`, `unzip`, `zip`, `rsync`, `openssh-client`, `procps`, `perl` |
| Script runtimes/data | `python3`, `python3-venv`, `jq`, `sqlite3` (JSON functions for OpenCode credential reader) |
| Search/previews | `ripgrep`, `fd-find`, `bat`, compatible `fzf`, `eza`, `zoxide`, optional `vivid` |
| Editor/terminal | Neovim >= 0.11 API baseline, compatible pinned plugins; prefer tested 0.12.x; tmux >= 3.5 for full parity; existing Ghostty |
| Clipboard/open URLs | `xclip` for i3/X11, `wl-clipboard` for Wayland sessions, `xdg-utils` |
| Git UI | `git-delta`/upstream delta release and `lazygit`; verify apt candidate availability |
| Node | Existing NVM, Node 24 for these TypeScript tests; no replacement with Ubuntu's older Node by accident |

Ubuntu release repositories differ. The implementation must check `apt-cache policy`, architecture, and installed versions; specify a vetted upstream release/version plus checksum when apt cannot satisfy a minimum. Do not assume `apt install fzf tmux neovim` meets the feature requirements, or that every Homebrew formula has an apt package with the same name.

Provide **executable** `~/.local/bin/fd` -> `fdfind` and `bat` -> `batcat` compatibility links when needed, only if no suitable command already exists and the destination is not user-owned. Shell aliases do not help fzf previews or scripts. Ensure normal login/non-login shell PATH sees them.

Optional dependency groups:

- **i3 desktop:** `i3-wm`, `i3status`, `i3lock`, `rofi`, `dex`, `autorandr`, `xss-lock`, `network-manager-gnome`, `pulseaudio-utils` (for `pactl`, not a request to replace PipeWire), `brightnessctl`, `playerctl`, `scrot`, `x11-xkb-utils`, `psmisc`. Verify i3 version supports the existing gaps/tiling directives. Do not install/change the session without opt-in.
- **Readers/files:** `newsboat`, Superfile, Rust/Cargo for repy v0.25.0, optional `sdcv` plus licensed dictionary data, `libimage-exiftool-perl`, `poppler-utils`, optional `ffmpeg`.
- **Work:** `gh`, `glab`, jira-cli, Go compatible with mrglass (source comment says >= 1.24.2; check actual `go.mod`), SDKMAN, AWS CLI, optional Docker Engine/CLI, kubectl and project-specific SDKs. Private `ecfx-tooling` stays a separately authorized clone.
- **Language servers:** Node/npm, Python/pip/venv, Rust/Cargo, Go, Ruby and Elixir/Erlang if those language workflows are enabled. Elm compiler/tools only when needed. Mason is not a replacement for host runtimes/build dependencies.
- **Keyboard parity (required, not an optional application):** use a Linux input remapper, preferably `keyd`, for Caps Lock → grave on both X11 and Wayland. Verify Ubuntu package availability and the installed version's configuration syntax; do not assume it is in the default apt repositories. See step 5 for safe activation and rollback.
- **Proxy:** preserve sing-box installation; `qrencode` optional for phone provisioning.
- **AI:** official Linux Pi/Claude/OpenCode installation as selected; authentication separate. Local Ollama/LM Studio optional, sized to laptop RAM/GPU.
- **Fonts:** install a user-selected Nerd Font for Powerlevel10k/icons; do not change system fonts blindly.

Do not bulk-install the Brewfile's historical Python versions, databases, GUI apps, and transitive graphics libraries. Do not enable PostgreSQL/nginx/Docker services merely because main lists them.

**Acceptance:** documented package groups and tool-version checks; dry-run/explain mode for bootstrap; no reliance on Homebrew or Pi's private PATH. Upgrading tmux must not kill existing sessions automatically.

## Step 3 — Import the portable snapshot, excluding protected platform files

1. Restore explicitly selected paths from `$SOURCE` into the integration worktree. Example for a first coherent group:
   ```sh
   git restore --source="$SOURCE" --worktree -- nvim tmux git
   ```
   Review the resulting diff and deleted files; a plain recursive copy would leave obsolete Neovim plugin configs behind.
2. Import the other groups from the disposition table. For `bin/`, generate an explicit source file list excluding `bin/proxyctl` and `bin/macdict`, including portable tests and executable modes. Do not restore all of `bin/` and accidentally overwrite the Ubuntu proxy controller.
3. Preserve symlinks, particularly `pi/skills/playwright-skill` and its vendored Claude target. Do not dereference it into a duplicate tree or lose upstream licenses.
4. Remove inherited `Brewfile`, `brew-install.sh`, and `aerospace/` from Ubuntu only. Keep Linux desktop/proxy files.
5. Merge ignore patterns; templates stay tracked, actual `secrets.env`, `.pi/`, `.claude/`, generated `claude/personal/`, and private settings stay ignored.
6. Do not run imported installers, vendor sync, model commands, or application startup during the import.

**Acceptance:** each path has an explained import/retain/drop decision; protected proxy and i3 files unchanged; obsolete Neovim files are actually deleted; all subsequent adaptation work is confined to the integration branch.

## Step 4 — Port shell initialization and shared OS operations

**Files:** `zsh/*`, `zsh-setup.sh`, `bin/dev`, `bin/jt`; new `bin/clipboard-copy` and tests (name is a proposed convention).

1. Add one small stdin-to-clipboard executable:
   - On an active Wayland session use `wl-copy` when available.
   - Otherwise, with X11 `$DISPLAY`, use `xclip -selection clipboard` (an optional `xsel` fallback is fine if tested).
   - With no usable desktop clipboard, return nonzero with a short diagnostic. Never claim success or echo sensitive input as a fallback.
   - Preserve stdin bytes; test through stubs without touching the real clipboard.
2. Port `today`/`yesterday` to functions using GNU date (`date -d yesterday +%F`) and quoted Git arguments. Pipe into that helper. Replace both fzf Ctrl-Y and `jt` Ctrl-Y calls to `pbcopy`; only print "copied" after successful copy.
3. Keep Powerlevel10k as the intended parity default, `fzf-tab` ahead of autosuggestions, and syntax highlighting last. Remove `brew` from the plugin array. Guard missing framework/optional binaries so a fresh shell is usable before setup; emit actionable, non-secret warnings rather than repeated stack traces.
4. Replace `.zprofile` with Linux-appropriate PATH setup. Remove all `/Users`, `/Applications`, Homebrew Ruby/JPEG paths, Rosetta alias, and Docker Desktop-injected blocks. Use deduplicated Zsh `path` entries for `$HOME/.local/bin`, `$HOME/bin`, `$HOME/.cargo/bin`, `$HOME/go/bin`, and optional installed tool directories.
5. Preserve Ubuntu's NVM initialization from `$NVM_DIR/nvm.sh`. Fix `bin/dev`'s spawned shell string too: it must source NVM even in a tmux process without an interactive `.zshrc`. Respect a custom `NVM_DIR` and keep `.nvmrc` selection/fallback behavior.
6. Preserve RVM/GEM_HOME only if this laptop still uses that environment. Guard `/etc/profile.d/rvm.sh`; put machine-specific choices in the local configuration. Do not reintroduce Homebrew Ruby or delete a working Ruby environment silently. Remove obsolete `/opt/nvim-linux64/bin` if it is not the chosen installed editor; don't shadow the working Snap version with a stale path.
7. Import `.zshenv`'s guarded mrglass secrets source. Guard Cargo's environment file. Keep the existing portable Perl `deadline()` function or use a tested Linux executable equivalent visible to non-interactive preview shells; do not put it exclusively in `.zshrc`.
8. Gate `fzf --zsh` on capability/version. Preferred target is a new enough fzf; an old-fzf fallback must warn and remain usable rather than produce startup errors. Guard zoxide/vivid. Fix `vimconfig` to point to `~/.config/nvim/init.lua`, not nonexistent `init.vim`. Fix the ineffective `grep='...'` assignment by using a real tested alias/function or dropping it.
9. Keep local configuration sourcing last; examples must be inert. Never globally export HTTP(S)/ALL/NO_PROXY for the TUN setup. Do not silently rewrite the real `.zshrc.local` or clear unrelated user environment variables.
10. Port `zsh-setup.sh`'s completion edit to a temporary-file transform or GNU syntax. Preserve `--unattended --keep-zshrc`. Test installing before and after symlink setup. Do not call `chsh` automatically.
11. Keep portable Pi aliases only after step 8 verifies providers/model IDs. `$HOME/.lmstudio/bin` may be a guarded optional PATH, never `/Users/dmitry/...`.

**Acceptance/tests:** clean sandbox `zsh -c true`, login shell and interactive shell startup; no missing Cargo/RVM/brew errors; working `fd`/`bat` in child shells; fzf and clipboard tests cover X11, Wayland, no display, and copy failure; completion generation works with stub kubectl/docker; no credentials printed. Test both no optional tools and fully configured environments.

## Step 5 — Migrate editor, Git, tmux and terminal behavior

### Neovim

- Start from the complete current main `nvim/` tree and lockfile. Do not resurrect stale local-main Copilot files: neither current branch tip has those old specs.
- Keep main's LSP root markers rather than Ubuntu's interim custom `root_dir` callback. Main consolidates Mason configuration and avoids deprecated `require('lspconfig').setup`.
- Verify every configured language server against host prerequisites. Web, Lua and Python should work on the basic development setup; document optional Ruby/Elixir/Go/Rust/Elm provisioning rather than report nonexistent servers as healthy.
- Keep `nvim/after/plugin/treesitter.lua`'s Markdown injection workaround for the pinned Treesitter/Neovim combination; don't upgrade all plugins opportunistically. Use lockfile restore, not a broad update.
- Check Telescope's `<leader>pp` with no `~/projects`, with a path containing spaces, and with `projects/worktrees/...`. Add a missing-directory guard if necessary (main calls `vim.fn.readdir(projects_root)` unconditionally).
- Validate wiki mappings with no wiki present, Markdown fenced-code preview, completion, normal editing, and system clipboard under the actual Linux session.
- Use isolated XDG config/data/cache/state for headless tests. Network plugin installation and Mason downloads belong to an explicit integration stage, not a supposedly offline syntax test.

### Git

- Keep aliases, delta pager, shared ignore rules and `~/.gitconfig.local` include.
- Remove the `sourcetree` diff/merge sections containing `opendiff` and `/Applications/...`. Do not choose a new merge tool without need.
- Import the inert local template; existing real identity/signing settings must survive. Never use the untracked root `.gitconfig` as the shared config source.

### tmux

- Import main's configuration and all helper dependencies before enabling its bindings.
- Full-parity target is tmux >= 3.5. If the user remains on 3.4, guard unsupported options and document the modified-key limitation; do not leave an invalid config. Treat upgrading the binary and restarting a server as separate operations.
- Keep backtick prefix, current-directory splits, Alt+number switching, popup pickers, pruning and day-plan. Implement the required Caps Lock → backtick mapping below; do not copy the macOS remapping scripts. Keep the existing backtick `send-prefix` binding so pressing Caps Lock twice sends a literal backtick to the pane.
- Install TPM/plugins only in the opt-in setup phase. Rebind vendored picker commands after TPM, as main does.
- Validate in a **separate tmux socket/server** with sandbox HOME. Never source this config into or kill the user's current server as a test. Continuum restore must be isolated from real saved sessions.

### Ghostty and i3

- Retain i3's Mod4 window/workspace bindings and its US/RU layout selection.
- Keep Ghostty's font/theme/padding and Ubuntu GTK/titlebar/tab-bar settings. Remove `macos-titlebar-style` and `macos-option-as-alt` from the Ubuntu config.
- Resolve Super shortcut collisions by favoring existing i3 bindings. Default recommendation: remove the colliding Ghostty editor-injection shortcuts and use Neovim's existing leader/navigation commands; do not move i3's established shortcuts just to imitate Command on macOS.
- Validate Shift/Ctrl/Alt+Enter end-to-end in Ghostty → tmux → Pi. The explicit Shift+Enter-to-newline mapping is a separate concern from tmux's extended-key support.

### Required Caps Lock → tmux prefix mapping

The user's “tmux super key” means the **tmux prefix**, not the desktop Super modifier. On macOS, `hidutil` maps Caps Lock to the physical grave/backtick key, while tmux uses backtick as its prefix. Reproduce that behavior on Ubuntu rather than changing tmux to Ctrl+B or mapping Caps Lock to Super.

**Suggested new files:** `keyboard/linux/keyd.conf.example`, `keyboard-linux-setup.sh`, `keyboard-linux-setup.test.sh`. These are new Linux implementations, not copies of main's plist/hidutil scripts.

1. Inspect existing keyboard remappers/configuration without modifying them. Preserve i3's `setxkbmap us,ru -option grp:win_space_toggle`, existing Super/Mod4 behavior, and unrelated device mappings. Do not enable two competing remappers for Caps Lock.
2. Prefer a system-level `keyd` mapping so the behavior is independent of Ghostty and works under both i3/X11 and GNOME/Wayland. Verify its current documentation and installed key names before writing the config. The intended main-layer mapping is `capslock = grave`, **not** a tap/hold overload, sticky modifier, or compose key. Pressing it must immediately send the prefix, without a hold timeout.
3. Match the built-in laptop keyboard by its verified device identifier. Include external keyboards only if the user wants the mapping there too; do not blindly install a wildcard configuration that affects unrelated input devices. Keep actual device identifiers in machine-local configuration, with an inert committed example.
4. Implement `apply`, `status`, and `remove` operations. `apply` must validate the config, back up existing owned config collision-safely, install it with appropriate root ownership, and arrange persistence with the supported systemd service. Do not overwrite foreign keyd config or change unrelated mappings. `remove` restores the previous owned mapping/config; don't disable a shared remapper service if other mappings depend on it.
5. Separate file generation from privileged activation. Provide a dry run and `KEYBOARD_SETUP=0`/links-only bypass for tests and staged rollout. **The final migration is not complete while the remap remains skipped.** Enabling/reloading the service is an explicit activation action with a recovery terminal available; tests stub the service/input commands and never grab real keyboard devices.
6. A Ghostty-only binding or a standalone `xmodmap` command is not an equivalent default: it either depends on application focus or does not cover Wayland/persistence. If keyd cannot be used, document and test a session-appropriate persistent alternative before declaring keyboard parity complete. Do not stack several untested fallbacks.
7. Preserve active-layout semantics rather than silently forcing the whole keyboard to US. A physical grave-key remap is translated by the active layout, just as the Mac's HID remap is. Test US and RU behavior explicitly; if tmux prefix access must also work while RU is selected and the simple physical mapping does not provide it, resolve that with a tested layout-aware solution rather than claiming success or changing existing layout switching.

**Keyboard acceptance tests (mandatory):**

- In the normal coding layout, Caps Lock then `c` creates a tmux window; Caps Lock then `j`/`a`/`o` invokes the migrated pickers, and Caps Lock then `e` opens day-plan when its prerequisites exist.
- Caps Lock twice sends one literal backtick into the pane; the original backtick key still works as the same prefix. Outside tmux, Caps Lock produces the same character as the original grave key (and Shift behaves consistently).
- Caps Lock no longer toggles capitalization and is not treated as Super or Ctrl. Existing physical Super+i3 bindings and Super+Space US/RU switching still work.
- No input delay, stuck modifiers, doubled events, or lost keyboard input. Validate at the input/terminal level and in Ghostty → tmux, not just by reading the config.
- Mapping survives logout/login, reboot, and suspend/resume. Test each desktop session actually used. Document observed US/RU behavior and any remaining layout limitation explicitly.
- `remove`/rollback restores prior Caps Lock behavior without losing unrelated keyboard settings; repeated `apply` is idempotent.

**Acceptance:** Neovim opens without configuration errors; selected LSP clients attach; Git diff uses delta; tmux parses on the chosen version and popups invoke installed helpers; i3 config validates (`i3 -C -c i3/config`); Ghostty retains resizing behavior; **Caps Lock prefix parity passes the tests above**. Manual key tests cover both i3/X11 and GNOME/Wayland only if those sessions are actually used.

## Step 6 — Migrate helper commands and fix Linux tests

**Files:** portable `bin/*`, their tests, and shared workflow support.

1. Import and preserve the workflows in:
   - `wt`, `dev`, `clean-worktrees`, `ecfx-daily-commits`;
   - `start-day`, `end-day`, `changes-since`, `daily-stats`, `day-note`, `day-plan`, `diary-links`;
   - `jt`, `mr-watch`, `sync-tickets`;
   - `session-picker`, `open-path`, `tmux-prune`;
   - `notes`, `vault-check`, `newsboat-urls`;
   - `cs`, `cs-add`, `plink`, `opencode-console-auth`.
2. Apply the clipboard/NVM changes from step 4. Fix hardcoded checkout paths in tests; assert source extraction succeeded so an empty regex cannot produce false passing cases.
3. Fix BSD-only `sed` in `bin/mr-watch.test.sh`; keep existing tested date/stat fallbacks elsewhere. Re-run the entire imported `bin/*.test.sh` suite after inspecting its isolation.
4. Ensure helpers invoked through `~/.local/bin` can find the repo when installed from a non-default checkout path. Follow `plink`'s symlink resolution pattern or provide a consistent explicit repository override. In particular, `newsboat-urls` and Ubuntu `proxyctl` default to `$HOME/projects/dotfiles`; don't let the integration checkout accidentally read the original tree.
5. Keep current work/project naming defaults rather than gratuitously generalizing every script. Make machine-specific paths configurable where necessary. Missing wiki, private tooling or authentication must produce an actionable failure/no-op, not a network request with template placeholders.
6. Tests for `sync-tickets`, `mr-watch`, `clean-worktrees`, `notes`, and agent launches must use fake API clients/temp repositories. Do not test them against real tickets, MRs, worktrees or remote notes.
7. Document `vault-check`'s dependency on the external `~/wiki/vault-lib.sh`. Do not claim vault/iCloud recovery is portable merely because this wrapper is; leave it a no-op without that library and inspect its Linux compatibility separately before enabling it.

**Acceptance:** portable command tests pass from a checkout whose path is not `/Users/dmitry/projects/dotfiles`; helper install list is explicit and excludes tests/macdict; no live API writes or real cleanup used as validation.

## Step 7 — Bring across optional terminal applications

1. **Superfile:** import `config.toml`/`hotkeys.toml`, link individual files under `${XDG_CONFIG_HOME:-$HOME/.config}/superfile` on Linux (verify with the installed application's `path-list`). Keep runtime state/logs/pins out of Git. Test the shell `spf()` wrapper's lastdir behavior. Document bat/exiftool/poppler/ffmpeg dependencies and tmux image-preview limitations.
2. **Newsboat:** import config/feed lists; switch browser to `xdg-open`; explicitly install `newsboat-urls`. Preview generated output with `-n`; preserve an existing user-managed `urls` file before first generation. Generate only when absent or clearly managed/explicitly requested. Create `~/wiki/saved` only as part of the selected wiki/reader setup, and warn if it is absent so Newsboat doesn't silently save into the working directory. Preserve cache/database.
3. **repy:** import config with `dictionary_client: "auto"`; do not import `macdict`. Keep pinned `v0.25.0` installation optional. Document optional `sdcv` data and test definition lookup only when installed. Check for existing `~/.repy/states.db` before creating the XDG config directory: changing prefixes can hide the old reading history. Back up and offer migration; never overwrite reading state. Keep future sync passwords out of tracked JSON (the application can rewrite its config).
4. **mrglass:** import config and inert secrets template. Build from the separately available project with a compatible Go version only if selected. Keep GitLab/GitHub login with glab/gh and Jira secrets outside Git; no automated credential lookup or copying.
5. Keep Ollama Modelfile import but defer actual model/runtime setup to step 8.

**Acceptance:** each selected app reads the right Linux config path and opens without losing previous state; absent optional apps do not break shell/installer; readers use Linux browser/dictionary behavior.

## Step 8 — Migrate Claude and Pi configuration without copying machine state

These are portable tools, not macOS software. Migrate their useful configurations, but treat their runtimes/providers as a separate compatibility gate.

### Claude Code

1. Import `claude/CLAUDE.md`, invoke-only global commands, personal skills, marketplace manifest, vendor manifests/lock and vendored sources/licenses, plus the daily plugin.
2. Follow current installer behavior: marketplace-based skill selection, per-command links, and a shared instruction file. Do not reintroduce obsolete whole-directory/global-skill linking just because the old README describes it.
3. `claude/personal/` is generated and ignored. Ensure the marketplace's generated personal plugin wrapper can be built from **committed vendor content without network refresh**; `SKILLS_SYNC=0` must not leave a fresh checkout pointing at a nonexistent plugin. Split wrapper generation from upstream refresh if necessary and test offline setup.
4. Merge only owned `WorktreeCreate`/`WorktreeRemove` hook entries into existing settings, backing up first and preserving unrelated hooks/settings. Main replaces those two arrays wholesale; don't silently discard user hooks.
5. Keep project plugins opt-in. Do not install all plugins into every project or run commands that submit work on behalf of the user.
6. Validate daily-plugin APIs against the installed Claude version using `claude plugin validate`/`claude plugin test` where supported. Its TSX hooks use `claude-code` APIs; do not pretend plain Node execution validates that integration. Audio uses the host API, not a hardcoded `afplay` call.

### Pi

1. Read the target Pi version's official configuration, packages, models, extensions, MCP and relevant TUI docs before adapting APIs. This review used the installed Pi 1.4.0 configuration/package/model/settings docs; do not assume all old third-party packages support that runtime.
2. Use `bin/plink`'s per-item mapping: settings, models, MCP source, instructions, prompts, agents, skills, extensions, packages, and shared modules. Preserve `auth.json`, `mcp-auth.json`, sessions, `install/`, npm/package state, and real/foreign retired-config files.
3. Keep relative `./packages/pi-recap` resolvable beside the installed settings. Keep the Playwright skill symlink target available. Do not activate `pi/archive/subagents/` or historical subagent routing JSON.
4. Resolve the **actual** source inconsistency: README/agent tests require `pi-subagents@0.76.0`, but `pi/settings.json` no longer declares it. Verify supported package/provider availability. If the intended delegation workflow still needs that package, explicitly declare a compatible pinned version, retaining disabled bundled prompts/skills as documented; otherwise update policies/tests to the supported replacement. Never load old and new delegation implementations together. Record this decision rather than silently skipping failing discovery tests.
5. Remove copied `deviceId` from portable defaults; let the target runtime retain/generate its own identity. Avoid committing runtime-only changelog fields. If the runtime writes these back through a symlink, use an installed local settings file with an explicit managed-key merge and update `plink`/tests accordingly. Do not simply let each laptop continually modify committed machine identity.
6. Preserve source model/provider preferences where available, but validate default, scoped models, recap model and shell aliases independently. Current source default is `opencode-go/longcat-2.5`; current scopes are `openai/gpt-6.1-sol` and `ollama/qwen2.5-coder:14b-16k`. Do not substitute the README's older six-model pool or enable paid fallback silently. Fix the `claude-bridge` alias mismatch.
7. `opencode-console-auth` needs sqlite3 with JSON support and a local OpenCode login. Tests use a synthetic DB; never invoke `... token` in a logged test against the real database. User auth is a manual activation step.
8. Ollama/LM Studio endpoints are portable but optional. Keep loopback bindings. MLX weights are not a Linux option: select a supported GGUF/backend and use the ID actually returned by the local server. Do not promise the 14B/30B models fit this laptop, download them automatically, or expose servers to the LAN. Leave the feature disabled/documented until hardware and model choice are confirmed.
9. Keep MCP `${VAR}` references and missing-variable behavior; auth stays local. Test that non-interactive launch environments receive required values, without dumping environment contents. Do not assume a secret in `.zshrc.local` reaches every non-interactive shell.
10. Keep optional Herdr integration inert when its environment is absent; no Herdr service installation is required. Verify third-party packages and local extension compatibility in a sandbox before real startup.

### Skills and instructions are part of the migration too

Scan executable examples, not just source code. Known fixes:

- `claude/skills/qa-comment/SKILL.md`, `pi/skills/qa-comment/SKILL.md`: replace `pbcopy` with the clipboard helper.
- `pi/skills/mr-description/SKILL.md`: replace the absolute `/Users/dmitry/projects/claude-components/...` hook path with configurable/`$HOME`-relative discovery, and handle a missing private repo.
- `pi/skills/checkstyle-enforcer/SKILL.md`, `cleanup-inbox-item/SKILL.md`: use the actual discovered checkout, not another person's `/Users/...` path.
- `pi/skills/duploctl/SKILL.md`, `obsidian-cli/SKILL.md`: no `/opt/homebrew` or `/Applications` binary fallback; optional tool discovery and Linux installation instructions.
- `pi/skills/mr-review-queue/scripts/triage.py` and affected skill READMEs: replace brew-only prerequisite guidance with the Ubuntu dependency guide.
- Audit codeartifact/deploy-ecr guidance and Gradle cache examples similarly. Literal sample paths/fixtures need not all be rewritten, but must not be used as real command targets.
- `supply-chain-ioc-check` contains macOS-specific threat checks: retain their platform qualification, add/point to Linux checks as appropriate, and never treat a missing LaunchAgent path as proof a Linux host is clean.
- Do not edit byte-exact vendored upstream skill content casually; use owned wrappers/local guidance so vendor sync does not erase changes.

**Acceptance:** linker tests and four local extension suites pass; agent discovery validates against the selected supported package; fresh sandbox startup has no extension errors; unavailable providers are clearly identified, not automatically substituted; no secrets, device identity or state copied from macOS. Live authentication/model calls require explicit approval.

## Step 9 — Compose the Ubuntu installer and regression tests

**Files:** `install.sh`, `install.test.sh`, any new installer/helper tests.

Start from Ubuntu's platform integration and selectively add main's portable behavior. An alternative is main's script with all platform-specific sections replaced, but the resulting behavior must satisfy the same contract.

1. Keep core link creation separate from optional network/system/runtime operations. Provide a documented links-only/offline mode that disables **all** external actions, including marketplace registration, Jira initialization and settings mutation outside the sandbox.
2. Link i3, Ghostty, tmux, Neovim, Git, all four Zsh files (`.zshrc`, `.zprofile`, `.zshenv`, `.p10k.zsh`), selected optional app configs, and the explicit helper list.
3. For symlinks: correct links are no-ops; repair broken/old links owned by this dotfiles installation; foreign links require an explicit overwrite decision and backup. For real files/directories, create unique backups without overwriting previous backups. Tests must cover a second backup and paths with spaces.
4. Seed inert local templates without replacing existing files, including dangling-symlink safety (`-e` alone misses a dangling link). Seed `.zshrc.local` and mrglass/proxy secrets mode 600; `.gitconfig.local` mode 644. Seeding proxy credentials must not depend on sing-box already being installed.
5. Separate proxy config/linking from privileged unit installation. Preserve the `/etc/systemd/system/sing-box.service` override and discovered binary path behavior; never replace it with `/usr/lib`'s unprivileged stock unit. Changes to an existing override require a diff/backup/explicit apply. No `systemctl enable --now` during generic config installation.
6. Retain explicit opt-in/skip controls for Zsh plugins, TPM/plugins, repy, SDKMAN, private ECFX tooling, vendor refresh, local models, and proxy service setup. Integrate the required Linux keyboard setup as a separate explicit activation step, with `KEYBOARD_SETUP=0` for sandbox/links-only operation. Linux error messages must not recommend `brew-install.sh`.
7. Keep SSH keys, known_hosts trust, provider auth, wiki restore and private repo access manual. An absent optional repo should warn and continue.
8. Fix main's test isolation before running its real installer:
   - Add `SDKMAN_SETUP=0` to the sandbox environment.
   - Disable/stub `claude`, `jira`, sudo/systemctl, package managers, curl/git network operations, model setup and any new optional step.
   - Use temporary HOME and all relevant XDG paths; clear inherited credential variables or construct an allowlisted environment.
   - Replace `stat -f %Lp` with GNU `stat -c %a` or a tested portable helper.
   - Check installer exit status explicitly; don't infer success only from a few files existing.
9. Test incomplete/malformed existing Claude settings without destroying them, reruns, no optional binaries, missing templates, inert examples, and the generated marketplace wrapper.
10. Print exactly what was linked/seeded/skipped and what the user still needs to configure. Do not report "proxy configured" merely because an empty stub exists.

**Acceptance:** links-only install runs twice without network, sudo or edits to source files; second run is idempotent; local data survives; no Linux install creates `~/Library`, AeroSpace config, macdict links or LaunchAgents.

## Step 10 — Validate proxy preservation and run the complete test matrix

### Proxy invariants

The shared renderer, JSON template, domain lists, and secrets example already match source. Keep Ubuntu's Linux README/service/controller and portable Happ test.

- Unmatched traffic and DNS remain proxied; configured direct domains resolve/route consistently; block/reader exception ordering remains tested.
- `proxyctl on/off/reload/logs` use systemd on Linux, `/etc/sing-box/config.json`, root:root mode 600, and journalctl.
- Add stubbed controller tests for backend selection and commands, no implicit activation, validation-before-install, and failure without real secrets.
- Add installer tests proving setup doesn't start/restart/enable the real service.
- No changing domain policy or enabling HTTP_PROXY as a migration convenience.
- A real tunnel smoke test is a final, approved manual action, with a known-good unit/config backup and a local recovery session; never do it over the only remote connection without a recovery path.

### Automated validation order

1. `git diff --check`; shell syntax by declared interpreter (`bash -n`, `zsh -n`); ShellCheck where applicable; parse JSON/TOML using suitable tooling without printing secrets.
2. Package/bootstrap and clipboard tests, plus installer sandbox tests.
3. `bash proxy/render.test.sh` and `bash proxy/render-happ.test.sh`.
4. Every imported `bin/*.test.sh`, then `claude/vendor-sync.test.sh`, owned skill/script tests, and daily-plugin shell tests. Audit test code first; use fixtures and isolated auth/config.
5. `bash bin/plink.test.sh` and:
   ```sh
   for extension in background-terminals inline-files mcp-env session-models; do
     (cd "pi/extensions/$extension" && npm test) || exit 1
   done
   ```
   Use Node 24. Run `pi/agents.test.mjs` with `PI_SUBAGENTS_PACKAGE` pointing to the deliberately selected installed package, adapting the test if the supported delegation implementation changed.
6. Claude's `claude/daily/tests/run-all.sh` additionally invokes CLI plugin validation/tests; run only with a compatible CLI and isolated state. A missing CLI is a documented untested integration, not a passing suite.
7. Isolated Neovim plugin/health/LSP checks, separate-socket tmux checks, i3/Ghostty validation. Then manual GUI/key/clipboard tests on the real session after approval.
8. Search active paths for macOS leftovers:
   ```sh
   rg -n --hidden '/Users/|/opt/homebrew|/Applications/|pbcopy|pbpaste|launchctl|hidutil|sed -i' zsh bin install.sh zsh-setup.sh git newsboat repy
   ```
   Review matches rather than blanket-replacing them: retained `proxyctl` intentionally contains a guarded Darwin backend. Run a broader scan of owned Claude/Pi workflow text too.

### Baseline tests actually run during this review

Tests were run on Ubuntu, against either the existing Ubuntu checkout or an exported, unmodified source snapshot; no live installation or proxy/service changes were performed.

| Test | Result |
|---|---|
| Ubuntu `proxy/render.test.sh` | 35 passed |
| Ubuntu `proxy/render-happ.test.sh` | 20 passed |
| Source `bin/plink.test.sh` | 41 passed |
| Source `bin/wt.test.sh` | 26 passed |
| Source Pi background-terminals | 26 passed |
| Source Pi inline-files | 7 passed |
| Source Pi mcp-env | 6 passed |
| Source Pi session-models | 5 passed |
| Source `bin/session-picker.test.sh` | 11 passed, **9 failed**, due to hardcoded Mac checkout paths |

Other suites, provider auth, live apps, and full installer behavior were not validated during planning. Passing unit tests do not establish third-party plugin API compatibility or live model availability.

## Step 11 — Documentation, review, controlled activation and rollback

1. Rewrite root `README.md` for **Ubuntu**, linking `ubuntu/README.md` and Linux proxy docs. Document installed paths, supported versions, core/optional dependency groups, all installer flags, generated files, authentication, and manual application activation.
2. Update Pi and Claude documentation to the actual installed package/model/discovery choices. Document deliberate differences from main in a small `docs/platform-differences.md`, including source SHA and the Linux-specific patch list for future syncs.
3. Review the final diff against both `$UBUNTU_BASE` and `$SOURCE`. Explicitly confirm i3/proxy preservation, main branch untouched, no device identity/credentials, no generated `claude/personal/` or model/runtime state, and no accidental root `.gitconfig` addition.
4. Suggested commit sequence (combine adjacent steps only if tests remain coherent):
   - Ubuntu dependency contract and platform cleanup;
   - Linux shell/clipboard/completion support;
   - editor/Git/tmux migration;
   - helper commands and portable tests;
   - terminal applications;
   - Claude/Pi configuration and workflow portability;
   - Ubuntu installer and regression tests;
   - final documentation/validation fixes.
5. Before activation, take a private backup of affected live configs, symlink targets, existing local settings, repy state and any systemd unit that will change. Record installed tool versions and where backups are stored. Don't put this backup in Git.
6. After approval, integrate the reviewed commits into `ubuntu` without rewriting existing history. Keep the integration worktree around until no live symlink depends on it. Prefer final links to the stable Ubuntu checkout.
7. Run links-only setup first, inspect the summary, then opt into each application/plugin/tool installation separately. Keep an existing terminal open while testing a new shell. Do not kill live tmux sessions to activate a new binary; start a separate server first. Leave proxy activation separate.
8. Rollback configuration commits with reviewed reverts or the recorded baseline, restore backed-up live files/symlinks explicitly, and restore a changed system unit/config only if applicable. Reverting Git alone does not undo installed packages, generated settings, migrated app state or systemd edits. Preserve all user data and credentials throughout rollback.

### Definition of done

- [ ] Ubuntu receives current useful shell, editor, Git, tmux and helper behavior.
- [ ] i3 remains the Linux desktop configuration; Ghostty remains resizable with the intended hidden chrome.
- [ ] **Caps Lock is the tmux prefix as on macOS:** Caps Lock → backtick, existing tmux prefix unchanged, double-Caps sends a literal backtick, original grave/Super/layout switching preserved, and the remap persists across reboot. Linux activation and rollback are tested.
- [ ] Linux proxy service/routing behavior is unchanged and covered by tests.
- [ ] No active Homebrew/Rosetta/Apple app/service dependency remains in Ubuntu setup.
- [ ] Clipboard, NVM, tool names, GNU utilities and Linux config paths work outside the agent harness.
- [ ] Fresh installation and repeated installation are tested and non-destructive.
- [ ] Optional apps/AI runtimes are either validated or explicitly documented as not activated; no silent paid-provider fallback.
- [ ] Credentials, runtime state, device identity, local configs and unrelated user hooks survive.
- [ ] Relevant automated tests pass; manual/unavailable integrations are listed honestly.
- [ ] Main is unchanged; Ubuntu's intentional differences and future resync procedure are documented.

## Decisions that need user input only at activation

Proceed with portable code/config migration and safe defaults without blocking on these:

1. Whether to activate Powerlevel10k immediately or keep the current robbyrussell prompt through a local override.
2. Which optional apps/work toolchains are actually wanted on Ubuntu.
3. Whether to upgrade tmux/fzf for full parity (recommended) versus temporarily use documented compatibility guards.
4. Whether local inference is wanted, and the laptop's suitable GGUF/model/runtime choice.
5. Which available AI account/model route should be the usable startup default if the source default is unavailable.
6. Whether the required Caps Lock → tmux-prefix mapping should also apply to external keyboards. It is required on the laptop keyboard; only the device scope and activation timing remain to confirm.

If a runtime/API discrepancy in step 8 cannot be resolved without changing user-visible workflow or billing, stop that optional integration, state the exact incompatibility, and ask. It must not block the core Ubuntu configuration migration.
