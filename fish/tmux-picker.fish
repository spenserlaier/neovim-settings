#!/usr/bin/env fish

# Shared session/window picker and its read-only preview command.
set mode $argv[1]
if contains -- "$mode" --preview-session --preview-window
    set target "$argv[2]"
    if test "$mode" = --preview-session
        tmux list-windows -t "$target" -F '#{?window_active,▶, } #{window_index}: #{window_name} — #{pane_current_command}' 2>/dev/null
        # A trailing colon targets the session's active window and pane.
        set target "$target:"
        printf '\n'
    end
    tmux display-message -p -t "$target" '#{session_name} > #{window_index}: #{window_name} | #{pane_current_command}
#{pane_current_path}' 2>/dev/null
    printf '\n'
    tmux capture-pane -ep -t "$target" 2>/dev/null
    exit $status
end

set tab (printf '\t')
set preview_script (string escape -- (status filename))
set preview_command "fish $preview_script --preview-window {1}"
set prompt 'Window> '
set header 'Enter: switch window · Ctrl-/: toggle preview'
if test "$mode" = --sessions
    set rows (tmux list-sessions -F "#{session_id}$tab#{?#{m/r:^[0-9]+\$,#{session_name}},#{b:session_path} (session #{session_name}),#{session_name}} | #{pane_current_path} | #{session_windows} windows#{?session_attached, [attached],}" 2>/dev/null)
    set preview_command "fish $preview_script --preview-session {1}"
    set prompt 'Session> '
    set header 'Enter: switch session · Ctrl-/: toggle preview'
else if test "$mode" = --windows
    # Resolve the session now, so previewing cannot change the search scope.
    set session_id (tmux display-message -p '#{session_id}')
    or exit 1
    set rows (tmux list-windows -t "$session_id" -F "#{window_id}$tab#{window_index}: #{window_name} | #{pane_current_command} | #{pane_current_path}#{?window_active, [current],}")
else
    printf 'Usage: tmux-picker.fish --sessions|--windows\n' >&2
    exit 1
end

if test (count $rows) -eq 0
    exit 0
end
set selected (printf '%s\n' $rows | fzf --reverse \
    --delimiter '\t' --with-nth=2.. --prompt="$prompt" --header="$header" \
    --preview="$preview_command" --preview-window='right,65%,border-left,<100(down,65%,border-top)' \
    --bind='ctrl-/:toggle-preview')
if test -z "$selected"
    exit 0
end
set target (string split -f 1 "$tab" -- "$selected")
if test "$mode" = --windows
    tmux select-window -t "$target"
else if test -z "$TMUX"
    tmux attach-session -t "$target"
else
    tmux switch-client -t "$target"
end
