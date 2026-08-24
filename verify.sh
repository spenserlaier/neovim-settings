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
"$generation/home-path/bin/nvim" --headless -u NONE -l scripts/verify-neovim.lua

echo "Verification passed."
