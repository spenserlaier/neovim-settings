function vi_fzf --description 'fzf with basic normal/insert modes'
    # Append to start so callers such as rgi can still reload their input.
    # Disabling the input preserves the query and prevents accidental edits.
    # Keep Enter untouched: --expect callers depend on its output format.
    command fzf $argv \
        --border --border-label=' INSERT · Esc: normal · Ctrl-C: cancel ' \
        --bind 'j:down,k:up' \
        --bind 'i,/:show-input+unbind(j,k,i,/)+change-border-label( INSERT · Esc: normal · Ctrl-C: cancel )' \
        --bind 'esc:hide-input+rebind(j,k,i,/)+change-border-label( NORMAL · j/k: move · i or /: insert · Ctrl-C: cancel )' \
        --bind 'ctrl-c:abort' \
        --bind 'start:+unbind(j,k,i,/)'
end
