#!/usr/bin/env fish

set action "$argv[1]"
set hints a s d f g h j k l z x c v b n m

if test "$action" = bind
    set bindings
    for key in $hints
        set -a bindings bind-key -T window-jump "$key" run-shell \
            "fish ~/.config/fish/tmux-window-hints.fish $key #{q:session_id} #{q:client_name}" ';'
    end
    tmux $bindings[1..-2]
    exit $status
end

function finish_jump --argument-names session
    set -l previous (tmux show-options -qv -t "$session" @jump_previous_status)
    set -l restore
    if test "$previous" = inherit
        set restore set-option -u -t "$session" status ';'
    else if test -n "$previous"
        set restore set-option -t "$session" status "$previous" ';'
    end
    tmux $restore set-option -u -t "$session" @jump_targets \; \
        set-option -u -t "$session" @jump_previous_status \; \
        set-option -u -t "$session" @jump_client
end

if test "$action" = cleanup
    # Detaching or changing sessions can bypass the jump key table altogether.
    for session in (tmux list-sessions -f '#{@jump_client}' -F '#{session_id}')
        set owner (tmux show-options -qv -t "$session" @jump_client)
        if not contains -- "$owner" (tmux list-clients -t "$session" -F '#{client_name}')
            finish_jump "$session"
        end
    end
    exit
end

set session "$argv[2]"
set client "$argv[3]"
if test -z "$session"; or test -z "$client"
    exit 1
end

if test "$action" = start
    set windows (tmux list-windows -t "$session" -F '#{window_id}')
    if not set -q windows[1]
        exit 0
    end
    # Only one client at a time can own a session's temporary third row.
    tmux set-option -o -t "$session" @jump_client "$client" 2>/dev/null
    or exit 0

    set previous (tmux show-options -qv -t "$session" status)
    if test -z "$previous"
        set previous inherit
    end
    set targets
    for index in (seq (math "min("(count $windows)", "(count $hints)")"))
        set -a targets "$windows[$index]/$hints[$index]"
    end
    tmux set-option -t "$session" @jump_previous_status "$previous" \; \
        set-option -t "$session" @jump_targets " "(string join ' ' $targets)" " \; \
        switch-client -c "$client" -T window-jump \; \
        set-option -t "$session" status 3
    or finish_jump "$session"
    exit
end

set owner (tmux show-options -qv -t "$session" @jump_client)
if test "$owner" != "$client"
    exit 0
end

set targets (tmux show-options -qv -t "$session" @jump_targets)
finish_jump "$session"
if test "$action" = picker
    tmux display-popup -c "$client" -t "$session:" -E -w 90% -h 90% \
        'fish ~/.config/fish/tmux-picker.fish --windows'
else if contains -- "$action" $hints
    set target (string match -r " (@[0-9]+)/$action " -- "$targets")[2]
    if test -n "$target"
        tmux select-window -t "$session:$target"
    end
end
