import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

double _widthOf(TextStyle style, {String text = 'Hallucinated Sunlight 0123'}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  group('variable axes', () {
    // A font whose axes are ignored renders every weight identically and
    // still looks plausible in a screenshot, which is exactly how a
    // broken subset or a dropped fvar table slips through review. Width
    // is the tell: the same string at two axis values must not measure
    // the same.
    test('Archivo honours the weight axis', () {
      final light = _widthOf(
        TextStyle(
          fontFamily: WaxFonts.display,
          package: WaxFonts.package,
          fontSize: 30,
          fontVariations: const [FontVariation('wght', 100)],
        ),
      );
      final heavy = _widthOf(
        TextStyle(
          fontFamily: WaxFonts.display,
          package: WaxFonts.package,
          fontSize: 30,
          fontVariations: const [FontVariation('wght', 900)],
        ),
      );
      expect(heavy, greaterThan(light));
    });

    test('Archivo honours the width axis', () {
      final normal = _widthOf(
        TextStyle(
          fontFamily: WaxFonts.display,
          package: WaxFonts.package,
          fontSize: 30,
          fontVariations: const [
            FontVariation('wght', 640),
            FontVariation('wdth', 100),
          ],
        ),
      );
      final expanded = _widthOf(
        TextStyle(
          fontFamily: WaxFonts.display,
          package: WaxFonts.package,
          fontSize: 30,
          fontVariations: const [
            FontVariation('wght', 640),
            FontVariation('wdth', 125),
          ],
        ),
      );
      expect(expanded, greaterThan(normal));
    });

    test('Inter honours the weight axis at the token values', () {
      // 460 (body) and 620 (overline) are unreachable through
      // FontWeight, so if these measure the same the tokens have
      // silently snapped to a static weight.
      final body = _widthOf(WaxType.body.copyWith(fontSize: 30, height: 1.2));
      final heavier = _widthOf(
        WaxType.body.copyWith(
          fontSize: 30,
          height: 1.2,
          fontVariations: const [FontVariation('wght', 620)],
        ),
      );
      expect(heavier, greaterThan(body));
    });

    test('Spline Sans Mono stays monospaced and tabular', () {
      final wide = _widthOf(WaxType.monoTime, text: '88:88');
      final narrow = _widthOf(WaxType.monoTime, text: '11:11');
      expect(narrow, closeTo(wide, 0.01));
    });
  });

  group('type tokens', () {
    test('carry their specified sizes and axes', () {
      expect(WaxType.display.fontSize, 30);
      expect(WaxType.display.height, closeTo(36 / 30, 0.001));
      expect(
        WaxType.display.fontVariations,
        containsAll(<FontVariation>[
          const FontVariation('wght', 640),
          const FontVariation('wdth', 125),
        ]),
      );
      expect(WaxType.titleEntity.fontSize, 21);
      expect(WaxType.body.fontSize, 14);
      expect(
        WaxType.body.fontVariations,
        contains(const FontVariation('wght', 460)),
      );
      expect(WaxType.overline.letterSpacing, 0.6);
      expect(WaxType.monoTime.fontSize, 13);
    });

    test('resolve to the bundled families, not the platform default', () {
      expect(WaxType.body.fontFamily, 'packages/waxdeck_ui/Inter');
      expect(WaxType.display.fontFamily, 'packages/waxdeck_ui/Archivo');
      expect(WaxType.monoData.fontFamily, 'packages/waxdeck_ui/SplineSansMono');
    });

    test('carry the owned fallback chain', () {
      // Without this chain, Flutter web fetches Noto from Google's CDN
      // for any script the primary faces miss, and a LAN-only instance
      // renders boxes.
      expect(
        WaxType.body.fontFamilyFallback,
        containsAll(<String>[
          'packages/waxdeck_ui/NotoSansArabic',
          'packages/waxdeck_ui/NotoSansHebrew',
          'packages/waxdeck_ui/NotoSansThai',
          'packages/waxdeck_ui/NotoSansCJK',
        ]),
      );
    });

    test('numbers are tabular everywhere they can line up', () {
      for (final style in <TextStyle>[
        WaxType.body,
        WaxType.caption,
        WaxType.monoTime,
        WaxType.monoData,
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });
  });

  group('non-Latin metadata', () {
    test('renders from bundled faces rather than a fetched fallback', () {
      // Arabic, Hebrew, Thai, and CJK metadata have to measure as real
      // glyphs. A missing face collapses to notdef boxes of a different
      // width, or to zero-width nothing. Han, kana, and hangul all ride
      // the one CJK face, so each is proved separately.
      for (final sample in <String>[
        'حسن',
        'שלום',
        'สวัสดี',
        '漢字',
        'かなカナ',
        '한글',
      ]) {
        expect(_widthOf(WaxType.titleItem, text: sample), greaterThan(8));
      }
    });

    test('the weight axis reaches the fallback faces too', () {
      // The type tokens set wght, opsz, and (on Archivo) wdth, and the
      // same variations are handed to every face in the chain. The Noto
      // fallbacks carry wght and no opsz, and their wdth tops out at 100
      // where Archivo's expanded cut asks for 125: unsupported tags are
      // ignored and out-of-range values clamp, both harmless. What must
      // not be harmless is wght being dropped, which would render every
      // non-Latin string at one weight while Latin text varies.
      for (final sample in <String>['حسن', 'שלום', 'สวัสดี']) {
        final light = _widthOf(
          WaxType.titleItem.copyWith(
            fontSize: 40,
            fontVariations: const [FontVariation('wght', 100)],
          ),
          text: sample,
        );
        final heavy = _widthOf(
          WaxType.titleItem.copyWith(
            fontSize: 40,
            fontVariations: const [FontVariation('wght', 900)],
          ),
          text: sample,
        );
        expect(
          heavy,
          greaterThan(light),
          reason: '$sample renders at a fixed weight',
        );
      }
    });
  });

  group('the theme font floor', () {
    // The theme names a family so that a bare style - one written with no
    // family at all, which old screens still contain - resolves to the
    // bundled UI face rather than asking Google's CDN for Roboto. It must
    // not do that by flattening the token faces: three faces carry three
    // jobs, and a floor applied over the top would make them one.
    test('leaves the token faces alone', () {
      final theme = buildWaxTheme();
      expect(
        theme.textTheme.displayLarge?.fontFamily,
        contains(WaxFonts.display),
      );
      expect(theme.textTheme.bodyMedium?.fontFamily, contains(WaxFonts.ui));
      expect(WaxType.monoTime.fontFamily, contains(WaxFonts.mono));
    });

    test('carries the owned fallback chain', () {
      // The package qualifies both the family and the chain, so what
      // lands on a style is the asset-path form.
      final theme = buildWaxTheme();
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        containsAll(WaxFonts.fallbacksQualified),
      );
    });
  });
}
