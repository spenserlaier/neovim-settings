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

source (status dirname)/functions/vi_fzf.fish

set tab (printf '\t')
set preview_script (string escape -- (status filename))
set preview_command "fish $preview_script --preview-window {1}"
set prompt 'Window> '
set header 'Enter: switch window · Ctrl-/: toggle preview'
set picker_options
if test "$mode" = --sessions
    set session_format "#{session_id}$tab#{?#{m/r:^[0-9]+\$,#{session_name}},#{b:session_path} (session #{session_name}),#{session_name}} | #{pane_current_path} | #{session_windows} windows#{?session_attached, [attached],}"
    set preview_command "fish $preview_script --preview-session {1}"
    set prompt 'Session> '
    set header 'Enter: switch · Ctrl-x: kill session (confirm) · Ctrl-/: preview'
    set picker_options --expect=ctrl-x --print-query
else if test "$mode" = --windows
    # Resolve the session now, so previewing cannot change the search scope.
    set session_id (tmux display-message -p '#{session_id}')
    or exit 1
    set rows (tmux list-windows -t "$session_id" -F "#{window_id}$tab#{window_index}: #{window_name} | #{pane_current_command} | #{pane_current_path}#{?window_active, [current],}")
else
    printf 'Usage: tmux-picker.fish --sessions|--windows\n' >&2
    exit 1
end

set query ''
while true
    if test "$mode" = --sessions
        set rows (tmux list-sessions -F "$session_format" 2>/dev/null)
    end
    if test (count $rows) -eq 0
        exit 0
    end
    set selected (printf '%s\n' $rows | vi_fzf --reverse \
        --delimiter '\t' --with-nth=2.. --prompt="$prompt" --header="$header" \
        --preview="$preview_command" --preview-window='right,65%,border-left,<100(down,65%,border-top)' \
        --bind='ctrl-/:toggle-preview' --query="$query" $picker_options)
    if test "$mode" = --windows
        if test -n "$selected"
            tmux select-window -t (string split -f 1 "$tab" -- "$selected")
        end
        exit $status
    end
    # --print-query and --expect emit query, key (empty for Enter), then row.
    if test (count $selected) -lt 3
        exit 0
    end
    set query "$selected[1]"
    set target (string split -f 1 "$tab" -- "$selected[3]")
    if test "$selected[2]" = ctrl-x
        set description (tmux display-message -p -t "$target:" '#{session_name} — #{session_path} (#{session_windows} windows)' 2>/dev/null)
        or continue
        set sessions (tmux list-sessions -F '#{session_id}')
        set warning 'All running servers, LLM clients, and other processes in this session will terminate.'
        if test (count $sessions) -eq 1
            set warning "$warning This is the last session; you will leave tmux."
        end
        printf '\nKill %s?\n%s\n' "$description" "$warning"
        set answer ''
        read --nchars 1 --prompt-str 'Press y to kill; any other key cancels [y/N]: ' answer
        set read_status $status
        printf '\n'
        if test $read_status -ne 0; or test "$answer" != y
            continue
        end
        set current (tmux display-message -p '#{session_id}' 2>/dev/null)
        set replacement (string match -v -- "$target" $sessions)[1]
        if test -n "$TMUX"; and test "$current" = "$target"; and test -n "$replacement"
            # Queue both on the server: switching can close this popup/script.
            tmux switch-client -t "$replacement" \; kill-session -t "$target"
            exit $status
        end
        tmux kill-session -t "$target"
        continue
    end
    if test -z "$TMUX"
        tmux attach-session -t "$target"
    else
        tmux switch-client -t "$target"
    end
    exit $status
end
