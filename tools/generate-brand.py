#!/usr/bin/env python3
"""Generate WaxDeck's brand assets: the mark, the app icons, the grain.

The mark is the tuner dial: a warm charcoal tile, an amber arc, and the
VU needle resting where a meter rests when the music is playing. It is
drawn here rather than exported from a design tool so the identity has a
single source that anyone can re-run, and so an icon size that reads badly
can be fixed by changing a number instead of by redrawing.

No third-party dependencies: shapes are evaluated as coverage over a
supersampled grid and written as PNG through zlib, and the ICO container
is a handful of structs around those PNGs. The only optional dependency is
fontTools (already provisioned by tools/fetch-fonts.sh), used to trace the
wordmark's letterforms into an SVG master.

    python3 tools/generate-brand.py

Everything it writes is committed; re-run it when the mark changes.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_BRAND = ROOT / "app/packages/waxdeck_ui/assets/brand"
APP = ROOT / "app/app"

# The palette, mirrored from waxdeck_ui's colour tokens. Keep in step with
# lib/src/tokens/colors.dart.
CANVAS_DARK = (0x16, 0x13, 0x0F)
SURFACE_DARK = (0x1E, 0x19, 0x13)
CANVAS_LIGHT = (0xFA, 0xF9, 0xF6)
AMBER = (0xE3, 0xA2, 0x44)
AMBER_DEEP = (0x8A, 0x5A, 0x12)
TEXT_DARK = (0xF3, 0xED, 0xE3)
HAIRLINE = (0x3B, 0x32, 0x26)
DIAL = (0x82, 0x70, 0x57)

SS = 4  # supersampling factor per axis


# --- tiny raster canvas ------------------------------------------------------


class Canvas:
    """An RGBA float canvas with analytic-ish coverage from supersampling."""

    def __init__(self, size: int, background=None):
        self.size = size
        self.px = [[(0.0, 0.0, 0.0, 0.0) for _ in range(size)] for _ in range(size)]
        if background is not None:
            self.fill_all(background)

    def fill_all(self, color):
        r, g, b = [c / 255 for c in color]
        self.px = [[(r, g, b, 1.0) for _ in range(self.size)] for _ in range(self.size)]

    def draw(self, inside, color, alpha=1.0, bounds=None):
        """Fill every pixel by the coverage of `inside(x, y)`."""
        step = 1.0 / SS
        offset = step / 2
        weight = 1.0 / (SS * SS)
        x0, y0, x1, y1 = (
            bounds or getattr(inside, "bounds", (0, 0, self.size, self.size))
        )
        x0 = max(0, int(math.floor(x0)))
        y0 = max(0, int(math.floor(y0)))
        x1 = min(self.size, int(math.ceil(x1)) + 1)
        y1 = min(self.size, int(math.ceil(y1)) + 1)
        for y in range(y0, y1):
            row = self.px[y]
            for x in range(x0, x1):
                coverage = 0.0
                for sy in range(SS):
                    py = y + offset + sy * step
                    for sx in range(SS):
                        if inside(x + offset + sx * step, py):
                            coverage += weight
                if coverage > 0:
                    r, g, b = [c / 255 for c in color]
                    a = coverage * alpha
                    pr, pg, pb, pa = row[x]
                    out_a = a + pa * (1 - a)
                    row[x] = (
                        (r * a + pr * pa * (1 - a)) / out_a,
                        (g * a + pg * pa * (1 - a)) / out_a,
                        (b * a + pb * pa * (1 - a)) / out_a,
                        out_a,
                    )

    def to_png(self) -> bytes:
        raw = bytearray()
        for row in self.px:
            raw.append(0)
            for r, g, b, a in row:
                raw += bytes(
                    (
                        max(0, min(255, round(r * 255))),
                        max(0, min(255, round(g * 255))),
                        max(0, min(255, round(b * 255))),
                        max(0, min(255, round(a * 255))),
                    )
                )
        return _png(self.size, self.size, bytes(raw))


def _png(width: int, height: int, raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


# --- shape helpers -----------------------------------------------------------


def rounded_rect(x0, y0, x1, y1, radius):
    def inside(x, y):
        cx = min(max(x, x0 + radius), x1 - radius)
        cy = min(max(y, y0 + radius), y1 - radius)
        if x0 <= x <= x1 and y0 <= y <= y1:
            if (x < x0 + radius or x > x1 - radius) and (
                y < y0 + radius or y > y1 - radius
            ):
                return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius
            return True
        return False

    inside.bounds = (x0, y0, x1, y1)
    return inside


def circle(cx, cy, radius):
    inside = lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius
    inside.bounds = (cx - radius, cy - radius, cx + radius, cy + radius)
    return inside


def arc(cx, cy, radius, thickness, start, sweep):
    """An annulus sector, angles in radians, 0 pointing right, y down."""
    inner = radius - thickness / 2
    outer = radius + thickness / 2
    end = start + sweep

    def inside(x, y):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        if not (inner <= d <= outer):
            return False
        angle = math.atan2(dy, dx)
        while angle < start:
            angle += math.tau
        return angle <= end

    inside.bounds = (cx - outer, cy - outer, cx + outer, cy + outer)
    return inside


def segment(x0, y0, x1, y1, thickness):
    half = thickness / 2

    def inside(px, py):
        dx, dy = x1 - x0, y1 - y0
        length2 = dx * dx + dy * dy
        t = 0.0 if length2 == 0 else ((px - x0) * dx + (py - y0) * dy) / length2
        t = max(0.0, min(1.0, t))
        return math.hypot(px - (x0 + t * dx), py - (y0 + t * dy)) <= half

    inside.bounds = (
        min(x0, x1) - half,
        min(y0, y1) - half,
        max(x0, x1) + half,
        max(y0, y1) + half,
    )
    return inside


# --- the mark ----------------------------------------------------------------


def draw_mark(
    size: int,
    *,
    background=None,
    tile: bool = True,
    ink=AMBER,
    dial=DIAL,
    padding: float = 0.0,
    monochrome: bool = False,
    flat=None,
    deflection: float = 0.6,
) -> Canvas:
    """The dial mark: an arc with the needle parked where a meter rests.

    `padding` insets the drawing for adaptive icons and maskable web
    icons, whose outer ring is cropped by the launcher.

    `flat` draws every stroke in one colour, for the tray glyphs, whose
    platforms want a single-ink shape they tint themselves. `deflection`
    moves the needle along the arc, which is how the tray says whether
    the music is playing: a badge in the corner would be mush at 22 px,
    and a meter that reads is the whole point of the mark.
    """
    if flat is not None:
        ink = dial = flat
    canvas = Canvas(size, background)
    inset = size * padding
    box0, box1 = inset, size - inset
    extent = box1 - box0

    if tile:
        canvas.draw(
            rounded_rect(box0, box0, box1, box1, extent * 0.22),
            CANVAS_DARK if not monochrome else (0, 0, 0),
        )

    cx = size / 2
    cy = box0 + extent * 0.78
    radius = extent * 0.44
    thickness = max(1.0, extent * 0.055)

    # The dial band, then the needle at the resting deflection the design
    # language uses for a paused meter.
    start = math.pi + math.pi * 0.19
    sweep = math.pi * 0.62
    canvas.draw(
        arc(cx, cy, radius, thickness, start, sweep),
        dial if not monochrome else (255, 255, 255),
        alpha=1.0 if not monochrome else 0.45,
    )

    angle = start + sweep * deflection
    tip_x = cx + math.cos(angle) * radius * 1.02
    tip_y = cy + math.sin(angle) * radius * 1.02
    needle = ink if not monochrome else (255, 255, 255)
    canvas.draw(
        segment(cx, cy, tip_x, tip_y, max(1.0, extent * 0.07)),
        needle,
    )
    canvas.draw(circle(cx, cy, max(1.2, extent * 0.075)), needle)

    # Two dial ticks: enough to read as equipment, few enough to survive
    # a 16 px favicon.
    for fraction in (0.12, 0.88):
        a = start + sweep * fraction
        r0 = radius * 1.16
        r1 = radius * 1.30
        canvas.draw(
            segment(
                cx + math.cos(a) * r0,
                cy + math.sin(a) * r0,
                cx + math.cos(a) * r1,
                cy + math.sin(a) * r1,
                max(1.0, extent * 0.035),
            ),
            dial if not monochrome else (255, 255, 255),
            alpha=1.0 if not monochrome else 0.45,
        )
    return canvas


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"  {path.relative_to(ROOT)} ({len(data) / 1024:.1f} KB)")


def write_icon(path: Path, size: int, **kwargs) -> None:
    write(path, draw_mark(size, **kwargs).to_png())


# --- containers --------------------------------------------------------------


def write_ico(path: Path, sizes) -> None:
    """A Windows icon: PNG-compressed entries in an ICONDIR."""
    images = [(s, draw_mark(s).to_png()) for s in sizes]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for size, png in images:
        entries += struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            len(png),
            offset,
        )
        blobs += png
        offset += len(png)
    write(path, header + entries + blobs)


def write_grain(path: Path, size: int = 64) -> None:
    """Deterministic monochrome noise for the player backdrop.

    Grain is what keeps a deep gradient from banding on OLED, so it ships
    as one small tiled asset rather than as a runtime shader.
    """
    state = 0x5EED
    raw = bytearray()
    for _ in range(size):
        raw.append(0)
        for _ in range(size):
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            value = 128 + ((state >> 16) % 128)
            raw += bytes((value, value, value, 255))
    write(path, _png(size, size, bytes(raw)))


# --- the wordmark ------------------------------------------------------------


def write_wordmark_svg(path: Path) -> None:
    """Trace 'WaxDeck' in Archivo Expanded into an SVG master.

    The app draws its wordmark live from the bundled font (WaxWordmark),
    so this file is for the places Flutter is not: the README, the docs
    header, packaging art.
    """
    cache = ROOT / "tools/.cache/fonttools"
    font_path = ROOT / "app/packages/waxdeck_ui/fonts/Archivo-Variable.ttf"
    if not (cache / "fontTools").exists() or not font_path.exists():
        print("  (skipping wordmark.svg: run tools/fetch-fonts.sh first)")
        return
    sys.path.insert(0, str(cache))
    from fontTools.pens.svgPathPen import SVGPathPen  # noqa: PLC0415
    from fontTools.ttLib import TTFont  # noqa: PLC0415
    from fontTools.varLib.instancer import instantiateVariableFont  # noqa: PLC0415

    font = TTFont(str(font_path))
    # Expanded, at the display token's weight.
    font = instantiateVariableFont(font, {"wght": 640, "wdth": 125}, inplace=True)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upem = font["head"].unitsPerEm

    paths, x = [], 0
    for char in "WaxDeck":
        name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        commands = pen.getCommands()
        if commands:
            paths.append(f'<path transform="translate({x} 0)" d="{commands}"/>')
        x += glyphs[name].width

    height = upem * 1.25
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {x} {height}" width="{x / upem * 64:.0f}" height="{height / upem * 64:.0f}">
  <title>WaxDeck</title>
  <g fill="#E3A244" transform="translate(0 {upem}) scale(1 -1)">
    {"\n    ".join(paths)}
  </g>
</svg>
"""
    write(path, svg.encode())


