# Interactive Fish configuration embedded by Home Manager.
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim +Man!"

fish_add_path ~/.local/bin
fish_add_path ~/.cargo/bin
fish_add_path ~/.npm-global/bin

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

function rgi --description 'Interactive ripgrep with fzf + bat preview'
    set -l rg_prefix 'rg --column --line-number --no-heading --color=always --smart-case'
    set -l initial_query (string join ' ' $argv)

    fzf \
        --ansi \
        --disabled \
        --query "$initial_query" \
        --prompt 'rg> ' \
        --delimiter ':' \
        --header 'Enter: print  Ctrl-O: open in nvim  Ctrl-F: fuzzy-filter' \
        --bind "start:reload:sleep 0.1; $rg_prefix {q} || true" \
        --bind "change:reload:sleep 0.1; $rg_prefix {q} || true" \
        --bind 'ctrl-f:unbind(change,ctrl-f)+change-prompt(fzf> )+enable-search+clear-query' \
        --bind 'ctrl-o:become(nvim +{2} {1})' \
        --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' \
        --preview-window 'right,60%,border-left,+{2}+3/3,~3'
end

bind -M insert \t atuin_or_complete
bind -M insert \cn accept-autosuggestion
set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
set -gx CARAPACE_EXCLUDES jj
carapace _carapace fish | source
COMPLETE=fish jj | source
