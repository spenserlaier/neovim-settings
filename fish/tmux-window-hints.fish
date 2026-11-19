#!/usr/bin/env fish

# A short-lived, home-row menu for the windows in one session.
set session_target "$argv[1]"
set client_tty "$argv[2]"
if test -z "$session_target"
    exit 1
end

set tab (printf '\t')
set hints a s d f g h j k l z x c v b n m
set windows (tmux list-windows -t "$session_target" -F "#{window_id}$tab#{window_index}$tab#{window_name}$tab#{pane_current_command}$tab#{b:pane_current_path}$tab#{@window_accent}" 2>/dev/null)
if test (count $windows) -eq 0
    exit 0
end

set menu -T 'Jump to window' -x C -y C
for index in (seq (math "min("(count $windows)", "(count $hints)")"))
    set fields (string split -m 5 "$tab" -- "$windows[$index]")
    set name (string replace -a '#' '##' -- (string sub -l 24 -- "$fields[3]"))
    set command (string replace -a '#' '##' -- "$fields[4]")
    set directory (string replace -a '#' '##' -- "$fields[5]")
    set marker '●'
    if string match -qr '^#[[:xdigit:]]{6}$' -- "$fields[6]"
        set marker "#[fg=$fields[6]]●#[default]"
    end
    set -a menu "$marker $fields[2]: $name | $command | $directory" \
        "$hints[$index]" "select-window -t $fields[1]"
end
if test (count $windows) -gt (count $hints)
    set -a menu 'More windows…' o 'display-popup -E -w 90% -h 90% "fish ~/.config/fish/tmux-picker.fish --windows"'
end
if test -n "$client_tty"
    tmux display-menu -c "$client_tty" $menu
else
    tmux display-menu $menu
end
