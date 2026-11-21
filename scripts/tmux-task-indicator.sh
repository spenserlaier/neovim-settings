# Update pane-local status without reading prompts, transcripts, or tool output.
action=$1

visible() {
    tmux list-clients -F '#{window_id}' 2>/dev/null | grep -Fxq -- "$1"
}

if [ "$action" = visit ]; then
    window=$2
    if visible "$window"; then
        for pane in $(tmux list-panes -t "$window" -F '#{pane_id}'); do
            tmux if-shell -F -t "$pane" '#{m/r:^(done|failed)$,#{@agent_state}}' \
                "set-option -qp -t $pane @agent_state idle"
            tmux if-shell -F -t "$pane" '#{m/r:^(done|failed)$,#{@task_state}}' \
                "set-option -qup -t $pane @task_state"
        done
    fi
    exit 0
fi

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
pane=$TMUX_PANE
case $action in
    task-start)
        tmux set-option -qp -t "$pane" @task_state working
        ;;
    task-end|agent-done|agent-failed)
        window=$(tmux display-message -p -t "$pane" '#{window_id}')
        state='done'
        case $action in
            task-end)
                option=@task_state
                if [ "$2" != 0 ]; then state=failed; fi
                # A shell returning from an agent also clears any stale agent state.
                tmux set-option -qup -t "$pane" @agent_state
                ;;
            agent-done) option=@agent_state ;;
            agent-failed) option=@agent_state; state=failed ;;
        esac
        if visible "$window"; then state=idle; fi
        tmux set-option -qp -t "$pane" "$option" "$state"
        ;;
    agent-start)
        tmux set-option -qp -t "$pane" @agent_state working
        ;;
    agent-working)
        tmux if-shell -F -t "$pane" '#{==:#{@agent_state},waiting}' \
            "set-option -qp -t $pane @agent_state working"
        ;;
    agent-waiting)
        tmux set-option -qp -t "$pane" @agent_state waiting
        ;;
    agent-idle)
        tmux set-option -qp -t "$pane" @agent_state idle
        ;;
    agent-exit)
        tmux set-option -qup -t "$pane" @task_state \; \
            set-option -qup -t "$pane" @agent_state
        ;;
esac
