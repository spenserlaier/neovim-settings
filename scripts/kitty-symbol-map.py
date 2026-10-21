"""Generate Kitty mappings for the pinned Noto symbol font's supported ranges."""

from pathlib import Path
import sys

from fontTools.ttLib import TTFont


# Unicode symbol blocks; leave text, private-use Nerd Font icons, and Kitty's
# built-in box drawing, block elements, and braille rendering alone.
SYMBOL_BLOCKS = (
    (0x2190, 0x23FF),
    (0x2460, 0x24FF),
    (0x25A0, 0x27FF),
    (0x2900, 0x2BFF),
    (0x1CC00, 0x1CEBF),
    (0x1D300, 0x1D35F),
    (0x1F000, 0x1FAFF),
    (0x1FB00, 0x1FBFF),
)


def contiguous_ranges(codepoints):
    start = end = codepoints[0]
    for codepoint in codepoints[1:]:
        if codepoint == end + 1:
            end = codepoint
        else:
            yield start, end
            start = end = codepoint
    yield start, end


def main(directory):
    paths = sorted([*Path(directory).rglob("*.ttf"), *Path(directory).rglob("*.otf")])
    if len(paths) != 1:
        raise ValueError(f"Expected one symbol font, found {paths}")
    with TTFont(paths[0]) as font:
        family = font["name"].getDebugName(16) or font["name"].getDebugName(1)
        cmap = font.getBestCmap()
        points = sorted(
            cp for cp in cmap
            if any(start <= cp <= end for start, end in SYMBOL_BLOCKS)
        )
    print("# Generated from the pinned font's cmap; only supported symbols are mapped.")
    print(f"# Font: {family}; {len(points)} mapped characters.")
    ranges = [
        f"U+{start:04X}" if start == end else f"U+{start:04X}-U+{end:04X}"
        for start, end in contiguous_ranges(points)
    ]
    for offset in range(0, len(ranges), 8):
        print(f"symbol_map {','.join(ranges[offset:offset + 8])} {family}")


if __name__ == "__main__":
    main(sys.argv[1])
