# Commands shared by the legacy config and Home Manager's generated config.
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim +Man!"

fish_add_path ~/.local/bin
fish_add_path ~/.local/share/mise/shims
fish_add_path ~/.cargo/bin
fish_add_path ~/.npm-global/bin
fish_add_path ~/.pyenv/bin

# Language runtime managers are optional during the Nix migration.
if type -q mise
    mise activate fish | source
end

set -g fish_key_bindings fish_vi_key_bindings

# Use z instead of cd automatically.
zoxide init fish | source
alias cd="z"

set -gx FZF_DEFAULT_OPTS "--bind 'ctrl-j:down,ctrl-k:up'"
alias cat="bat"

function ls
    command eza --hyperlink --icons=auto $argv
end

function nvim
    # If arguments are passed (e.g., nvim filename.txt), just open it normally.
    if count $argv > /dev/null
        command nvim $argv
    else
        set file (fzf)
        if test -n "$file"
            command nvim $file
        end
    end
end

function atuin_or_complete
    set cmd (commandline -b)
    if test -z "$cmd"
        _atuin_search
    else
        commandline -f complete
    end
end

if type -q xcrun
    set -gx SDKROOT (xcrun --show-sdk-path)
end

set -gx PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
if type -q pyenv
    pyenv init - | source
    pyenv virtualenv-init - | source
end

bind -M insert \t atuin_or_complete
set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
carapace _carapace fish | source
