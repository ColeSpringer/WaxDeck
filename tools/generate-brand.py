#!/usr/bin/env python3
"""Derive WaxDeck's brand assets from the one committed master.

`docs/brand/waxdeck.png` is the logo: a candle burning against a record,
over textured paper, with the wordmark under it. Everything this script
writes is a crop, a resample, or a composite of that file, so the
identity has one source and an icon that reads badly is fixed by moving
a number here rather than by redrawing anything.

Two derived shapes carry it. The **chip** is the emblem on its own paper,
rounded - what an app icon is, and what puts the mark on a dark surface
without a halo. The **silhouette** is the emblem keyed out of that paper
into pure alpha, for the surfaces that supply their own colour: a macOS
template image, an Android status-bar icon, a Linux tray glyph.

Both are measured, not authored. Paper is read off the master's corner
patches, and the silhouette is keyed on blurred darkness rather than on
distance from paper - see key_silhouette, where the difference between a
readable glyph and a black circle lives. Everything is computed at master
resolution so the downsample does the feathering for free.

No third-party dependencies and no network: PNG decode is zlib plus an
unfilter, resampling is a two-pass separable area average, and the ICO
container is a handful of structs around PNGs.

    python3 tools/generate-brand.py

It also writes an uncommitted contact sheet to `tools/.cache/`, which is
the eyeball gate: roughly forty artifacts on one page at render size.
Everything else it writes is committed; re-run it when the master
changes.
"""

from __future__ import annotations

import base64
import json
import math
import os
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "docs/brand"
UI_BRAND = ROOT / "app/packages/waxdeck_ui/assets/brand"
APP = ROOT / "app/app"
CACHE = ROOT / "tools/.cache"

MASTER = BRAND / "waxdeck.png"

# Crops, in master pixel coordinates (the master is 1254 square).
#
# LOCKUP is the whole composition, emblem over wordmark, with a margin.
# EMBLEM is the square an app icon uses. Both emblem boxes are centred on
# the disc at (630, 462) rather than on the emblem's ink: the tonearm's
# outer tip is a faint tail reaching to x=1115, and centring on the ink
# it pulls pushes the disc visibly left and low. The tail crops instead,
# which costs about forty pixels nobody can see and buys a mark that sits
# in the middle of its own icon.
#
# EMBLEM_TIGHT frames the disc alone, for the sizes at and below 32
# pixels where the arm is three grey pixels that read as damage. The
# bottom of both is bounded by the wordmark, whose ink starts at y=901.
LOCKUP_BOX = (121, 11, 1162, 1152)
EMBLEM_BOX = (205, 37, 1055, 887)
EMBLEM_TIGHT_BOX = (245, 85, 1015, 855)

# Ink colours lifted from the master for the surfaces that need a flat
# one. Kept in step with waxdeck_ui's colour tokens.
CANVAS_DARK = (0x16, 0x13, 0x0F)
TEXT_LIGHT = (0xF3, 0xED, 0xE3)
AMBER = (0xE3, 0xA2, 0x44)

SS = 4  # supersampling factor per axis, for the drawn overlays


# --- images ------------------------------------------------------------------


class Image:
    """An 8-bit RGBA raster, one flat bytearray, row-major."""

    __slots__ = ("w", "h", "px")

    def __init__(self, w: int, h: int, px: bytearray | None = None):
        self.w = w
        self.h = h
        self.px = px if px is not None else bytearray(w * h * 4)

    def copy(self) -> "Image":
        return Image(self.w, self.h, bytearray(self.px))

    def to_png(self) -> bytes:
        return encode_png(self)


