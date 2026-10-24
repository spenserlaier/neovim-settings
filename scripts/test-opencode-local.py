"""Exercise real autossh with isolated fake SSH/Ollama; needs autossh, flock, jq."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts/opencode-local.sh"


def wait_for(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for tunnel state")


def check():
    for tool in ("autossh", "flock", "jq"):
        assert shutil.which(tool), f"Missing test dependency: {tool}"

    with tempfile.TemporaryDirectory(prefix="opencode-tunnel-") as temporary:
        directory = Path(temporary)
        cache = directory / "cache/opencode"
        env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                   XDG_CACHE_HOME=str(directory / "cache"),
                   TUNNEL_TEST_DIR=str(directory),
                   AUTOSSH_PATH=str(directory / "ssh"),
                   OPENCODE_OLLAMA_SSH_HOST="test@desktop",
                   OPENCODE_OLLAMA_SSH_IDENTITY="/unused/test-key")

        def executable(name, body):
            path = directory / name
            path.write_text(f"#!{sys.executable}\n" + body)
            path.chmod(0o755)

        executable("ssh", '''
import json, os, signal, sys, time
from pathlib import Path
root = Path(os.environ['TUNNEL_TEST_DIR'])
pid_file = root / 'ssh.pid'
if '-O' in sys.argv:
    if pid_file.exists():
        try:
            os.kill(int(pid_file.read_text()), signal.SIGTERM)
        except ProcessLookupError:
            pass
    sys.exit(0)
with (root / 'ssh-starts').open('a') as f:
    f.write(json.dumps({'pid': os.getpid(), 'args': sys.argv[1:]}) + '\\n')
if (root / 'offline').exists():
    sys.exit(255)
pid_file.write_text(str(os.getpid()))
signal.signal(signal.SIGTERM, lambda *_: sys.exit(255))
try:
    while True:
        time.sleep(0.1)
finally:
    if pid_file.exists() and pid_file.read_text() == str(os.getpid()):
        pid_file.unlink()
''')
        executable("curl", '''
import json, os, sys
from pathlib import Path
root = Path(os.environ['TUNNEL_TEST_DIR'])
if not (root / 'ssh.pid').exists():
    sys.exit(7)
model = 'other:1b' if (root / 'missing-model').exists() else 'qwen3.8:27b'
print(json.dumps({'models': [{'name': model}]}))
''')
        executable("opencode", '''
import json, os, sys
from pathlib import Path
with (Path(os.environ['TUNNEL_TEST_DIR']) / 'opencode-calls').open('a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
''')

        def command(*args):
            return ["bash", "-euo", "pipefail", str(LAUNCHER), *args]

        def run(*args, expected=0):
            result = subprocess.run(command(*args), env=env, capture_output=True,
                                    text=True, timeout=20)
            assert result.returncode == expected, result.stderr
            return result

        def starts():
            path = directory / "ssh-starts"
            return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

        def calls():
            path = directory / "opencode-calls"
            return path.read_text().splitlines() if path.exists() else []

        try:
            # A failed initial connection must keep retrying, then become ready.
            (directory / "offline").touch()
            first = subprocess.Popen(command("--continue"), env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            wait_for(lambda: len(starts()) >= 1)
            (directory / "offline").unlink()
            _, error = first.communicate(timeout=20)
            assert first.returncode == 0, error.decode()
            supervisor = int((cache / "ollama-autossh.pid").read_text())
            assert json.loads(calls()[0]) == ["--continue"]

            # Concurrent launches must reuse the same supervisor and SSH child.
            previous_starts = len(starts())
            clients = [subprocess.Popen(command(), env=env) for _ in range(5)]
            assert all(client.wait(timeout=15) == 0 for client in clients)
            assert len(starts()) == previous_starts
            assert int((cache / "ollama-autossh.pid").read_text()) == supervisor

            # Simulate a broken transport: real autossh must replace its child.
            old_child = int((directory / "ssh.pid").read_text())
            os.kill(old_child, signal.SIGKILL)
            wait_for(lambda: (directory / "ssh.pid").exists()
                     and int((directory / "ssh.pid").read_text()) != old_child)
            run("--session", "test-session")

            # Stop must terminate supervisor AND child without respawning.
            run("--stop-tunnel")
            assert not (cache / "ollama-autossh.pid").exists()
            assert not (directory / "ssh.pid").exists()
            stopped_starts = len(starts())
            time.sleep(1)
            assert len(starts()) == stopped_starts
            run("--stop-tunnel")  # Idempotent even with no live tunnel.

            # Ignore a stale PID belonging to an unrelated live process.
            (cache / "ollama-autossh.pid").write_text(str(os.getpid()))
            run()
            assert int((cache / "ollama-autossh.pid").read_text()) != os.getpid()

            # A missing model must never launch OpenCode or kill recovery.
            (directory / "missing-model").touch()
            previous_calls = len(calls())
            result = run(expected=1)
            assert "qwen3.8:27b is missing" in result.stderr
            assert len(calls()) == previous_calls
            os.kill(int((cache / "ollama-autossh.pid").read_text()), 0)
            run("--stop-tunnel")

            # An old unsupervised SSH tunnel is replaced on the next launch.
            legacy = subprocess.Popen([str(directory / "ssh"), "-NT"], env=env)
            wait_for(lambda: (directory / "ssh.pid").exists())
            (directory / "missing-model").unlink()
            run()
            legacy.wait(timeout=5)
            assert int((directory / "ssh.pid").read_text()) != legacy.pid
            run("--stop-tunnel")
            print("Passed: initial failure recovery, concurrent reuse, SSH restart, "
                  "shutdown, stale PID, model guard, and legacy migration")
        finally:
            run("--stop-tunnel")


if __name__ == "__main__":
    check()
