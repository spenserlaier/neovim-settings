#!/usr/bin/env python3
"""Show selected tmux bindings from annotations beside their definitions."""

import re
import sys
from pathlib import Path


MARKER = re.compile(r"^# CHEAT_SHEET_ENTRY: ([^|]+) \| (.+)$")
PREFIX = re.compile(r"^set -g prefix (\S+)$")


def readable(key: str) -> str:
    key = key.strip("'\"")
    if key.startswith("C-"):
        return "Ctrl-" + key[2:]
    return key


def binding(line: str) -> tuple[str, bool]:
    words = line.split()
    if not words or words[0] not in ("bind", "bind-key"):
        raise ValueError("annotation must precede a tmux bind or bind-key command")
    index = 1
    prefixed = True
    while index < len(words) and words[index].startswith("-"):
        flag = words[index]
        if flag == "-n":
            prefixed = False
        elif flag == "-T":
            index += 1
            if index >= len(words) or words[index] != "prefix":
                raise ValueError("only the prefix key table is supported")
        elif flag != "-r":
            raise ValueError(f"unsupported tmux bind option: {flag}")
        index += 1
    if index >= len(words):
        raise ValueError("binding has no key")
    return readable(words[index]), prefixed


def entries(config: Path) -> list[tuple[str, str, str]]:
    lines = config.read_text().splitlines()
    prefix = next((readable(match.group(1)) for line in lines if (match := PREFIX.match(line))), None)
    if prefix is None:
        raise ValueError("tmux prefix was not found")
    result = []
    for index, line in enumerate(lines):
        match = MARKER.fullmatch(line)
        if line.startswith("# CHEAT_SHEET_ENTRY:") and match is None:
            raise ValueError(f"{config}:{index + 1}: malformed cheat sheet annotation")
        if match is None:
            continue
        if index + 1 >= len(lines):
            raise ValueError(f"{config}:{index + 1}: annotation has no binding")
        try:
            key, prefixed = binding(lines[index + 1])
        except ValueError as error:
            raise ValueError(f"{config}:{index + 1}: {error}") from error
        result.append((match.group(1).strip(), f"{prefix} {key}" if prefixed else key, match.group(2).strip()))
    return result


def main() -> int:
    if len(sys.argv) < 2:
        print("cheat-sheet: missing tmux configuration path", file=sys.stderr)
        return 2
    args = sys.argv[2:]
    if args and args not in (["tmux"], ["--tmux"]):
        print("Usage: cheat-sheet [tmux|--tmux]", file=sys.stderr)
        return 2
    try:
        items = entries(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        print(f"cheat-sheet: {error}", file=sys.stderr)
        return 1
    print("Tmux shortcuts")
    group = None
    width = max(len(key) for _, key, _ in items)
    for category, key, description in items:
        if category != group:
            print(f"\n{category}")
            group = category
        print(f"  {key:<{width}}  {description}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
