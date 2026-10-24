function vi_fzf --description 'fzf with basic normal/insert modes'
    set -l insert_actions 'show-input+unbind(j,k,i,/)+change-border-label( INSERT · Esc: normal · Ctrl-C: cancel )'
    set -l normal_actions 'hide-input+rebind(j,k,i,/)+change-border-label( NORMAL · j/k: move · i or /: insert · Esc: cancel )'
    set -l start_actions 'unbind(j,k,i,/)'
    # Opt-in persistence for callers which reopen the picker, such as jjr.
    if set -q VI_FZF_MODE_FILE; and test -n "$VI_FZF_MODE_FILE"
        set insert_actions "$insert_actions"'+execute-silent(printf insert > "$VI_FZF_MODE_FILE")'
        set normal_actions "$normal_actions"'+execute-silent(printf normal > "$VI_FZF_MODE_FILE")'
        if test -f "$VI_FZF_MODE_FILE"; and test (command cat -- "$VI_FZF_MODE_FILE") = normal
            set start_actions "$normal_actions"
        end
    end
    set -lx VI_FZF_NORMAL_ACTIONS "$normal_actions"
    # Append to start so callers such as rgi can still reload their input.
    # Disabling the input preserves the query and prevents accidental edits.
    # Keep Enter untouched: --expect callers depend on its output format.
    # rgi's --disabled still accepts typing; only hidden input means normal mode.
    command fzf $argv \
        --border --border-label=' INSERT · Esc: normal · Ctrl-C: cancel ' \
        --bind 'j:down,k:up' \
        --bind "i,/:$insert_actions" \
        --bind 'esc:transform:test "$FZF_INPUT_STATE" != hidden && printf "%s\n" "$VI_FZF_NORMAL_ACTIONS" || echo abort' \
        --bind 'ctrl-u:half-page-up,ctrl-d:half-page-down' \
        --bind 'ctrl-c:abort' \
        --bind "start:+$start_actions"
end
