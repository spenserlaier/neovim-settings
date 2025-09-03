#!/usr/bin/env bash
set -e

# Get the directory of this script, even if called from elsewhere
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Neovim
mkdir -p ~/.config
ln -sf "$DOTFILES/nvim" ~/.config/nvim

# Kitty
mkdir -p ~/.config/kitty
ln -sf "$DOTFILES/kitty/kitty.conf" ~/.config/kitty/kitty.conf

# Tmux
ln -sf "$DOTFILES/tmux/tmux.conf" ~/.tmux.conf

echo "Dotfiles installed!"

