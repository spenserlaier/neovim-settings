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

Direnv and nix-direnv are managed natively and integrated with Fish. Pyenv and
Mise are not part of this configuration; project runtimes belong in development
shells instead.

Tmux is managed through its native module. `tmux/common.conf` contains the shared
configuration, while Home Manager supplies pinned Resurrect and Continuum
plugins.

Ranger is installed by Nix, and Home Manager links the repository's existing
Ranger configuration into `~/.config/ranger`.

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

On Apple Silicon macOS or x86-64 Linux, run:

```sh
./install.sh
```

When necessary, the script installs Nix using the official multi-user installer.
It then activates the matching flake target with Home Manager. The first run
uses Home Manager's documented `nix run` bootstrap; subsequent runs use the
`home-manager` command installed by this configuration.

Kitty and the preferred fonts remain an optional macOS layer. On a machine with
Homebrew installed, install them separately with:

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
the Nix-wrapped Neovim tools and parsers without loading or modifying Lazy's
runtime state.

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