def decode_png(path: Path) -> Image:
    """Decode an 8-bit non-interlaced RGB or RGBA PNG into an Image.

    The asserts name the fix rather than the failure: a re-export that
    arrives 16-bit, palettized, or interlaced is a thing somebody did in
    a design tool, and "re-save it as X" is the useful message.
    """
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    idat, header, i = bytearray(), None, 8
    while i < len(data):
        length = struct.unpack(">I", data[i : i + 4])[0]
        kind = data[i + 4 : i + 8]
        body = data[i + 8 : i + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        i += 12 + length
    if header is None:
        raise SystemExit(f"{path}: no IHDR")
    w, h, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0 or colour not in (2, 6):
        raise SystemExit(
            f"{path}: unsupported PNG profile (bit depth {depth}, colour type "
            f"{colour}, interlace {interlace}). Re-export it as an 8-bit "
            "non-interlaced RGB or RGBA PNG."
        )
    channels = 3 if colour == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = w * channels
    out = Image(w, h)
    prior = bytearray(stride)
    pos = 0
    for y in range(h):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        _unfilter(filter_type, line, prior, channels, stride)
        if channels == 4:
            out.px[y * w * 4 : (y + 1) * w * 4] = line
        else:
            row = bytearray(w * 4)
            for x in range(w):
                s, d = x * 3, x * 4
                row[d] = line[s]
                row[d + 1] = line[s + 1]
                row[d + 2] = line[s + 2]
                row[d + 3] = 255
            out.px[y * w * 4 : (y + 1) * w * 4] = row
        prior = line
    return out


def _unfilter(kind: int, line: bytearray, prior: bytearray, ch: int, stride: int) -> None:
    if kind == 0:
        return
    if kind == 1:
        for x in range(ch, stride):
            line[x] = (line[x] + line[x - ch]) & 0xFF
    elif kind == 2:
        for x in range(stride):
            line[x] = (line[x] + prior[x]) & 0xFF
    elif kind == 3:
        for x in range(stride):
            left = line[x - ch] if x >= ch else 0
            line[x] = (line[x] + ((left + prior[x]) >> 1)) & 0xFF
    elif kind == 4:
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b = prior[x]
            c = prior[x - ch] if x >= ch else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[x] = (line[x] + pred) & 0xFF
    else:
        raise SystemExit(f"unknown PNG filter {kind}")


def _chunk(tag: bytes, body: bytes) -> bytes:
    return (
        struct.pack(">I", len(body))
        + tag
        + body
        + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    )


def _png(width: int, height: int, raw: bytes) -> bytes:
    """An RGBA PNG from already-filtered scanlines."""
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


# How many bits of each channel survive when an image has to stay
# truecolour. The master is a textured illustration: its grain is what
# makes it expensive to compress and what hides the quantisation, so
# six bits is invisible here and takes about a third off every file.
POSTERIZE_BITS = 6


def encode_png(img: Image) -> bytes:
    """Encode, choosing the cheaper of two representations.

    An image with 256 or fewer distinct colours - every silhouette, every
    flat glyph - is written as an exact palette, one byte a pixel instead
    of four, with no loss at all. Anything with more is the artwork
    itself, which stays truecolour and is posterised instead.

    Both paths filter adaptively, picking the scanline predictor with the
    smallest absolute sum. That is the standard heuristic and it is worth
    the passes: unfiltered rows of a textured illustration compress badly
    enough that the difference shows in an APK.
    """
    counts: dict[bytes, int] = {}
    for i in range(0, len(img.px), 4):
        px = bytes(img.px[i : i + 4])
        if px not in counts:
            counts[px] = len(counts)
            if len(counts) > 256:
                break
    if len(counts) <= 256:
        return _palette_png(img, counts)
    return _truecolour_png(img)


def _truecolour_png(img: Image) -> bytes:
    mask = (0xFF << (8 - POSTERIZE_BITS)) & 0xFF
    stride = img.w * 4
    flat = bytearray(img.px)
    for i in range(0, len(flat), 4):
        flat[i] &= mask
        flat[i + 1] &= mask
        flat[i + 2] &= mask
    return _png(img.w, img.h, bytes(_filtered(flat, stride, 4)))


def _palette_png(img: Image, palette: dict[bytes, int]) -> bytes:
    entries = sorted(palette, key=palette.get)
    index = {px: i for i, px in enumerate(entries)}
    rows = bytearray(img.w * img.h)
    for i in range(img.w * img.h):
        rows[i] = index[bytes(img.px[i * 4 : i * 4 + 4])]
    header = struct.pack(">IIBBBBB", img.w, img.h, 8, 3, 0, 0, 0)
    plte = b"".join(bytes(e[:3]) for e in entries)
    body = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"PLTE", plte)
    )
    alphas = bytes(e[3] for e in entries)
    # tRNS may be truncated at the last opaque entry, and is omitted when
    # every entry is opaque.
    trimmed = alphas.rstrip(b"\xff")
    if trimmed:
        body += _chunk(b"tRNS", trimmed)
    filtered = _filtered(rows, img.w, 1)
    return body + _chunk(b"IDAT", zlib.compress(bytes(filtered), 9)) + _chunk(b"IEND", b"")


# Byte -> its distance from zero as a signed residual, which is what the
# minimum-sum-of-absolutes heuristic scores. A table plus translate keeps
# the scoring loop out of Python.
_ABS = bytes(min(v, 256 - v) for v in range(256))


