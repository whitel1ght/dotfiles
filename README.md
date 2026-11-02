# Ubuntu dotfiles

Personal configuration for an Ubuntu laptop, migrated selectively from the
macOS `main` branch. Portable shell/editor/terminal/workflow settings are
shared where useful; Ubuntu keeps its own i3 desktop, Ghostty behavior, systemd
proxy and keyboard setup.

## Quick start

1. Review [Ubuntu setup and package guidance](ubuntu/README.md), especially the
   dependency/version checks and Caps Lock → tmux prefix activation.
2. Preview and test the non-destructive configuration links:
   ```bash
   DRY_RUN=1 DOTFILES_LINKS_ONLY=1 ./install.sh
   bash install.test.sh
   ```
3. Link configuration and seed inert local examples:
   ```bash
   DOTFILES_LINKS_ONLY=1 ./install.sh
   ```
4. Configure only the local credentials and optional applications you use.
   Install packages, refresh Claude/Pi packages, configure the keyboard, and
   enable the proxy in separate reviewed steps.
5. Review the [Ubuntu workflow and optional service lifecycle](ubuntu/README.md#daily-workflows-and-optional-user-services) before installing or activating user timers.

## Main configuration

- `i3/`, `ghostty/`: Ubuntu desktop and terminal behavior.
- `keyboard/`, `keyboard-linux-setup.sh`: explicit keyd mapping; Caps Lock emits
  backtick for the tmux prefix without changing Super/Mod4.
- `zsh/`, `zsh-setup.sh`: Zsh, Powerlevel10k, plugins, completions, and optional
  local environment.
- `nvim/`, `tmux/`, `git/`: editor, terminal multiplexer, and Git configuration.
- `bin/`: portable worktree, daily workflow, wiki/repository synchronization, friction/decision, Jira, Pi-management, reader, clipboard, and agent helpers. Links are installed individually; user credentials and runtime state remain external.
- `claude/`, `pi/`: optional agent configuration; credentials and runtime state
  stay local.
- `newsboat/`, `repy/`, `superfile/`, `mrglass/`: optional terminal apps.
- `proxy/`, `bin/proxyctl`: Ubuntu's systemd-based sing-box routing.
- `ubuntu/`: package lists, dependency checks and platform setup guide.

## Safety defaults

`install.sh` links configuration and seeds only absent local files. It does not
install apt packages, change the login shell, modify the active keyboard,
replace user Claude/Pi state, authenticate to services, write to a wiki, or
start/enable sing-box. Optional setup actions are opt-in; `DOTFILES_LINKS_ONLY=1`
forces linking/seeding only. Existing unrelated symlinks/settings are preserved.

The templates (`*.example`) are inert. Real Git identity, Jira tokens, proxy
credentials, SSH trust, model downloads and app databases never belong in this
repository. Do not put `HTTP_PROXY`/`HTTPS_PROXY` variables in shell config;
the sing-box TUN handles routing below the application layer.

## Implementation and tests

The migration and platform-specific decisions are recorded in
[`docs/plans/ubuntu-main-migration.md`](docs/plans/ubuntu-main-migration.md).
Run [the Ubuntu setup guide](ubuntu/README.md) for dependency versions, Caps
Lock mapping and validation. The initial Ubuntu migration source was `origin/main`
commit `4bc05e98a23b8ef4be3310ef1b5b92f09c63e37d`. The parity refresh selectively
audited the active portable features at `origin/main`
`5681fa20266740813e3ad2b445b2cc52bf47e88d`; macOS-only applications and
services remain intentionally excluded.
