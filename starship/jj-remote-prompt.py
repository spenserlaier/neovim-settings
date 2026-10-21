"""Read-only remote bookmark row for Starship; no fetching or WC snapshotting."""

import collections
import json
import os
import shutil
import subprocess
import unicodedata


def jj(*args):
    return subprocess.run(
        ["jj", "--ignore-working-copy", "--color", "never", "--no-pager", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=2,
    ).stdout


def ancestor_distances(graph, depth):
    """Graph records are ordered with the working-copy commit first."""
    distances = {}
    queue = collections.deque([(graph[0][0], 0)])
    parents = {record[0]: record[1:] for record in graph}
    while queue:
        commit, distance = queue.popleft()
        if commit in distances or distance > depth:
            continue
        distances[commit] = distance
        queue.extend((parent, distance + 1) for parent in parents.get(commit, []))
    return distances


def select_remotes(refs, distances):
    local_names = {
        ref["name"]
        for ref in refs
        if not ref.get("remote")
        and any(target in distances for target in ref["targets"])
    }
    selected = [
        ref
        for ref in refs
        if ref.get("remote") not in (None, "git")
        and (
            ref["name"] in local_names
            or any(target in distances for target in ref["targets"])
        )
    ]
    return sorted(
        selected,
        key=lambda ref: (
            min((distances.get(t, float("inf")) for t in ref["targets"]),
                default=float("inf")),
            ref["name"],
            ref["remote"],
        ),
    )


def relation_suffix(local_only, remote_only):
    # Counts are relative to the working copy, not to the local bookmark.
    if local_only and remote_only:
        return f"↔↑{remote_only}↓{local_only}"
    if remote_only:
        return f"↑{remote_only}"
    if local_only:
        return f"~{local_only}"
    return ""


def visible_width(text):
    return sum(
        0 if unicodedata.combining(char)
        else 2 if unicodedata.east_asian_width(char) in ("W", "F")
        else 1
        for char in text
    )


def wrap_entries(entries, width):
    """Wrap between complete entries; never truncate a bookmark name."""
    lines = []
    line = "remote "
    for entry in entries:
        if line not in ("remote ", "       "):
            if visible_width(line + ", " + entry) > width:
                lines.append(line + ",")
                line = "       "
            else:
                line += ", "
        line += entry
    if entries:
        lines.append(line)
    return "\n".join(lines)


def main():
    depth = max(0, int(os.environ.get("JJ_STARSHIP_ANCESTOR_BOOKMARK_DEPTH", "10")))
    graph = [line.split() for line in jj(
        "log", "--no-graph", "-r", f"ancestors(@, {depth + 1})",
        "-T", 'commit_id ++ " " ++ parents.map(|p| p.commit_id()).join(" ") ++ "\\n"',
    ).splitlines()]
    if not graph:
        return
    distances = ancestor_distances(graph, depth)
    template = (
        '\'{"name":\' ++ json(name) ++ \',"remote":\' ++ json(remote)'
        ' ++ \',"targets":\' ++ json(added_targets.map(|c| c.commit_id()))'
        ' ++ \',"conflict":\' ++ json(conflict) ++ "}\\n"'
    )
    refs = [json.loads(line) for line in jj(
        "bookmark", "list", "--all-remotes", "-T", template,
    ).splitlines()]
    entries = []
    for ref in select_remotes(refs, distances):
        name = f'{ref["name"]}@{ref["remote"]}'
        if ref["conflict"]:
            suffix = "!"
        elif not ref["targets"]:
            suffix = " (deleted)"
        else:
            # Only hexadecimal commit IDs enter this revset, never bookmark names.
            target = ref["targets"][0]
            counts = jj(
                "log", "--no-graph", "-r", f"({target}..@) | (@..{target})",
                "-T", 'if(self.contained_in("::@"), "L", "R")',
            )
            suffix = relation_suffix(counts.count("L"), counts.count("R"))
        # Keep terminal control characters out of the prompt.
        name = "".join(c if not unicodedata.category(c).startswith("C") else "?"
                       for c in name)
        entries.append(name + suffix)
    columns = os.environ.get("COLUMNS")
    width = int(columns) if columns else shutil.get_terminal_size((80, 24)).columns
    output = wrap_entries(entries, max(1, width - 1))
    if output:
        print(output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        # A prompt should remain usable outside repos and during concurrent edits.
        pass
