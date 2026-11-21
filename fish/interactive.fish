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

alias cat="bat"

function ls
    command eza --hyperlink --icons=auto $argv
end

function nvim
    # If arguments are passed (e.g., nvim filename.txt), just open it normally.
    if count $argv > /dev/null
        command nvim $argv
    else
        set -l mode_file (mktemp -t nvim-picker.XXXXXXXXXX)
        or return 1
        set -lx VI_FZF_MODE_FILE "$mode_file"
        printf insert > "$mode_file"
        __nvim_picker
        set -l picker_status $status
        command rm -f -- "$mode_file"
        return $picker_status
    end
end

function __nvim_picker --description 'Toggle filename and content search before opening Neovim'
    set -l mode files
    set -l query ''
    while true
        set -l selected
        set -l picker_status
        if test "$mode" = files
            set selected (__nvim_files | __file_picker \
                --query "$query" --prompt 'open> ' --tiebreak=index --print-query --expect=ctrl-g \
                --header 'FILES · Enter: open · Ctrl-G: search contents · Recent files first · Ctrl-/: preview')
            set picker_status $status
        else
            set selected (__rgi pick "$query")
            set picker_status $status
        end
        # fzf returns 1 when Ctrl-G is pressed with no filename matches.
        if test (count $selected) -ge 2; and test "$selected[2]" = ctrl-g
            set query "$selected[1]"
            if test "$mode" = files
                set mode contents
            else
                set mode files
            end
        else if test $picker_status -eq 0; and test (count $selected) -ge 3
            if test "$mode" = files
                command nvim -- "$selected[3]"
            else
                set -l match (string split -m 2 ':' -- "$selected[3]")
                command nvim +$match[2] -- "$match[1]"
            end
            return $status
        else
            return $picker_status
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

function __nvim_files --description 'Project files, with existing Neovim history first'
    set -l files (rg --files --hidden --no-ignore-exclude --glob '!.git/**')
    # Read ShaDa without loading plugins or changing the history on disk.
    set -l recent (command nvim --headless -u NONE -i NONE \
        -c 'lua pcall(vim.cmd.rshada, {args = {vim.fn.stdpath("state") .. "/shada/main.shada"}}); for _, file in ipairs(vim.v.oldfiles) do io.write(vim.fn.fnamemodify(file, ":."), "\n") end' \
        -c 'qa!' 2>/dev/null)
    begin
        for file in $recent
            if contains -- "$file" $files
                printf '%s\n' "$file"
            end
        end
        if test (count $files) -gt 0
            printf '%s\n' $files
        end
    end | awk '!seen[$0]++'
end

function __file_picker --description 'Shared filename picker with preview'
    vi_fzf \
        --preview 'bat --color=always --style=numbers -- {}' \
        --preview-window 'right,60%,border-left,<100(down,60%,border-top)' \
        --bind 'ctrl-/:toggle-preview' $argv
end

function rgi --description 'Interactive ripgrep with fzf + bat preview'
    __rgi print $argv
end

function __rgi --description 'Content picker with caller-specific Enter action'
    set -l mode $argv[1]
    set -e argv[1]
    set -l rg_prefix 'rg --column --line-number --no-heading --color=always --smart-case --hidden --no-ignore-exclude --glob "!.git/**"'
    set -l initial_query (string join ' ' $argv)
    set -l header 'Enter: print · Ctrl-O: open in nvim · Ctrl-F: fuzzy-filter · Ctrl-/: preview'
    set -l options
    if test "$mode" = open
        set header 'Enter: open · Ctrl-F: fuzzy-filter · Ctrl-/: preview'
        set options --bind 'enter:become(nvim +{2} -- {1})'
    else if test "$mode" = pick
        set header 'CONTENTS · Enter: open · Ctrl-G: search files · Ctrl-F: fuzzy-filter · Ctrl-/: preview'
        set options --print-query --expect=ctrl-g
    end

    vi_fzf \
        --ansi \
        --disabled \
        --query "$initial_query" \
        --prompt 'rg> ' \
        --delimiter ':' \
        --header "$header" \
        --bind "start:reload:sleep 0.1; $rg_prefix {q} || true" \
        --bind "change:reload:sleep 0.1; $rg_prefix {q} || true" \
        --bind 'ctrl-f:unbind(change,ctrl-f)+change-prompt(fzf> )+enable-search+clear-query' \
        --bind 'ctrl-o:become(nvim +{2} -- {1})' \
        --bind 'ctrl-/:toggle-preview' \
        --preview 'bat --color=always --style=numbers --highlight-line {2} -- {1}' \
        --preview-window 'right,60%,border-left,+{2}+3/3,~3,<100(down,60%,border-top)' $options