# --- platform kits -----------------------------------------------------------


def android(res: Path) -> None:
    for folder, size in (
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ):
        write_icon(res / folder / "ic_launcher.png", size)
        # Adaptive layers are drawn on a 108dp canvas of which only the
        # centre 72dp is guaranteed visible, so the mark is inset.
        write_icon(
            res / folder / "ic_launcher_foreground.png",
            round(size * 108 / 48),
            tile=False,
            padding=0.22,
        )
        write_icon(
            res / folder / "ic_launcher_monochrome.png",
            round(size * 108 / 48),
            tile=False,
            padding=0.22,
            monochrome=True,
        )
        # Android 12 splash: the icon inside the system's circle.
        write_icon(
            res / folder / "splash_icon.png",
            round(size * 288 / 48),
            tile=False,
            padding=0.28,
        )

    (res / "values").mkdir(parents=True, exist_ok=True)
    write(
        res / "values/colors.xml",
        b"""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tools/generate-brand.py -->
<resources>
    <color name="wax_canvas">#FAF9F6</color>
    <color name="wax_canvas_dark">#16130F</color>
    <color name="wax_icon_background">#16130F</color>
</resources>
""",
    )
    write(
        res / "mipmap-anydpi-v26/ic_launcher.xml",
        b"""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tools/generate-brand.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/wax_icon_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
""",
    )


