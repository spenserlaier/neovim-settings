# Home Manager

This repository uses a flake-based Home Manager configuration for its portable
command-line and editor environment.

The common module installs the command-line and editor packages. Home Manager
also owns the Git, Jujutsu, Atuin, and Starship configurations through their
native program modules. The TOML configuration files remain the source of truth
for Jujutsu, Atuin, and Starship; the small Git configuration is represented
directly in the Home Manager module.

Fish is managed through its native module. Shared interactive behavior lives in
`fish/interactive.fish`; Home Manager embeds that file in its generated Fish
configuration and generates the Atuin and Starship integrations.

Neovim is the default terminal editor through Home Manager's `defaultEditor`
setting (`EDITOR`), plus session-wide `VISUAL` and `SYSTEMD_EDITOR` variables.
Log out and back in after activation so applications inherit these settings.
Interactive Fish also sets `EDITOR` and `VISUAL` directly.
`sudo` may discard editor variables and exclude Nix programs from its PATH;
for privileged systemd edits, use `sudo env SYSTEMD_EDITOR="$(command -v nvim)" systemctl edit ollama`
from Bash, or `sudo env SYSTEMD_EDITOR=(command -s nvim) systemctl edit ollama`
from Fish. These commands give systemd the absolute editor path explicitly.

CLI input uses basic vi bindings: Fish configures its own editor, the native
Readline module generates `~/.inputrc`, and Home Manager also generates
`~/.editrc` for libedit clients. This covers tools such as `psql` regardless of
which of those libraries they use. Press Escape to enter command mode and `i`
to return to insert mode.

Linux installs `xclip` for X11 clipboard access and `wl-clipboard` (`wl-copy`
and `wl-paste`) for Wayland. Neovim automatically selects an available clipboard
provider for the session. These tools do not require OpenGL driver integration.
On macOS, Neovim uses the system's `pbcopy` and `pbpaste` instead.

`PYTHON_BASIC_REPL=1` selects Python's traditional REPL so it uses these input
settings, trading PyREPL's newer multiline editing interface for vi bindings.
After activation, start a fresh login session to pick up the environment change.
For Racket's XREPL, enter `,input readline` once and restart Racket; XREPL saves
that preference itself. Its default expression editor does not use these files.
Other CLIs with their own input editors may need their own vi-mode setting.

Repository fzf pickers share `fish/functions/vi_fzf.fish`: bare `nvim`, `rgi`,
`fdi`, directory session creation, and the tmux session/window pickers. They
start in insert mode. Escape enters normal mode, where `j`/`k` move down/up;
`i` or `/` resumes typing. Normal mode hides the input while preserving the
query and results; the border shows the mode. Escape in normal mode cancels.
Ctrl-U/Ctrl-D move half a page up/down through results in either mode, preserving
the query. Enter accepts in either mode, and Ctrl-C cancels. Existing picker
shortcuts still work, including `rgi`'s Ctrl-F switch from ripgrep to fuzzy
filtering. This requires fzf 0.59 or newer.
The wrapper is opt-in; plain `fzf` and Neovim Telescope keep their own bindings.

Bare `nvim` opens a filename picker under the current directory with a file
preview. Files from Neovim's saved recent-file history appear first, followed
by the remaining files; the usual ignore rules still apply. Enter opens the
selected file. Ctrl-G toggles between filename and content search, preserving
the query and normal/insert mode; Enter in content search opens the matching
line. The picker headers show these shortcuts;
Ctrl-/ toggles previews, which move below the results in narrow terminals.
`fdi` shares the filename preview, while standalone `fdi` and `rgi` keep Enter
for printing a result and Ctrl-O for opening it. Passing arguments to `nvim`
continues to invoke the editor directly.

`jjr` reviews the current Jujutsu change in a file picker with diff previews.
Run `jjr -H` (or `jjr --hunks`) to start with individual hunks instead;
`jjr -h` shows help. Both modes use the shared vi-style picker bindings.
Ctrl-G switches between files and hunks, keeping the filter text and selecting
the corresponding file or its first matching hunk when possible. The header
shows the active mode. The picker retains normal/insert mode across switches
and editor/diff visits. Enter opens the selected diff through Delta's full-screen
pager; quit the pager to return. Ctrl-O opens the working file in Neovim at the
selected change, then refreshes the list when Neovim exits. The picker retains
the query and selection where possible. Ctrl-/ toggles the preview.

Deleted files, binary files, and symlinks open their diff instead of launching
Neovim. Files without textual hunks (including pure renames and mode changes)
remain available in hunk mode as a `[no text hunks]` entry. Deleted hunks open at
the nearest remaining line. Each refresh reviews one consistent snapshot of
the current change, even if another process edits files during inspection;
Ctrl-O always opens the live working file. Run from any workspace subdirectory.
This command does not stage, restore, or otherwise rewrite changes. It depends
on the managed Fish `vi_fzf` function, fzf, jj, Delta, and Neovim.

