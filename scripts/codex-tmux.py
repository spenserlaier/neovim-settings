#!/usr/bin/env python3
"""Read Codex's pane-local OSC 7501 status reports for the tmux indicator."""

import os
import re
import selectors
import shlex
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path


STATUS = re.compile(
    rb"\x1b\]7501;state=(?:(idle|working|blocked|done|error):app=codex"
    rb"(?::kind=(?:permission|question|auth))?|(clear))(?:\x07|\x1b\\)"
)
ACTIONS = {
    b"idle": "agent-idle",
    b"working": "agent-start",
    b"blocked": "agent-waiting",
    b"done": "agent-done",
    b"error": "agent-failed",
}


def watch(address, tmux, indicator):
    pane = os.environ["TMUX_PANE"]
    pending = b""
    previous = None
    control = None
    try:
        with socket.socket(socket.AF_UNIX) as listener, selectors.DefaultSelector() as events:
            listener.bind(address)
            listener.listen(1)
            events.register(sys.stdin, selectors.EVENT_READ)
            events.register(listener, selectors.EVENT_READ)
            while True:
                for key, _ in events.select():
                    if key.fileobj is listener:
                        control, _ = listener.accept()
                        return
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        return
                    pending += chunk
                    end = 0
                    for match in STATUS.finditer(pending):
                        end = match.end()
                        state = match[1] or b"idle"
                        # The visit hook acknowledges completion after a window switch.
                        if state == b"idle" and previous in (b"done", b"error"):
                            continue
                        if state != previous:
                            subprocess.run([indicator, ACTIONS[state]], check=False)
                            previous = state
                    # Retain only enough of the tail for a split escape sequence.
                    pending = pending[end:][-128:]
    finally:
        if previous is not None:
            subprocess.run([indicator, "agent-exit"], check=False)
        # Tmux may keep an output-only pipe after its reader exits, until
        # the next write. Close our pipe without touching a replacement.
        subprocess.run([
            tmux, "if-shell", "-F", "-t", pane,
            f"#{{==:#{{pane_pipe_pid}},{os.getpid()}}}",
            shlex.join(["pipe-pane", "-t", pane]),
        ], stderr=subprocess.DEVNULL, check=False)
        Path(address).unlink(missing_ok=True)
        Path(address).parent.rmdir()
        if control is not None:
            control.close()


def start(tmux, indicator):
    pane = os.environ["TMUX_PANE"]
    directory = Path(tempfile.mkdtemp(prefix="codex-tmux-", dir="/tmp"))
    address = str(directory / "status")
    command = "exec " + shlex.join([
        "/usr/bin/env", f"TMUX={os.environ['TMUX']}", f"TMUX_PANE={pane}",
        sys.executable, str(Path(__file__).resolve()), tmux, indicator, "watch", address,
    ]).replace("%", "%%").replace("#", "##")
    pipe = shlex.join(["pipe-pane", "-O", "-t", pane, command])
    result = subprocess.run(
        [tmux, "if-shell", "-F", "-t", pane, "#{==:#{?pane_pipe,1,0},0}",
         f"{pipe} ; display-message -p started"], capture_output=True, text=True, check=False,
    )
    if result.returncode == 0 and result.stdout.strip() == "started":
        print(address)
    else:
        directory.rmdir()


def stop(address):
    # Codex can exit before the monitor process has finished opening the socket.
    with socket.socket(socket.AF_UNIX) as control:
        control.settimeout(1)
        deadline = time.monotonic() + 1
        while Path(address).parent.exists() and time.monotonic() < deadline:
            try:
                control.connect(address)
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.02)
            else:
                try:
                    control.recv(1)
                except OSError:
                    pass
                return


if __name__ == "__main__":
    tmux, indicator, action, *args = sys.argv[1:]
    if action == "start":
        start(tmux, indicator)
    elif action == "stop":
        stop(*args)
    elif action == "watch":
        watch(*args, tmux, indicator)
