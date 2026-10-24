#!/usr/bin/env python3
"""Browse the current jj change using the shared vi_fzf picker."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")


def run_jj(root, *args):
    return subprocess.check_output(
        ["jj", "--no-pager", "--color=never", *args], cwd=root, text=True
    )


def split_hunks(patch):
    """Keep file metadata and context; find the first changed destination line."""
    lines = patch.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if HUNK.match(line)]
    header = "".join(lines[: starts[0]]) if starts else patch
    result = []
    for number, start in enumerate(starts):
        end = starts[number + 1] if number + 1 < len(starts) else len(lines)
        match = HUNK.match(lines[start])
        cursor = int(match[3])
        destination = max(1, cursor)
        for line in lines[start + 1 : end]:
            if line.startswith(("+", "-")):
                destination = max(1, cursor)
                break
            if line.startswith(" "):
                cursor += 1
        result.append({
            "line": destination,
            "heading": lines[start].strip(),
            "patch": header + "".join(lines[start:end]),
        })
    return result


def collect(root):
    # Snapshot once, then use the same immutable commit for every file diff.
    commit = run_jj(root, "log", "-r", "@", "--no-graph", "-T", "commit_id").strip()
    listing = run_jj(
        root, "--ignore-working-copy", "diff", "-r", commit, "-T",
        'json(path) ++ "\\t" ++ status_char ++ "\\t" ++ json(source.path()) ++ "\\n"',
    )
    entries = []
    for row in listing.splitlines():
        path_json, status, source_json = row.split("\t")
        path, source = json.loads(path_json), json.loads(source_json)
        # Include both sides of a rename, with literal filesets for unusual names.
        paths = list(dict.fromkeys([path, source]))
        patch = run_jj(root, "--ignore-working-copy", "diff", "-r", commit, "--git", "--",
                       *["root-file:" + json.dumps(p, ensure_ascii=False) for p in paths])
        hunks = split_hunks(patch)
        entry = {"path": path, "status": status, "patch": patch,
                 "line": hunks[0]["line"] if hunks else 1}
        entries.append({**entry, "key": [path, 0], "heading": ""})
        for index, hunk in enumerate(hunks or [{"line": 1, "heading": "[no text hunks]", "patch": patch}]):
            entries.append({**entry, **hunk, "key": [path, index + 1]})
    return entries


def label(entry):
    # Escape control characters in display labels; raw paths stay in JSON only.
    path = json.dumps(entry["path"], ensure_ascii=False)[1:-1]
    return f'{entry["status"]} {path}' + (f'  {entry["heading"]}' if entry["heading"] else "")


def show_patch(patch, fullscreen=False):
    # Delta supplies syntax coloring and pagination; it is already in home.packages.
    command = ["delta", "--paging=" + ("always" if fullscreen else "never")]
    if not fullscreen:
        command += ["--width", os.environ.get("FZF_PREVIEW_COLUMNS", "80")]
    subprocess.run(command, input=patch, text=True, check=False)


def preview(state, identifier):
    entries = json.loads(Path(state).read_text())
    show_patch(entries[int(identifier)]["patch"])


def open_entry(root, entry):
    path = root / entry["path"]
    if entry["status"] == "D" or not path.is_file() or path.is_symlink():
        # Deleted/binary-only entries remain reviewable without creating files.
        show_patch(entry["patch"], fullscreen=True)
        return
    with path.open("rb") as stream:
        if b"\0" in stream.read(8192):
            show_patch(entry["patch"], fullscreen=True)
            return
    with path.open("rb") as stream:
        line_count = sum(1 for _ in stream)
    line = min(entry["line"], max(1, line_count))
    subprocess.run(["nvim", f"+{line}", "--", str(path)], cwd=root, check=False)


def pick(entries, mode, query, selected, state):
    visible = [(i, entry) for i, entry in enumerate(entries) if bool(entry["key"][1]) == (mode == "hunks")]
    rows = "".join(f"{i}\t{label(entry)}\n" for i, entry in visible)
    common = ["--delimiter=\t", "--with-nth=2..", "--layout=reverse", "--no-sort", "--no-multi"]
    # Calculate the selected row after filtering, keeping the file across mode switches.
    matches = subprocess.run(["fzf", *common, "--filter", query], input=rows, text=True,
                             stdout=subprocess.PIPE, check=False).stdout.splitlines()
    position = 1
    if selected:
        candidates = [(n + 1, entries[int(row.split("\t", 1)[0])]) for n, row in enumerate(matches)]
        exact = next((n for n, entry in candidates if entry["key"] == selected), None)
        position = exact or next((n for n, entry in candidates if entry["path"] == selected[0]), 1)
    other = "files" if mode == "hunks" else "hunks"
    helper = shlex.join([sys.executable, str(Path(__file__).resolve()), "--preview", state]) + " {1}"
    command = [
        "fish", "-c", "vi_fzf $argv", "--", *common,
        "--query", query, "--print-query", "--expect=ctrl-g,ctrl-o,enter",
        "--prompt", f"{mode}> ",
        "--header", f"{mode.upper()} · Ctrl-G: {other} · Enter: diff · Ctrl-O: nvim · Ctrl-/: preview",
        "--preview", helper,
        "--preview-window", "right,65%,border-left,<100(down,60%,border-top)",
        "--bind", "ctrl-/:toggle-preview", "--bind", f"start:pos({position})",
    ]
    environment = {**os.environ, "VI_FZF_MODE_FILE": state + ".vi-mode"}
    result = subprocess.run(command, input=rows, text=True, stdout=subprocess.PIPE,
                            env=environment, check=False)
    output = result.stdout.splitlines()
    if result.returncode not in (0, 1) or len(output) < 2:
        return None
    identifier = int(output[2].split("\t", 1)[0]) if len(output) > 2 else None
    return output[0], output[1], entries[identifier] if identifier is not None else None


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--preview":
        preview(sys.argv[2], sys.argv[3])
        return
    parser = argparse.ArgumentParser(description="Review the current jj change. Ctrl-G switches files/hunks; Enter shows the diff; Ctrl-O opens Neovim and returns.")
    parser.add_argument("-H", "--hunks", action="store_true", help="start in hunk mode")
    args = parser.parse_args()
    root = Path(run_jj(None, "root").strip())
    mode, query, selected = "hunks" if args.hunks else "files", "", None
    with tempfile.TemporaryDirectory(prefix="jjr-") as directory:
        state = str(Path(directory) / "entries.json")
        entries = collect(root)
        while entries:
            Path(state).write_text(json.dumps(entries))
            picked = pick(entries, mode, query, selected, state)
            if picked is None:
                return
            query, action, entry = picked
            if entry:
                selected = entry["key"]
            if action == "ctrl-g":
                mode = "files" if mode == "hunks" else "hunks"
            elif entry:
                if action == "ctrl-o":
                    open_entry(root, entry)
                    entries = collect(root)
                else:
                    show_patch(entry["patch"], fullscreen=True)
            else:
                return
        print("jjr: no changes in the current change.")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"jjr: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
