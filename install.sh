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
