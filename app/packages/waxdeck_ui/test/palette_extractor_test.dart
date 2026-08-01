import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// [pixels] colours as one RGBA buffer, in the order given.
Uint8List _rgba(List<Color> pixels) {
  final bytes = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    final color = pixels[i];
    bytes[i * 4] = (color.r * 255).round();
    bytes[i * 4 + 1] = (color.g * 255).round();
    bytes[i * 4 + 2] = (color.b * 255).round();
    bytes[i * 4 + 3] = (color.a * 255).round();
  }
  return bytes;
}

Uint8List _fill(Color color, {int count = 4096}) =>
    _rgba(List<Color>.filled(count, color));

void main() {
  group('palette extraction', () {
    test('reads the hue of a coloured sleeve', () {
      final palette = extractPalette(_fill(const Color(0xFFB4321E)));
      expect(palette, isNotNull);
      expect(palette!.isFallback, isFalse);
      final hue = HSLColor.fromColor(palette.glow).hue;
      // Red-orange, whatever the clamps did to its saturation and
      // lightness: the hue is the artwork's and only the hue is.
      expect(hue, closeTo(13, 8));
    });

    test('lifts a dim colour into a usable glow', () {
      // Near-black with a red cast: drawn as it stands it is dirt at any
      // opacity, and it is what half of album art looks like.
      final palette = extractPalette(_fill(const Color(0xFF2A0B06)));
      expect(palette, isNotNull);
      expect(HSLColor.fromColor(palette!.glow).lightness, greaterThan(0.4));
      expect(HSLColor.fromColor(palette.glow).saturation, greaterThan(0.29));
    });

    test('refuses a greyscale sleeve rather than washing with grey', () {
      expect(extractPalette(_fill(const Color(0xFF7A7A7A))), isNull);
      expect(extractPalette(_fill(const Color(0xFF101010))), isNull);
      expect(extractPalette(_fill(const Color(0xFFF2F2F2))), isNull);
    });

    test('finds the one colour on an otherwise neutral cover', () {
      // A white sleeve with a small teal mark: the colour a listener
      // would name if asked, and a hundredth of the pixels.
      final pixels = <Color>[
        ...List<Color>.filled(4000, const Color(0xFFF4F1EA)),
        ...List<Color>.filled(96, const Color(0xFF11837E)),
      ];
      final palette = extractPalette(_rgba(pixels));
      expect(palette, isNotNull);
      expect(HSLColor.fromColor(palette!.glow).hue, closeTo(177, 10));
    });

    test('ignores transparent pixels', () {
      // A cut-out sleeve: the transparent half is a saturated colour
      // with no alpha, and reading it would name the cover by what is
      // not drawn.
      final pixels = <Color>[
        ...List<Color>.filled(2048, const Color(0x0022FF22)),
        ...List<Color>.filled(2048, const Color(0xFF2B4FCB)),
      ];
      final palette = extractPalette(_rgba(pixels));
      expect(palette, isNotNull);
      expect(HSLColor.fromColor(palette!.glow).hue, closeTo(226, 12));
    });

    test('ignores partly transparent pixels too', () {
      // The bytes arrive premultiplied, so a half-alpha crimson is a
      // half-brightness crimson on the wire. Counted, a feathered edge
      // or a drop shadow pulls the reading toward black; the opaque
      // pixels are the only ones that say what colour the artwork is.
      final pixels = <Color>[
        // Green at half alpha, premultiplied: what the engine hands over
        // for a colour that is half-covering whatever is behind it.
        ...List<Color>.filled(3000, const Color(0x8000BB00)),
        ...List<Color>.filled(1096, const Color(0xFF2B4FCB)),
      ];
      final palette = extractPalette(_rgba(pixels));
      expect(palette, isNotNull);
      expect(HSLColor.fromColor(palette!.glow).hue, closeTo(226, 12));
    });

    test('answers nothing for nothing', () {
      expect(extractPalette(Uint8List(0)), isNull);
      expect(extractPalette(_fill(const Color(0x00000000))), isNull);
    });

    test('a wash is deeper than its glow', () {
      // Dark shines colour through darkness and light mixes it into
      // paper: the same value cannot do both, which is why there are
      // two.
      final palette = extractPalette(_fill(const Color(0xFF8FC7E8)))!;
      expect(
        HSLColor.fromColor(palette.wash).lightness,
        lessThan(HSLColor.fromColor(palette.glow).lightness),
      );
    });
  });

  group('palette tween', () {
    test('crossfades between two readings', () {
      const a = WaxPalette(
        glow: Color(0xFF000000),
        wash: Color(0xFF000000),
        isFallback: true,
      );
      const b = WaxPalette(
        glow: Color(0xFFFFFFFF),
        wash: Color(0xFFFFFFFF),
        isFallback: false,
      );
      final tween = WaxPaletteTween(begin: a, end: b);
      expect(tween.lerp(0.5).glow.r, closeTo(0.5, 0.02));
      expect(tween.transform(0).glow, a.glow);
      expect(tween.transform(1).glow, b.glow);
    });
  });

  group('waveform downsampling', () {
    test('a thousand buckets become as many bars as the bar has room for', () {
      final peaks = List<double>.generate(1000, (i) => i / 999);
      expect(downsamplePeaks(peaks, 120).length, 120);
      expect(downsamplePeaks(peaks, 120).last, closeTo(1, 0.01));
      expect(downsamplePeaks(peaks, 120).first, lessThan(0.02));
    });

    test('a bar takes the loudest bucket it covers, not the mean', () {
      // One transient in a quiet passage is the shape you aim a scrub
      // at; averaged over its neighbours it disappears.
      final peaks = <double>[0.1, 0.1, 0.9, 0.1, 0.1, 0.1, 0.1, 0.1];
      expect(downsamplePeaks(peaks, 2).first, 0.9);
    });

    test('fewer peaks than bars repeats rather than inventing', () {
      expect(downsamplePeaks(<double>[0.2, 0.8], 4), <double>[
        0.2,
        0.2,
        0.8,
        0.8,
      ]);
    });

    test('nothing in, nothing out', () {
      expect(downsamplePeaks(const <double>[], 40), isEmpty);
      expect(downsamplePeaks(<double>[0.5], 0), isEmpty);
    });
  });
}
