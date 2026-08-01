import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'palette.dart';

/// Reads one piece of artwork's colour out of its decoded pixels.
///
/// Pure and free of `BuildContext`, so it can run wherever the caller
/// decides: it takes bytes and answers a value. Null means the artwork
/// has no colour worth using - a black-and-white sleeve, a scan of
/// paper, a monochrome podcast logo - and the caller draws the domain
/// hue instead. Answering a near-grey would be worse than answering
/// nothing: a wash of it reads as a smudge rather than as atmosphere.
///
/// [rgba] is RGBA8888, four bytes a pixel, as
/// `Image.toByteData(format: rawRgba)` gives it - which is
/// **premultiplied**, so a pixel's colour channels are already scaled by
/// its alpha. Only fully opaque pixels are read, where premultiplied and
/// straight are the same bytes; anything below that is a blend toward
/// whatever is behind it rather than a colour the artwork has, and
/// counting it would drag the reading toward black. The dimensions do
/// not matter here - this is a histogram, not a layout - so only the
/// length is read.
///
/// What comes back is atmosphere and only atmosphere. The guardrails in
/// the colour system are why this returns a [WaxPalette] with no "on"
/// colours: nothing extracted from artwork may become text, an icon, or
/// a colour that carries meaning.
WaxPalette? extractPalette(Uint8List rgba) {
  final pixels = rgba.length ~/ 4;
  if (pixels == 0) return null;

  // Enough pixels to find the dominant colour of a cover and few enough
  // to stay off the frame budget: the caller decodes at 64 px, and a
  // caller that hands over more gets sampled rather than scanned.
  const sampleTarget = 4096;
  final stride = math.max(1, pixels ~/ sampleTarget);

  // 5 bits of hue-carrying detail per channel is too fine for 4,000
  // samples to fill; 3 bits puts a cover's reds in one bucket without
  // merging them with its oranges.
  const shift = 5;
  const buckets = 1 << (3 * (8 - shift));
  final counts = Uint32List(buckets);
  final sumR = Uint32List(buckets);
  final sumG = Uint32List(buckets);
  final sumB = Uint32List(buckets);
  final weights = Float64List(buckets);

  for (var p = 0; p < pixels; p += stride) {
    final i = p * 4;
    // Opaque only. A cut-out corner is not a colour at all, and a
    // feathered edge, a rounded logo's antialiasing, or a drop shadow
    // is a colour multiplied by its own alpha - read as it stands it is
    // the artwork's hue dragged some fraction of the way to black.
    if (rgba[i + 3] != 255) continue;
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];

    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    if (max == 0) continue;
    final saturation = (max - min) / max;
    final value = max / 255;

    // What makes a colour usable as a wash: it has to be a colour at
    // all, and it has to survive being drawn at a tenth of its opacity.
    // Near-greys wash out to nothing, near-blacks read as dirt, and
    // blown highlights read as fog. The score is the weight of evidence
    // for a hue, not a count of pixels: a sleeve that is nine-tenths
    // black and one-tenth crimson is a crimson sleeve.
    final weight = saturation * saturation * value * (1 - value * 0.35);
    if (weight <= 0.02) continue;

    final key =
        ((r >> shift) << (2 * (8 - shift))) |
        ((g >> shift) << (8 - shift)) |
        (b >> shift);
    counts[key]++;
    sumR[key] += r;
    sumG[key] += g;
    sumB[key] += b;
    weights[key] += weight;
  }

  var best = -1;
  var bestWeight = 0.0;
  for (var key = 0; key < buckets; key++) {
    if (weights[key] > bestWeight) {
      bestWeight = weights[key];
      best = key;
    }
  }
  if (best < 0) return null;

  // Against the samples actually taken, so the threshold means the same
  // thing whatever size the caller decoded at.
  final sampled = (pixels + stride - 1) ~/ stride;
  if (bestWeight / sampled < _usableFloor) return null;

  final count = counts[best];
  final dominant = HSLColor.fromColor(
    Color.fromARGB(
      255,
      sumR[best] ~/ count,
      sumG[best] ~/ count,
      sumB[best] ~/ count,
    ),
  );

  return WaxPalette(
    // The hue is the artwork's; the saturation and lightness are the
    // system's. An artwork colour is drawn at a tenth of its opacity
    // over a fixed canvas, so what arrives is decided as much by the
    // clamp as by the sleeve, and letting a blown-out cover through
    // unclamped is how a backdrop stops being a backdrop.
    glow: dominant
        .withSaturation(dominant.saturation.clamp(0.30, 0.85))
        .withLightness(dominant.lightness.clamp(0.42, 0.62))
        .toColor(),
    // Deeper, because light mode mixes this into paper rather than
    // shining it through darkness: the same colour that glows at 18
    // percent over near-black disappears at 10 percent over near-white.
    wash: dominant
        .withSaturation(dominant.saturation.clamp(0.35, 0.90))
        .withLightness(dominant.lightness.clamp(0.32, 0.52))
        .toColor(),
    isFallback: false,
  );
}

/// How much colour a piece of artwork has to carry before its colour is
/// worth using.
///
/// Averaged over the samples taken: a cover whose every pixel is a
/// saturated mid-tone scores near 0.5, and one with a single coloured
/// letter on white scores near zero. The floor sits low because a small
/// bright mark on a neutral sleeve is exactly the colour a listener
/// would name if asked - it only has to clear the noise a scan's warm
/// paper leaves behind.
const double _usableFloor = 0.004;
