#!/usr/bin/env python3
"""Rederive WaxFonts' symbol-scatter routing tables from the fonts.

The detection ladder in `waxdeck_ui/lib/src/fonts/wax_fonts.dart` routes
the symbol scatter (U+2000-2BFF) by what the committed faces can
actually draw: codepoints only the colour emoji face maps go to the
emoji face, codepoints only the CJK face maps go to CJK, and anything an
eager Latin face draws - or nothing draws - falls through. This script
reads the font files and prints the two Dart tables, so the ladder and
the assets cannot drift apart by hand-editing: run it after `make fonts`
changes a face and paste the output.

Needs fontTools (`pip install fonttools`); it is not part of `make
generate` because the faces themselves change only when fetch-fonts.sh
is deliberately re-run.
"""

from fontTools.ttLib import TTFont
from pathlib import Path

UI = Path(__file__).resolve().parent.parent / "app/packages/waxdeck_ui"

# The BMP scatter fetch-fonts.sh subsets into the emoji face, minus the
# regions the ladder owns for whole scripts (CJK's 0x3000+ claim stays
# with CJK).
SCATTER_RANGES = [
    (0x203C, 0x203C), (0x2049, 0x2049), (0x2122, 0x2122), (0x2139, 0x2139),
    (0x2194, 0x21AA), (0x231A, 0x231B), (0x2328, 0x2328), (0x23CF, 0x23CF),
    (0x23E9, 0x23FA), (0x24C2, 0x24C2), (0x25AA, 0x25AB), (0x25B6, 0x25B6),
    (0x25C0, 0x25C0), (0x25FB, 0x25FE), (0x2600, 0x27BF), (0x2934, 0x2935),
    (0x2B00, 0x2B5F),
]


def codepoints(path: Path) -> set[int]:
    font = TTFont(path, fontNumber=0, lazy=True)
    out: set[int] = set()
    for table in font["cmap"].tables:
        if table.isUnicode():
            out |= set(table.cmap.keys())
    return out


def ranges(cps: set[int]) -> list[tuple[int, int]]:
    out: list[list[int]] = []
    for c in sorted(cps):
        if out and c == out[-1][1] + 1:
            out[-1][1] = c
        else:
            out.append([c, c])
    return [(a, b) for a, b in out]


def dart_table(name: str, cps: set[int]) -> str:
    pairs = [f"0x{a:04X}, 0x{b:04X}," for a, b in ranges(cps)]
    body = "\n    ".join(pairs)
    return f"  static const List<int> {name} = <int>[\n    {body}\n  ];"


def main() -> int:
    emoji = codepoints(UI / "assets/fonts/NotoColorEmoji.ttf")
    cjk = codepoints(UI / "assets/fonts/NotoSansCJK.otf")
    eager: set[int] = set()
    for name in ("Inter-Variable.ttf", "Archivo-Variable.ttf", "SplineSansMono-Variable.ttf"):
        eager |= codepoints(UI / "fonts" / name)

    scatter: set[int] = set()
    for a, b in SCATTER_RANGES:
        scatter |= set(range(a, b + 1))

    to_emoji = {c for c in scatter if c in emoji and c not in eager}
    to_cjk = {c for c in scatter if c in cjk and c not in emoji and c not in eager}

    print(dart_table("_emojiScatter", to_emoji))
    print()
    print(dart_table("_cjkScatter", to_cjk))
    print()
    left = sorted(scatter & eager)
    print(f"// eager-drawn, deliberately unrouted: {', '.join(f'{c:04X}' for c in left)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