def tray(out: Path) -> None:
    """The desktop tray glyphs: the mark with no tile, in one ink.

    Three platform conventions and two play states. macOS wants a
    template image - black with alpha, which the system inverts for a
    dark menu bar - and Windows wants the pair drawn for it, because a
    taskbar's own theme is what decides which reads. Linux takes the
    mark's own amber, where a StatusNotifier host draws it at all.

    The needle says the state: parked while paused, swung up while
    playing.
    """
    states = (("playing", 0.9), ("paused", 0.32))
    for state, deflection in states:
        write_icon(
            out / f"{state}-template.png",
            44,
            tile=False,
            flat=(0, 0, 0),
            deflection=deflection,
        )
        write_icon(
            out / f"{state}-light.png",
            32,
            tile=False,
            flat=CANVAS_DARK,
            deflection=deflection,
        )
        write_icon(
            out / f"{state}-dark.png",
            32,
            tile=False,
            flat=TEXT_DARK,
            deflection=deflection,
        )
        write_icon(out / f"{state}.png", 48, tile=False, deflection=deflection)


def macos(appicon: Path) -> None:
    entries = []
    for size, scales in ((16, (1, 2)), (32, (1, 2)), (128, (1, 2)), (256, (1, 2)), (512, (1, 2))):
        for scale in scales:
            pixels = size * scale
            name = f"app_icon_{pixels}.png"
            write_icon(appicon / name, pixels)
            entries.append(
                {
                    "size": f"{size}x{size}",
                    "idiom": "mac",
                    "filename": name,
                    "scale": f"{scale}x",
                }
            )
    write(
        appicon / "Contents.json",
        (
            json.dumps(
                {"images": entries, "info": {"version": 1, "author": "waxdeck"}},
                indent=2,
            )
            + "\n"
        ).encode(),
    )


