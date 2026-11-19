#!/usr/bin/env fish

# Window IDs are stable for their lifetime; neighboring IDs get different accents.
set palette '#f38ba8' '#a6e3a1' '#f9e2af' '#89b4fa' '#cba6f7' '#fab387' '#94e2d5' '#f5c2e7'
for window_id in (tmux list-windows -a -F '#{window_id}' | sort -u)
    set number (string sub -s 2 -- "$window_id")
    set index (math "$number % "(count $palette)" + 1")
    set accent $palette[$index]
    tmux set-option -w -t "$window_id" @window_accent "$accent"
    tmux set-option -w -t "$window_id" pane-active-border-style "fg=$accent"
end
