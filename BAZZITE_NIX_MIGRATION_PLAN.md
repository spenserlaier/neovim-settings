# Bazzite Nix migration: checkpoint record

Updated 2026-09-25. This records the checkpoints and reboots used for the
Bazzite migration. The guarded `./install.sh` now requires the tested,
host-visible Determinate Nix installation before activating Home Manager on
Bazzite. See [NIX.md](NIX.md) for the reusable installation path.

## Current state

- Host: Bazzite 44 Kinoite, x86_64. After checkpoint 1, the composefs root
  is writable with a transient upper layer under tmpfs-backed `/run`.
  `/etc` and `/var` remain persistent Btrfs mounts. Determinate Nix is now
  installed; `/nix` is mounted from persistent `/home/nix`.
- The primary dotfiles checkout is a Jujutsu working copy based on the local
  `master` branch. Home Manager owns the live Fish, Neovim, Kitty, and Ranger
  links in the Nix store; the original links and files remain in the checkpoint
  4 backup.
- Local `master` contains the tested migration and the original checkpoint
  history. The `nix-migration` branch remains as a local reference to the
  tested cutover. Its temporary `/tmp/neovim-settings-nix-migration` worktree
  was used for isolated verification and branch reconciliation.
- Bazzite's `/usr/lib/ostree/prepare-root.conf` contains:

  ```ini
  [composefs]
  enabled = yes
  [sysroot]
  readonly = true
  ```

  The tracked `/etc/ostree/prepare-root.conf` override now adds
  `[root] transient = true` while preserving these settings.

## Checkpoint 1: prepare the transient-root boot

Goal: allow an ephemeral `/nix` mount point while retaining Bazzite's existing
composefs and read-only sysroot settings. This changes early boot behavior;
schedule the reboot for a time when work can be interrupted. First record the
current deployment with `rpm-ostree status` and confirm an older deployment is
available in the boot menu. Do not continue if the host's current settings have
changed since the state recorded above.

Create `/etc/ostree/prepare-root.conf` with the existing settings **and** the
new root setting:

```ini
[composefs]
enabled = yes
[sysroot]
readonly = true
[root]
transient = true
```

Track it in the initramfs with
`rpm-ostree initramfs-etc --track=/etc/ostree/prepare-root.conf`, inspect the
queued deployment, then reboot. Do not install Nix in the same session before
checking the new boot. OSTree documents that `root.transient=true` requires
composefs and uses a tmpfs upper layer; `/etc` and `/var` remain persistent by
default. If the new deployment does not boot, use the previous deployment from
the boot menu and investigate before retrying.

After reboot, verify the effective configuration, the new root mount, and the
live dotfiles:

```sh
cat /etc/ostree/prepare-root.conf
findmnt -T / -o TARGET,SOURCE,FSTYPE,OPTIONS
rpm-ostree status
readlink -f ~/.config/fish
fish --version
```

The root mount should now be writable with a transient overlay upper layer;
seeing `overlay` alone is insufficient because the current read-only composefs
root also reports that filesystem type. Record the actual mount options here.

**Checkpoint 1 result (2026-09-25): passed after reboot.** The booted
`rpm-ostree` deployment tracks `/etc/ostree/prepare-root.conf` in the
initramfs; the previous deployment remains available.
The override has the exact three sections shown above. On the host,
`findmnt -T /` reports `composefs`/`overlay` with `rw` and
`upperdir=/run/ostree/.private/root/upper`; `/run` is `tmpfs`. `/etc` and
`/var` are writable Btrfs mounts. The live Fish link still resolves to this
checkout and Fish reports version 4.9.3. Nix was not installed at this point.

## Checkpoint 2: install host-visible Nix

Only after checkpoint 1 passes, run the Determinate installer with its `ostree`
planner. Omit `--no-confirm` so its proposed changes can be inspected before
accepting. Its current ostree planner creates persistent `/var/home/nix`, mounts
it at host-visible `/nix`, and configures systemd services, Nix profiles, and
SELinux policy when applicable. Review the actual plan displayed by the
installer; its behavior can change with releases.

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install ostree
```

If the installer fails, stop. Follow its own rollback guidance and inspect
`nix.mount`/`nix-directory.service`; do not run the ordinary `./install.sh` as
a fallback. When installation succeeds, verify now and again after reboot:

```sh
findmnt -T /nix -o TARGET,SOURCE,FSTYPE,OPTIONS
nix --version
nix run nixpkgs#hello
```

Confirm `/nix` is visible to a normal host shell and backed by persistent
`/var/home/nix`. This is the property required for Home Manager links and
programs to work outside a Nix user namespace.

**Checkpoint 2 result (2026-09-25): passed after reboot.** The installer
reported success. On the host, `/nix` is a writable
Btrfs mount sourced from `/home/nix` (the same persistent location as
`/var/home/nix`). `nix-daemon.service` and `nix.mount` are active.
`nix --version` reports Determinate Nix 3.22.5 / Nix 2.35.2, and
`nix run nixpkgs#hello` printed `Hello, world!`.

After reboot, the host still mounts `/nix` read/write from
`/dev/nvme0n1p3[/home/nix]`; `nix.mount` and `nix-daemon.service` are active.
`nix --version` still reports Determinate Nix 3.22.5 / Nix 2.35.2, and
`nix run nixpkgs#hello` prints `Hello, world!`. The root overlay remains
writable with its upper layer under `/run/ostree/.private/root/upper`, and the
booted deployment still tracks `/etc/ostree/prepare-root.conf`.

