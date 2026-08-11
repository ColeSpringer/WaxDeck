import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

void main() {
  setUp(WaxFonts.resetForTest);

  group('script detection', () {
    test('finds each deferred script by its runes', () {
      expect(WaxFonts.scriptsIn('حسن'), {WaxScript.arabic});
      expect(WaxFonts.scriptsIn('שלום'), {WaxScript.hebrew});
      expect(WaxFonts.scriptsIn('สวัสดี'), {WaxScript.thai});
      expect(WaxFonts.scriptsIn('漢字'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('ひらがな'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('カタカナ'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('한글'), {WaxScript.cjk});
      // Supplementary-plane ideographs arrive as surrogate pairs; runes
      // must see the codepoint, not the halves.
      expect(WaxFonts.scriptsIn('\u{20BB7}'), {WaxScript.cjk});
      // Presentation forms and full/halfwidth forms count as their
      // scripts too: tag data in the wild uses them.
      expect(WaxFonts.scriptsIn('ײַ'), {WaxScript.hebrew});
      expect(WaxFonts.scriptsIn('ﻼ'), {WaxScript.arabic});
      expect(WaxFonts.scriptsIn('ｱ'), {WaxScript.cjk});
      // So do the CJK symbol blocks track listings lean on: enclosed
      // letters, squared units, vertical forms, and extended jamo.
      expect(WaxFonts.scriptsIn('㈱'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('㍿'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('︱'), {WaxScript.cjk});
      expect(WaxFonts.scriptsIn('ힰ'), {WaxScript.cjk});
    });

    test('mixed text reports every script it contains', () {
      expect(WaxFonts.scriptsIn('Duke Ellington משהו 東京 กรุงเทพ'), {
        WaxScript.hebrew,
        WaxScript.cjk,
        WaxScript.thai,
      });
    });

    test('Latin, Greek, and Cyrillic need nothing', () {
      expect(
        WaxFonts.scriptsIn('Sigur Ros, Ω, Чайковский 0123 (feat. no one)'),
        isEmpty,
      );
    });

    test('a stray byte-order mark is not Arabic', () {
      // BOMs routinely survive UTF-16 taggers into ID3 text; U+FEFF
      // sits numerically at the end of the Arabic presentation forms
      // block but must not pull down the Arabic face for an all-Latin
      // library.
      expect(WaxFonts.scriptsIn('﻿Everything In Its Place'), isEmpty);
      expect(WaxFonts.scriptsIn('﻾'), {WaxScript.arabic});
    });

    test('an installed script stops being reported', () async {
      expect(WaxFonts.scriptsIn('漢'), {WaxScript.cjk});
      await WaxFonts.ensureScript(WaxScript.cjk);
      expect(WaxFonts.isLoaded(WaxScript.cjk), isTrue);
      expect(WaxFonts.scriptsIn('漢'), isEmpty);
    });

    test('a started load stops being reported before it lands', () async {
      // The loader never retries, so a script is handled from the
      // moment its load begins; reporting it again would only buy
      // repeated scans for a load that is already underway (or that
      // already failed for good).
      final inFlight = WaxFonts.ensureScript(WaxScript.cjk);
      expect(WaxFonts.scriptsIn('漢'), isEmpty);
      await inFlight;
    });
  });

  group('the scripts added for real libraries', () {
    // One sample per bundled face: a script that stops being detected is
    // a library that renders boxes, and the ranges are the only thing
    // between the two.
    const samples = <WaxScript, String>{
      WaxScript.devanagari: 'हिन्दी',
      WaxScript.bengali: 'বাংলা',
      WaxScript.gurmukhi: 'ਪੰਜਾਬੀ',
      WaxScript.gujarati: 'ગુજરાતી',
      WaxScript.tamil: 'தமிழ்',
      WaxScript.telugu: 'తెలుగు',
      WaxScript.kannada: 'ಕನ್ನಡ',
      WaxScript.malayalam: 'മലയാളം',
      WaxScript.sinhala: 'සිංහල',
      WaxScript.khmer: 'ខ្មែរ',
      WaxScript.lao: 'ລາວ',
      WaxScript.myanmar: 'မြန်မာ',
      WaxScript.georgian: 'ქართული',
      WaxScript.armenian: 'Հայերեն',
      WaxScript.ethiopic: 'አማርኛ',
    };

    for (final entry in samples.entries) {
      test('${entry.key.name} is detected from its own script', () {
        expect(WaxFonts.scriptsIn(entry.value), <WaxScript>{entry.key});
      });
    }

    test('a danda warms Devanagari rather than nothing', () {
      // Shared Indic punctuation that lives in Devanagari's block. It
      // over-warms by design: a face nobody looks at costs a load, a
      // missing one costs a box.
      expect(WaxFonts.scriptsIn('।'), <WaxScript>{WaxScript.devanagari});
    });

    test('emoji are detected across the ranges they really use', () {
      expect(WaxFonts.scriptsIn('😀'), <WaxScript>{WaxScript.emoji});
      expect(WaxFonts.scriptsIn('🇩🇪'), <WaxScript>{WaxScript.emoji});
      expect(WaxFonts.scriptsIn('☀'), <WaxScript>{WaxScript.emoji});
      expect(WaxFonts.scriptsIn('⭐'), <WaxScript>{WaxScript.emoji});
      // Emoji by default with no variation selector: a watch in a
      // podcast title is an emoji, not a symbol.
      expect(WaxFonts.scriptsIn('⌚'), <WaxScript>{WaxScript.emoji});
      // An explicit VS16 asks for emoji presentation, so the face is
      // warmed even where the base character is a text symbol.
      expect(WaxFonts.scriptsIn('\u2733\uFE0F'), <WaxScript>{WaxScript.emoji});
    });

    test('the rating stars stay in the eager chain', () {
      // U+2605/2606 are in the Latin subset and draw as text. Pulling a
      // ten-megabyte colour face for a rating row is the failure this
      // carve-out exists to prevent.
      expect(WaxFonts.scriptsIn('★☆'), isEmpty);
    });

    test('the scatter routes by which face holds the glyph', () {
      // The musical note is not an emoji and the colour face cannot
      // draw it; CJK can, so a title's note warms CJK rather than
      // downloading ten megabytes to draw tofu.
      expect(WaxFonts.scriptsIn('♪'), <WaxScript>{WaxScript.cjk});
      expect(WaxFonts.scriptsIn('✓'), <WaxScript>{WaxScript.cjk});
      // The black square is emoji-only and used to slip the warm list.
      expect(WaxFonts.scriptsIn('⬛'), <WaxScript>{WaxScript.emoji});
      // The ballot X is drawn by no owned face: tofu either way, so
      // nothing downloads for it.
      expect(WaxFonts.scriptsIn('✗'), isEmpty);
      // The play triangle is in the eager Latin subset and stays text.
      expect(WaxFonts.scriptsIn('▶'), isEmpty);
    });
  });

  group('loading', () {
    testWidgets('every deferred face loads from the shipped assets', (
      tester,
    ) async {
      // The bundle in the test binding resolves the same assets the app
      // ships, so this proves the paths in _faces point at real files
      // (a renamed or missing asset fails here, not as quiet tofu).
      for (final script in WaxScript.values) {
        await WaxFonts.ensureScript(script);
        expect(WaxFonts.isLoaded(script), isTrue, reason: '$script');
      }
    });

    testWidgets('ensureScript is one load per script', (tester) async {
      final first = WaxFonts.ensureScript(WaxScript.arabic);
      final second = WaxFonts.ensureScript(WaxScript.arabic);
      expect(identical(first, second), isTrue);
      await first;
    });

    testWidgets('ensureFor with no deferred scripts does nothing', (
      tester,
    ) async {
      await WaxFonts.ensureFor('plain latin title');
      for (final script in WaxScript.values) {
        expect(WaxFonts.isLoaded(script), isFalse);
      }
    });
  });

  group('chain consistency', () {
    test('qualified names mirror the unqualified chain', () {
      expect(WaxFonts.fallbacksQualified, [
        for (final family in WaxFonts.fallbacks)
          'packages/${WaxFonts.package}/$family',
      ]);
      expect(
        WaxFonts.uiQualified,
        'packages/${WaxFonts.package}/${WaxFonts.ui}',
      );
    });
  });
}