Run `python3 scripts/test-jjr.py` to check hunk destinations, literal filenames,
rename/deletion/binary handling, and filtered mode-switch selection using a
temporary Jujutsu repository.

Starship uses the Nix-packaged `jj-starship` custom module for both Jujutsu and
Git repositories. The built-in Git modules are disabled so colocated Jujutsu
workspaces show one version-control segment. The package is pinned by this
repository's nixpkgs lock file; no separate flake input is needed.

`jj hist` shows the current change's ancestors and descendants without the
default log's revision filtering. The Starship local bookmark row keeps its
existing comma-based wrapping. A separate peach (`#fab387`) `↗ remote` row shows remote
bookmarks within ten ancestor edges of the working copy, plus remote
counterparts of local bookmarks in that range. It excludes synthetic `@git`
refs, includes remote-only bookmarks, and reflects the last fetched state.
The ancestor range follows `JJ_STARSHIP_ANCESTOR_BOOKMARK_DEPTH` when set.

Remote suffixes compare against the working copy: `~N` means N commits behind,
`↑N` means N commits ahead, and `↔↑N↓M` means diverged (N remote-only commits,
M working-copy-only commits). An exact match has no suffix; `!` marks a
conflicted remote bookmark. Unlike the local row's shortest ancestor distance,
remote counts include all commits on each side of a merge. The remote row wraps
between complete entries without shortening names or limiting their count.
Names wider than the terminal naturally wrap within the terminal itself.

Direnv and nix-direnv are managed natively and integrated with Fish. Pyenv and
Mise are not part of this configuration; project runtimes belong in development
shells instead.

Tmux is managed through its native module. `tmux/common.conf` contains the shared
configuration, while Home Manager supplies pinned Resurrect and Continuum
plugins.

With the `Ctrl-a` prefix, `f` searches existing tmux sessions, including detached
sessions, showing their directories, window counts, and attachment status.
Numeric session names are displayed with their starting directory's basename
(for example, `neovim-settings (session 10)`); custom names are preserved.
`F` searches directories and opens or creates a project session named after
the directory. Plain `tmux`/`new-session` creation can still assign numeric names.
`g` opens the current session's window picker with command and directory labels,
and `r` reloads the tmux configuration.

Outside tmux, Fish also accepts `Ctrl-a`, `f` to attach to an existing session,
and `Ctrl-a`, `Shift-f` to choose a project directory before creating or
attaching to its session. Both shortcuts work in insert and normal mode.
Cancelling a picker returns to the current shell prompt without creating a
session. No preliminary tmux session is needed.

Both existing-session and window pickers have a large, color-preserving preview
of the selected item's active pane. Session previews also list its windows.
The preview moves below the list in narrow popups; `Ctrl-/` toggles it.
Previews capture terminal contents when the selection changes, without sending
input to the process. They do not continuously refresh or combine split panes.

In the session picker, `Ctrl-x` requests deletion of the highlighted session.
The confirmation names the session and directory, shows its window count, and
warns that all its processes will terminate. Only lowercase `y` confirms;
Escape, any other key, or end-of-input cancels. The list refreshes afterward
and keeps the search query. Deleting the current session switches to another
session first and closes the picker; deleting the last session leaves tmux,
with an additional warning in the confirmation.

Ranger is installed by Nix, and Home Manager links the repository's existing
Ranger configuration into `~/.config/ranger`.

Home Manager links the repository's Kitty configuration into `~/.config/kitty`.
On Linux, install Kitty through the host package manager (`sudo dnf install kitty`
on Fedora) so it uses the host graphics stack. Thunderbird is installed by Home
Manager on Linux. Kitty and Thunderbird use the optional Homebrew layer on macOS. Codex CLI is installed by Home Manager on both platforms;
its version follows the pinned Nixpkgs input. Run `codex` to sign in after
activation. Home Manager
installs CaskaydiaCove Nerd Font, FiraCode Nerd Font, and Noto Sans Symbols 2
through `home/fonts.nix`. On macOS its native font module copies them into
`~/Library/Fonts/HomeManager`; on Linux the Fontconfig module exposes them.
Existing Homebrew-installed fonts are left in place during this migration.

Kitty keeps CaskaydiaCove for text and Nerd Font icons. Home Manager generates
`kitty/symbol-fonts.conf` from Noto's actual character coverage, assigning its
supported Unicode symbol ranges to that font. Text, private-use
icons, box drawing, block elements, and braille retain their existing handling.
This avoids per-character fallback fixes and mappings to characters absent from
the font. The remote row uses a north-east arrow (`↗`, U+2197) for a simple,
distinct silhouette, rendered by Noto Sans Symbols 2 through this mapping.
The existing `∅` mapping to FiraCode remains for a symbol outside Noto's coverage.

