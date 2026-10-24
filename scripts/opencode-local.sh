# Included by writeShellApplication, which supplies Bash and strict mode.
# Credentials stay in ~/.ssh, outside the Nix store.
desktop="${OPENCODE_OLLAMA_SSH_HOST:-spenser@192.168.4.209}"
identity="${OPENCODE_OLLAMA_SSH_IDENTITY:-$HOME/.ssh/id_ed25519_desktop}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
socket="$cache_dir/ollama-ssh"
pid_file="$cache_dir/ollama-autossh.pid"
log_file="$cache_dir/ollama-autossh.log"
umask 077
mkdir -p "$cache_dir"
chmod 700 "$cache_dir"

# Serialize launches and stops, including simultaneous OpenCode sessions. Close
# this descriptor in the background process and before handing off to OpenCode.
exec 9>"$cache_dir/ollama-tunnel.lock"
flock -x 9

supervisor_running() {
  [[ -f "$pid_file" ]] || return 1
  read -r supervisor_pid < "$pid_file" || return 1
  [[ "$supervisor_pid" =~ ^[1-9][0-9]*$ ]] || return 1
  kill -0 "$supervisor_pid" 2>/dev/null || return 1
  # A stale PID file must not cause us to signal an unrelated process.
  case "$(ps -p "$supervisor_pid" -o comm= 2>/dev/null)" in
    autossh|*/autossh) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "${1:-}" == "--stop-tunnel" ]]; then
  if supervisor_running; then
    kill -TERM "$supervisor_pid"
    for ((attempt = 0; attempt < 50; attempt++)); do
      if ! supervisor_running; then
        break
      fi
      sleep 0.1
    done
    if supervisor_running; then
      echo "Tunnel supervisor did not stop; see $log_file" >&2
      exit 1
    fi
  fi
  # Also handles a tunnel left by the pre-autossh launcher.
  ssh -S "$socket" -O exit "$desktop" 2>/dev/null || true
  rm -f "$pid_file"
  exit 0
fi

if ! supervisor_running; then
  # Migrate an existing unsupervised tunnel instead of competing for its port.
  ssh -S "$socket" -O exit "$desktop" 2>/dev/null || true
  # Keep SSH in the foreground under autossh. Keepalives detect dead transports;
  # autossh retries even when the first connection fails (e.g. waking offline).
  # Both autossh's logger and SSH's stderr append to this log; neither reads it.
  # shellcheck disable=SC2094
  AUTOSSH_GATETIME=0 AUTOSSH_POLL=30 AUTOSSH_LOGFILE="$log_file" \
    nohup autossh -M 0 -NT -S "$socket" \
    -i "$identity" \
    -o ControlMaster=yes \
    -o ControlPersist=no \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -L 127.0.0.1:11435:127.0.0.1:11435 \
    "$desktop" </dev/null >>"$log_file" 2>&1 9>&- &
  printf '%s\n' "$!" > "$pid_file"
  # Wait for nohup to exec autossh before another launcher checks the PID.
  for ((attempt = 0; attempt < 20; attempt++)); do
    if supervisor_running; then
      break
    fi
    sleep 0.1
  done
  if ! supervisor_running; then
    echo "Could not start the tunnel supervisor; see $log_file" >&2
    exit 1
  fi
fi
exec 9>&-

# Allow time for a new or reconnecting tunnel, then check the intended model.
# The supervisor keeps retrying in the background if the desktop is offline.
for ((attempt = 0; attempt < 6; attempt++)); do
  if curl --fail --silent --show-error --connect-timeout 2 --max-time 5 \
    http://127.0.0.1:11435/api/tags 2>/dev/null | \
    jq -e 'any(.models[]; .name == "qwen3.8:27b")' >/dev/null; then
    exec opencode "$@"
  fi
  if ((attempt < 5)); then
    sleep 1
  fi
done

echo 'Desktop Ollama is unavailable or qwen3.8:27b is missing.' >&2
echo "The tunnel will keep reconnecting; retry opencode-local when ready. Log: $log_file" >&2
exit 1
