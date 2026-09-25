# Bazzite Nix migration: resume plan

Updated 2026-09-25. This is a checklist for future Codex sessions and for the
reboots required by the host installation. Stop at each checkpoint and record
the result here before continuing. Do not run this repository's current
`./install.sh` on Bazzite: it uses the standard Nix installer and immediately
activates Home Manager.

## Current state

- Host: Bazzite 44 Kinoite, x86_64. The root is a read-only composefs overlay;
  `/var` and `/home` are persistent. Nix and `/nix` are absent.
- The live dotfiles checkout is this directory, currently at `master` commit
  `163f42e` (Git HEAD detached because Jujutsu manages the working copy).
  `~/.config/fish`, `~/.config/nvim`, `~/.config/kitty`, and
  `~/.config/ranger` point into this checkout. Keep it on `master` during prep.
- Local Git branch `nix-migration` is at `5e06706`, one commit ahead of
  `origin/nix-migration`. That commit ports the Jujutsu completion fix into
  `fish/interactive.fish`; Fish syntax and `complete -C 'jj lo'` were checked.
  It has **not** been pushed.
- A separate worktree is currently at `/tmp/neovim-settings-nix-migration`.
  `/tmp` may be cleared by reboot. The *branch and commit* are stored in this
  repository's Git data and should persist. After reboot, run `git worktree
  list`; if the temporary worktree is gone, prune the stale entry and recreate
  a worktree from local branch `nix-migration` before doing branch work. Do not
  switch this live checkout to that branch.
- Bazzite's `/usr/lib/ostree/prepare-root.conf` currently contains:

  ```ini
  [composefs]
  enabled = yes
  [sysroot]
  readonly = true
  ```

  There is no `/etc/ostree/prepare-root.conf` override yet.

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

**Checkpoint 1 result:** pending.

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

**Checkpoint 2 result:** pending.

## Checkpoint 3: build without activating

Use the separate `nix-migration` worktree. Verify that it includes commit
`5e06706` and has no unexpected changes. Run `./verify.sh` from that worktree;
it evaluates both flake targets and builds/checks the Linux Home Manager
generation without switching the live dotfiles. If it fails, fix the branch
first. No Home Manager activation at this checkpoint.

**Checkpoint 3 result:** pending.

## Checkpoint 4: controlled Home Manager cutover

Before activation, inventory and back up the existing live links and any
non-link files Home Manager would replace. In particular inspect Fish, Neovim,
Kitty, Ranger, Atuin, Starship, Git, Jujutsu, and tmux paths. Resolve activation
collisions deliberately; do not switch this repo checkout from `master` as a
shortcut. Build a tested activation command and a concrete rollback procedure
for this machine, then activate at a convenient time. Check a fresh Fish shell,
`jj` completion, Neovim startup/LSP/parsers, tmux, and Kitty before treating
the cutover as successful.

**Checkpoint 4 result:** pending.

## Checkpoint 5: repository cleanup

Update `install.sh` and `NIX.md` with the tested Bazzite path and a guard so
the generic Linux installer cannot accidentally use the ordinary multi-user
installer here. After the host has run well, reconcile branch history and make
the tested `nix-migration` branch the new `master`. Do not merge/promote it
merely because Nix installed successfully.

## References

- OSTree prepare-root options: https://ostreedev.github.io/ostree/man/ostree-prepare-root.html
- Determinate ostree planner: https://github.com/DeterminateSystems/nix-installer/blob/main/src/planner/ostree.rs
- Fedora Nix guidance for rpm-ostree: https://fedoraproject.org/wiki/Changes/Nix_package_tool
- Installer failure example on an ostree host: https://github.com/DeterminateSystems/nix-installer/issues/1771
