function codex
    if not set -q TMUX[1] TMUX_PANE[1]; or not isatty stdout
        command codex $argv
        return $status
    end

    set -l reader "$__fish_config_dir/../tmux/codex-status"
    set -l monitor ("$reader" start)
    command codex $argv
    set -l codex_status $status
    if set -q monitor[1]
        "$reader" stop "$monitor"
    end
    return $codex_status
end
