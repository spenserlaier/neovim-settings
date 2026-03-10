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
alias ls="eza --hyperlink"
function atuin_or_complete
    set cmd (commandline -b)
    if test -z "$cmd"
        _atuin_search
    else
        commandline -f complete
    end
end

bind -M insert \t atuin_or_complete
end
