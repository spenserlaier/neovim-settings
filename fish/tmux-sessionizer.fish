#!/usr/bin/env fish

# 1. If an argument is passed, use it. Otherwise, use fzf to pick a directory.
if test (count $argv) -eq 1
    set selected $argv[1]
else
    # Increased depth to 4 so it actually finds nested git repositories
    set selected (fd . ~/Documents ~/Desktop -t d -d 4 2>/dev/null | fzf)
end

# 2. If you hit escape in fzf, exit cleanly
if test -z "$selected"
    exit 0
end

# 3. Clean up the folder name for Tmux (strip both dots and colons)
set selected_name (basename "$selected" | string replace -a '.' '_' | string replace -a ':' '_')
set tmux_running (pgrep tmux)

# 4. If tmux isn't running at all, start it with this new session
if test -z "$TMUX"; and test -z "$tmux_running"
    tmux new-session -s $selected_name -c $selected
    exit 0
end

# 5. If the session doesn't exist yet, create it in the background
if not tmux has-session -t=$selected_name 2>/dev/null
    tmux new-session -ds $selected_name -c $selected
end

# 6. Finally, switch to the session
if test -z "$TMUX"
    tmux attach-session -t $selected_name
else
    tmux switch-client -t $selected_name
end
