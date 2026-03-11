#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"  # ensure current shell sees it
if ! command -v mise >/dev/null; then
  curl https://mise.run | sh
fi

# Install homebrew if necessary (installs additional software not available with mise)
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH immediately
  if [[ "$(uname -s)" == "Linux" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  else
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

# Get the directory of this script, even if called from elsewhere
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install additional software via Brewfile
brew bundle --file="$DOTFILES/Brewfile"
# Neovim
mkdir -p ~/.config
ln -sfn "$DOTFILES/nvim" ~/.config/nvim

# Create the directory neovim uses to store undo information persistently
mkdir -p ~/.local/state/nvim/undo


# Tmux
ln -sf "$DOTFILES/tmux/tmux.conf" ~/.tmux.conf

# Atuin
mkdir -p ~/.config/atuin
ln -sf "$DOTFILES/atuin/config.toml" ~/.config/atuin/config.toml

# Ranger
rm -rf ~/.config/ranger
ln -sfn "$DOTFILES/ranger" ~/.config/ranger
# Starship
ln -sfn "$DOTFILES/starship/starship.toml" ~/.config/starship.toml
# Kitty
rm -rf ~/.config/kitty
ln -sfn "$DOTFILES/kitty" ~/.config/kitty
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
# Git
GITCONFIG_SOURCE="$DOTFILES/git/.gitconfig"
GITCONFIG_DEST="$HOME/.gitconfig"

# Ensure source exists
if [ ! -f "$GITCONFIG_SOURCE" ]; then
  echo "Error: expected gitconfig at $GITCONFIG_SOURCE"
  exit 1
fi

# Backup existing gitconfig if it isn't already a symlink
if [ -e "$GITCONFIG_DEST" ] && [ ! -L "$GITCONFIG_DEST" ]; then
  BACKUP_PATH="$GITCONFIG_DEST.$(date +%Y%m%d%H%M%S).bak"
  echo "Backing up existing gitconfig → $BACKUP_PATH"
  mv "$GITCONFIG_DEST" "$BACKUP_PATH"
fi

# Create/update symlink
ln -sf "$GITCONFIG_SOURCE" "$GITCONFIG_DEST"

echo "Dotfiles and tools installed!"


