if status is-interactive
# Commands to run in interactive sessions can go here
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim +Man!"
fish_add_path ~/.local/bin
fish_add_path ~/.local/share/mise/shims
fish_add_path ~/.cargo/bin
fish_add_path ~/.npm-global/bin
fish_add_path ~/.pyenv/bin
mise activate fish | source
starship init fish | source
set -g fish_key_bindings fish_vi_key_bindings
atuin init fish --disable-up-arrow | source
# use z instead of cd automatically
zoxide init fish | source
# make 'cd' behave like z
alias cd="z"
alias cat="bat"
function ls
    command eza --hyperlink --icons $argv
end
function nvim
    # If arguments are passed (e.g., nvim filename.txt), just open it normally
    if count $argv > /dev/null
        command nvim $argv
    else
        # If no arguments, launch fzf and store the result
        set file (fzf)
        # If a file was actually selected (you didn't hit escape), open it
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
pyenv init - | source
pyenv virtualenv-init - | source

bind -M insert \t atuin_or_complete
end