Kitty loads the Catppuccin Mocha palette from `kitty/current-theme.conf`. Its
ANSI colors are used by shell programs, including `jj-starship`; tmux does not
define a separate palette. Neovim selects Catppuccin independently in
`nvim/init.lua`. Kitty maps the Jujutsu empty-description symbol (`∅`) to
FiraCode Nerd Font Mono because CaskaydiaCove does not contain that glyph.
Kitty starts Fish from `~/.nix-profile/bin` explicitly, so it loads the
Home Manager Fish and Starship integration even when the account's login shell
is Bash.

Neovim is installed through its native module and is the default editor. Its
configuration is copied into the Nix store and linked at `~/.config/nvim`, while
native build and search dependencies are included in Neovim's wrapped runtime.
Nix supplies the active language servers, StyLua, ShellCheck, shfmt, and
Markdownlint. Neovim enables those servers directly without Mason. Nix also
pins nvim-treesitter and the configured language parsers; Lazy continues to
manage the remaining plugins (including Tree-sitter text objects and context)
during this migration phase.

Project-specific formatters such as Darker remain discoverable through `PATH`
and can be supplied by a Direnv development shell without becoming global home
packages.

## Local AI client

Home Manager installs OpenCode and manages its configuration from
`opencode/opencode.json` through `home/opencode.nix`. Run `opencode-local` in
the directory containing the files you want to work with. It opens or reuses
an SSH tunnel to `spenser@192.168.4.209`, forwarding client loopback port 11435
to the desktop's loopback port 11435. This is the desktop's separate Qwen
Ollama instance; port 11434 belongs to an older instance.

The launcher uses `~/.ssh/id_ed25519_desktop` with key authentication and checks
that `qwen3.8:27b` is available before starting OpenCode. Keys are never copied
into the Nix store. On another device, provision its authorized SSH key and
set `OPENCODE_OLLAMA_SSH_IDENTITY` if it has a different filename. Set
`OPENCODE_OLLAMA_SSH_HOST` to use another SSH hostname, such as a VPN address.
SSH host keys must already be trusted and encrypted private keys unlocked in
an SSH agent; the launcher does not prompt for passwords. The desktop must be
awake and reachable over the LAN or a private VPN.

Only the `home` model provider is enabled, including for background model
tasks. The custom model explicitly advertises image input and attachments to
OpenCode, matching Qwen's vision support. The configured context is 32768
tokens, matching the running server at
setup, with up to 8192 output tokens. Session sharing is disabled. Tool actions
request approval; web fetch and search are denied. These permissions are
application controls, not an OS sandbox. Approved shell commands can still
access the network. Files and tools
live on the client; model context is sent to the desktop. No server settings
are changed by this setup.

The tunnel is shared between launches and supervised by `autossh`. SSH
keepalives detect an unresponsive connection after roughly 90 seconds while
the client is awake; autossh then reconnects, retrying with backoff while the
desktop or network is unavailable. After sleep or a network change, future
requests can recover once the tunnel returns; an interrupted generation may
still need to be retried. Reconnection requires the SSH key to remain usable
(including an unlocked SSH agent for an encrypted key).

The supervisor PID, SSH control socket, lock, and `ollama-autossh.log` live under
`~/.cache/opencode` (or `$XDG_CACHE_HOME/opencode`). The supervisor continues
running after OpenCode exits, including if the launch health check fails.
Run `opencode-local --stop-tunnel` to stop both the supervisor and tunnel;
this affects all sessions sharing it. The first launch with autossh replaces
any tunnel left by the older launcher. Stop the tunnel before changing the SSH
host or identity environment variables. Plain `opencode` uses the same
configuration but expects the tunnel to be running already. OpenCode updates
are managed by the pinned Nix package rather than its self-updater.

## Install

### Bazzite x86-64

Bazzite needs a host-visible, persistent `/nix` before Home Manager activation.
On the tested Bazzite 44 Kinoite host, `/etc/ostree/prepare-root.conf` preserves
the composefs and read-only sysroot settings and adds `[root] transient = true`.
The override is tracked with `rpm-ostree initramfs-etc`, and the host is rebooted
and checked before installing Nix. The full sequence and boot rollback are in
[the migration checkpoint log](BAZZITE_NIX_MIGRATION_PLAN.md).

