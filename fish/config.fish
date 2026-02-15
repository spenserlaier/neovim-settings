if status is-interactive
# Commands to run in interactive sessions can go here
starship init fish | source
set -g fish_key_bindings fish_vi_key_bindings
atuin init fish --disable-up-arrow | source
# use z instead of cd automatically
zoxide init fish | source
# make 'cd' behave like z
alias cd="z"
# bind atuin search to jj
bind -M insert \t _atuin_search
end