def web(web_dir: Path) -> None:
    write_icon(web_dir / "favicon.png", 32)
    write_icon(web_dir / "icons/Icon-192.png", 192)
    write_icon(web_dir / "icons/Icon-512.png", 512)
    # Maskable icons are cropped to whatever shape the platform likes, so
    # the mark sits inside the safe zone on a full-bleed field.
    write_icon(web_dir / "icons/Icon-maskable-192.png", 192, tile=False, padding=0.20, background=CANVAS_DARK)
    write_icon(web_dir / "icons/Icon-maskable-512.png", 512, tile=False, padding=0.20, background=CANVAS_DARK)


def main() -> int:
    print("brand: design system assets")
    write_grain(UI_BRAND / "grain.png")
    write_wordmark_svg(UI_BRAND / "wordmark.svg")
    write_icon(UI_BRAND / "mark-512.png", 512)

    print("brand: tray")
    tray(APP / "assets/tray")

    print("brand: web")
    web(APP / "web")

    print("brand: android")
    android(APP / "android/app/src/main/res")

    print("brand: macos")
    macos(APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset")

    print("brand: windows")
    write_ico(APP / "windows/runner/resources/app_icon.ico", (16, 24, 32, 48, 64, 128, 256))

    print("brand: linux")
    for size in (16, 32, 48, 64, 128, 256, 512):
        write_icon(
            APP / f"linux/icons/hicolor/{size}x{size}/apps/waxdeck.png",
            size,
        )
    return 0


if __name__ == "__main__":
    os.chdir(ROOT)
    raise SystemExit(main())
