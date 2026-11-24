"""Integration checks using an isolated tmux server; requires tmux, fish, fzf."""

import json
import fcntl
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time


ROOT = Path(__file__).resolve().parents[1]
TMUX = shutil.which("tmux")
FZF = shutil.which("fzf")


def check(codex_only=False):
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
        indicator = config_dir.parent / "tmux" / "task-indicator"
        indicator.parent.mkdir()
        indicator.write_text("#!/bin/sh\n" + (ROOT / "scripts/tmux-task-indicator.sh").read_text())
        indicator.chmod(0o755)
        real_jump = directory / "real-jump"
        env = dict(os.environ, HOME=str(directory),
                   PATH=f"{directory}:{os.environ['PATH']}",
                   PICKER_LOG=str(log), PICKER_ROWS=str(rows), PICKER_QUERY="",
                   PICKER_REAL_JUMP_FILE=str(real_jump),
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
if args[0] in ('attach-session', 'switch-client', 'select-window', 'display-popup'):
    with open(os.environ['PICKER_LOG'], 'a') as f:
        f.write(json.dumps(args) + '\\n')
    if os.path.exists(os.environ['PICKER_REAL_JUMP_FILE']) and (
        args[0] == 'select-window' or (args[0] == 'switch-client' and '-T' in args)):
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
args = [arg for arg in sys.argv[1:] if arg != '--print-query']
action = ''
if os.environ.get('PICKER_DELETE'):
    from pathlib import Path
    marker = Path(os.environ['PICKER_ACTION_FILE'])
    if marker.exists():
        sys.exit(130)
    marker.touch()
    action = 'delete'
result = subprocess.run([{FZF!r}, *args, '--filter', os.environ['PICKER_QUERY']],
                        input=data, text=True, capture_output=True)
if result.returncode not in (0, 1):
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
if result.stdout:
    if '--print-query' in sys.argv:
        print(os.environ['PICKER_QUERY'])
        if action:
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
                         "#{window_id}", "-n", "third", "-c", str(directory), "sleep 120")
            assert tmux("display-message", "-p", "-t", third,
                        "#{@window_accent}").startswith("#")
            assert tmux("display-message", "-p", "-t", sid, "#{T:status-left}") == ""
            named_label = tmux("display-message", "-p", "-t", "=team app:", "#{T:status-left}")
            assert named_label == "[team app]", named_label
            jump_bindings = tmux("list-keys", "-T", "window-jump")
            assert "Escape" in jump_bindings and "Any" in jump_bindings, jump_bindings

            def wait_for(get_value, expected):
                for _ in range(100):
                    value = get_value()
                    if value == expected:
                        return
                    time.sleep(0.02)
                assert value == expected, (value, expected, tmux("show-messages").splitlines()[:20])

            # Simulate the TUI's terminal reports with the daemon pane absent.
            fake_codex = directory / "codex"
            reports = r'''
import sys
import time

for state in sys.stdin:
    state = state.strip()
    if state == "exit":
        sys.exit(7)
    # Split the OSC prefix across writes to exercise streaming detection.
    print("\x1b]75", end="", flush=True)
    time.sleep(0.05)
    print(f"01;state={state}\x1b\\", end="", flush=True)
'''
            # Give tmux the same argv[0] it sees for the real Codex binary.
            fake_codex.write_text(f'''#!/usr/bin/env python3
import os
import sys
os.execv(sys.executable, ["codex", "-c", {reports!r}])
''')
            fake_codex.chmod(0o755)
            status_reader = indicator.with_name("codex-status")
            status_reader.write_text("#!/bin/sh\nexec " + shlex.join([
                sys.executable,
                str(ROOT / "scripts/codex-tmux.py"), TMUX, str(indicator),
            ]) + ' "$@"\n')
            status_reader.chmod(0o755)
            function = shlex.quote(str(ROOT / "fish/functions/codex.fish"))
            codex_pane = tmux("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", sid,
                              "env", f"PATH={env['PATH']}", f"XDG_CONFIG_HOME={config_dir.parent}",
                              "fish", "--no-config", "-i")
            tmux("send-keys", "-t", codex_pane, "-l",
                 f"source {function}; codex; printf 'CODEX_EXIT=%s\\n' $status")
            tmux("send-keys", "-t", codex_pane, "Enter")

            def codex_icon():
                return tmux("display-message", "-p", "-t", codex_pane, "#{E:@status_task_icon}")

            def codex_pipe():
                return tmux("display-message", "-p", "-t", codex_pane, "#{?pane_pipe,1,0}")

            wait_for(codex_pipe, "1")
            if sys.platform == "linux":
                wait_for(lambda: tmux("display-message", "-p", "-t", codex_pane,
                                      "#{pane_current_command}"), "codex")
                wait_for(lambda: tmux("display-message", "-p", "-t", codex_pane,
                                      "#{window_name}"), "codex")
            for state, expected in (("idle:app=codex", "●"), ("working:app=codex", "◐"),
                                    ("blocked:app=codex:kind=question", "?"),
                                    ("done:app=codex", "✓")):
                tmux("send-keys", "-t", codex_pane, state, "Enter")
                try:
                    wait_for(codex_icon, expected)
                except AssertionError:
                    raise AssertionError((state, codex_icon(), codex_pipe(),
                                          tmux("capture-pane", "-p", "-t", codex_pane),
                                          tmux("display-message", "-p", "-t", codex_pane,
                                               "#{@agent_state}"))) from None
            tmux("send-keys", "-t", codex_pane, "exit", "Enter")
            wait_for(codex_pipe, "0")
            wait_for(codex_icon, "●")
            assert "CODEX_EXIT=7" in tmux("capture-pane", "-p", "-t", codex_pane)
            tmux("kill-pane", "-t", codex_pane)

            if codex_only:
                print("Verified Codex terminal status.")
                return

            # A real client shows aligned hints and returns to two rows when Jump ends.
            second = tmux("display-message", "-p", "-t", f"{sid}:1", "#{window_id}")
            for index, label in enumerate(("git diff", "nix build", "cargo test")):
                target = f"{sid}:{index}"
                tmux("rename-window", "-t", target, "fish")
                tmux("set-option", "-p", "-t", target, "@last_shell_command", label)
            real_jump.touch()
            pid, terminal = pty.fork()
            if pid == 0:
                os.execve(TMUX, [TMUX, "-S", socket, "attach-session", "-t", sid], env)

            def status_height():
                return tmux("show-options", "-Av", "-t", sid, "status")

            def key_table():
                return tmux("list-clients", "-F", "#{client_key_table}")

            def start_jump():
                os.write(terminal, b"\x01 ")
                wait_for(key_table, "window-jump")
                wait_for(status_height, "3")

            def close_jump(key):
                os.write(terminal, key)
                wait_for(key_table, "root")
                wait_for(status_height, "2")

            try:
                fcntl.ioctl(terminal, termios.TIOCSWINSZ,
                            struct.pack("HHHH", 30, 120, 0, 0))
                wait_for(lambda: tmux("list-clients", "-F", "#{session_id}"), sid)
                client_tty = tmux("list-clients", "-F", "#{client_tty}")

                def task(*args):
                    pane = tmux("display-message", "-p", "-t", second, "#{pane_id}")
                    subprocess.run([str(indicator), *args], env=dict(env, TMUX_PANE=pane), check=True)

                def icon():
                    return tmux("display-message", "-p", "-t", second, "#{E:@status_task_icon}")

                task("task-start")
                assert icon() == "◐"
                task("task-end", "1")
                assert icon() == "!"
                task("agent-idle")
                assert icon() == "●"
                task("agent-start")
                assert icon() == "◐"
                task("agent-waiting")
                assert icon() == "?"
                task("agent-working")
                assert icon() == "◐"
                task("agent-done")
                assert icon() == "✓"

                start_jump()
                output = b""
                deadline = time.monotonic() + 3
                while b"[d]" not in output and time.monotonic() < deadline:
                    if select.select([terminal], [], [], 0.1)[0]:
                        output += os.read(terminal, 65536)
                assert all(hint in output for hint in (b"[a] git diff", b"[s] nix build", b"[d]")), (
                    output[-1000:], tmux("show-options", "-t", sid),
                    tmux("display-message", "-p", "-c", client_tty,
                         "#{W:#{window_id}:#{@jump_targets}:#{E:@status_jump_key} }"))
                assert b"cargo test" not in output
                expanded = tmux("display-message", "-p", "-c", client_tty, "#{E:status-format[1]}")
                assert "fill=#45475a" in expanded, expanded
                assert "git diff" not in expanded and "nix build" not in expanded, expanded
                close_jump(b"s")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), second)
                wait_for(icon, "●")
                task("agent-start")
                task("agent-done")
                assert icon() == "●"
                task("agent-exit")

                tmux("set-option", "-p", "-t", f"{sid}:0", "@last_shell_command", "ls")
                tmux("set-option", "-p", "-t", f"{sid}:0", "@last_shell_fallback", "pwd")
                start_jump()
                jump_row = tmux("display-message", "-p", "-c", client_tty, "#{E:status-format[2]}")
                assert "[a] ls" in jump_row and "[s] nix build" in jump_row, jump_row
                close_jump(b"\x1b")
                assert tmux("display-message", "-p", "-t", sid, "#{window_id}") == second
                expanded = tmux("display-message", "-p", "-c", client_tty, "#{E:status-format[1]}")
                assert "fill=#45475a" not in expanded, expanded

                start_jump()
                close_jump(b"o")
                wait_for(lambda: json.loads(log.read_text().splitlines()[-1])[0], "display-popup")
                popup = json.loads(log.read_text().splitlines()[-1])
                assert popup[:5] == ["display-popup", "-c", client_tty, "-t", f"{sid}:"]
                assert "--windows" in popup[-1]

                start_jump()
                close_jump(b"a")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), wid)

                tmux("move-window", "-d", "-s", third, "-t", f"{sid}:7")
                start_jump()
                close_jump(b"7")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), third)
                start_jump()
                close_jump(b"2")
                assert tmux("display-message", "-p", "-t", sid, "#{window_id}") == third

                # The normal numeric binding still works and higher indexes still have letters.
                os.write(terminal, b"\x010")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), wid)
                tmux("move-window", "-d", "-s", third, "-t", f"{sid}:10")
                start_jump()
                close_jump(b"d")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), third)
                os.write(terminal, b"\x010")
                wait_for(lambda: tmux("display-message", "-p", "-t", sid, "#{window_id}"), wid)

                start_jump()
                close_jump(b"q")
                assert tmux("display-message", "-p", "-t", sid, "#{window_id}") == wid

                # The bar recovers even when no Jump key binding runs.
                start_jump()
                tmux("switch-client", "-c", client_tty, "-T", "root")
                wait_for(status_height, "2")
                start_jump()
                close_jump(b"\x1b")

                start_jump()
                tmux("switch-client", "-c", client_tty, "-T", "root")
                start_jump()
                time.sleep(0.45)
                assert key_table() == "window-jump" and status_height() == "3"
                close_jump(b"\x1b")

                # A stale owner from a previous configuration must never block entry.
                tmux("set-option", "-t", sid, "@jump_client", client_tty, ";",
                     "set-option", "-t", sid, "@jump_previous_status", "inherit", ";",
                     "set-option", "-t", sid, "@jump_targets", f" {wid}/a ", ";",
                     "set-option", "-t", sid, "status", "3")
                start_jump()
                close_jump(b"\x1b")

                start_jump()
                tmux("switch-client", "-c", client_tty, "-t", "=team app")
                wait_for(status_height, "2")
                wait_for(key_table, "root")
                tmux("switch-client", "-c", client_tty, "-t", sid)

                # Jump also works when no windows share both a name and a directory.
                tmux("rename-window", "-t", f"{sid}:1", "second")
                start_jump()
                tmux("detach-client", "-t", client_tty)
                wait_for(status_height, "2")
                wait_for(lambda: tmux("show-options", "-qv", "-t", sid, "@jump_client"), "")
            finally:
                if not os.waitpid(pid, os.WNOHANG)[0]:
                    os.kill(pid, signal.SIGTERM)
                    os.waitpid(pid, 0)
                os.close(terminal)
                real_jump.unlink()

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
            print("Verified previews, labels, selection, confirmation cancellation, deletion, list refresh, current-session handoff, last-session warning, Quick Jump, and Codex terminal status.")
        finally:
            subprocess.run([TMUX, "-S", socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    check(codex_only=sys.argv[1:] == ["--codex-only"])