def _filtered(data: bytearray, stride: int, ch: int) -> bytearray:
    """Adaptive per-scanline filtering, minimum sum of absolute residuals.

    None, Sub, Up, and Paeth; Average is left out because it costs a full
    Python pass per row and, on this artwork, never won one. The three
    that stay are cheap enough to build with slice arithmetic.
    """
    out = bytearray()
    prior = bytes(stride)
    zeros = bytes(ch)
    for y in range(len(data) // stride):
        line = bytes(data[y * stride : (y + 1) * stride])
        cands = [
            (0, line),
            (1, bytes((a - b) & 0xFF for a, b in zip(line, zeros + line))),
            (2, bytes((a - b) & 0xFF for a, b in zip(line, prior))),
            (4, _paeth(line, prior, ch, zeros)),
        ]
        best_kind, best_line = min(cands, key=lambda c: sum(c[1].translate(_ABS)))
        out.append(best_kind)
        out += best_line
        prior = line
    return out


def _paeth(line: bytes, prior: bytes, ch: int, zeros: bytes) -> bytes:
    out = bytearray(len(line))
    left = zeros + line
    upleft = zeros + prior
    for x in range(len(line)):
        a, b, c = left[x], prior[x], upleft[x]
        est = a + b - c
        pa, pb, pc = abs(est - a), abs(est - b), abs(est - c)
        pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
        out[x] = (line[x] - pred) & 0xFF
    return bytes(out)


def crop(img: Image, box) -> Image:
    """Crop to box, padding with transparent where it leaves the image."""
    x0, y0, x1, y1 = box
    out = Image(x1 - x0, y1 - y0)
    for y in range(y0, y1):
        if y < 0 or y >= img.h:
            continue
        sx0, sx1 = max(x0, 0), min(x1, img.w)
        if sx1 <= sx0:
            continue
        src = (y * img.w + sx0) * 4
        dst = ((y - y0) * out.w + (sx0 - x0)) * 4
        out.px[dst : dst + (sx1 - sx0) * 4] = img.px[src : src + (sx1 - sx0) * 4]
    return out


def resize(img: Image, dw: int, dh: int) -> Image:
    """Two-pass separable area average.

    Area average rather than a windowed filter: every use here is a
    downscale, where it is both correct and ring-free, and rings are what
    a logo with hard ink edges shows first. Rows into a flat buffer, then
    columns, so the cost is proportional to the pixels rather than to the
    square of the ratio - which is what keeps this in seconds without a
    native dependency.
    """
    if (dw, dh) == (img.w, img.h):
        return img.copy()
    spans_x = _spans(img.w, dw)
    mid = bytearray(img.h * dw * 4)
    for y in range(img.h):
        row = y * img.w * 4
        out = y * dw * 4
        for x in range(dw):
            a, b = spans_x[x]
            n = b - a
            r = g = bl = al = 0
            base = row + a * 4
            for i in range(n):
                o = base + i * 4
                r += img.px[o]
                g += img.px[o + 1]
                bl += img.px[o + 2]
                al += img.px[o + 3]
            o = out + x * 4
            mid[o] = r // n
            mid[o + 1] = g // n
            mid[o + 2] = bl // n
            mid[o + 3] = al // n
    spans_y = _spans(img.h, dh)
    result = Image(dw, dh)
    for y in range(dh):
        a, b = spans_y[y]
        n = b - a
        out = y * dw * 4
        for x in range(dw):
            r = g = bl = al = 0
            for sy in range(a, b):
                o = (sy * dw + x) * 4
                r += mid[o]
                g += mid[o + 1]
                bl += mid[o + 2]
                al += mid[o + 3]
            o = out + x * 4
            result.px[o] = r // n
            result.px[o + 1] = g // n
            result.px[o + 2] = bl // n
            result.px[o + 3] = al // n
    return result


def _spans(src: int, dst: int):
    out = []
    for i in range(dst):
        a = i * src // dst
        b = max((i + 1) * src // dst, a + 1)
        out.append((a, min(b, src)))
    return out


class Source:
    """One crop of the master, with a halving chain under it.

    Every output is a downscale, and downscaling from the nearest
    power-of-two level rather than from the full crop is what keeps the
    whole run in seconds: a 1254-wide pass costs the same whether the
    output is 512 or 16.
    """

    def __init__(self, img: Image):
        self.levels = [img]
        while min(self.levels[-1].w, self.levels[-1].h) > 64:
            last = self.levels[-1]
            self.levels.append(resize(last, max(last.w // 2, 1), max(last.h // 2, 1)))
        self._cache: dict[tuple[int, int], Image] = {}

    def at(self, w: int, h: int | None = None) -> Image:
        h = h if h is not None else w
        key = (w, h)
        if key not in self._cache:
            best = self.levels[0]
            for level in self.levels:
                if level.w >= w * 2 and level.h >= h * 2:
                    best = level
            self._cache[key] = resize(best, w, h)
        return self._cache[key]


# --- paper, and keying the emblem out of it ----------------------------------


def measure_paper(img: Image) -> tuple[int, int, int]:
    """The master's paper colour, averaged over its four corner patches.

    Measured rather than declared, so a re-export that shifts the paper
    warmer moves the Android icon background with it instead of leaving
    a seam nobody looks for.
    """
    patch = max(8, img.w // 32)
    total = [0, 0, 0]
    count = 0
    for cx, cy in ((0, 0), (img.w - patch, 0), (0, img.h - patch), (img.w - patch, img.h - patch)):
        for y in range(cy, cy + patch):
            for x in range(cx, cx + patch):
                o = (y * img.w + x) * 4
                total[0] += img.px[o]
                total[1] += img.px[o + 1]
                total[2] += img.px[o + 2]
                count += 1
    return tuple(c // count for c in total)


# The silhouette: the record filled solid, with the candle punched out
# of it. Everything about how it is keyed is a consequence of what this
# mark is made of, and the two obvious approaches both fail on it.
#
# Keying "everything that is not paper" gives a filled circle - the disc
# is the outline, so the candle that makes it WaxDeck dissolves into the
# ink around it. Keying on brightness instead shreds it: the record's
# grooves are drawn as paper-coloured lines across the dark, so a
# brightness threshold cuts the disc into loose arcs that read as a
# scribble at status-bar size.
#
# What separates the candle from the grooves is not lightness but
# warmth. The grooves are the paper (red minus blue about 49); the wax,
# the halo, and the flame are saturated orange (86 to 150); the ink is
# nearly neutral (21). So the void is keyed on red-minus-blue, the disc
# is filled from its own geometry rather than from its pixels, and the
# tonearm comes in as dark ink outside that circle.
#
# Both channels are blurred first because both halves are textured: the
# disc carries light speckle and the candle carries dark wood grain, and
# a threshold on raw pixels turns the first into holes and the second
# into crumbs.
DISC_CENTRE = (630, 470)
DISC_RADIUS = 379
SIL_BLUR = 7
SIL_VOID = 70
SIL_VOID_FEATHER = 18
SIL_INK = 62


def key_silhouette(img: Image) -> Image:
    """Alpha for the one-colour surfaces: a record with a candle in it."""
    luma = _blurred(img, SIL_BLUR, _luma)
    warm = _blurred(img, SIL_BLUR, _warmth)
    cx, cy = DISC_CENTRE
    radius2 = DISC_RADIUS * DISC_RADIUS
    out = Image(img.w, img.h)
    for y in range(img.h):
        dy2 = (y - cy) ** 2
        base = y * img.w
        for x in range(img.w):
            i = base + x
            if (x - cx) ** 2 + dy2 > radius2 and luma[i] > SIL_INK:
                continue  # paper, or something too light to be the arm
            value = warm[i]
            if value >= SIL_VOID:
                continue  # the candle, its halo, or its flame
            t = 1.0
            if value > SIL_VOID - SIL_VOID_FEATHER:
                t = (SIL_VOID - value) / SIL_VOID_FEATHER
                t = t * t * (3 - 2 * t)  # smoothstep
            o = i * 4
            out.px[o] = img.px[o]
            out.px[o + 1] = img.px[o + 1]
            out.px[o + 2] = img.px[o + 2]
            out.px[o + 3] = int(t * 255 + 0.5)
    return out


def _luma(r: int, g: int, b: int) -> int:
    return (299 * r + 587 * g + 114 * b) // 1000


def _warmth(r: int, g: int, b: int) -> int:
    return r - b if r > b else 0


def _blurred(img: Image, radius: int, channel) -> list[int]:
    """One derived channel, box-blurred separably with running sums."""
    w, h = img.w, img.h
    values = [0] * (w * h)
    for i in range(w * h):
        o = i * 4
        values[i] = channel(img.px[o], img.px[o + 1], img.px[o + 2])
    span = radius * 2 + 1
    rows = [0] * (w * h)
    for y in range(h):
        base = y * w
        total = values[base] * (radius + 1)
        for x in range(1, radius + 1):
            total += values[base + min(x, w - 1)]
        for x in range(w):
            rows[base + x] = total // span
            total += values[base + min(x + radius + 1, w - 1)] - values[base + max(x - radius, 0)]
    out = [0] * (w * h)
    for x in range(w):
        total = rows[x] * (radius + 1)
        for y in range(1, radius + 1):
            total += rows[min(y, h - 1) * w + x]
        for y in range(h):
            out[y * w + x] = total // span
            total += rows[min(y + radius + 1, h - 1) * w + x] - rows[max(y - radius, 0) * w + x]
    return out


def flatten(img: Image, background) -> Image:
    """Composite over an opaque background."""
    br, bg, bb = background
    out = Image(img.w, img.h)
    for i in range(img.w * img.h):
        o = i * 4
        a = img.px[o + 3]
        if a == 255:
            out.px[o : o + 4] = img.px[o : o + 4]
            continue
        out.px[o] = (img.px[o] * a + br * (255 - a)) // 255
        out.px[o + 1] = (img.px[o + 1] * a + bg * (255 - a)) // 255
        out.px[o + 2] = (img.px[o + 2] * a + bb * (255 - a)) // 255
        out.px[o + 3] = 255
    return out


def tinted(img: Image, colour) -> Image:
    """The alpha channel, in one flat colour: a silhouette."""
    r, g, b = colour
    out = Image(img.w, img.h)
    for i in range(img.w * img.h):
        o = i * 4
        out.px[o] = r
        out.px[o + 1] = g
        out.px[o + 2] = b
        out.px[o + 3] = img.px[o + 3]
    return out


# --- drawn overlays ----------------------------------------------------------


def coverage(size: int, inside) -> list[list[float]]:
    """Supersampled coverage of a predicate, as a size x size mask."""
    step = 1.0 / SS
    offset = step / 2
    weight = 1.0 / (SS * SS)
    mask = [[0.0] * size for _ in range(size)]
    x0, y0, x1, y1 = getattr(inside, "bounds", (0, 0, size, size))
    for y in range(max(0, int(y0)), min(size, int(math.ceil(y1)) + 1)):
        row = mask[y]
        for x in range(max(0, int(x0)), min(size, int(math.ceil(x1)) + 1)):
            hits = 0.0
            for sy in range(SS):
                py = y + offset + sy * step
                for sx in range(SS):
                    if inside(x + offset + sx * step, py):
                        hits += weight
            row[x] = hits
    return mask


def rounded_rect(x0, y0, x1, y1, radius):
    def inside(x, y):
        cx = min(max(x, x0 + radius), x1 - radius)
        cy = min(max(y, y0 + radius), y1 - radius)
        if x0 <= x <= x1 and y0 <= y <= y1:
            return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius or (
                x0 + radius <= x <= x1 - radius or y0 + radius <= y <= y1 - radius
            )
        return False

    inside.bounds = (x0, y0, x1, y1)
    return inside


def circle(cx, cy, radius):
    def inside(x, y):
        return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius

    inside.bounds = (cx - radius, cy - radius, cx + radius, cy + radius)
    return inside


def segment(x0, y0, x1, y1, thickness):
    dx, dy = x1 - x0, y1 - y0
    length2 = dx * dx + dy * dy
    half = thickness / 2

    def inside(x, y):
        if length2 == 0:
            return (x - x0) ** 2 + (y - y0) ** 2 <= half * half
        t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / length2))
        px, py = x0 + t * dx, y0 + t * dy
        return (x - px) ** 2 + (y - py) ** 2 <= half * half

    inside.bounds = (
        min(x0, x1) - half,
        min(y0, y1) - half,
        max(x0, x1) + half,
        max(y0, y1) + half,
    )
    return inside


def triangle(ax, ay, bx, by, cx, cy):
    def side(px, py, x0, y0, x1, y1):
        return (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0)

    def inside(x, y):
        d1 = side(x, y, ax, ay, bx, by)
        d2 = side(x, y, bx, by, cx, cy)
        d3 = side(x, y, cx, cy, ax, ay)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

    inside.bounds = (min(ax, bx, cx), min(ay, by, cy), max(ax, bx, cx), max(ay, by, cy))
    return inside


def paint(img: Image, mask, colour) -> None:
    """Composite a flat colour through a coverage mask."""
    r, g, b = colour
    for y in range(img.h):
        row = mask[y]
        for x in range(img.w):
            c = row[x]
            if c <= 0:
                continue
            o = (y * img.w + x) * 4
            a = img.px[o + 3] / 255
            out_a = c + a * (1 - c)
            if out_a <= 0:
                continue
            img.px[o] = int((r * c + img.px[o] * a * (1 - c)) / out_a)
            img.px[o + 1] = int((g * c + img.px[o + 1] * a * (1 - c)) / out_a)
            img.px[o + 2] = int((b * c + img.px[o + 2] * a * (1 - c)) / out_a)
            img.px[o + 3] = int(out_a * 255 + 0.5)


def erase(img: Image, mask) -> None:
    """Knock a coverage mask out of the alpha channel."""
    for y in range(img.h):
        row = mask[y]
        for x in range(img.w):
            c = row[x]
            if c <= 0:
                continue
            o = (y * img.w + x) * 4
            img.px[o + 3] = int(img.px[o + 3] * (1 - c))


# --- the two derived shapes --------------------------------------------------


class Brand:
    """The master, its crops, and the two shapes everything is made of."""

    def __init__(self):
        master = decode_png(MASTER)
        if master.w != master.h:
            raise SystemExit(f"{MASTER}: expected a square master, got {master.w}x{master.h}")
        self.paper = measure_paper(master)
        self.lockup = Source(crop(master, LOCKUP_BOX))
        self.flat_emblem = Source(crop(master, EMBLEM_BOX))
        self.flat_tight = Source(crop(master, EMBLEM_TIGHT_BOX))
        keyed = key_silhouette(master)
        self.keyed_emblem = Source(crop(keyed, EMBLEM_BOX))
        self.keyed_tight = Source(crop(keyed, EMBLEM_TIGHT_BOX))

    def emblem(self, size: int, tight: bool = False) -> Image:
        """The emblem on its own paper, square, edge to edge."""
        return (self.flat_tight if tight else self.flat_emblem).at(size)

    def silhouette(self, size: int, colour, tight: bool = False) -> Image:
        """The emblem keyed out of the paper, in one flat colour."""
        return tinted((self.keyed_tight if tight else self.keyed_emblem).at(size), colour)

    def chip(self, size: int, radius_ratio: float = 0.22, tight: bool = False) -> Image:
        """The emblem on paper with rounded corners: the app-icon shape.

        Rounded rather than square because the mark is a disc, and a disc
        in a hard square reads as a sticker. The corner is the platform's
        own proportion; every platform that masks further masks inside
        this one.
        """
        img = self.emblem(size, tight=tight).copy()
        if radius_ratio <= 0:
            return img
        mask = coverage(size, rounded_rect(0, 0, size, size, size * radius_ratio))
        for y in range(size):
            row = mask[y]
            for x in range(size):
                o = (y * size + x) * 4
                img.px[o + 3] = int(img.px[o + 3] * row[x])
        return img

    def inset(self, size: int, safe: float, background) -> Image:
        """The emblem inset into a full-bleed field of its own paper.

        For the canvases a platform crops without telling anybody: an
        Android adaptive foreground, a maskable web icon. The field is
        the measured paper, so the inset is seamless against the
        background the manifest declares.
        """
        inner = max(1, int(size * (1 - 2 * safe)))
        art = flatten(self.emblem(inner), background)
        out = Image(size, size)
        br, bg, bb = background
        for i in range(size * size):
            o = i * 4
            out.px[o] = br
            out.px[o + 1] = bg
            out.px[o + 2] = bb
            out.px[o + 3] = 255
        off = (size - inner) // 2
        for y in range(inner):
            src = y * inner * 4
            dst = ((y + off) * size + off) * 4
            out.px[dst : dst + inner * 4] = art.px[src : src + inner * 4]
        return out


# The play/pause badge the tray glyphs carry, as a fraction of the icon.
BADGE_SIZE = 0.38
BADGE_HALO = 0.055


def badged(img: Image, state: str, colour) -> Image:
    """A tray glyph with its transport state in the bottom-right corner.

    The state used to be the needle's deflection, which asked a person to
    read an angle in a 16-pixel glyph. A triangle and two bars are the
    two shapes every transport control in the world already uses.

    The halo is knocked out of the alpha rather than filled with a
    colour: a tray icon is drawn over whatever the menu bar is, so a
    filled halo would be a light patch on a dark bar.
    """
    out = img.copy()
    size = img.w
    box = size * BADGE_SIZE
    halo = size * BADGE_HALO
    cx = size - box / 2 - size * 0.02
    cy = size - box / 2 - size * 0.02
    erase(out, coverage(size, circle(cx, cy, box / 2 + halo)))
    if state == "playing":
        h = box * 0.52
        w = box * 0.46
        paint(
            out,
            coverage(size, triangle(cx - w / 2, cy - h / 2, cx - w / 2, cy + h / 2, cx + w / 2, cy)),
            colour,
        )
    else:
        bar = box * 0.16
        h = box * 0.5
        for dx in (-box * 0.15, box * 0.15):
            paint(
                out,
                coverage(size, rounded_rect(cx + dx - bar / 2, cy - h / 2, cx + dx + bar / 2, cy + h / 2, bar / 3)),
                colour,
            )
    return out


# --- containers --------------------------------------------------------------


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"  {path.relative_to(ROOT)} ({len(data) / 1024:.1f} KB)")


def write_ico(path: Path, brand: Brand, sizes) -> None:
    """A Windows icon: PNG-compressed entries in an ICONDIR.

    The small entries take the tight crop. A 16-pixel icon showing the
    tonearm shows three grey pixels beside the disc, which reads as a
    rendering fault rather than as an arm.
    """
    images = [(s, brand.chip(s, tight=s <= 32).to_png()) for s in sizes]
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
    as one small tiled asset rather than as a runtime shader. It is
    texture rather than identity, so it does not come off the master and
    its bytes do not move when the master does.
    """
    state = 0x5EED
    px = bytearray()
    for _ in range(size * size):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        value = 128 + ((state >> 16) % 128)
        px += bytes((value, value, value, 255))
    write(path, Image(size, size, px).to_png())


# --- platform kits -----------------------------------------------------------


def padded(inner: Image, size: int) -> Image:
    """Center inner on a transparent size canvas: the safe-zone inset.

    Adaptive layers, splash icons, and status glyphs are all drawn on
    canvases a launcher crops without asking - only the middle survives
    every mask - so their content renders smaller and this supplies the
    margin. It also keeps every resample a downscale: the content is
    always smaller than the canvas, so no density ever asks the source
    for more pixels than the emblem crop holds.
    """
    out = Image(size, size)
    ox = (size - inner.w) // 2
    oy = (size - inner.h) // 2
    for y in range(inner.h):
        src = y * inner.w * 4
        dst = ((oy + y) * size + ox) * 4
        out.px[dst : dst + inner.w * 4] = inner.px[src : src + inner.w * 4]
    return out


def android(brand: Brand, res: Path) -> None:
    paper = brand.paper
    for folder, size in (
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ):
        write(res / folder / "ic_launcher.png", brand.chip(size).to_png())
        # Adaptive layers are drawn on a 108dp canvas of which only the
        # centre 72dp is guaranteed visible. Full-bleed paper rather than
        # a transparent field: the background is the same measured paper,
        # so the two layers meet with no seam and the icon never depends
        # on the quality of a keyed edge.
        adaptive = round(size * 108 / 48)
        write(res / folder / "ic_launcher_foreground.png", brand.inset(adaptive, 0.22, paper).to_png())
        # The monochrome layer is masked like the other adaptive layers:
        # only the centre 72dp of the 108dp canvas is guaranteed
        # visible, so the silhouette is drawn at 0.56 of the canvas and
        # padded out, or a themed icon crops a quarter of the disc.
        write(
            res / folder / "ic_launcher_monochrome.png",
            padded(brand.silhouette(round(adaptive * 0.56), (0, 0, 0)), adaptive).to_png(),
        )
        # Android 12 splash: the system shows a circle of about two
        # thirds of this canvas, so the coin sits at 0.44 - inside the
        # mask with margin, the proportion the pre-rewrite script used.
        splash = round(size * 288 / 48)
        write(
            res / folder / "splash_icon.png",
            padded(brand.chip(round(splash * 0.44), radius_ratio=0.5), splash).to_png(),
        )

    # The status-bar icon for the playback and download notifications.
    # Android keeps only the alpha channel here and tints the rest, so
    # this is the emblem as a silhouette; the tint is passed from Dart.
    # Held against the resource shrinker by res/raw/keep.xml, since the
    # only thing naming it is a Dart string.
    for folder, size in (
        ("drawable-mdpi", 24),
        ("drawable-hdpi", 36),
        ("drawable-xhdpi", 48),
        ("drawable-xxhdpi", 72),
        ("drawable-xxxhdpi", 96),
    ):
        # A small breathing inset, as the pre-rewrite glyph had: the
        # status bar draws these tiny and edge-to-edge reads cramped.
        write(
            res / folder / "ic_stat_waxdeck.png",
            padded(brand.silhouette(round(size * 0.84), (255, 255, 255), tight=True), size).to_png(),
        )

    (res / "values").mkdir(parents=True, exist_ok=True)
    write(
        res / "values/colors.xml",
        (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tools/generate-brand.py -->\n"
            "<resources>\n"
            '    <color name="wax_canvas">#FAF9F6</color>\n'
            '    <color name="wax_canvas_dark">#16130F</color>\n'
            f'    <color name="wax_icon_background">{hex_colour(paper)}</color>\n'
            "</resources>\n"
        ).encode(),
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


def hex_colour(colour) -> str:
    return "#%02X%02X%02X" % tuple(colour)


def tray(brand: Brand, out: Path) -> None:
    """The desktop tray glyphs: the emblem as a silhouette, badged.

    Three platform conventions and two transport states. macOS wants a
    template image - black with alpha, which the system inverts for a
    dark menu bar - and Windows wants the pair drawn for it, because a
    taskbar's own theme is what decides which reads. Linux takes a
    colour glyph, where a StatusNotifier host draws one at all.

    The tight crop throughout: a menu bar renders these at 16 to 22
    points, and the tonearm is noise at that size.
    """
    for state in ("playing", "paused"):
        accent = AMBER if state == "playing" else TEXT_LIGHT
        write(
            out / f"{state}-template.png",
            badged(brand.silhouette(44, (0, 0, 0), tight=True), state, (0, 0, 0)).to_png(),
        )
        write(
            out / f"{state}-light.png",
            badged(brand.silhouette(32, CANVAS_DARK, tight=True), state, CANVAS_DARK).to_png(),
        )
        write(
            out / f"{state}-dark.png",
            badged(brand.silhouette(32, TEXT_LIGHT, tight=True), state, TEXT_LIGHT).to_png(),
        )
        # The colour Linux variant keeps the artwork and takes an amber
        # badge, which is the one place the state gets a colour of its own.
        write(out / f"{state}.png", badged(brand.chip(48, tight=True), state, accent).to_png())


def macos(brand: Brand, appicon: Path) -> None:
    entries = []
    for size, scales in ((16, (1, 2)), (32, (1, 2)), (128, (1, 2)), (256, (1, 2)), (512, (1, 2))):
        for scale in scales:
            pixels = size * scale
            name = f"app_icon_{pixels}.png"
            write(appicon / name, brand.chip(pixels, tight=pixels <= 32).to_png())
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


def web(brand: Brand, web_dir: Path) -> None:
    write(web_dir / "favicon.png", brand.chip(32, tight=True).to_png())
    write(web_dir / "icons/Icon-192.png", brand.chip(192).to_png())
    write(web_dir / "icons/Icon-512.png", brand.chip(512).to_png())
    # Maskable icons are cropped to whatever shape the platform likes, so
    # the emblem sits inside the safe zone on a full-bleed field.
    write(web_dir / "icons/Icon-maskable-192.png", brand.inset(192, 0.20, brand.paper).to_png())
    write(web_dir / "icons/Icon-maskable-512.png", brand.inset(512, 0.20, brand.paper).to_png())


BOOT_MARKER = "<!-- brand:boot-emblem -->"


def boot_emblem(brand: Brand, index: Path) -> None:
    """Replace the boot skeleton's emblem with the real one, in place.

    The marker is the contract: everything between the two comments is
    this script's to rewrite, and everything around it - including the
    hash-redirect shim further down the file - is not touched.
    """
    html = index.read_text()
    if html.count(BOOT_MARKER) != 2:
        raise SystemExit(
            f"{index}: expected two {BOOT_MARKER} comments delimiting the boot emblem"
        )
    png = brand.chip(128).to_png()
    data = base64.b64encode(png).decode()
    body = (
        f'\n      <img class="boot-emblem" alt="" src="data:image/png;base64,{data}">\n      '
    )
    start = html.index(BOOT_MARKER) + len(BOOT_MARKER)
    end = html.index(BOOT_MARKER, start)
    index.write_text(html[:start] + body + html[end:])
    print(f"  {index.relative_to(ROOT)} (boot emblem, {len(data) / 1024:.1f} KB base64)")


# --- the contact sheet -------------------------------------------------------


def contact_sheet(tiles, path: Path) -> None:
    """Every artifact at render size, on one page, on two grounds.

    The eyeball gate covers about forty files and most of them are too
    small to judge in a file listing. Two grounds because half of these
    are drawn over whatever the platform's chrome happens to be, and a
    glyph that looks right on one can vanish on the other - which is what
    a near-black tray icon does in a dark file browser, every time,
    without being wrong.

    Packed left to right with the row height following the tallest tile
    in it, so the small artifacts sit together at a size somebody can
    compare rather than being scattered across a grid sized by the
    biggest one.
    """
    # The labels are the sheet's legend: tiles carry no text, so this
    # printed order is how a reviewer names what they are looking at.
    print("  tiles, in sheet order:", ", ".join(label for label, _ in tiles))
    pad = 14
    width = 1100
    rows, row, x, tallest = [], [], pad, 0
    for tile in tiles:
        img = tile[1]
        if x + img.w + pad > width and row:
            rows.append((row, tallest))
            row, x, tallest = [], pad, 0
        row.append((x, img))
        x += img.w + pad
        tallest = max(tallest, img.h)
    if row:
        rows.append((row, tallest))
    band = sum(h + pad for _, h in rows) + pad
    sheet = Image(width, band * 2)
    for index in range(2):
        ground = (28, 24, 20) if index == 0 else (246, 243, 237)
        top = index * band
        for y in range(top, top + band):
            base = y * width * 4
            for x in range(width):
                o = base + x * 4
                sheet.px[o] = ground[0]
                sheet.px[o + 1] = ground[1]
                sheet.px[o + 2] = ground[2]
                sheet.px[o + 3] = 255
        cursor = top + pad
        for row, height in rows:
            for left, img in row:
                offset = cursor + (height - img.h) // 2
                for y in range(img.h):
                    for x in range(img.w):
                        so = (y * img.w + x) * 4
                        a = img.px[so + 3]
                        if a == 0:
                            continue
                        do = ((offset + y) * width + left + x) * 4
                        for c in range(3):
                            sheet.px[do + c] = (
                                img.px[so + c] * a + sheet.px[do + c] * (255 - a)
                            ) // 255
            cursor += height + pad
    write(path, sheet.to_png())


def main() -> int:
    if not MASTER.exists():
        raise SystemExit(f"{MASTER} is missing; the brand master is the one input")
    print(f"brand: reading {MASTER.relative_to(ROOT)}")
    brand = Brand()
    print(f"  paper {hex_colour(brand.paper)}")

    print("brand: design system assets")
    write_grain(UI_BRAND / "grain.png")
    write(UI_BRAND / "emblem-256.png", brand.chip(256).to_png())

    print("brand: docs")
    lockup = brand.lockup.at(640, round(640 * brand.lockup.levels[0].h / brand.lockup.levels[0].w))
    write(BRAND / "lockup-640.png", lockup.to_png())
    # Full bleed, no rounding: this one is for upload surfaces (Discord
    # art assets and the like) that mask their own corners. Baked-in
    # rounded transparency there reads as dark notches - the host's
    # ground showing through inside its own crop.
    write(BRAND / "emblem-512.png", brand.chip(512, radius_ratio=0).to_png())

    print("brand: tray")
    tray(brand, APP / "assets/tray")

    print("brand: web")
    web(brand, APP / "web")
    boot_emblem(brand, APP / "web/index.html")

    print("brand: android")
    android(brand, APP / "android/app/src/main/res")

    print("brand: macos")
    macos(brand, APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset")

    print("brand: windows")
    write_ico(APP / "windows/runner/resources/app_icon.ico", brand, (16, 24, 32, 48, 64, 128, 256))
    write(APP / "windows/runner/resources/store_logo.png", brand.chip(256).to_png())

    print("brand: linux")
    for size in (16, 32, 48, 64, 128, 256, 512):
        write(
            APP / f"linux/icons/hicolor/{size}x{size}/apps/waxdeck.png",
            brand.chip(size, tight=size <= 32).to_png(),
        )

    print("brand: contact sheet (uncommitted)")
    tiles = [
        ("chip-16", brand.chip(16, tight=True)),
        ("chip-24", brand.chip(24, tight=True)),
        ("chip-32", brand.chip(32, tight=True)),
        ("chip-48", brand.chip(48)),
        ("chip-64", brand.chip(64)),
        ("chip-128", brand.chip(128)),
        ("chip-192", brand.chip(192)),
        ("chip-256", brand.chip(256)),
        ("adaptive-108", brand.inset(108, 0.22, brand.paper)),
        ("adaptive-192", brand.inset(192, 0.22, brand.paper)),
        ("maskable-192", brand.inset(192, 0.20, brand.paper)),
        ("splash-288", brand.chip(288, radius_ratio=0.5)),
        ("mono-108", brand.silhouette(108, (0, 0, 0))),
        ("stat-24", brand.silhouette(24, (255, 255, 255), tight=True)),
        ("stat-48", brand.silhouette(48, (255, 255, 255), tight=True)),
        ("stat-96", brand.silhouette(96, (255, 255, 255), tight=True)),
    ]
    for state in ("playing", "paused"):
        accent = AMBER if state == "playing" else TEXT_LIGHT
        tiles += [
            (f"{state}-template", badged(brand.silhouette(44, (0, 0, 0), tight=True), state, (0, 0, 0))),
            (f"{state}-light", badged(brand.silhouette(32, CANVAS_DARK, tight=True), state, CANVAS_DARK)),
            (f"{state}-dark", badged(brand.silhouette(32, TEXT_LIGHT, tight=True), state, TEXT_LIGHT)),
            (f"{state}-colour", badged(brand.chip(48, tight=True), state, accent)),
        ]
    tiles.append(("lockup", brand.lockup.at(240, round(240 * brand.lockup.levels[0].h / brand.lockup.levels[0].w))))
    contact_sheet(tiles, CACHE / "brand-contact-sheet.png")
    return 0


if __name__ == "__main__":
    os.chdir(ROOT)
    raise SystemExit(main())
