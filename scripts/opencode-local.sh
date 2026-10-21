# Included by writeShellApplication, which supplies Bash and strict mode.
# Credentials stay in ~/.ssh, outside the Nix store.
desktop="${OPENCODE_OLLAMA_SSH_HOST:-spenser@192.168.4.209}"
identity="${OPENCODE_OLLAMA_SSH_IDENTITY:-$HOME/.ssh/id_ed25519_desktop}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
socket="$cache_dir/ollama-ssh"
mkdir -p "$cache_dir"
chmod 700 "$cache_dir"

if [[ "${1:-}" == "--stop-tunnel" ]]; then
  exec ssh -S "$socket" -O exit "$desktop"
fi

if ! ssh -S "$socket" -O check "$desktop" 2>/dev/null; then
  ssh -fNT -M -S "$socket" \
    -i "$identity" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ControlPersist=600 \
    -L 127.0.0.1:11435:127.0.0.1:11435 \
    "$desktop"
fi

# Check the intended model before launching; never fall back to a cloud model.
if ! curl --fail --silent --show-error --max-time 15 \
  http://127.0.0.1:11435/api/tags | \
  jq -e 'any(.models[]; .name == "qwen3.8:27b")' >/dev/null; then
  echo 'Desktop Ollama is unavailable or qwen3.8:27b is missing.' >&2
  exit 1
fi

exec opencode "$@"
