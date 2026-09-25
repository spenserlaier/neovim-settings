#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    home_target='spenser@macos'
    nix_install_args=()
    ;;
  Linux-x86_64)
    home_target='spenser@linux'
    nix_install_args=(--daemon)
    ;;
  *)
    echo "Unsupported installation host: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

is_bazzite=false
if [[ "$home_target" == 'spenser@linux' && -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" == bazzite || "${VARIANT_ID:-}" == bazzite ]]; then
    is_bazzite=true
  fi
fi

if [[ "$is_bazzite" == true ]]; then
  nix_profile='/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  if ! command -v nix >/dev/null 2>&1 && [[ -r "$nix_profile" ]]; then
    # shellcheck disable=SC1090
    source "$nix_profile"
  fi

  if ! command -v nix >/dev/null 2>&1; then
    echo 'Bazzite requires the Determinate ostree Nix installation before Home Manager activation.' >&2
    echo 'Follow the Bazzite instructions in NIX.md; the ordinary multi-user installer is not suitable here.' >&2
    exit 1
  fi

  nix_mount="$(findmnt -n -T /nix -o TARGET 2>/dev/null || true)"
  nix_mount_options="$(findmnt -n -T /nix -o OPTIONS 2>/dev/null || true)"
  if [[ "$nix_mount" != /nix || ",${nix_mount_options}," != *,rw,* || ! /nix -ef /var/home/nix ]]; then
    echo 'Bazzite needs a writable host /nix mount backed by /var/home/nix.' >&2
    echo 'Check nix.mount and the Determinate ostree installation before activating Home Manager.' >&2
    exit 1
  fi

  "$repo_root/verify.sh"
  flake_attr="path:$repo_root#homeConfigurations.\"$home_target\".activationPackage"
  generation="$(nix build --no-link --print-out-paths "$flake_attr" | tail -n 1)"
  DRY_RUN=1 "$generation/activate"
  env -u DRY_RUN "$generation/activate"
  echo "Home Manager configuration activated: $home_target"
  exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
  echo 'Installing Nix using the official multi-user installer...'
  curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install |
    sh -s -- "${nix_install_args[@]}"

  nix_profile='/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  if [[ -r "$nix_profile" ]]; then
    # shellcheck disable=SC1090
    source "$nix_profile"
  fi
fi

if ! command -v nix >/dev/null 2>&1; then
  echo 'Nix was installed, but is not available in this shell.' >&2
  echo 'Open a new shell and run ./install.sh again.' >&2
  exit 1
fi

flake="path:$repo_root#$home_target"

if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "$flake"
else
  nix run home-manager/master -- switch --flake "$flake"
fi

echo "Home Manager configuration activated: $home_target"
