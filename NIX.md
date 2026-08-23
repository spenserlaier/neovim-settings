# Home Manager

This repository is migrating incrementally from the existing Homebrew, Mise,
and symlink installer to a flake-based Home Manager configuration.

The common module installs the command-line and editor packages. Home Manager
also owns the Git, Jujutsu, Atuin, and Starship configurations through their
native program modules. The TOML configuration files remain the source of truth
for Jujutsu, Atuin, and Starship; the small Git configuration is represented
directly in the Home Manager module.

Atuin and Starship's Home Manager Fish integrations remain disabled while the
existing Fish configuration initializes them. This avoids initializing either
program twice during the incremental migration.

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

Activation is intentionally deferred until the generated package manifest has
been reviewed and the existing Homebrew/Mise overlap has been considered.
