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
