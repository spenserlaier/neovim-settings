#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

echo "Evaluating Home Manager targets..."
nix eval --raw 'path:.#homeConfigurations."spenser@macos".activationPackage.drvPath' >/dev/null
nix eval --raw 'path:.#homeConfigurations."spenser@linux".activationPackage.drvPath' >/dev/null

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    home_target='spenser@macos'
    ;;
  Linux-x86_64)
    home_target='spenser@linux'
    ;;
  *)
    echo "Unsupported verification host: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

echo "Building $home_target without creating a result symlink..."
generation="$({ nix build --no-link --print-out-paths "path:.#homeConfigurations.\"$home_target\".activationPackage"; } | tail -n 1)"

echo "Checking tracked data files..."
jq empty nvim/lazy-lock.json

echo "Checking the Nix-wrapped Neovim runtime..."
# Home Manager installs Neovim plugins in its XDG data tree at activation.
# Point this isolated check at the built tree so it can inspect those plugins
# without changing the live home directory.
XDG_DATA_HOME="$generation/home-files/.local/share" \
  "$generation/home-path/bin/nvim" --headless -u NORC -l scripts/verify-neovim.lua

echo "Verification passed."
