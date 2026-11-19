"""Integration checks using an isolated tmux server; requires tmux, fish, fzf."""

import json
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
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
        config_dir = directory / ".config" / "fish"
        config_dir.mkdir(parents=True)
        (config_dir / "tmux-window-colors.fish").symlink_to(
            ROOT / "fish/tmux-window-colors.fish")
        (config_dir / "tmux-window-hints.fish").symlink_to(
            ROOT / "fish/tmux-window-hints.fish")
        real_menu = directory / "real-menu"
        env = dict(os.environ, HOME=str(directory),
                   PATH=f"{directory}:{os.environ['PATH']}",
                   PICKER_LOG=str(log), PICKER_ROWS=str(rows), PICKER_QUERY="",
                   PICKER_REAL_MENU_FILE=str(real_menu),
                   PICKER_ACTION_FILE=str(directory / 'action'), FZF_DEFAULT_OPTS="")
        env.pop("TMUX", None)
        env.pop("TMUX_PANE", None)

        def tmux(*args):
            return subprocess.check_output(
                [TMUX, "-S", socket, *args], text=True, env=env).strip()

        # Intercept only interactive attachment/switching; other calls use tmux.
        (directory / "tmux").write_text(f'''#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
if args[0] in ('attach-session', 'switch-client', 'select-window', 'display-menu'):
    with open(os.environ['PICKER_LOG'], 'a') as f:
        f.write(json.dumps(args) + '\\n')
    if args[0] == 'display-menu' and os.path.exists(os.environ['PICKER_REAL_MENU_FILE']):
        sys.exit(subprocess.call([{TMUX!r}, '-S', {socket!r}, *args]))
else:
    sys.exit(subprocess.call([{TMUX!r}, '-S', {socket!r}, *args]))
''')
        # Real fzf filtering tests the displayed fields without requiring a TTY.
        (directory / "fzf").write_text(f'''#!/usr/bin/env python3
import os, subprocess, sys
data = sys.stdin.read()
with open(os.environ['PICKER_ROWS'], 'w') as f:
    f.write(data)
args = [arg for arg in sys.argv[1:] if arg not in ('--expect=ctrl-x', '--print-query')]
action = ''
if os.environ.get('PICKER_DELETE'):
    from pathlib import Path
    marker = Path(os.environ['PICKER_ACTION_FILE'])
    if marker.exists():
        sys.exit(130)
    marker.touch()
    action = 'ctrl-x'
result = subprocess.run([{FZF!r}, *args, '--filter', os.environ['PICKER_QUERY']],
                        input=data, text=True, capture_output=True)
if result.returncode not in (0, 1):
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
if result.stdout:
    if '--expect=ctrl-x' in sys.argv:
        print(os.environ['PICKER_QUERY'])
        print(action)
    print(result.stdout.splitlines()[0])
''')
        for name in ("tmux", "fzf"):
            (directory / name).chmod(0o755)

        def picker(*args, answer=""):
            return subprocess.check_output(
                ["fish", "--no-config", str(ROOT / "fish/tmux-picker.fish"), *args],
                env=env, text=True, input=answer)

        def delete(query, answer):
            env['PICKER_QUERY'] = query
            env['PICKER_DELETE'] = '1'
            Path(env['PICKER_ACTION_FILE']).unlink(missing_ok=True)
            try:
                return picker('--sessions', answer=answer)
            finally:
                env.pop('PICKER_DELETE')

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

            env["PICKER_QUERY"] = f"{ROOT.name} (session 10)"
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
            assert "tmux-window-hints.fish" in bindings, bindings
            assert any("-r -T prefix n" in line and "next-window" in line
                       for line in bindings.splitlines()), bindings
            assert any("-r -T prefix p" in line and "previous-window" in line
                       for line in bindings.splitlines()), bindings
            accents = tmux("list-windows", "-t", sid,
                           "-F", "#{@window_accent}").splitlines()
            assert len(accents) == 2 and len(set(accents)) == 2, accents
            assert all(accent.startswith("#") for accent in accents), accents
            assert tmux("show-options", "-w", "-v", "-t", wid,
                        "pane-active-border-style") == f"fg={accents[0]}"
            assert "@window_accent" in tmux("show-options", "-gw", "-v",
                                             "window-status-format")
            env["PICKER_QUERY"] = "second"
            picker("--windows")
            assert "\x1b[" in rows.read_text() and "●" in rows.read_text()
            third = tmux("new-window", "-d", "-t", sid, "-P", "-F",
                         "#{window_id}", "-n", "third", "sleep 120")
            assert tmux("display-message", "-p", "-t", third,
                        "#{@window_accent}").startswith("#")
            subprocess.run(["fish", "--no-config", str(ROOT / "fish/tmux-window-hints.fish"),
                            sid], env=env, check=True)
            menu = json.loads(log.read_text().splitlines()[-1])
            assert menu[:6] == ["display-menu", "-T", "Jump to window", "-x", "C", "-y"], menu
            assert "a" in menu and "s" in menu and "d" in menu, menu
            assert f"select-window -t {wid}" in menu, menu
            assert any("●" in item and "#[fg=#" in item for item in menu), menu

            # An attached client must actually show the menu and jump on one key.
            second = tmux("display-message", "-p", "-t", f"{sid}:1", "#{window_id}")
            real_menu.touch()
            pid, terminal = pty.fork()
            if pid == 0:
                os.execve(TMUX, [TMUX, "-S", socket, "attach-session", "-t", sid], env)
            try:
                fcntl.ioctl(terminal, termios.TIOCSWINSZ,
                            struct.pack("HHHH", 30, 120, 0, 0))
                for _ in range(50):
                    if tmux("list-clients", "-F", "#{session_id}") == sid:
                        break
                    time.sleep(0.02)
                if select.select([terminal], [], [], 1)[0]:
                    os.read(terminal, 65536)
                client_tty = tmux("list-clients", "-F", "#{client_tty}")
                menu_process = subprocess.Popen(
                    ["fish", "--no-config", str(ROOT / "fish/tmux-window-hints.fish"),
                     sid, client_tty], env=env, stderr=subprocess.PIPE)
                output = b""
                deadline = time.monotonic() + 3
                while b"Jump to window" not in output and time.monotonic() < deadline:
                    if select.select([terminal], [], [], 0.1)[0]:
                        output += os.read(terminal, 65536)
                assert b"Jump to window" in output, (
                    output[-500:], log.read_text().splitlines()[-1],
                    tmux("list-clients", "-F", "#{client_key_table}"),
                    tmux("show-messages"))
                os.write(terminal, b"s")
                assert menu_process.wait(timeout=3) == 0, menu_process.stderr.read()
                for _ in range(50):
                    if tmux("display-message", "-p", "-t", sid,
                            "#{window_id}") == second:
                        break
                    time.sleep(0.02)
                assert tmux("display-message", "-p", "-t", sid,
                            "#{window_id}") == second
                if select.select([terminal], [], [], 0.1)[0]:
                    os.read(terminal, 65536)
                os.write(terminal, b"\x01")
                time.sleep(0.05)
                assert tmux("list-clients", "-F", "#{client_key_table}") == "prefix"
                os.write(terminal, b" ")
                output = b""
                deadline = time.monotonic() + 3
                while b"Jump to window" not in output and time.monotonic() < deadline:
                    if select.select([terminal], [], [], 0.1)[0]:
                        output += os.read(terminal, 65536)
                assert b"Jump to window" in output, (
                    output[-500:], log.read_text().splitlines()[-1],
                    tmux("list-clients", "-F", "#{client_key_table}"),
                    tmux("show-messages"))
                os.write(terminal, b"a")
                for _ in range(50):
                    if tmux("display-message", "-p", "-t", sid,
                            "#{window_id}") == wid:
                        break
                    time.sleep(0.02)
                assert tmux("display-message", "-p", "-t", sid,
                            "#{window_id}") == wid
            finally:
                os.kill(pid, signal.SIGTERM)
                os.waitpid(pid, 0)
                os.close(terminal)
                real_menu.unlink()

            # Confirmation rejects no, Escape, uppercase Y, Enter, and EOF.
            before = log.read_text()
            for answer in ('n', '\x1b', 'Y', '\n', ''):
                output = delete('team app', answer)
                assert 'LLM clients' in output and 'team app' in output
                assert tmux('has-session', '-t', '=team app') == ''
                assert log.read_text() == before
            output = delete('team app', 'y')
            assert 'last session' not in output
            assert tmux('list-sessions', '-F', '#{session_name}') == '10'
            assert 'team app' not in rows.read_text(), 'List did not refresh'

            other = tmux('new-session', '-d', '-P', '-F', '#{session_id}',
                         '-s', 'replacement', 'sleep 120')
            delete(f'{ROOT.name} (session 10)', 'y')
            assert json.loads(log.read_text().splitlines()[-1]) == [
                'switch-client', '-t', other, ';', 'kill-session', '-t', sid]

            # The switch is intercepted above; delete the last session for real.
            tmux('kill-session', '-t', other)
            env.pop('TMUX')
            output = delete(f'{ROOT.name} (session 10)', 'y')
            assert 'last session; you will leave tmux' in output
            result = subprocess.run([TMUX, '-S', socket, 'list-sessions'], capture_output=True)
            assert result.returncode != 0
            print("Verified previews, labels, selection, confirmation cancellation, deletion, list refresh, current-session handoff, last-session warning, and config.")
        finally:
            subprocess.run([TMUX, "-S", socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    check()
