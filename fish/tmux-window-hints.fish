#!/usr/bin/env fish

set action "$argv[1]"
set hints a s d f g h j k l z x c v b n m
set digits 0 1 2 3 4 5 6 7 8 9

if test "$action" = bind
    set bindings
    for key in $hints $digits
        set -a bindings bind-key -T window-jump "$key" run-shell \
            "fish ~/.config/fish/tmux-window-hints.fish $key #{q:session_id} #{q:client_name} #{q:@jump_token} #{q:@jump_targets}" ';'
    end
    tmux $bindings[1..-2]
    exit $status
end

function finish_jump --argument-names session token
    set -l previous (tmux show-options -qv -t "$session" @jump_previous_status)
    set -l restore
    if test "$previous" = inherit
        set restore "set-option -u -t '$session' status; "
    else if contains -- "$previous" off on 2 3 4 5
        set restore "set-option -t '$session' status $previous; "
    end

    # A delayed cleanup must never tear down a more recent Jump.
    tmux if-shell -F -t "$session:" "#{==:#{@jump_token},$token}" \
        "$restore set-option -qu -t '$session' @jump_targets; \
        set-option -qu -t '$session' @jump_command_windows; \
        set-option -qu -t '$session' @jump_previous_status; \
        set-option -qu -t '$session' @jump_client; \
        set-option -qu -t '$session' @jump_token" 2>/dev/null
end

function clear_inactive_jump --argument-names session
    set -l owner (tmux show-options -qv -t "$session" @jump_client)
    if test -z "$owner"
        return 0
    end
    set -l token (tmux show-options -qv -t "$session" @jump_token)
    set -l active_clients (tmux list-clients -t "$session" -F '#{?#{==:#{client_key_table},window-jump},#{client_name},}')
    if not contains -- "$owner" $active_clients
        finish_jump "$session" "$token"
    end
end

if test "$action" = cleanup
    # A client can leave the key table without running a Jump binding.
    for session in (tmux list-sessions -f '#{@jump_client}' -F '#{session_id}')
        clear_inactive_jump "$session"
    end
    exit
end

set session "$argv[2]"
set client "$argv[3]"
set token "$argv[4]"
if test -z "$session"; or test -z "$client"
    exit 1
end

if test "$action" = watch
    # tmux can reset the key table without invoking Escape or the Any binding.
    set active "$client window-jump $token"
    set format '#{client_name} #{client_key_table} #{@jump_token}'
    while contains -- "$active" (tmux list-clients -t "$session" -F "$format" 2>/dev/null)
        sleep 0.25
    end
    # Let an already queued key binding capture its window targets first.
    sleep 0.1
    finish_jump "$session" "$token"
    exit
end

if test "$action" = start
    clear_inactive_jump "$session"
    # Quote each identity field, including literal newlines in directory names.
    set identity_format '#{window_id} #{window_index} #{q:window_name} #{s!'\n'!\\\\n!:#{q:pane_current_path}}'
    set rows (tmux list-windows -t "$session" -F "$identity_format")
    set windows
    set identities
    set seen
    set duplicates
    set targets
    for row in $rows
        set fields (string split -m 2 ' ' -- "$row")
        set -a windows "$fields[1]"
        set -a identities "$fields[3]"
        if contains -- "$fields[3]" $seen
            set -a duplicates "$fields[3]"
        end
        set -a seen "$fields[3]"
        if contains -- "$fields[2]" $digits
            set -a targets "$fields[1]/$fields[2]"
        end
    end
    if not set -q windows[1]
        exit 0
    end
    set previous (tmux show-options -qv -t "$session" status)
    if test -z "$previous"
        set previous inherit
    end
    set command_windows
    for index in (seq (math "min("(count $windows)", "(count $hints)")"))
        set -a targets "$windows[$index]/$hints[$index]"
        if contains -- "$identities[$index]" $duplicates
            set -a command_windows "$windows[$index]"
        end
    end
    # Claim ownership and enter the key table in the same command queue.
    set token $fish_pid
    set watch "fish ~/.config/fish/tmux-window-hints.fish watch "(string escape -- "$session" "$client" "$token" | string join ' ')
    tmux set-option -o -t "$session" @jump_client "$client" \; \
        set-option -t "$session" @jump_token "$token" \; \
        set-option -t "$session" @jump_previous_status "$previous" \; \
        set-option -t "$session" @jump_targets " $targets " \; \
        set-option -t "$session" @jump_command_windows " $command_windows " \; \
        switch-client -c "$client" -T window-jump \; \
        set-option -t "$session" status 3 \; \
        run-shell -b "$watch" 2>/dev/null
    or clear_inactive_jump "$session"
    exit
end

if not string match -qr '^[0-9]+$' -- "$token"
    exit 0
end

finish_jump "$session" "$token"
if test "$action" = picker
    tmux display-popup -c "$client" -t "$session:" -E -w 90% -h 90% \
        'fish ~/.config/fish/tmux-picker.fish --windows'
else if contains -- "$action" $hints $digits
    set target (string match -r " (@[0-9]+)/$action " -- "$argv[5]")[2]
    if test -n "$target"
        tmux select-window -t "$session:$target"
    end
end