end

function fdi --description 'Fuzzy file picker with fzf + bat preview'
    set -l initial_query (string join ' ' $argv)

    rg --files --hidden --no-ignore-exclude --glob '!.git/**' | __file_picker \
        --query "$initial_query" \
        --prompt 'files> ' \
        --header 'Enter: print · Ctrl-O: open in nvim · Ctrl-/: preview' \
        --bind 'ctrl-o:become(nvim -- {})'
end

function __tmux_sessionizer
    fish "$__fish_config_dir/tmux-sessionizer.fish" $argv
    commandline -f repaint
end

function __tmux_foreground_command --argument-names line
    # A trailing ampersand backgrounds the command when it has an even number of preceding backslashes.
    not string match -qr '(^|[^\\\\])(?:\\\\\\\\)*&\s*$' -- "$line"
end

function __tmux_task_start --on-event fish_preexec
    if not set -q TMUX[1] TMUX_PANE[1]; or set -q fish_private_mode
        return
    end
    if __tmux_foreground_command "$argv[1]"
        "$__fish_config_dir/../tmux/task-indicator" task-start
    end
end

function __tmux_note_command --on-event fish_postexec
    set -l command_status $status
    if not set -q TMUX[1] TMUX_PANE[1]; or test -z "$TMUX_PANE"; or set -q fish_private_mode
        return
    end
    if __tmux_foreground_command "$argv[1]"
        "$__fish_config_dir/../tmux/task-indicator" task-end "$command_status"
    end

    # Tokenize without evaluating the command. Retain only names and known subcommands.
    set -l words
    printf '%s\n' "$argv[1]" | read --tokenize --array words
    while contains -- "$words[1]" command builtin exec time env sudo
        set -e words[1]
    end
    if string match -q '*=*' -- "$words[1]"
        return
    end
    set -l program (string replace -r '^.*/' '' -- "$words[1]")
    if not string match -qr '^[a-zA-Z0-9_.][a-zA-Z0-9_.+-]*$' -- "$program"
        return
    end
    set -l label "$program"
    switch "$program:$words[2]"
        case git:diff git:log git:status git:add git:commit git:push git:pull git:fetch git:switch git:rebase \
            jj:diff jj:log jj:status jj:describe jj:new jj:edit jj:rebase jj:git \
            nix:build nix:develop nix:run nix:flake nix:fmt nix:eval \
            cargo:build cargo:check cargo:run cargo:test \
            npm:run npm:test npm:install pnpm:run pnpm:test pnpm:install \
            uv:run uv:sync uv:pip
            set label "$program $words[2]"
    end
    command tmux set-option -qp -t "$TMUX_PANE" @last_shell_command "$label" 2>/dev/null
end

# Match the tmux prefix shortcuts when starting from a plain Fish shell.
for mode in insert default
    bind -M $mode \caf '__tmux_sessionizer --sessions'
    bind -M $mode \caF __tmux_sessionizer
end

bind -M insert \t atuin_or_complete
bind -M insert \cn accept-autosuggestion
set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
set -gx CARAPACE_EXCLUDES jj
carapace _carapace fish | source
COMPLETE=fish jj | source
