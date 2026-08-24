# Home Manager

This repository is migrating incrementally from the existing Homebrew, Mise,
and symlink installer to a flake-based Home Manager configuration.

The common module installs the command-line and editor packages. Home Manager
also owns the Git, Jujutsu, Atuin, and Starship configurations through their
native program modules. The TOML configuration files remain the source of truth
for Jujutsu, Atuin, and Starship; the small Git configuration is represented
directly in the Home Manager module.

Fish is managed through its native module. Shared interactive behavior lives in
`fish/interactive.fish`; Home Manager embeds that file in its generated Fish
configuration and generates the Atuin and Starship integrations. The legacy
`fish/config.fish` sources the same shared file and initializes those integrations
itself, so the pre-Nix installer remains usable during the migration.

Direnv and nix-direnv are managed natively and integrated with Fish. Pyenv has
been removed. Mise is no longer initialized or added to Fish's path, although
its legacy installer artifacts remain temporarily; its language runtimes are
not part of this Home Manager configuration.

Tmux is managed through its native module. `tmux/common.conf` contains the shared
configuration, while Home Manager supplies pinned Resurrect and Continuum
plugins. The legacy `tmux/tmux.conf` sources the same shared configuration and
retains TPM bootstrap support only for the pre-Nix installer.

Neovim is installed through its native module and is the default editor. Its
configuration is copied into the Nix store and linked at `~/.config/nvim`, while
native build and search dependencies are included in Neovim's wrapped runtime.
Lazy, Mason, and nvim-treesitter continue to manage plugins, development tools,
and parsers at runtime during this migration phase.

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