The installer placed a Fish startup file in `/etc/fish/conf.d`, but the
installed Fish binaries use `/usr/etc/fish` or Homebrew's Fish configuration
directory, so they did not read it. The live `fish/config.fish` now sources
Nix's Fish profile script when present. Fresh Fish processes find `nix`.
After reboot, a fresh Fish process still finds `nix`, and the live Fish link
still resolves to this checkout.

## Checkpoint 3: build without activating

Use the separate `nix-migration` worktree. Verify that it includes commit
`5e06706` and has no unexpected changes. Run `./verify.sh` from that worktree;
it evaluates both flake targets and builds/checks the Linux Home Manager
generation without switching the live dotfiles. If it fails, fix the branch
first. No Home Manager activation at this checkpoint.

**Checkpoint 3 result (2026-09-25): passed.** The separate worktree contains
`5e06706` and is clean at `eb4a347`. `./verify.sh` evaluates both Home Manager
targets, builds the Linux generation without a result link, validates
`nvim/lazy-lock.json`, and checks the built Neovim runtime (14 parsers and 18
executables). The first run exposed a test setup issue: Home Manager's Neovim
plugins live in the generated XDG data tree, which is not yet linked into the
live home. Commit `eb4a347` points the isolated Neovim check at that built tree.
No Home Manager activation was run; the live configuration links still resolve
to this checkout.

## Checkpoint 4: controlled Home Manager cutover

Before activation, inventory and back up the existing live links and any
non-link files Home Manager would replace. In particular inspect Fish, Neovim,
Kitty, Ranger, Atuin, Starship, Git, Jujutsu, and tmux paths. Resolve activation
collisions deliberately; do not switch this repo checkout from `master` as a
shortcut. Build a tested activation command and a concrete rollback procedure
for this machine, then activate at a convenient time. Check a fresh Fish shell,
`jj` completion, Neovim startup/LSP/parsers, tmux, and Kitty before treating
the cutover as successful.

**Checkpoint 4 result (2026-09-25): passed.** The original links and
conflicting files were backed up under
`~/.local/state/nix-migration-backups/checkpoint4-20260925/`. Its `original/`
directory preserves the old links and files; `content/` snapshots the old
Fish, Kitty, Neovim, and Ranger directories; `displaced/` contains the moved
live paths. The old Fish universal variables were preserved in a real
`~/.config/fish` directory, then the obsolete Mise shims entry was removed
from `fish_user_paths`. The original Git, Jujutsu, and tmux config files were
moved aside so their Home Manager equivalents take effect. The unrelated
`~/.config/git/ignore` and `~/.config/jj/repos` remain in place.

`./verify.sh` and an activation dry run passed for the final configuration.
The tested activation command was
`/nix/store/6rbadi18xa0nawf4hr73ilicwfwgvd95-home-manager-generation/activate`;
it completed successfully and is the current Home Manager generation. No
`./install.sh` run or Git branch switch was involved. Fresh Fish resolves
Neovim, Jujutsu, and tmux from `~/.nix-profile/bin` and Nix from the
Determinate profile; `complete -C 'jj lo'` offers `log`. Live Neovim starts,
loads Nix Tree-sitter and the Lua parser, and attaches `lua_ls` to a Lua file.
An isolated tmux server loaded the new config with `C-a` prefix and Continuum
enabled. Kitty parsed the new config with zero errors. Git and Jujutsu report
the expected user name. The first activation noted a pre-existing failed
rootless `docker.service` user unit during systemd reload; activation still
completed, and the final update completed without that warning.

For rollback, run
`bash ~/.local/state/nix-migration-backups/checkpoint4-20260925/rollback.sh`
in a host shell, then open a fresh shell and restart Kitty/tmux. The script
moves the active Home Manager links into `activated-on-rollback/` and restores
the original links and files from `original/`. It leaves the Nix installation
and Home Manager generation available for diagnosis.

## Checkpoint 5: repository cleanup

Update `install.sh` and `NIX.md` with the tested Bazzite path and a guard so
the generic Linux installer cannot accidentally use the ordinary multi-user
installer here. After the host has run well, reconcile branch history and make
the tested `nix-migration` branch the new `master`. Do not merge/promote it
merely because Nix installed successfully.

**Checkpoint 5 result (2026-09-25): passed locally.** `install.sh` now detects
Bazzite and refuses to run the ordinary multi-user Nix installer. It requires
the writable host `/nix` mount backed by `/var/home/nix`, runs `./verify.sh`,
builds the matching activation package, dry runs it, and then activates it.
The script's executable bit was fixed, and `./install.sh` completed successfully
on this host. [NIX.md](NIX.md) documents the tested Bazzite path and the
checkpoint 4 backup/rollback location.

The original `master` history was merged into `nix-migration`. The Fish merge
conflict was resolved in favor of the tested Home Manager configuration.
Local `master` was fast-forwarded to the tested result, and the primary
Jujutsu working copy was advanced to it. The temporary pre-cutover Fish change
is retained in Jujutsu history and the checkpoint backup; its behavior is now
provided by `home/common.nix`.

## References

- OSTree prepare-root options: https://ostreedev.github.io/ostree/man/ostree-prepare-root.html
- Determinate ostree planner: https://github.com/DeterminateSystems/nix-installer/blob/main/src/planner/ostree.rs
- Fedora Nix guidance for rpm-ostree: https://fedoraproject.org/wiki/Changes/Nix_package_tool
- Installer failure example on an ostree host: https://github.com/DeterminateSystems/nix-installer/issues/1771
