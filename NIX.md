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

Starship uses the Nix-packaged `jj-starship` custom module for both Jujutsu and
Git repositories. The built-in Git modules are disabled so colocated Jujutsu
workspaces show one version-control segment. The package is pinned by this
repository's nixpkgs lock file; no separate flake input is needed.

Direnv and nix-direnv are managed natively and integrated with Fish. Pyenv and
Mise are not part of this configuration; project runtimes belong in development
shells instead.

Tmux is managed through its native module. `tmux/common.conf` contains the shared
configuration, while Home Manager supplies pinned Resurrect and Continuum
plugins.

Ranger is installed by Nix, and Home Manager links the repository's existing
Ranger configuration into `~/.config/ranger`.

Home Manager links the repository's Kitty configuration into `~/.config/kitty`.
Kitty itself and the preferred fonts remain part of the optional macOS Homebrew
layer.
Kitty loads the Catppuccin Mocha palette from `kitty/current-theme.conf`. Its
ANSI colors are used by shell programs, including `jj-starship`; tmux does not
define a separate palette. Neovim selects Catppuccin independently in
`nvim/init.lua`. Kitty maps the Jujutsu empty-description symbol (`∅`) to
FiraCode Nerd Font Mono because CaskaydiaCove does not contain that glyph.

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

Kitty and the preferred fonts are installed on macOS through Homebrew. On a
machine with Homebrew installed, install them with:

```sh
brew bundle --file Brewfile
```

## Verify

Run the repository-local verification command before committing changes to the
Home Manager or Neovim configuration:

```sh
./verify.sh
```

It evaluates both supported Home Manager targets, builds the current host
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