Install Nix with the Determinate `ostree` planner, reviewing its proposed
changes before accepting:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install ostree
```

Reboot and confirm that `/nix` is mounted read/write from persistent
`/var/home/nix`, `nix --version` works, and `nix run nixpkgs#hello` succeeds in
a normal host shell. Back up or move aside existing configuration paths that
Home Manager will replace. In particular, an old `~/.config/fish` or
`~/.config/kitty` symlink into this repository must be moved before activation;
otherwise Home Manager could write links through it into the checkout. Keep
the old links and files for rollback. The tested host backup and rollback
script are recorded in the checkpoint log.

From this checkout, run:

```sh
./install.sh
```

On Bazzite, the script refuses to install Nix through the ordinary multi-user
installer. It requires the writable `/nix` mount backed by `/var/home/nix`, runs
`./verify.sh`, builds the Linux activation package without a `result` symlink,
dry runs that exact generation's activation, and then activates it. If the dry
run finds collisions, move those paths aside after backing them up and rerun
the script. The tested first cutover used this built-generation activation
method; later updates can also use this command from the checkout:

```sh
home-manager switch --flake 'path:.#spenser@linux'
```

Home Manager's Fish startup sources the Determinate Nix profile when present
and puts `~/.nix-profile/bin` first, so fresh shells use the managed tools even
when an older desktop session still carries Mise paths.

### Apple Silicon macOS and other x86-64 Linux

Run `./install.sh`. When necessary, the script installs Nix using the official
installer. It then activates the matching flake target with Home Manager. The
first run uses Home Manager's `nix run` bootstrap; subsequent runs use the
`home-manager` command installed by this configuration.

Kitty and Thunderbird are installed on macOS through Homebrew; fonts and Codex
CLI are installed by Home Manager. On a machine with Homebrew installed, run:

```sh
brew bundle --file Brewfile
```

### Neovim runtime state

Home Manager links `~/.config/nvim` into the read-only Nix store. Lazy.nvim
therefore stores its writable lockfile at Neovim's data directory
(`~/.local/share/nvim/lazy-lock.json` by default), seeded from the repository's
`nvim/lazy-lock.json` on first launch. Plugin installs and updates can write
there without changing the managed configuration. To persist intentional
plugin version changes in the setup, copy that runtime lockfile back to the
repository before rebuilding. Later activations preserve the runtime lockfile.

### Desktop keyboard configuration

The `spenser@linux-kde` target imports pinned Plasma Manager and `home/kde.nix`.
It maps Caps Lock to Escape and Ctrl+Alt+T to `/usr/bin/kitty`, disabling the
Konsole launcher shortcut. Install Kitty through the host package manager first.
Only these declared settings are managed; the rest of the desktop settings are
preserved. Keyboard options are set to `caps:escape`, replacing other XKB options.

`./install.sh` and `./verify.sh` select this target when `XDG_CURRENT_DESKTOP`
contains `KDE`. In SSH or other sessions without that variable, select it explicitly:

```sh
home-manager switch --flake 'path:.#spenser@linux-kde'
```

Log out and back in if Plasma has not picked up the updated keyboard settings.
The generic `spenser@linux` and macOS targets do not manage desktop shortcuts.
Other desktops would need their own modules:

| Desktop | Caps Lock to Escape | Ctrl+Alt+T launches Kitty |
| --- | --- | --- |
| KDE Plasma (including this Fedora host) | Plasma Manager `programs.plasma.input.keyboard.options = [ "caps:escape" ];` | Plasma Manager `programs.plasma.hotkeys.commands` with `keys = [ "Ctrl+Alt+T" ];` and a Kitty executable path |
| GNOME | Home Manager `dconf.settings`, `org/gnome/desktop/input-sources` `xkb-options = [ "caps:escape" ];` | GNOME custom keybinding via `dconf.settings` |
| macOS | Native modifier-key setting, or a separate managed remapping tool | A separate launcher/shortcut tool with a managed configuration |

References: [Plasma Manager options](https://nix-community.github.io/plasma-manager/options.html),
[Home Manager dconf settings](https://nix-community.github.io/home-manager/options/home-manager/dconf.html).

## Verify

Run the repository-local verification command before committing changes to the
Home Manager or Neovim configuration:

```sh
./verify.sh
```

It evaluates all three Home Manager targets, builds the current host
without creating a `result` symlink, validates the Lazy lock file, and checks
the Nix-wrapped Neovim tools and parsers against the built Home Manager XDG data
tree without activating it or loading Lazy's runtime state.

## Build without activating

On Apple Silicon macOS:

```sh
nix build path:.#homeConfigurations."spenser@macos".activationPackage
```

On x86-64 Linux:

```sh
nix build path:.#homeConfigurations."spenser@linux".activationPackage
```

Using `path:.` makes local Jujutsu working-copy files visible to Nix before the
change is committed. After the configuration is committed, `.#...` works too.

Build before activation to catch evaluation and package errors. The current
macOS profile can then be activated with:

```sh
home-manager switch --flake 'path:.#spenser@macos'
```
