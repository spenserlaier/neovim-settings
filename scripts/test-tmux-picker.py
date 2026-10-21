"""Integration checks using an isolated tmux server; requires tmux, fish, fzf."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
TMUX = shutil.which("tmux")
FZF = shutil.which("fzf")


def check():
    with tempfile.TemporaryDirectory(prefix="tmux-picker-") as temporary:
        directory = Path(temporary)
        socket = str(directory / "socket")
        log = directory / "calls.jsonl"
        rows = directory / "rows"
        env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                   PICKER_LOG=str(log), PICKER_ROWS=str(rows), PICKER_QUERY="")
        env.pop("TMUX", None)

        def tmux(*args):
            return subprocess.check_output(
                [TMUX, "-S", socket, *args], text=True, env=env).strip()

        # Intercept only interactive attachment/switching; other calls use tmux.
        (directory / "tmux").write_text(f'''#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
if args[0] in ('attach-session', 'switch-client', 'select-window'):
    with open(os.environ['PICKER_LOG'], 'a') as f:
        f.write(json.dumps(args) + '\\n')
else:
    sys.exit(subprocess.call([{TMUX!r}, '-S', {socket!r}, *args]))
''')
        # Real fzf filtering tests the displayed fields without requiring a TTY.
        (directory / "fzf").write_text(f'''#!/usr/bin/env python3
import os, subprocess, sys
data = sys.stdin.read()
with open(os.environ['PICKER_ROWS'], 'w') as f:
    f.write(data)
result = subprocess.run([{FZF!r}, *sys.argv[1:], '--filter', os.environ['PICKER_QUERY']],
                        input=data, text=True, capture_output=True)
if result.returncode not in (0, 1):
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
if result.stdout:
    print(result.stdout.splitlines()[0])
''')
        for name in ("tmux", "fzf"):
            (directory / name).chmod(0o755)

        def picker(*args):
            return subprocess.check_output(
                ["fish", "--no-config", str(ROOT / "fish/tmux-picker.fish"), *args],
                env=env, text=True)

        try:
            sid = tmux("-f", "/dev/null", "new-session", "-d", "-P", "-F",
                       "#{session_id}", "-s", "10", "-c", str(ROOT),
                       "printf 'PICKER_CONTENT\\n'; exec sleep 120")
            wid = tmux("display-message", "-p", "-t", sid, "#{window_id}")
            tmux("new-window", "-d", "-t", sid, "-n", "second", "sleep 120")
            tmux("new-session", "-d", "-s", "team app", "-c", str(ROOT), "sleep 120")
            for _ in range(50):
                if "PICKER_CONTENT" in tmux("capture-pane", "-p", "-t", wid):
                    break
                time.sleep(0.02)

            env["PICKER_QUERY"] = "neovim-settings (session 10)"
            picker("--sessions")
            assert json.loads(log.read_text().splitlines()[-1]) == ["attach-session", "-t", sid]
            assert "team app" in rows.read_text()
            assert str(ROOT) in rows.read_text()
            env["TMUX"] = f"{socket},0,0"
            env["TMUX_PANE"] = tmux("display-message", "-p", "-t", sid, "#{pane_id}")
            env["PICKER_QUERY"] = "team app"
            picker("--sessions")
            assert json.loads(log.read_text().splitlines()[-1])[0] == "switch-client"
            before = log.read_text()
            env["PICKER_QUERY"] = "NO_SUCH_SESSION"
            picker("--sessions")
            assert log.read_text() == before
            env["PICKER_QUERY"] = "second"
            picker("--windows")
            assert json.loads(log.read_text().splitlines()[-1])[0] == "select-window", rows.read_text()
            assert "team app" not in rows.read_text()
            assert "PICKER_CONTENT" in picker("--preview-window", wid)
            preview = picker("--preview-session", sid)
            assert "second" in preview and "PICKER_CONTENT" in preview
            assert tmux("list-sessions", "-F", "#{session_name}").splitlines() == ["10", "team app"]

            # Parse the repository config on this isolated server as well.
            tmux("source-file", str(ROOT / "tmux/common.conf"))
            bindings = tmux("list-keys", "-T", "prefix")
            assert "--windows" in bindings, bindings
            assert "--sessions" in bindings, bindings
            print("Verified session labels, scoped windows, previews, stable IDs, cancellation, and tmux config.")
        finally:
            subprocess.run([TMUX, "-S", socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    check()
