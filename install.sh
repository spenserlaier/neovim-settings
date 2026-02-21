#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"  # ensure current shell sees it
if ! command -v mise >/dev/null; then
  curl https://mise.run | sh
fi

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

# Fish
mkdir -p ~/.config/fish
#ln -sf "$DOTFILES/fish/config.fish" ~/.config/fish/config.fish
# The line below symlinks the whole fish directory, which also installs functions
# avoid nesting issues by removing existing dir 
if [ -e ~/.config/fish ]; then
  rm -rf ~/.config/fish
fi
ln -s "$DOTFILES/fish" ~/.config/fish
# Mise
ln -sf "$DOTFILES/mise/.mise.toml" ~/.mise.toml
mise install

echo "Dotfiles and tools installed!"


