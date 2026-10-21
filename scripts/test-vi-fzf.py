"""Exercise the shared picker with real keystrokes in a pseudo-terminal."""

import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import struct
import tempfile
import termios
import time


ROOT = Path(__file__).resolve().parents[1]


def check(keys, expected, options="", query="", status=0, rows=("alpha", "beta", "jki/")):
    with tempfile.TemporaryDirectory(prefix="vi-fzf-") as temporary:
        directory = Path(temporary)
        output = directory / "output"
        script = directory / "picker.fish"
        script.write_text(
            f"source {shlex.quote(str(ROOT / 'fish/functions/vi_fzf.fish'))}\n"
            "printf '%s\\n' " + " ".join(shlex.quote(row) for row in rows)
            + " | vi_fzf --reverse --no-clear "
            f"--query {shlex.quote(query)} {options} > {shlex.quote(str(output))}\n"
            "exit $status\n"
        )
        pid, terminal = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 140, 0, 0))
            os.environ.update(TERM="xterm-256color", FZF_DEFAULT_OPTS="")
            os.environ.pop("FZF_DEFAULT_OPTS_FILE", None)
            os.execvp("fish", ["fish", "--no-config", str(script)])

        screen = bytearray()
        child_status = None

        def drain(seconds):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if select.select([terminal], [], [], max(0, deadline - time.monotonic()))[0]:
                    try:
                        data = os.read(terminal, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            return
                        raise
                    if not data:
                        return
                    screen.extend(data)

        try:
            deadline = time.monotonic() + 5
            while b"INSERT" not in screen and time.monotonic() < deadline:
                drain(0.1)
            assert b"INSERT" in screen, screen.decode(errors="replace")
            drain(0.15)
            for key in keys:
                os.write(terminal, key)
                drain(0.2)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                finished, child_status = os.waitpid(pid, os.WNOHANG)
                if finished:
                    break
                child_status = None
                drain(0.1)
            assert child_status is not None, screen.decode(errors="replace")
            assert os.waitstatus_to_exitcode(child_status) == status, screen.decode(errors="replace")
            actual = output.read_text()
            if expected is not None:
                assert actual == expected, (keys, actual, expected)
            return actual
        finally:
            if child_status is None:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(terminal)


if __name__ == "__main__":
    check([b"jki/", b"\r"], "jki/\n")  # Insert-mode literal keys.
    check([b"\x1b", b"j", b"\r"], "beta\n")
    check([b"\x1b", b"jjk", b"\r"], "beta\n")
    check([b"\x1b", b"z\x7f", b"\r"], "al\nalpha\n",
          options="--print-query", query="al")  # Normal mode cannot edit.
    for insert in (b"i", b"/"):
        check([b"\x1b", insert, b"ki/", b"\x1b", b"\r"], "jki/\njki/\n",
              options="--print-query", query="j")
    check([b"\x1b", b"j", b"\x18"], "\nctrl-x\nbeta\n",
          options="--expect=ctrl-x --print-query")
    check([b"\r"], "\n\nalpha\n", options="--expect=ctrl-x --print-query")
    # A caller's start reload must survive the wrapper's initialization.
    check([b"\r"], "reloaded\n", options="--bind 'start:reload(printf reloaded)'")
    # rgi-style external reload and its Ctrl-F transition are independent of mode.
    check([b"be", b"\x1b", b"i", b"\x06", b"be", b"\x1b", b"\r"],
          "be\nbeta\n", options="--disabled --print-query "
          "--bind 'change:reload(printf beta)' "
          "--bind 'ctrl-f:unbind(change,ctrl-f)+change-prompt(fzf> )+enable-search+clear-query'")
    for keys in ([b"\x03"], [b"\x1b", b"\x03"], [b"\x1b", b"\x1b"]):
        check(keys, "", status=130)
    # More than a screen of results distinguishes half-page movement from j/k.
    rows = [f"item {number:02}" for number in range(80)]
    for mode_keys in ([], [b"\x1b"]):
        output = check([*mode_keys, b"\x04", b"\r"], None,
                       options="--print-query", query="item", rows=rows)
        query, selected = output.splitlines()
        assert query == "item", output
        assert 1 < int(selected.split()[1]) < 40, output
        check([*mode_keys, b"\x04", b"\x15", b"\r"], "item\nitem 00\n",
              options="--print-query", query="item", rows=rows)
        # Ctrl-D must navigate even with an empty query rather than aborting.
        output = check([*mode_keys, b"\x04", b"\r"], None, rows=rows)
        assert 1 < int(output.split()[1]) < 40, output
    print("Verified insert/normal modes, query preservation, half-page navigation, cancellation, "
          "expected-key output, caller reloads, and the rgi search transition.")
